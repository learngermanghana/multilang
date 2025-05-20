import re
import os
import streamlit as st
import openai

# --- Streamlit page configuration ---
st.set_page_config(page_title="Letter Coach", layout="wide")
# Hide Streamlit footer
st.markdown("<style>footer {visibility: hidden;}</style>", unsafe_allow_html=True)

# --- Retrieve OpenAI API Key ---
api_key = os.getenv("OPENAI_API_KEY")
if not api_key:
    try:
        api_key = st.secrets["general"]["OPENAI_API_KEY"]
    except Exception:
        api_key = None
if not api_key:
    st.error(
        "❌ OpenAI API key not found. "
        "Set OPENAI_API_KEY as an environment variable or add it to secrets.toml under [general]."
    )
    st.stop()

# Initialize OpenAI client
openai.api_key = api_key
client = openai.OpenAI(api_key=api_key)

# --- Supported languages and connectors ---
LANGUAGES = ["German","French","Spanish","Italian","Portuguese","English"]
DEFAULT_CONNECTORS = {
    # ... (same connector dict as before) ...
}
# For brevity, re-use your existing DEFAULT_CONNECTORS dict here

# --- Translation strings ---
TRANSLATIONS = {
    # ... (same TRANSLATIONS dict as before) ...
}
# Re-use your existing TRANSLATIONS dict here

# --- GPT grammar check helper ---
def grammar_check_with_gpt(text: str, language: str) -> list[str]:
    prompt = (
        f"You are a {language} language tutor. Check the following {language} text "
        "for grammar and spelling errors. Return each error as: "
        "`<error>` ⇒ `<suggestion>` — `<brief English explanation>`\n\n"
        f"Text:\n{text}"
    )
    response = client.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[{"role":"user","content":prompt}],
        temperature=0
    )
    return response.choices[0].message.content.strip().splitlines()

# --- Annotate errors helper ---
def annotate_text_with_errors(text: str, gpt_results: list[str]) -> str:
    ann = text
    color = "#e15759"
    for line in gpt_results:
        if "⇒" in line:
            err = line.split("⇒")[0].strip(" `")
            ann = re.sub(
                re.escape(err),
                f"<span style='background-color:{color}; color:#fff'>{err}</span>",
                ann,
                flags=re.IGNORECASE
            )
    return ann.replace("\n", "  \n")

# --- Main UI ---
# Sidebar: pick instruction and writing languages
inst_lang = st.sidebar.selectbox("", LANGUAGES, format_func=lambda x: TRANSLATIONS[x]["ui_language"])
text_lang = st.sidebar.selectbox(
    TRANSLATIONS[inst_lang]["select_language"], LANGUAGES
)

# App header
st.title("📝 Letter Coach – Multilingual Letter Correction for Real Exam Practice")
connectors_by_level = DEFAULT_CONNECTORS[text_lang]

# Select level and task\level = st.selectbox(TRANSLATIONS[inst_lang]["level"], ["A1","A2","B1","B2"])
tasks = ["Formal Letter","Informal Letter"] + (["Opinion Essay"] if level in ("B1","B2") else [])
task_type = st.selectbox(TRANSLATIONS[inst_lang]["task_type"], tasks)

# Writing tips and switch guide
st.markdown("### " + TRANSLATIONS[inst_lang]["writing_tips"])
with st.expander(TRANSLATIONS[inst_lang]["writing_tips"]):
    st.markdown("- 💡 Use the left sidebar to select the instruction and writing languages.")
    if level == "A1":
        st.markdown("- 📝 Keep sentences simple (present tense).\n- Short and clear.")
    elif level == "A2":
        st.markdown("- 🔗 Use connectors (weil, denn, deshalb).\n- Add time expressions and polite forms.")
    elif level == "B1":
        st.markdown("- ✅ Present pros and cons.\n- Vary sentence structures.")
    else:
        st.markdown("- 📚 Support opinions with examples.\n- Use passive and conditional clauses.")

# Text input area
student_text = st.text_area(TRANSLATIONS[inst_lang]["write_prompt"], height=300)

# Submit processing
if st.button(TRANSLATIONS[inst_lang]["submit_btn"]):
    if not student_text.strip():
        st.warning("Please enter text before submitting.")
    else:
        with st.spinner("Processing…"):
            gpt_results = grammar_check_with_gpt(student_text, text_lang)
            words = re.findall(r"\w+", student_text.lower())
            unique_ratio = len(set(words)) / len(words) if words else 0
            sentences = re.split(r'[.!?]', student_text)
            avg_words = len(words) / max(1, len([s for s in sentences if s.strip()]))
            readability = ("Easy" if avg_words<=12 else "Medium" if avg_words<=17 else "Hard")
            content_score = 10
            grammar_score = max(1, 5 - len(gpt_results))
            vocab_score = min(5, int(unique_ratio*5))
            structure_score = 5
            total = content_score + grammar_score + vocab_score + structure_score

        # Display metrics
        st.markdown(f"**{TRANSLATIONS[inst_lang]['readability']}:** {readability} ({avg_words:.1f} w/s)")
        st.metric("Content", f"{content_score}/10")
        st.metric("Grammar", f"{grammar_score}/5")
        st.metric("Vocabulary", f"{vocab_score}/5")
        st.metric("Structure", f"{structure_score}/5")
        st.markdown(f"**Total: {total}/25**")

        # Why these scores?
        st.markdown(f"**{TRANSLATIONS[inst_lang]['why_scores']}**")
        st.markdown(f"- 📖 Content: fixed = {content_score}/10")
        st.markdown(f"- ✏️ Grammar: {len(gpt_results)} errors ⇒ {grammar_score}/5")
        st.markdown(f"- 💬 Vocabulary: ratio {unique_ratio:.2f}, penalties ⇒ {vocab_score}/5")
        st.markdown(f"- 🔧 Structure: fixed = {structure_score}/5")

        # Grammar suggestions
        if gpt_results:
            st.markdown(f"**{TRANSLATIONS[inst_lang]['grammar_suggestions']}:**")
            for line in gpt_results:
                st.markdown(f"- {line}")

        # Connector hints
        hints = sorted(connectors_by_level[level])[:4]
        st.info(f"{TRANSLATIONS[inst_lang]['try_connectors']}: {', '.join(hints)}…")

        # Annotated text
        annotated = annotate_text_with_errors(student_text, gpt_results)
        st.markdown(f"**{TRANSLATIONS[inst_lang]['annotated_text']}:**", unsafe_allow_html=True)
        st.markdown(annotated, unsafe_allow_html=True)

        # Download feedback
        feedback = (
            f"Feedback – {task_type} ({text_lang} {level})\n"
            f"Scores: {total}/25\n"
            f"Grammar Suggestions:\n" + "\n".join(gpt_results)
        )
        st.download_button("💾 Download feedback", data=feedback, file_name="feedback.txt")
