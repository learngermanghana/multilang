import re
import os
import streamlit as st
import openai

# --- Page Config ---
st.set_page_config(page_title="Letter Coach", layout="wide")
st.markdown("<style>footer {visibility: hidden;}</style>", unsafe_allow_html=True)

# --- API Key ---
api_key = os.getenv("OPENAI_API_KEY")
if not api_key:
    try:
        api_key = st.secrets["general"]["OPENAI_API_KEY"]
    except KeyError:
        api_key = None
if not api_key:
    st.error("❌ OpenAI API key missing. Set OPENAI_API_KEY env var or secrets.toml under [general].")
    st.stop()
openai.api_key = api_key
client = openai.OpenAI(api_key=api_key)

# --- Supported languages & connectors ---
LANGUAGES = ["English","German","French","Spanish","Italian","Portuguese"]
DEFAULT_CONNECTORS = {
    "English": {"A1":{"and","but"},"A2":{"however","for example"},"B1":{"nevertheless","moreover"},"B2":{"although","in conclusion"}},
    "German":  {"A1":{"und","aber"},"A2":{"deshalb","denn"},    "B1":{"jedoch","allerdings"},   "B2":{"dennoch","demzufolge"}},
    "French":  {"A1":{"et","mais"},  "A2":{"cependant","donc"},  "B1":{"néanmoins","ainsi"},  "B2":{"toutefois","en conclusion"}},
    "Spanish": {"A1":{"y","pero"},  "A2":{"sin embargo","por ejemplo"},"B1":{"no obstante","por lo tanto"},"B2":{"no obstante","finalmente"}},
    "Italian": {"A1":{"e","ma"},     "A2":{"tuttavia","quindi"},  "B1":{"pertanto","inoltre"},  "B2":{"sebbene","infine"}},
    "Portuguese":{"A1":{"e","mas"},   "A2":{"entretanto","por exemplo"},"B1":{"contudo","portanto"},"B2":{"embora","finalmente"}}
}

# --- UI Translations ---
TRANSLATIONS = {
    "English": {"ui_language":"Instruction language","select_language":"Choose writing language","level":"Select your level","task_type":"Select task type","writing_tips":"Writing Tips & Language Switch","write_prompt":"Write your letter or essay below:","submit":"Submit for Feedback","readability":"Readability","grammar_suggestions":"Grammar Suggestions","try_connectors":"Try connectors like","annotated":"Annotated Text","why_scores":"Why these scores?"},
    "German":  {"ui_language":"Anleitungssprache","select_language":"Schriftsprache wählen","level":"Niveau wählen","task_type":"Aufgabentyp","writing_tips":"Schreibtipps & Sprachwechsel","write_prompt":"Text hier eingeben:","submit":"Senden","readability":"Lesbarkeit","grammar_suggestions":"Grammatikvorschläge","try_connectors":"Konnektoren wie","annotated":"Annotierter Text","why_scores":"Warum diese Bewertungen?"},
    "French":  {"ui_language":"Langue d'instruction","select_language":"Choisir la langue","level":"Niveau","task_type":"Type de tâche","writing_tips":"Conseils & Changer langue","write_prompt":"Écrivez votre texte :","submit":"Soumettre","readability":"Lisibilité","grammar_suggestions":"Suggestions grammar","try_connectors":"Connecteurs :","annotated":"Texte annoté","why_scores":"Pourquoi ces notes ?"},
    "Spanish": {"ui_language":"Idioma instrucción","select_language":"Seleccione idioma","level":"Nivel","task_type":"Tipo de tarea","writing_tips":"Consejos & Cambio idioma","write_prompt":"Escriba su texto :","submit":"Enviar","readability":"Legibilidad","grammar_suggestions":"Sugerencias gramaticales","try_connectors":"Conectores :","annotated":"Texto anotado","why_scores":"¿Por qué estas puntuaciones?"},
    "Italian": {"ui_language":"Lingua istruzione","select_language":"Seleziona lingua","level":"Livello","task_type":"Tipo compito","writing_tips":"Suggerimenti & Cambio lingua","write_prompt":"Inserisci testo :","submit":"Invia","readability":"Leggibilità","grammar_suggestions":"Suggerimenti","try_connectors":"Connettori :","annotated":"Testo annotato","why_scores":"Perché questi punteggi?"},
    "Portuguese":{"ui_language":"Idioma instrução","select_language":"Selecionar idioma","level":"Nível","task_type":"Tipo tarefa","writing_tips":"Dicas & Mudar idioma","write_prompt":"Escreva seu texto :","submit":"Enviar","readability":"Legibilidade","grammar_suggestions":"Sugestões gramaticais","try_connectors":"Conectores :","annotated":"Texto anotado","why_scores":"Por que essas pontuações?"}
}

# --- GPT grammar check ---
def grammar_check_with_gpt(text: str, language: str) -> list[str]:
    prompt = (
        f"You are a {language} language tutor. Check the following {language} text for errors. "
        "Return each as `<error>` ⇒ `<suggestion>` — `<brief English explanation>`\n\n"
        f"Text:\n{text}"
    )
    resp = client.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[{"role":"user","content":prompt}],
        temperature=0
    )
    return resp.choices[0].message.content.strip().splitlines()

# --- Annotate errors ---
def annotate_text_with_errors(text: str, results: list[str]) -> str:
    for line in results:
        if "⇒" in line:
            err = line.split("⇒")[0].strip(" `")
            text = re.sub(
                re.escape(err),
                f"<span style='background-color:#e15759; color:#fff'>{err}</span>",
                text,
                flags=re.IGNORECASE
            )
    return text.replace("\n", "  \n")

# --- Main UI ---
inst_lang = st.sidebar.selectbox("", LANGUAGES, format_func=lambda l: TRANSLATIONS[l]["ui_language"])
write_lang = st.sidebar.selectbox(TRANSLATIONS[inst_lang]["select_language"], LANGUAGES)

st.title("📝 Letter Coach – Multilingual Letter Correction for Real Exam Practice")
connectors = DEFAULT_CONNECTORS[write_lang]

level = st.selectbox(TRANSLATIONS[inst_lang]["level"], ["A1","A2","B1","B2"])
tasks = ["Formal Letter","Informal Letter"] + (["Opinion Essay"] if level in ("B1","B2") else [])
task = st.selectbox(TRANSLATIONS[inst_lang]["task_type"], tasks)

st.markdown("### " + TRANSLATIONS[inst_lang]["writing_tips"])
with st.expander(TRANSLATIONS[inst_lang]["writing_tips"]):
    st.markdown("- 💡 Use sidebar to choose instruction & writing languages.")
    if level == "A1":
        st.markdown("- 📝 Simple present tense; short, clear sentences.")
        elif level == "A2":
        st.markdown("- 🔗 Use connectors (weil, denn).
- Include time expressions & polite forms.")
    elif level == "B1":
        st.markdown("- ✅ Present pros & cons; vary structures.")
    else:
        st.markdown("- 📚 Support opinions with examples; use passive/conditional.")

text = st.text_area(TRANSLATIONS[inst_lang]["write_prompt"], height=300)

if st.button(TRANSLATIONS[inst_lang]["submit"]):
    if not text.strip():
        st.warning("Please enter text before submitting.")
    else:
        results = grammar_check_with_gpt(text, write_lang)
        words = re.findall(r"\w+", text.lower())
        unique_ratio = len(set(words)) / len(words) if words else 0
        sentences = re.split(r'[.!?]', text)
        avg_w = len(words) / max(1, len([s for s in sentences if s.strip()]))
        readability = "Easy" if avg_w <= 12 else "Medium" if avg_w <= 17 else "Hard"
        scores = {
            "content": 10,
            "grammar": max(1, 5 - len(results)),
            "vocab": min(5, int(unique_ratio * 5)),
            "structure": 5
        }
        total = sum(scores.values())

        # Metrics
        st.markdown(f"**{TRANSLATIONS[inst_lang]['readability']}:** {readability} ({avg_w:.1f} w/s)")
        st.metric("Content", f"{scores['content']}/10")
        st.metric("Grammar", f"{scores['grammar']}/5")
        st.metric("Vocabulary", f"{scores['vocab']}/5")
        st.metric("Structure", f"{scores['structure']}/5")
        st.markdown(f"**Total: {total}/25**")

        # Organized breakdown
        st.markdown(f"**{TRANSLATIONS[inst_lang]['why_scores']}**")
        col1, col2 = st.columns(2)
        with col1:
            st.markdown("**📖 Content**")
            st.write(f"fixed = {scores['content']}/10")
            st.markdown("**✏️ Grammar**")
            st.write(f"{len(results)} errors ⇒ {scores['grammar']}/5")
        with col2:
            st.markdown("**💬 Vocabulary**")
            st.write(f"ratio {unique_ratio:.2f}, penalties ⇒ {scores['vocab']}/5")
            st.markdown("**🔧 Structure**")
            st.write(f"fixed = {scores['structure']}/5")

        # Suggestions
        if results:
            st.markdown(f"**{TRANSLATIONS[inst_lang]['grammar_suggestions']}:**")
            for line in results:
                st.markdown(f"- {line}")

        # Connector hints
        hints = sorted(connectors[level])[:4]
        st.info(f"{TRANSLATIONS[inst_lang]['try_connectors']}: {', '.join(hints)}…")

        # Annotated text
        annotated = annotate_text_with_errors(text, results)
        st.markdown(f"**{TRANSLATIONS[inst_lang]['annotated']}:**", unsafe_allow_html=True)
        st.markdown(annotated, unsafe_allow_html=True)

        # Download feedback
        feedback = (
            f"Feedback – {task} ({write_lang} {level})\n"
            f"Scores: {total}/25\nGrammar Suggestions:\n" + "\n".join(results)
        )
        st.download_button("💾 Download feedback", data=feedback, file_name="feedback.txt")
