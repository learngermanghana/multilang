import re
import os
import streamlit as st
import openai

# Streamlit page configuration
st.set_page_config(page_title="Letter Coach", layout="wide")
# Hide Streamlit footer branding
st.markdown("<style>footer {visibility: hidden;}</style>", unsafe_allow_html=True)

# -- Retrieve OpenAI API Key --
api_key = os.getenv("OPENAI_API_KEY")
if not api_key:
    try:
        api_key = st.secrets["general"]["OPENAI_API_KEY"]
    except Exception:
        api_key = None
if not api_key:
    st.error(
        "❌ OpenAI API key not found. "
        "Set OPENAI_API_KEY as an environment variable or add to secrets.toml under [general]."
    )
    st.stop()

openai.api_key = api_key
client = openai.OpenAI(api_key=api_key)

# -- Supported languages and default connectors --
LANGUAGES = ["German", "French", "Spanish", "Italian", "Portuguese", "English"]
DEFAULT_CONNECTORS = {
    "German": {
        "A1": {"und","aber","weil"},
        "A2": {"deshalb","deswegen","trotzdem","obwohl","sobald","außerdem","zum Beispiel","und","aber","oder"},
        "B1": {"jedoch","allerdings","hingegen","trotzdem","dennoch","folglich","daher","deshalb"},
        "B2": {"allerdings","dennoch","demzufolge","sodass","obgleich","wenngleich","abschließend","letztendlich"}
    },
    "French": {
        "A1": {"et","mais","parce que"},
        "A2": {"cependant","donc","lorsque","aussi","par exemple","et","mais","ou"},
        "B1": {"cependant","toutefois","néanmoins","en outre","par conséquent","ainsi"},
        "B2": {"toutefois","néanmoins","en conséquence","bien que","quoique","ainsi","finalement","en conclusion"}
    },
    "Spanish": {
        "A1": {"y","pero","porque"},
        "A2": {"sin embargo","por lo tanto","aunque","además","por ejemplo","y","pero","o"},
        "B1": {"sin embargo","no obstante","por consiguiente","además","obviamente","por lo que"},
        "B2": {"no obstante","por ende","aunque","si bien","por consiguiente","para concluir","finalmente"}
    },
    "Italian": {
        "A1": {"e","ma","perché"},
        "A2": {"tuttavia","quindi","quando","anche","ad esempio","e","ma","o"},
        "B1": {"tuttavia","comunque","pertanto","inoltre","di conseguenza","quindi"},
        "B2": {"tuttavia","nondimeno","pertanto","sebbene","nonostante","infine","in conclusione"}
    },
    "Portuguese": {
        "A1": {"e","mas","porque"},
        "A2": {"entretanto","portanto","quando","também","por exemplo","e","mas","ou"},
        "B1": {"entretanto","porém","contudo","além disso","portanto","assim"},
        "B2": {"no entanto","não obstante","portanto","embora","apesar de","finalmente","por fim"}
    },
    "English": {
        "A1": {"and","but","because"},
        "A2": {"however","therefore","when","also","for example","and","but","or"},
        "B1": {"however","nevertheless","therefore","moreover","consequently","thus"},
        "B2": {"nevertheless","nonetheless","therefore","although","despite","finally","in conclusion"}
    }
}

# -- Translation strings for UI labels --
TRANSLATIONS = {
    lang: {
        "select_language": {
            "English":"Choose writing language",
            "German":"Schriftsprache wählen",
            "French":"Choisir la langue",
            "Spanish":"Seleccione idioma",
            "Italian":"Seleziona lingua",
            "Portuguese":"Selecionar idioma"
        }[lang],
        "ui_language": {
            "English":"Instruction language",
            "German":"Anleitungssprache",
            "French":"Langue d'instruction",
            "Spanish":"Idioma de instrucción",
            "Italian":"Lingua di istruzione",
            "Portuguese":"Idioma de instrução"
        }[lang],
        "level": {
            "English":"Select your level",
            "German":"Niveau wählen",
            "French":"Sélectionnez votre niveau",
            "Spanish":"Seleccione su nivel",
            "Italian":"Seleziona il livello",
            "Portuguese":"Selecione seu nível"
        }[lang],
        "task_type": {
            "English":"Select task type",
            "German":"Aufgabentyp",
            "French":"Type de tâche",
            "Spanish":"Tipo de tarea",
            "Italian":"Tipo di compito",
            "Portuguese":"Tipo de tarefa"
        }[lang],
        "writing_tips": {
            "English":"Writing Tips & How to Switch Languages",
            "German":"Schreibtipps & Sprachwechsel",
            "French":"Conseils d'écriture & Changer de langue",
            "Spanish":"Consejos de escritura y cambio de idioma",
            "Italian":"Suggerimenti di scrittura e cambio lingua",
            "Portuguese":"Dicas de escrita e mudança de idioma"
        }[lang],
        "write_prompt": {
            "English":"Write your letter or essay below:",
            "German":"Schreiben Sie Ihren Text hier:",
            "French":"Écrivez votre texte ici :",
            "Spanish":"Escriba su texto aquí:",
            "Italian":"Scrivi il tuo testo qui:",
            "Portuguese":"Escreva seu texto aqui:"
        }[lang],
        "submit_btn": {
            "English":"Submit for Feedback",
            "German":"Senden",
            "French":"Soumettre",
            "Spanish":"Enviar",
            "Italian":"Invia",
            "Portuguese":"Enviar"
        }[lang],
        "readability": {
            "English":"Readability",
            "German":"Lesbarkeit",
            "French":"Lisibilité",
            "Spanish":"Legibilidad",
            "Italian":"Leggibilità",
            "Portuguese":"Legibilidade"
        }[lang],
        "grammar_suggestions": {
            "English":"Grammar Suggestions",
            "German":"Grammatikvorschläge",
            "French":"Suggestions de grammaire",
            "Spanish":"Sugerencias gramaticales",
            "Italian":"Suggerimenti grammaticali",
            "Portuguese":"Sugestões gramaticais"
        }[lang],
        "try_connectors": {
            "English":"Try connectors like",
            "German":"Nutzen Sie Konnektoren wie",
            "French":"Essayez des connecteurs comme",
            "Spanish":"Use conectores como",
            "Italian":"Prova connettori come",
            "Portuguese":"Use conectores como"
        }[lang],
        "annotated_text": {
            "English":"Annotated Text",
            "German":"Annotierter Text",
            "French":"Texte annoté",
            "Spanish":"Texto anotado",
            "Italian":"Testo annotato",
            "Portuguese":"Texto anotado"
        }[lang],
        "why_scores": {
            "English":"Why these scores?",
            "German":"Warum diese Bewertungen?",
            "French":"Pourquoi ces notes ?",
            "Spanish":"¿Por qué estas puntuaciones?",
            "Italian":"Perché questi punteggi?",
            "Portuguese":"Por que essas pontuações?"
        }[lang]
    }
    for lang in LANGUAGES
}

# -- GPT grammar check --
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

# -- Annotate errors --
def annotate_text_with_errors(text: str, gpt_results: list[str]) -> str:
    ann = text
    color = "#e15759"
    for line in gpt_results:
        if "⇒" in line:
            err = line.split("⇒")[0].strip(" `")
            # highlight all occurrences
            ann = re.sub(
                re.escape(err),
                f"<span style='background-color:{color}; color:#fff'>{err}</span>",
                ann,
                flags=re.IGNORECASE
            )
    return ann.replace("\n", "  \n")

# -- Main UI --
# Sidebar: instruction language then writing language
inst_lang = st.sidebar.selectbox(
    "", LANGUAGES, format_func=lambda x: TRANSLATIONS[x]["ui_language"]
)
text_lang = st.sidebar.selectbox(
    TRANSLATIONS[inst_lang]["select_language"], LANGUAGES
)

# Header
st.title("📝 Letter Coach – Multilingual Letter Correction for Real Exam Practice")
connectors_by_level = DEFAULT_CONNECTORS.get(text_lang, {})

# Level & Task
level = st.selectbox(TRANSLATIONS[inst_lang]["level"], ["A1", "A2", "B1", "B2"])
tasks = ["Formal Letter", "Informal Letter"] + (["Opinion Essay"] if level in ("B1","B2") else [])
task_type = st.selectbox(TRANSLATIONS[inst_lang]["task_type"], tasks)

# Writing Tips & Language Switch Instructions
st.markdown("### " + TRANSLATIONS[inst_lang]["writing_tips"])
with st.expander(TRANSLATIONS[inst_lang]["writing_tips"]):
    st.markdown("- 💡 Use the left sidebar to pick the **instruction** language and the **writing** language before you start.")
    if level == "A1":
        st.markdown("- 📝 Write simple, present-tense sentences.\n- Keep it short and clear.")
    elif level == "A2":
        st.markdown("- 🔗 Use connectors like weil, denn, deshalb.\n- Include time expressions and polite forms.")
    elif level == "B1":
        st.markdown("- ✅ Present pros and cons.\n- Vary sentence structures with subordinate clauses.")
    else:
        st.markdown("- 📚 Support opinions with examples.\n- Use passive voice and conditional clauses.")

# Text Input
student_text = st.text_area(TRANSLATIONS[inst_lang]["write_prompt"], height=300)

# On Submit: Process
if st.button(TRANSLATIONS[inst_lang]["submit_btn"]):
    if not student_text.strip():
        st.warning("Please enter your text before submitting.")
    else:
        with st.spinner("Processing…"):
            gpt_results = grammar_check_with_gpt(student_text, text_lang)
            words = re.findall(r"\w+", student_text.lower())
            unique_ratio = len(set(words)) / len(words) if words else 0
            sentences = re.split(r'[.!?]', student_text)
            avg_words = len(words) / max(1, len([s for s in sentences if s.strip()]))
            readability = "Easy" if avg_words <= 12 else "Medium" if avg_words <= 17 else "Hard"
            content_score = 10
            grammar_score = max(1, 5 - len(gpt_results))
            vocab_score = min(5, int(unique_ratio * 5))
            structure_score = 5
            total = content_score + grammar_score + vocab_score + structure_score

        # Display Metrics
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
        st.markdown(f("- 🔧 Structure: fixed = {structure_score}/5"))

        # Grammar Suggestions
        if gpt_results:
            st.markdown(f"**{TRANSLATIONS[inst_lang]['grammar_suggestions']}:**")
            for line in gpt_results:
                st.markdown(f"- {line}")

        # Connector hints
        hints = sorted(connectors_by_level.get(level, []))[:4]
        st.info(f"{TRANSLATIONS[inst_lang]['try_connectors']}: {', '.join(hints)}…")

        # Annotated text
        annotated = annotate_text_with_errors(student_text, gpt_results)
        st.markdown(f"**{TRANSLATIONS[inst_lang]['annotated_text']}:**", unsafe_allow_html=True)
        st.markdown(annotated, unsafe_allow_html=True)

        # Download feedback
        feedback = (
            f"Feedback – {task_type} ({text_lang} {level})\n"
            f"Scores: {total}/25\nGrammar Suggestions:\n" + "\n".join(gpt_results)
        )
        st.download_button("💾 Download feedback", data=feedback, file_name="feedback.txt")
