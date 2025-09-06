/**
 * Falowen Automations — Balance & Payment Reminders (Complete)
 *
 * Replaces the Announcement blaster with:
 *  1) Balance-change email notifier
 *  2) 15‑day payment reminder after ContractStart if balance > 0 (auto-termination warning)
 *  3) Final notice after ContractEnd if balance > 0 (no carry-over; full payment required to join a new class)
 *  4) Follow-up email after Welcome with Telegram notifications guide and Class Calendar reminders
 *
 * Students sheet should include (case-insensitive OK):
 *   Name | Level | StudentCode | Email | Balance | ContractStart | ContractEnd | EnrollDate | ClassName | (optional Contract Link)
 */

/************ CONFIG ************/
const SCORES_CSV_URL   = 'https://docs.google.com/spreadsheets/d/1BRb8p3Rq0VpFCLSwL4eS9tSgXBo9hSWzfW_J_7W36NQ/export?format=csv&gid=2121051612';
const STUDENTS_CSV_URL = 'https://docs.google.com/spreadsheets/d/12NXf5FeVHr7JJT47mRHh7Jp-TC1yhPS7ZG6nzZVTt1U/export?format=csv&gid=104087906';

const TZ           = 'Africa/Accra';
const SENDER_NAME  = 'Learn Language Education Academy';
const SENDER_EMAIL = 'Learngermanghana@gmail.com';

const APP_LINK            = 'https://www.falowen.app';
const MY_RESULTS_TAB_LINK = 'https://www.falowen.app/?tab=My+Results+and+Resources';
const MY_COURSE_TAB_LINK  = 'https://www.falowen.app/?tab=My+Course';
const LOGO_URL            = 'https://i.imgur.com/7uJRrbr.png';  // your logo

// Onboarding copy (used in welcome)
const ONBOARDING_STEPS_HTML =
  'Go to <a href="' + APP_LINK + '">' + APP_LINK + '</a>, click <b>Create Account</b>, use your registered ' +
  '<b>email</b> and <b>student code</b>, set a unique password, then <b>log in to start learning</b>. ' +
  'Use <b>My Results</b> to view your scores when they’re posted.';

/************ BEHAVIOR ************/
const LOOKBACK_HOURS       = 15;   // new scores scan window
const ENROLL_LOOKBACK_DAYS = 14;   // welcome only recent enrolments (if date exists)
const MAX_KEYS_STORED      = 6000; // de-dupe memory size

// Balance & Payments behavior
const BALANCE_SCAN_MINUTES = 15; // how often balance changes are checked (via trigger)
const PAYMENT_REMINDER_DAYS_AFTER_START = 15; // first reminder after ContractStart

/* ================= MENU & TRIGGERS ================= */
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Falowen Automations')
    .addItem('Install/Refresh Triggers', 'installTriggers')
    .addSeparator()
    .addItem('Run: New Scores Now', 'newScoresWatcherJob')
    .addItem('Run: Weekly Summary Now', 'weeklySummaryJob')
    .addItem('Run: Welcome Check Now', 'newStudentsWatcherJob')
    .addItem('Run: Balance Change Scan Now', 'balanceWatcherJob')
    .addItem('Run: Payment Reminders Now', 'paymentRemindersJob')
    .addItem('Process Outbox Now', 'processOutboxJob')
    .addItem('Check Email Quota', 'logQuota_')
    .addSeparator()
    .addItem('Resend Welcome (prompt)', 'promptResendWelcome')
    .addSeparator()
    .addItem('Debug: Force Rescan', 'debugForceRescan')
    .addToUi();
}

// Self-healing installs: creates missing triggers (safe to run anytime)
function ensureTrigger_(fn, builderFn) {
  var exists = ScriptApp.getProjectTriggers().some(function(t){ return t.getHandlerFunction() === fn; });
  if (!exists) {
    builderFn().create();
    Logger.log('Created trigger → %s', fn);
  } else {
    Logger.log('Trigger already exists → %s', fn);
  }
}

function installTriggers() {
  // ScriptApp.getProjectTriggers().forEach(function(t){ ScriptApp.deleteTrigger(t); }); // optional reset
  ensureTrigger_('newScoresWatcherJob',   function(){ return ScriptApp.newTrigger('newScoresWatcherJob').timeBased().everyMinutes(15); });
  ensureTrigger_('processOutboxJob',      function(){ return ScriptApp.newTrigger('processOutboxJob').timeBased().everyMinutes(15); });
  ensureTrigger_('weeklySummaryJob',      function(){ return ScriptApp.newTrigger('weeklySummaryJob').timeBased().onWeekDay(ScriptApp.WeekDay.MONDAY).atHour(8); });
  ensureTrigger_('newStudentsWatcherJob', function(){ return ScriptApp.newTrigger('newStudentsWatcherJob').timeBased().everyMinutes(15); });

  // Replacement for announcements: balance/payment triggers
  ensureTrigger_('balanceWatcherJob',     function(){ return ScriptApp.newTrigger('balanceWatcherJob').timeBased().everyMinutes(BALANCE_SCAN_MINUTES); });
  ensureTrigger_('paymentRemindersJob',   function(){ return ScriptApp.newTrigger('paymentRemindersJob').timeBased().everyDays(1).atHour(8); });

  listTriggers_();
  try { SpreadsheetApp.getActiveSpreadsheet().toast('Triggers checked/installed. See Logs.', 'Falowen', 5); } catch(e){}
}

/* ================= MAIN JOBS ================= */
// 1) Weekly summary (runs weekly)
function weeklySummaryJob() {
  var data = loadData_();
  var now = new Date();
  var since = new Date(now.getTime() - 7*24*60*60*1000);
  var byStudent = groupByStudent_(data.scores, data.students);

  for (var key in byStudent) {
    var s = byStudent[key];
    if (!s.email) continue;
    var weekRows = s.rows.filter(function(r){ return r.date && r.date >= since; });
    if (!weekRows.length) continue;

    var avg = avgScore_(weekRows);
    var completed = uniqueCount_(weekRows.map(function(r){ return r.assignment; }));
    var nxt = skippedAndNext_(s.level, s.rows);

    var inner = renderWeeklyInner_(s.name, s.level, weekRows, avg, completed, nxt.skipped, nxt.nextTask, since, now);
    var html  = renderEmailShell_('Your Weekly Progress — ' + s.level, inner);
    sendOrQueueEmail_(s.email, 'Your Weekly Progress — ' + s.level + ' (' + fmt_(now) + ')', html);
  }
}

// 2) New scores (runs every 15 min)
function newScoresWatcherJob() {
  var props = PropertiesService.getScriptProperties();
  var lastISO = props.getProperty('LAST_PROCESSED_ISO') || '1970-01-01T00:00:00Z';
  var lastProcessed = new Date(lastISO);
  var now = new Date();
  var windowStart = new Date(now.getTime() - LOOKBACK_HOURS*60*60*1000);

  var data = loadData_();
  var scores = data.scores, students = data.students;

  var directory = {}; students.forEach(function(s){ directory[s.student_code] = s; });
  var processedSet = loadProcessedSet_();

  var todayKey = Utilities.formatDate(now, 'UTC', 'yyyy-MM-dd'); // Accra == UTC
  var candidates = scores.filter(function(r) {
    if (!r.date) return false;
    var rKey = Utilities.formatDate(r.date, 'UTC', 'yyyy-MM-dd');
    return (r.date > lastProcessed) || (r.date >= windowStart) || (rKey === todayKey);
  });

  Logger.log('scores=%s, lastProcessed=%s, lookback=%sh, today=%s, candidates=%s',
             scores.length, lastProcessed.toISOString(), LOOKBACK_HOURS, todayKey, candidates.length);

  if (!candidates.length) {
    props.setProperty('LAST_PROCESSED_ISO', now.toISOString());
    return;
  }

  var byKey = {};
  var maxDate = lastProcessed;

  candidates.forEach(function(r) {
    var dateKey = r.date ? Utilities.formatDate(r.date, 'UTC', 'yyyy-MM-dd') : 'nodate';
    // fingerprint includes comments+link so edits re-trigger
    var fingerprint = shortHash_((r.comments||'') + '|' + (r.link||''));
    var uniqueKey = [r.student_code, (r.level||'').toUpperCase(), r.assignment, dateKey, fingerprint].join('|');
    if (processedSet[uniqueKey]) return;

    var grp = r.student_code + '|' + (r.level||'').toUpperCase();
    if (!byKey[grp]) { byKey[grp] = []; }
    byKey[grp].push({row:r, uniqueKey:uniqueKey});

    if (r.date && r.date > maxDate) maxDate = r.date;
  });

  var sentCount = 0;
  for (var grp in byKey) {
    var parts = grp.split('|');
    var scode = parts[0], lvl = parts[1];
    var sInfo = directory[scode];
    if (!sInfo || !sInfo.email) continue;

    var bundle = byKey[grp];
    var justAdded = bundle.map(function(b){ return b.row; });

    var allForStudent = scores.filter(function(r){ return r.student_code===scode && ((r.level||'').toUpperCase()===lvl); });
    var nxt = skippedAndNext_(lvl, allForStudent);
    var avg = avgScore_(justAdded);

    var inner = renderNewScoresInner_(sInfo.name, lvl, justAdded, avg, nxt.nextTask);
    var html  = renderEmailShell_('New Results Posted — ' + lvl, inner);
    var ok = sendOrQueueEmail_(sInfo.email, 'New Results Posted — ' + lvl, html);
    if (ok) {
      bundle.forEach(function(b){ processedSet[b.uniqueKey] = 1; });
      sentCount++;
    }
  }

  saveProcessedSet_(processedSet);
  props.setProperty('LAST_PROCESSED_ISO', (maxDate && maxDate.toISOString()) || now.toISOString());
  Logger.log('New-scores emails sent: ' + sentCount);
}

// 3) New students welcome (runs every 15 min). Sends ONCE per student_code, only if NO assignments yet.
function newStudentsWatcherJob() {
  var props = PropertiesService.getScriptProperties();
  var raw = props.getProperty('PROCESSED_STUDENTS') || '{}';
  var processed = {};
  try { processed = JSON.parse(raw) || {}; } catch(e){ processed = {}; }

  var now = new Date();
  var enrollWindowStart = new Date(now.getTime() - ENROLL_LOOKBACK_DAYS*24*60*60*1000);

  // Load data once
  var data = loadData_();
  var scores = data.scores;
  var students = data.students;

  // Build lookup of who already has any score
  var hasScore = {};
  scores.forEach(function(r){ if (r.student_code) hasScore[r.student_code] = true; });

  var sent = 0;

  students.forEach(function(s){
    if (!s.student_code || !s.email) return;

    // Only welcome if student has NO assignment rows yet
    if (hasScore[s.student_code]) return;

    var already = processed[s.student_code];
    // If welcomed before, only resend if email changed
    if (already && already.email === s.email) return;

    // Guard by recent enroll date if present
    if (s.enroll_date && s.enroll_date < enrollWindowStart) return;

    var inner = renderWelcomeInner_(s.name, s.email, s.student_code, s.level, s.contract_link, s.class_name);
    var html  = renderEmailShell_('Welcome to Falowen', inner);
    var ok = sendOrQueueEmail_(s.email, 'Welcome to Learn Language Education Academy', html);
    if (ok) {
      // Follow-up message: Telegram notifications + Class calendar reminders
      var inner2 = renderNotifySetupInner_(s.name, s.student_code);
      var html2  = renderEmailShell_('Get Notifications & Class Reminders', inner2);
      sendOrQueueEmail_(s.email, 'Set Up Notifications & Class Calendar', html2);

      processed[s.student_code] = { email: s.email, welcomed_at: new Date().toISOString() };
      sent++;
    }
  });

  props.setProperty('PROCESSED_STUDENTS', JSON.stringify(processed));
  Logger.log('Welcome emails sent: ' + sent);
}

/* ================= NEW: BALANCE CHANGE WATCHER ================= */
// Detects changes in the Balance column of the Students sheet and notifies the student.
function balanceWatcherJob() {
  var students = loadStudents_();
  var dir = {}; students.forEach(function(s){ dir[s.student_code] = s; });

  var map = loadBalanceMap_(); // { code: lastBalanceNumber }
  var updated = 0;

  students.forEach(function(s){
    if (!s.student_code || !s.email) return;
    // Treat missing balance as 0
    var current = (typeof s.balance === 'number' && !isNaN(s.balance)) ? s.balance : 0;
    var prev = map[s.student_code];

    // If we have no previous record, initialize without emailing to avoid a flood
    if (typeof prev === 'undefined') {
      map[s.student_code] = current;
      return;
    }

    if (Number(prev) !== Number(current)) {
      var inner = renderBalanceUpdateInner_(s.name || 'Student', current);
      var html  = renderEmailShell_('Your Balance Has Been Updated', inner);
      var ok = sendOrQueueEmail_(s.email, 'Balance Update — Learn Language Education Academy', html);
      if (ok) {
        map[s.student_code] = current;
        updated++;
      }
    }
  });

  saveBalanceMap_(map);
  Logger.log('Balance updates emailed: ' + updated);
}

function renderBalanceUpdateInner_(name, balance) {
  var balText = (balance > 0)
    ? '<b>Outstanding Balance:</b> GHS ' + Number(balance).toFixed(2)
    : '<b>Balance:</b> GHS 0.00 (Paid) ✅';

  return [
    '<p>Hi ' + escape_(name) + ',</p>',
    '<p>Your account balance has been <b>updated</b>.</p>',
    '<p>' + balText + '</p>',
    '<p>To download your <b>receipt</b>, open <a href="' + MY_RESULTS_TAB_LINK + '" target="_blank">My Results & Resources → Downloads</a> in the Falowen app.</p>',
    '<p>If you believe there is an error, reply to this email and we will assist.</p>',
    '<p>— ' + SENDER_NAME + '</p>'
  ].join('');
}

/* ================= NEW: PAYMENT REMINDERS ================= */
// Runs daily @ 08:00 Accra.
function paymentRemindersJob() {
  var props = PropertiesService.getScriptProperties();
  var firstMap = loadJsonMap_(props.getProperty('PAY_REMIND_15') || '{}');   // codes that got 15-day reminder
  var finalMap = loadJsonMap_(props.getProperty('PAY_FINAL') || '{}');       // codes that got final notice

  var today = new Date();
  var students = loadStudents_();
  var sentFirst = 0, sentFinal = 0;

  students.forEach(function(s){
    if (!s.student_code || !s.email) return;
    var bal = (typeof s.balance === 'number' && !isNaN(s.balance)) ? s.balance : 0;
    var start = s.contract_start; // Date or null
    var end   = s.contract_end;   // Date or null

    // 1) 15-day reminder after ContractStart if balance > 0
    if (bal > 0 && start instanceof Date) {
      var daysSinceStart = Math.floor((today - start) / (24*60*60*1000));
      if (daysSinceStart >= PAYMENT_REMINDER_DAYS_AFTER_START && !firstMap[s.student_code]) {
        var inner1 = renderPay15Inner_(s.name || 'Student', bal, start);
        var html1  = renderEmailShell_('Payment Reminder — ' + s.level, inner1);
        var ok1 = sendOrQueueEmail_(s.email, 'Payment Reminder — Action Required', html1);
        if (ok1) { firstMap[s.student_code] = new Date().toISOString(); sentFirst++; }
      }
    }

    // 2) Final notice when ContractEnd passed and balance > 0
    if (bal > 0 && end instanceof Date) {
      var pastEnd = today.getTime() > end.getTime();
      if (pastEnd && !finalMap[s.student_code]) {
        var inner2 = renderFinalNoticeInner_(s.name || 'Student', bal, end);
        var html2  = renderEmailShell_('Final Notice — Contract Ended', inner2);
        var ok2 = sendOrQueueEmail_(s.email, 'Final Notice — Full Payment Required to Join New Class', html2);
        if (ok2) { finalMap[s.student_code] = new Date().toISOString(); sentFinal++; }
      }
    }
  });

  props.setProperty('PAY_REMIND_15', JSON.stringify(firstMap));
  props.setProperty('PAY_FINAL', JSON.stringify(finalMap));
  Logger.log('Payment reminders sent — 15-day: ' + sentFirst + ' | final: ' + sentFinal);
}

function renderPay15Inner_(name, balance, startDate) {
  return [
    '<p>Hi ' + escape_(name) + ',</p>',
    '<p>This is a friendly reminder that <b>15 days</b> have passed since your contract started (<b>' + fmt_(startDate) + '</b>).</p>',
    '<p>You still have an <b>outstanding balance</b> of <b>GHS ' + Number(balance).toFixed(2) + '</b>. Please make your payment.</p>',
    '<div style="margin:12px 0;padding:10px;border:1px solid #fecaca;background:#fef2f2;border-radius:10px;">',
      '<b>Important:</b> If payment is not made, your access to the Falowen app will <b>automatically terminate</b>.',
    '</div>',
    '<p>You can download your <b>receipt</b> anytime from <a href="' + MY_RESULTS_TAB_LINK + '" target="_blank">My Results & Resources → Downloads</a>.</p>',
    '<p>If you need help, reply to this email.</p>',
    '<p>— ' + SENDER_NAME + '</p>'
  ].join('');
}

function renderFinalNoticeInner_(name, balance, endDate) {
  return [
    '<p>Hi ' + escape_(name) + ',</p>',
    '<p>Your contract <b>expired</b> on <b>' + fmt_(endDate) + '</b>.</p>',
    '<p>Your account still shows an <b>outstanding balance</b> of <b>GHS ' + Number(balance).toFixed(2) + '</b>. Please settle this balance.</p>',
    '<div style="margin:12px 0;padding:10px;border:1px solid #fecaca;background:#fef2f2;border-radius:10px;">'
      + '<b>Policy clarification:</b> If you return <i>while your contract is still active</i>, you may pay the outstanding amount and continue in the same class. '
      + 'However, once the class ends / the contract has expired, previous partial payments do <b>not</b> carry over. To join a <b>new class</b>, you must make a <b>full payment for the new class</b>.'
    + '</div>',
    '<p>You may download receipts from <a href="' + MY_RESULTS_TAB_LINK + '" target="_blank">My Results & Resources → Downloads</a>.</p>',
    '<p>Reply to this email if you have questions or need assistance.</p>',
    '<p>— ' + SENDER_NAME + '</p>'
  ].join('');
}

/* ============ Manual helpers ============ */
function promptResendWelcome() {
  var ui = SpreadsheetApp.getUi();
  var resp = ui.prompt('Resend Welcome', 'Enter student_code (e.g., felixa1):', ui.ButtonSet.OK_CANCEL);
  if (resp.getSelectedButton() !== ui.Button.OK) return;
  var scode = normalizeCode_(resp.getResponseText());

  var students = loadStudents_();
  var s = students.find(function(x){ return x.student_code === scode; });
  if (!s || !s.email) { ui.alert('Not found or missing email.'); return; }

  var inner = renderWelcomeInner_(s.name, s.email, s.student_code, s.level, s.contract_link, s.class_name);
  var html  = renderEmailShell_('Welcome to Falowen', inner);
  var ok = sendOrQueueEmail_(s.email, 'Welcome to Learn Language Education Academy', html);
  if (ok) {
    // Follow-up message: Telegram notifications + Class calendar reminders
    var inner2 = renderNotifySetupInner_(s.name, s.student_code);
    var html2  = renderEmailShell_('Get Notifications & Class Reminders', inner2);
    sendOrQueueEmail_(s.email, 'Set Up Notifications & Class Calendar', html2);
  }
  ui.alert(ok ? 'Welcome email sent.' : 'Send failed. Check logs.');
}

// Force a rescan of recent rows (clears state)
function debugForceRescan() {
  var props = PropertiesService.getScriptProperties();
  props.deleteProperty('LAST_PROCESSED_ISO');
  props.deleteProperty('PROCESSED_SET');
  props.deleteProperty('PROCESSED_STUDENTS');
  // New state stores for payment/balance
  props.deleteProperty('BALANCE_MAP');
  props.deleteProperty('PAY_REMIND_15');
  props.deleteProperty('PAY_FINAL');
  Logger.log('Reset done: will scan fresh on next run.');
}

/* ================= DATA LAYER ================= */
function loadData_() {
  var scores = csvToObjects_(fetchCSV_(SCORES_CSV_URL)).map(function(row){
    var sc = (row.student_code || row.studentcode || '').toString();
    return normalizeScoreRow_({
      student_code: sc, name: row.name, assignment: row.assignment, score: row.score,
      comments: row.comments, date: row.date, level: row.level, link: row.link
    });
  }).filter(function(r){ return r.student_code && r.assignment && r.level; });

  var students = loadStudents_();
  return {scores: scores, students: students};
}

function loadStudents_() {
  // Accepts: Name | Level | StudentCode | Email | Balance | ContractStart | ContractEnd | EnrollDate | ClassName | (optional contract link columns)
  var rows = csvToObjects_(fetchCSV_(STUDENTS_CSV_URL));
  return rows.map(function(row){
    var sc = (row.student_code || row.studentcode || row.code || row['student code'] || '').toString();
    var contractLink = row.contract || row.contractlink || row['contract link'] || row.contract_url || row['contract url'] || row.contractpdf || row['contract pdf'] || '';
    var enrollDate   = parseDate_(row.enrolldate || row['enroll date'] || row['enrollment date'] || row.enrolled || '');
    var className    = (row.class || row.classname || row['class name'] || row['class_name'] || '').toString().trim();

    // New fields
    var contractStart = parseDate_(row.contractstart || row['contract start'] || row.contract_begin || row['contract begin'] || '');
    var contractEnd   = parseDate_(row.contractend   || row['contract end']   || row.contract_stop  || row['contract stop']   || '');
    var balanceRaw    = row.balance || row['amount due'] || row['balance due'] || row.outstanding || row['outstanding balance'] || '';
    var balance       = (balanceRaw === '' || balanceRaw == null) ? 0 : Number(String(balanceRaw).toString().replace(/[\,\s]/g,'').replace(/GHS/i,''));
    if (isNaN(balance)) balance = 0;

    return {
      student_code: normalizeCode_(sc),
      name: (row.name || '').toString().trim(),
      level: ((row.level || '') + '').toUpperCase().trim(),
      email: (row.email || row['email address'] || '').toString().trim(),
      contract_link: (contractLink || '').toString().trim(),
      enroll_date: enrollDate,
      class_name: className,
      contract_start: contractStart,
      contract_end: contractEnd,
      balance: balance
    };
  });
}

function fetchCSV_(url) {
  var res = UrlFetchApp.fetch(url, {muteHttpExceptions:true});
  if (res.getResponseCode() !== 200) throw new Error('Failed to fetch CSV: ' + res.getResponseCode());
  return res.getContentText();
}

function csvToObjects_(csvText) {
  var rows = Utilities.parseCsv(csvText);
  if (!rows.length) return [];
  var headers = rows[0].map(function(h){ return (h||'').toString().trim().toLowerCase(); });
  return rows.slice(1).map(function(r){
    var o = {};
    headers.forEach(function(h,i){ o[h] = r[i]; });
    return o;
  });
}

function normalizeScoreRow_(row) {
  var sc = (row.student_code || '').toString();
  var lvl = ((row.level || '') + '').toUpperCase().trim();
  var score = parseFloat(row.score);
  var date = parseDate_(row.date);
  return {
    student_code: normalizeCode_(sc),
    name: (row.name || '').toString().trim(),
    assignment: (row.assignment || '').toString().trim(),
    score: isNaN(score) ? null : score,
    date: date,
    level: lvl,
    comments: (row.comments || '').toString().trim(),
    link: (row.link || '').toString().trim()
  };
}

function normalizeCode_(v) {
  return String(v||'').trim().toLowerCase().replace(/\s+/g,'');
}

function parseDate_(v) {
  if (!v) return null;
  var s = String(v).trim();
  var try1 = new Date(s);
  if (!isNaN(try1.getTime())) return try1;
  var m = s.match(/^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})/);
  if (m) {
    var d = Number(m[1]), mo = Number(m[2])-1, yy = Number(m[3]);
    var y = (yy < 100) ? Number('20' + (yy < 10 ? '0' + yy : yy)) : yy;
    return new Date(y, mo, d);
  }
  return null;
}

function groupByStudent_(scores, students) {
  var directory = {}; students.forEach(function(s){ directory[s.student_code] = s; });
  var grouped = {};
  scores.forEach(function(r) {
    var s = directory[r.student_code] || {};
    var key = r.student_code + '|' + r.level;

    if (!grouped[key]) {
      grouped[key] = {
        student_code: r.student_code,
        level: r.level,
        name: (s.name || r.name || '(No Name)'),
        email: (s.email || ''),
        rows: []
      };
    }
    grouped[key].rows.push(r);
  });
  return grouped;
}

function avgScore_(rows) {
  var vals = rows.map(function(r){ return Number(r.score); }).filter(function(x){ return !isNaN(x); });
  return vals.length ? vals.reduce(function(a,b){ return a+b; }, 0) / vals.length : null;
}

function uniqueCount_(arr) { var m={}; arr.forEach(function(x){ m[x]=1; }); return Object.keys(m).length; }

function skippedAndNext_(level, allRows) {
  var LEVEL_SCHEDULES = {}; // optional: paste schedules
  var schedule = LEVEL_SCHEDULES[level] || [];
  var done = {};
  allRows.forEach(function(r){ extractNums_(r.assignment).forEach(function(n){ done[n]=1; }); });
  var completed = Object.keys(done).map(Number);
  var lastNum = completed.length ? Math.max.apply(null, completed) : 0;

  var skipped = [];
  schedule.forEach(function(lesson){
    var nums = extractNums_(lesson.chapter||'');
    var hasAssn = !!lesson.assignment;
    for (var i=0;i<nums.length;i++){
      var n = nums[i];
      if (hasAssn && n < lastNum && !done[n]) { skipped.push('Day ' + (lesson.day||'?') + ': ' + lesson.chapter + ' – ' + (lesson.topic||'')); break; }
    }
  });

  var nextTask = null;
  for (var j=0;j<schedule.length;j++){
    var lesson = schedule[j];
    var topic = String(lesson.topic||'').toLowerCase();
    if (topic.indexOf('schreiben')>=0 && topic.indexOf('sprechen')>=0) continue;
    var nArr = extractNums_(lesson.chapter||''); var n = nArr.length ? Math.max.apply(null, nArr) : null;
    if (n && n > lastNum) { nextTask = 'Day ' + (lesson.day||'?') + ': ' + lesson.chapter + ' – ' + (lesson.topic||''); break; }
  }
  return {skipped:skipped, nextTask:nextTask};
}

function extractNums_(t){ var m = String(t||'').match(/\d+(?:\.\d+)?/g); return m?m.map(Number):[]; }

/* ================= BRANDING: EMAIL LAYOUT ================= */
function renderEmailShell_(titleText, bodyHtml) {
  var styles =
    'font-family:Arial,Helvetica,sans-serif;color:#111;line-height:1.6;background:#f6f8fb;margin:0;padding:0;';
  var cardStyle =
    'max-width:620px;margin:24px auto;background:#ffffff;border-radius:14px;box-shadow:0 6px 20px rgba(0,0,0,0.06);overflow:hidden;';
  var headerStyle = 'text-align:center;padding:24px 20px 10px 20px;background:#ffffff;';
  var logoStyle = 'width:120px;height:auto;';
  var titleStyle = 'font-size:22px;font-weight:700;margin:10px 0 0 0;color:#0f172a;';
  var contentStyle = 'padding:18px 22px 8px 22px;font-size:15px;';
  var footerStyle = 'padding:14px 22px 26px 22px;font-size:12px;color:#475569;text-align:center;';
  var ctaWrapStyle = 'text-align:center;padding:12px 22px 22px 22px;';
  var ctaStyle =
    'display:inline-block;padding:12px 18px;border-radius:10px;text-decoration:none;background:#2563eb;color:#fff;font-weight:600;';

  var html =
    '<!doctype html><html><head><meta name="viewport" content="width=device-width"/><meta charset="UTF-8"/></head>' +
    '<body style="' + styles + '">' +
      '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">' +
        '<tr><td>' +
          '<div style="' + cardStyle + '">' +
            '<div style="' + headerStyle + '">' +
              '<img src="' + LOGO_URL + '" alt="Falowen" style="' + logoStyle + '"/>' +
              '<h1 style="' + titleStyle + '">' + escape_(titleText) + '</h1>' +
            '</div>' +
            '<div style="' + contentStyle + '">' + bodyHtml + '</div>' +
            '<div style="' + ctaWrapStyle + '">' +
              '<a href="' + APP_LINK + '" style="' + ctaStyle + '">Go to Falowen App</a>' +
            '</div>' +
            '<div style="' + footerStyle + '">' +
              'Need help? Reply to this email • © ' + (new Date().getFullYear()) + ' ' + SENDER_NAME +
            '</div>' +
          '</div>' +
        '</td></tr>' +
      '</table>' +
    '</body></html>';
  return html;
}

/* ================= EMAIL CONTENT (BRANDED) ================= */
function scoreLabel_(score) {
  var s = Number(score);
  if (isNaN(s)) return '';
  if (s >= 90) return 'Excellent 🌟';
  if (s >= 75) return 'Good 👍';
  if (s >= 60) return 'Sufficient ✔️';
  return 'Needs Improvement ❗';
}

function motivationLine_(avg) {
  if (avg == null) return '';
  if (avg >= 85) return 'Outstanding work — keep pushing, you’re on fire! 🔥';
  if (avg >= 70) return 'Nice progress — a little more practice and you’ll level up fast! 💪';
  if (avg >= 55) return 'You’re getting there — keep at it and review the tricky parts. 📘';
  return 'Don’t worry — consistency wins. Let’s focus on last week’s topics and build up. 🌱';
}

function renderWeeklyInner_(name, level, weekRows, avg, completed, skipped, nextTask, since, now) {
  var items = weekRows
    .sort(function(a,b){ return b.date - a.date; })
    .slice(0, 6)
    .map(function(r){
      return '<li>' + escape_(r.assignment) + ' — <b>' + (r.score!=null?r.score:'—') + '</b> (' + fmt_(r.date) + ')</li>';
    }).join('');

  var skippedHtml = (skipped && skipped.length)
    ? '<p><b>Skipped assignments to catch up:</b></p><ul>' + skipped.slice(0,6).map(function(s){ return '<li>'+escape_(s)+'</li>'; }).join('') + (skipped.length>6?'<li>…and more</li>':'') + '</ul>'
    : '';

  var nextHtml = nextTask ? '<p><b>Next recommended task:</b><br>' + escape_(nextTask) + '</p>' : '';
  var mot = motivationLine_(avg);

  return [
    '<p>Hi ' + escape_(name) + ',</p>',
    '<p>Your weekly progress for <b>' + escape_(level) + '</b> (' + fmt_(since) + ' – ' + fmt_(now) + '):</p>',
    (mot ? '<p>' + mot + '</p>' : ''),
    '<ul><li><b>Assignments completed:</b> ' + completed + '</li><li><b>Average score:</b> ' + (avg!=null?avg.toFixed(1):'—') + '</li></ul>',
    (items ? '<p><b>Recent results:</b></p><ul>' + items + '</ul>' : ''),
    skippedHtml,
    nextHtml,
    '<p><i>Tip:</i> Use <b>My Results</b> in the app to review your posted scores.</p>',
    '<p>— ' + SENDER_NAME + '</p>'
  ].join('');
}

// New scores email: include Feedback and reference link per row
function renderNewScoresInner_(name, level, newRows, avg, nextTask) {
  var items = newRows
    .sort(function(a,b){ return b.date - a.date; })
    .map(function(r){
      var label = scoreLabel_(r.score);
      var feedback = escape_(r.comments || 'No feedback provided.');
      var ref = (r.link && r.link.trim()) ? ' <br><b>Lesen &amp; Hören Reference:</b> <a href="'+escape_(r.link)+'" target="_blank">Click here</a>' : '';
      return '<li><b>' + escape_(r.assignment) + '</b> — ' +
             '<b>' + (r.score!=null?r.score:'—') + '</b> ' + (label?('('+escape_(r.label||label)+')'):'') +
             ' (' + fmt_(r.date) + ')' +
             '<br><b>Feedback:</b> ' + feedback + ref + '</li>';
    }).join('');

  var mot = motivationLine_(avg);
  var nextHtml = nextTask ? '<p><b>Next recommended task:</b><br>' + escape_(nextTask) + '</p>' : '';

  return [
    '<p>Hi ' + escape_(name) + ',</p>',
    '<p>Your new results for <b>' + escape_(level) + '</b> are ready. Log in and keep learning!</p>',
    (mot ? '<p>' + mot + '</p>' : ''),
    '<ul>' + items + '</ul>',
    nextHtml,
    '<p><i>Tip:</i> Use <b>My Results</b> in the app to review your posted scores.</p>',
    '<p>— ' + SENDER_NAME + '</p>'
  ].join('');
}

// First welcome email — now includes Class Name when available
function renderWelcomeInner_(name, email, code, level, contractLink, className) {
  var contractLine = contractLink
    ? '<p>Your contract: <a href="' + escape_(contractLink) + '">' + escape_(contractLink) + '</a></p>'
    : '';
  var classLine = (className && String(className).trim())
    ? '<li>Class: <b>' + escape_(className) + '</b></li>'
    : '';
  return [
    '<p>Hello ' + escape_(name) + ',</p>',
    '<p>Welcome to <b>' + SENDER_NAME + '</b> and to <b>' + escape_(level) + '</b>!</p>',
    contractLine,
    '<p><b>Your account details</b></p>',
    '<ul>',
      '<li>Email: <b>' + escape_(email) + '</b></li>',
      '<li>Student Code: <b>' + escape_(code) + '</b></li>',
      classLine,
      '<li>You’ll set your own password during sign-up.</li>',
    '</ul>',
    '<p><b>Get started now</b></p>',
    '<ol><li>' + ONBOARDING_STEPS_HTML + '</li></ol>',
    '<p><b>Receipts &amp; Enrollment Letter:</b> In the app, open <b>My Results &amp; Resources</b>, then go to <b>Downloads</b> to download your <b>Receipt</b> and <b>Letter of Enrollment</b>. '
    + '<a href="' + MY_RESULTS_TAB_LINK + '" target="_blank">Open My Results &amp; Resources</a>.</p>',
    '<p>Questions? Just reply to this email — we’re here to help.</p>',
    '<p>— ' + SENDER_NAME + '</p>'
  ].join('');
}

// Second email after welcome: Notifications + Calendar setup (Telegram bot + Class calendar)
function renderNotifySetupInner_(name, code) {
  return [
    '<p>Hi ' + escape_(name) + ',</p>',
    '<p>To receive <b>automatic notifications</b> (results, reminders, updates) on <b>Telegram</b>, follow these 3 steps:</p>',
    '<ol>',
      '<li>Open this link on Telegram: <a href="https://t.me/falowenbot" target="_blank">https://t.me/falowenbot</a></li>',
      '<li>Click <b>Start</b></li>',
      '<li>Type: <code>/register ' + escape_(code) + '</code> (Example: <code>/register kwame202</code>)</li>',
    '</ol>',
    '<p>That’s it! You will now receive important updates directly on Telegram.</p>',
    '<hr style="border:none;border-top:1px solid #e5e7eb;margin:14px 0;"/>',
    '<p><b>Class reminders & Zoom link</b></p>',
    '<p>Go to <a href="' + MY_COURSE_TAB_LINK + '" target="_blank">My Course → Classroom → Calendar</a> and follow the instructions to add your class schedule to your calendar for <b>auto reminders</b>. '
    + 'The <b>Zoom link</b> is saved there as well.</p>',
    '<p>— ' + SENDER_NAME + '</p>'
  ].join('');
}

/* ================= SENDER & QUEUE ================= */
function sendEmailWithGmail(toEmail, subject, html) {
  if (!toEmail) return false;
  try {
    MailApp.sendEmail({
      to: toEmail,
      subject: subject,
      htmlBody: html,
      name: SENDER_NAME,
      replyTo: SENDER_EMAIL
    });
    Logger.log('Email sent → ' + toEmail + ' | ' + subject);
    return true;
  } catch (e) {
    Logger.log('Email error: ' + e);
    return false;
  }
}

// Outbox queue: sheet-backed
function getOutboxSheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName('Outbox');
  if (!sh) {
    sh = ss.insertSheet('Outbox');
    sh.appendRow(['status','to','subject','html','created_at','sent_at','error']);
  }
  return sh;
}

function enqueueEmail_(toEmail, subject, html) {
  if (!toEmail) return false;
  var sh = getOutboxSheet_();
  sh.appendRow(['PENDING', toEmail, subject, html, new Date().toISOString(), '', '']);
  return true;
}

// Wrapper: send now if quota allows, else queue
function sendOrQueueEmail_(toEmail, subject, html) {
  if (!toEmail) return false;
  try {
    var remaining = MailApp.getRemainingDailyQuota();
    if (remaining <= 0) {
      enqueueEmail_(toEmail, subject, html);
      Logger.log('Quota 0: queued → ' + toEmail);
      return true;
    }
    MailApp.sendEmail({
      to: toEmail,
      subject: subject,
      htmlBody: html,
      name: SENDER_NAME,
      replyTo: SENDER_EMAIL
    });
    Logger.log('Email sent → ' + toEmail + ' | ' + subject + ' | remaining: ' + (remaining-1));
    return true;
  } catch (e) {
    enqueueEmail_(toEmail, subject, html);
    Logger.log('Send failed; queued. ' + e);
    return false;
  }
}

function processOutboxJob() {
  var remaining = MailApp.getRemainingDailyQuota();
  if (remaining <= 0) {
    Logger.log('Outbox: quota 0, skipping.');
    return;
  }
  var sh = getOutboxSheet_();
  var data = sh.getDataRange().getValues();
  if (data.length <= 1) { Logger.log('Outbox empty.'); return; }

  var header = data[0];
  var rows = data.slice(1);
  var statusIdx = header.indexOf('status');
  var toIdx     = header.indexOf('to');
  var subjIdx   = header.indexOf('subject');
  var htmlIdx   = header.indexOf('html');
  var sentIdx   = header.indexOf('sent_at');
  var errIdx    = header.indexOf('error');

  var maxToSend = Math.min(remaining, 100); // soft cap per run
  var sent = 0;

  for (var i = 0; i < rows.length && sent < maxToSend; i++) {
    var r = rows[i];
    if (String(r[statusIdx]).toUpperCase() !== 'PENDING') continue;
    var rowNum = i + 2;

    try {
      MailApp.sendEmail({
        to: r[toIdx],
        subject: r[subjIdx],
        htmlBody: r[htmlIdx],
        name: SENDER_NAME,
        replyTo: SENDER_EMAIL
      });
      sh.getRange(rowNum, statusIdx+1).setValue('SENT');
      sh.getRange(rowNum, sentIdx+1).setValue(new Date().toISOString());
      sh.getRange(rowNum, errIdx+1).setValue('');
      sent++;
    } catch (e) {
      sh.getRange(rowNum, statusIdx+1).setValue('ERROR');
      sh.getRange(rowNum, errIdx+1).setValue(String(e));
    }
  }
  Logger.log('Outbox processed. Sent: ' + sent + ' | Remaining quota: ' + (MailApp.getRemainingDailyQuota()));
}

function logQuota_() {
  var remaining = MailApp.getRemainingDailyQuota();
  Logger.log('Remaining daily quota: ' + remaining + ' recipients');
  try { SpreadsheetApp.getActiveSpreadsheet().toast('Remaining daily quota: ' + remaining, 'Quota', 5); } catch(e){}
}

/* ================= UTILITIES ================= */
function fmt_(d){ return Utilities.formatDate(d, TZ, 'dd MMM yyyy'); }
function escape_(s){ return String(s||'').replace(/[&<>"]/g, function(m){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m]; }); }

// Short base64(MD5) hash, first 6 chars (for de-dupe fingerprints)
function shortHash_(s) {
  try {
    var bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, s || '');
    var b64 = Utilities.base64Encode(bytes);
    return b64.replace(/[^A-Za-z0-9]/g,'').substring(0,6);
  } catch(e) { return '000000'; }
}

function listTriggers_() {
  var rows = ScriptApp.getProjectTriggers().map(function(t){
    return [
      t.getHandlerFunction(),
      t.getTriggerSource(),
      t.getEventType(),
      t.getUniqueId()
    ].join(' | ');
  });
  Logger.log('\n' + rows.join('\n') + '\n');
}

function loadProcessedSet_() {
  var raw = PropertiesService.getScriptProperties().getProperty('PROCESSED_SET');
  if (!raw) return {};
  try {
    var arr = JSON.parse(raw);
    var out = {}; arr.forEach(function(k){ out[k]=1; });
    return out;
  } catch(e){ return {}; }
}
function saveProcessedSet_(setObj) {
  var keys = Object.keys(setObj);
  if (keys.length > MAX_KEYS_STORED) {
    keys = keys.slice(keys.length - MAX_KEYS_STORED);
    var trimmed = {}; keys.forEach(function(k){ trimmed[k]=1; });
    setObj = trimmed;
  }
  PropertiesService.getScriptProperties().setProperty('PROCESSED_SET', JSON.stringify(Object.keys(setObj)));
}

// === NEW: Balance map state helpers ===
function loadBalanceMap_(){
  var raw = PropertiesService.getScriptProperties().getProperty('BALANCE_MAP');
  if (!raw) return {};
  try { return JSON.parse(raw) || {}; } catch(e){ return {}; }
}
function saveBalanceMap_(obj){
  var keys = Object.keys(obj);
  if (keys.length > MAX_KEYS_STORED) {
    // Keep most recent by key order (best-effort)
    keys = keys.slice(keys.length - MAX_KEYS_STORED);
    var trimmed = {}; keys.forEach(function(k){ trimmed[k]=obj[k]; });
    obj = trimmed;
  }
  PropertiesService.getScriptProperties().setProperty('BALANCE_MAP', JSON.stringify(obj));
}
function loadJsonMap_(raw){ try { return JSON.parse(raw) || {}; } catch(e){ return {}; } }
