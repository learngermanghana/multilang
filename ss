// functions/index.js
// Firebase Functions v2 (Node 20)

const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { google } = require("googleapis");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();

// ── Secret names (set them with `firebase functions:secrets:set ...`) ──────────
const BOT_TOKEN            = defineSecret("TELEGRAM_BOT_TOKEN");   // your bot token
const TEACHER_CHAT_ID      = defineSecret("TELEGRAM_CHAT_ID");     // your own chat id
const WEBHOOK_SECRET       = defineSecret("TELEGRAM_WEBHOOK_SECRET"); // optional

const GSHEET_ROSTER_ID     = defineSecret("GSHEET_ROSTER_ID");
const GSHEET_ROSTER_RANGE  = defineSecret("GSHEET_ROSTER_RANGE");  // e.g. Students!A:Z
const GSHEET_SCORES_ID     = defineSecret("GSHEET_SCORES_ID");
const GSHEET_SCORES_RANGE  = defineSecret("GSHEET_SCORES_RANGE");  // e.g. Scores!A:H

// ── Helpers ───────────────────────────────────────────────────────────────────
function tsToMs(ts) {
  try {
    if (typeof ts === "number") return ts > 1e12 ? ts : ts * 1000;
    if (ts instanceof Date) return ts.getTime();
    if (ts?.toDate) return ts.toDate().getTime();
    if (ts?.toMillis) return ts.toMillis();
    if (ts && typeof ts === "object" && "_seconds" in ts) {
      return Number(ts._seconds) * 1000 + Math.floor(Number(ts._nanoseconds || 0) / 1e6);
    }
    if (typeof ts === "string") return new Date(ts).getTime();
  } catch (_) {}
  return 0;
}

function bestTimeMs(data, meta = {}) {
  const c = [
    tsToMs(data.submitted_at),
    tsToMs(data.timestamp),
    tsToMs(data.created_at),
    tsToMs(data.updated_at),
    meta.updateTime?.toDate?.().getTime?.() || 0,
    meta.createTime?.toDate?.().getTime?.() || 0,
  ].filter(Boolean);
  return c.length ? Math.max(...c) : Date.now();
}

function pickTitle(data, docId) {
  const fields = ["title", "lesson", "assignment", "lesson_key", "topic", "name", "subject"];
  for (const k of fields) {
    const v = data?.[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return docId || "(no title)";
}

function fmtTime(ms) {
  const d = new Date(ms);
  // UTC-ish readable
  return d.toISOString().replace("T", " ").slice(0, 19);
}

async function sendTelegramText(chatId, text, opts = {}) {
  const token = BOT_TOKEN.value();
  const url = `https://api.telegram.org/bot${token}/sendMessage`;
  const body = {
    chat_id: chatId,
    text,
    parse_mode: "HTML",
    disable_web_page_preview: true,
    ...opts,
  };
  try {
    await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  } catch (e) {
    console.error("sendTelegramText error:", e?.message || e);
  }
}

async function notifyTeacher(lines) {
  const chatId = TEACHER_CHAT_ID.value();
  if (!chatId) return;
  await sendTelegramText(chatId, lines.join("\n"));
}

// Look up a student's chat id by code, from Firestore (populated by /register or syncSheets)
async function chatIdForStudentCode(code) {
  if (!code) return null;

  // First check roster doc
  const r = await db.collection("roster").doc(String(code)).get();
  if (r.exists && r.data()?.chat_id) return r.data().chat_id;

  // Fallback check mapping by chat docs
  const q = await db.collection("telegram_users").where("student_code", "==", String(code)).limit(1).get();
  if (!q.empty) return q.docs[0].data().chat_id || null;

  return null;
}

// ── 1) FINAL SUBMISSIONS → notify teacher ─────────────────────────────────────
exports.onFinalSubmission = onDocumentWritten(
  {
    region: "us-central1",
    document: "submissions/{level}/posts/{postId}",
    secrets: [BOT_TOKEN, TEACHER_CHAT_ID],
  },
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return; // deleted – ignore

    // Only alert when it is a final submission
    // (either created with status=submitted, or it changed to submitted)
    const before = event.data?.before?.data();
    const statusNow = (after.status || "").toLowerCase();
    const statusWas = (before?.status || "").toLowerCase();

    const isFinal =
      statusNow === "submitted" &&
      ( !before || statusWas !== "submitted" ); // fire once when it becomes submitted

    if (!isFinal) return;

    const ms = bestTimeMs(after, event.data?.after);
    const title = pickTitle(after, event.params.postId);
    const studentName = after.student_name || after.name || "(unknown)";
    const studentCode = after.student_code || "(unknown)";
    const level = after.level || event.params.level || "(level?)";

    const msg = [
      "📥 <b>New final submission</b>",
      `<b>Title:</b> ${title}`,
      `<b>Student:</b> ${studentName} (${studentCode})`,
      `<b>Level:</b> ${level}`,
      `<b>Time:</b> ${fmtTime(ms)}`,
    ];
    await notifyTeacher(msg);
  }
);

// ── 2) CLASS BOARD POSTS → notify teacher + students in class ─────────────────
exports.onClassBoardPost = onDocumentCreated(
  {
    region: "us-central1",
    document: "class_board/{className}/posts/{postId}",
    secrets: [BOT_TOKEN, TEACHER_CHAT_ID],
  },
  async (event) => {
    const data = event.data?.data() || {};
    const className = event.params.className;

    const title = pickTitle(data, event.params.postId);
    const studentName = data.student_name || data.author || "(unknown)";
    const studentCode = data.student_code || "";

    // Notify teacher
    await notifyTeacher([
      "🧾 <b>Class board post</b>",
      `<b>Class:</b> ${className}`,
      `<b>Title:</b> ${title}`,
      `<b>By:</b> ${studentName}${studentCode ? ` (${studentCode})` : ""}`,
      `<b>Time:</b> ${fmtTime(bestTimeMs(data, event.data))}`,
    ]);

    // DM every member of this class who has chat_id in roster
    try {
      const snap = await db.collection("roster").where("class_board", "==", className).get();
      if (!snap.empty) {
        const text =
          `🛎️ <b>${className}</b>\n` +
          `New post: <b>${title}</b>\n` +
          (data.summary ? `${data.summary}\n` : "");
        const sends = [];
        snap.forEach((doc) => {
          const chatId = doc.data()?.chat_id;
          if (chatId) sends.push(sendTelegramText(chatId, text));
        });
        if (sends.length) await Promise.allSettled(sends);
      }
    } catch (e) {
      console.error("DM class members error:", e?.message || e);
    }
  }
);

// ── 3) SYNC SHEETS (Roster & Scores) → Firestore ─────────────────────────────
async function getSheetsValues(spreadsheetId, range) {
  const auth = await google.auth.getClient({
    scopes: ["https://www.googleapis.com/auth/spreadsheets.readonly"],
  });
  const sheets = google.sheets({ version: "v4", auth });
  const res = await sheets.spreadsheets.values.get({ spreadsheetId, range });
  return res.data.values || [];
}

function indexHeaders(row) {
  const map = {};
  row.forEach((h, i) => (map[(h || "").toString().trim().toLowerCase()] = i));
  return (name) => {
    const key = (name || "").toLowerCase();
    const idx = map[key];
    return typeof idx === "number" ? idx : -1;
  };
}

exports.syncSheets = onSchedule(
  {
    region: "us-central1",
    schedule: "every 4 hours",
    timeZone: "Africa/Accra",
    secrets: [GSHEET_ROSTER_ID, GSHEET_ROSTER_RANGE, GSHEET_SCORES_ID, GSHEET_SCORES_RANGE],
  },
  async () => {
    // --- Roster ---
    try {
      const rosterValues = await getSheetsValues(GSHEET_ROSTER_ID.value(), GSHEET_ROSTER_RANGE.value());
      if (rosterValues.length) {
        const h = indexHeaders(rosterValues[0]);
        for (let i = 1; i < rosterValues.length; i++) {
          const r = rosterValues[i] || [];
          const code = r[h("studentcode")] || r[h("student_code")] || r[h("code")] || "";
          if (!code) continue;
          const name = r[h("name")] || "";
          const level = r[h("level")] || "";
          const className = r[h("classname")] || r[h("class")] || "";
          const phone = r[h("phone")] || "";
          const email = r[h("email")] || "";

          await db.collection("roster").doc(String(code)).set(
            {
              student_code: String(code),
              name,
              level,
              class_board: className,
              phone,
              email,
              // `chat_id` gets filled by /register
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        }
      }
    } catch (e) {
      console.error("Roster sync error:", e?.message || e);
    }

    // --- Scores (optional DM if chat_id exists) ---
    try {
      const scoresValues = await getSheetsValues(GSHEET_SCORES_ID.value(), GSHEET_SCORES_RANGE.value());
      if (scoresValues.length) {
        const h = indexHeaders(scoresValues[0]);
        for (let i = 1; i < scoresValues.length; i++) {
          const r = scoresValues[i] || [];
          const code = (r[h("studentcode")] || r[h("student_code")] || "").toString().trim();
          if (!code) continue;

          const title = (r[h("assignment")] || r[h("title")] || "").toString().trim();
          const score = (r[h("score")] || "").toString().trim();
          const comments = (r[h("comments")] || "").toString().trim();
          const date = (r[h("date")] || "").toString().trim();
          const level = (r[h("level")] || "").toString().trim();
          const link = (r[h("link")] || "").toString().trim();

          const fingerprint = crypto
            .createHash("sha1")
            .update([code, title, score, comments, date].join("|"))
            .digest("hex");

          const docRef = db.collection("scores").doc(code).collection("items").doc(fingerprint);
          const exists = await docRef.get();
          if (exists.exists) continue;

          await docRef.set({
            student_code: code,
            title,
            score,
            comments,
            date,
            level,
            link,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
          });

          // DM the student if registered
          const chatId = await chatIdForStudentCode(code);
          if (chatId) {
            const lines = [
              "📊 <b>New score</b>",
              `<b>Assignment:</b> ${title || "(untitled)"}`,
              `<b>Score:</b> ${score || "-"}`,
              comments ? `<b>Comments:</b> ${comments}` : "",
              date ? `<b>Date:</b> ${date}` : "",
              level ? `<b>Level:</b> ${level}` : "",
            ].filter(Boolean);
            await sendTelegramText(chatId, lines.join("\n"));
          }
        }
      }
    } catch (e) {
      console.error("Scores sync error:", e?.message || e);
    }
  }
);

// ── 4) Telegram webhook (PUBLIC) + simple commands ───────────────────────────
exports.telegramWebhook = onRequest(
  { region: "us-central1", invoker: "public", secrets: [BOT_TOKEN, WEBHOOK_SECRET] },
  async (req, res) => {
    try {
      // Optional shared-secret header check (only if the secret is set)
      const expected = (WEBHOOK_SECRET.value && WEBHOOK_SECRET.value()) || "";
      if (expected) {
        const got = req.get("X-Telegram-Bot-Api-Secret-Token") || "";
        if (got !== expected) return res.status(401).send("unauthorized");
      }

      // ACK first so Telegram doesn't retry
      res.status(200).send("ok");

      const update = req.body || {};
      const msg = update.message || update.edited_message || null;
      if (!msg) return;

      const chatId = msg.chat?.id;
      const text = (msg.text || "").trim();

      // Commands
      if (/^\/start\b/i.test(text) || /^\/help\b/i.test(text)) {
        const h =
          "<b>Welcome!</b>\n" +
          "Use <code>/register &lt;StudentCode&gt;</code> to link your account.\n" +
          "Commands: <code>/register</code>, <code>/id</code>, <code>/stop</code>, <code>/help</code>";
        return sendTelegramText(chatId, h);
      }

      if (/^\/id\b/i.test(text)) {
        return sendTelegramText(chatId, `<b>Your chat id:</b> <code>${chatId}</code>`);
      }

      if (/^\/stop\b/i.test(text)) {
        await db.collection("telegram_users").doc(String(chatId)).set(
          { chat_id: String(chatId), active: false, stopped_at: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        );
        return sendTelegramText(chatId, "You are unsubscribed. Send /register to subscribe again.");
      }

      const reg = /^\/register\s+([A-Za-z0-9_-]+)\s*$/i.exec(text);
      if (reg) {
        const code = reg[1];
        // Save mapping
        await db.collection("telegram_users").doc(String(chatId)).set(
          {
            chat_id: String(chatId),
            student_code: String(code),
            active: true,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        // Also mirror onto roster doc if present
        await db.collection("roster").doc(String(code)).set(
          {
            student_code: String(code),
            chat_id: String(chatId),
            chat_linked_at: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        await sendTelegramText(chatId, `✅ Registered. StudentCode: <b>${code}</b>`);
        // Let teacher know
        await notifyTeacher([`👤 Student linked: <b>${code}</b> (chat: ${chatId})`]);
        return;
      }

      // Fallback echo for unknown text
      if (/^\/.+/.test(text)) {
        return sendTelegramText(chatId, "Unknown command. Try /help");
      }
    } catch (e) {
      // Always OK to Telegram
      try { res.status(200).send("ok"); } catch (_) {}
      console.error("telegramWebhook error:", e?.message || e);
    }
  }
);
