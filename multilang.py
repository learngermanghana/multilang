import re
import os
import streamlit as st
import openai

st.set_page_config(page_title="MultiLang Checker", layout="wide")
# Hide Streamlit footer branding
st.markdown("<style>footer {visibility: hidden;}</style>", unsafe_allow_html=True)

# -- OpenAI API Key --
api_key = st.secrets.get("general", {}).get("OPENAI_API_KEY") or os.getenv("OPENAI_API_KEY")
if not api_key:
    st.error("❌ OpenAI API key not found. Add it to secrets.toml under [general] or set as environment variable.")
    st.stop()
openai.api_key = api_key
client = openai.OpenAI(api_key=api_key)

# -- Supported languages and default connectors --
LANGUAGES = ["German", "French", "Spanish", "Italian", "Portuguese", "English"]
DEFAULT_CONNECTORS = {
    "German": {"A1": {"und","aber","weil"}, "A2": {"deshalb","deswegen","trotzdem","obwohl","sobald","außerdem","zum Beispiel","und","aber","oder"}, "B1": {"jedoch","allerdings","hingegen","trotzdem","dennoch","folglich","daher","deshalb"}, "B2": {"allerdings","dennoch","demzufolge","sodass","obgleich","wenngleich","abschließend","letztendlich"}},
    "French": {"A1": {"et","mais","parce que"}, "A2": {"cependant","donc","lorsque","aussi","par exemple","et","mais","ou"}, "B1": {"cependant","toutefois","néanmoins","en outre","par conséquent","ainsi"}, "B2": {"toutefois","néanmoins","en conséquence","bien que","quoique","ainsi","finalement","en conclusion"}},
    "Spanish": {"A1": {"y","pero","porque"}, "A2": {"sin embargo","por lo tanto","aunque","además","por ejemplo","y","pero","o"}, "B1": {"sin embargo","no obstante","por consiguiente","además","obviamente","por lo que"}, "B2": {"no obstante","por ende","aunque","si bien","por consiguiente","para concluir","finalmente"}},
    "Italian": {"A1": {"e","ma","perché"}, "A2": {"tuttavia","quindi","quando","anche","ad esempio","e","ma","o"}, "B1": {"tuttavia","comunque","pertanto","inoltre","di conseguenza","quindi"}, "B2": {"tuttavia","nondimeno","pertanto","sebbene","nonostante","infine","in conclusione"}},
    "Portuguese": {"A1": {"e","mas","porque"}, "A2": {"entretanto","portanto","quando","também","por exemplo","e","mas","ou"}, "B1": {"entretanto","porém","contudo","além disso","portanto","assim"}, "B2": {"no entanto","não obstante","portanto","embora","apesar de","finalmente","por fim"}},
    "English": {"A1": {"and","but","because"}, "A2": {"however","therefore","when","also","for example","and","but","or"}, "B1": {"however","nevertheless","therefore","moreover","consequently","thus"}, "B2": {"nevertheless","nonetheless","therefore","although","despite","finally","in conclusion"}}
}

# -- Translation strings for UI --
TRANSLATIONS = {
    lang: {
        "select_language": {
            "English":"Select language","German":"Sprache wählen","French":"Choisir la langue","Spanish":"Seleccione idioma","Italian":"Seleziona lingua","Portuguese":"Selecionar idioma"
        }[lang],
        "ui_language": {
            "English":"Instruction language","German":"Sprache der Anleitung","French":"Langue d'instruction","Spanish":"Idioma de instrucción","Italian":"Lingua di istruzione","Portuguese":"Idioma de instrução"
        }[lang],
        "level": {"English":"Select your level","German":"Wählen Sie Ihr Niveau","French":"Sélectionnez votre niveau","Spanish":"Seleccione su nivel","Italian":"Seleziona il tuo livello","Portuguese":"Selecione seu nível"}[lang],
        "task_type": {"English":"Select task type","German":"Aufgabentyp wählen","French":"Sélectionnez le type de tâche","Spanish":"Seleccione tipo de tarea","Italian":"Seleziona tipo di compito","Portuguese":"Selecione o tipo de tarefa"}[lang],
        "writing_tips": {"English":"Writing Tips and Advice","German":"Schreibtipps und Ratschläge","French":"Conseils d'écriture","Spanish":"Consejos de escritura","Italian":"Suggerimenti di scrittura","Portuguese":"Dicas de escrita"}[lang],
        "write_prompt": {"English":"Write your letter or essay below:","German":"Schreiben Sie Ihren Brief oder Aufsatz unten:","French":"Écrivez votre lettre ou essai ci-dessous :","Spanish":"Escriba su carta o ensayo a continuación:","Italian":"Scrivi qui la tua lettera o saggio:","Portuguese":"Escreva sua carta ou ensaio abaixo:"}[lang],
        "submit_btn": {"English":"Submit for Feedback","German":"Zur Rückmeldung einreichen","French":"Soumettre pour retour","Spanish":"Enviar para comentarios","Italian":"Invia per feedback","Portuguese":"Enviar para feedback"}[lang],
        "readability": {"English":"Readability","German":"Lesbarkeit","French":"Lisibilité","Spanish":"Legibilidad","Italian":"Leggibilità","Portuguese":"Legibilidade"}[lang],
        "grammar_suggestions": {"English":"Grammar Suggestions","German":"Grammatikvorschläge","French":"Suggestions de grammaire","Spanish":"Sugerencias de gramática","Italian":"Suggerimenti grammaticali","Portuguese":"Sugestões gramaticais"}[lang],
        "try_connectors": {"English":"Try connectors like","German":"Versuchen Sie Konnektoren wie","French":"Essayez des connecteurs comme","Spanish":"Pruebe conectores como","Italian":"Prova connettori come","Portuguese":"Tente conectores como"}[lang],
        "annotated_text": {"English":"Annotated Text","German":"Annotierter Text","French":"Texte annoté","Spanish":"Texto anotado","Italian":"Testo annotato","Portuguese":"Texto anotado"}[lang]
    } for lang in LANGUAGES
}

# -- GPT grammar check --
def grammar_check_with_gpt(text: str, language: str) -> list[str]:
    prompt = (
        f"You are a {language} language tutor. Check the following {language} text for grammar and spelling errors. "
        "For each error, return a line in this format: `<error>` ⇒ `<suggestion>` — `<brief English explanation>`\n\n"
        f"Text:\n{text}"
    )
    response = client.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[{"role":"user","content":prompt}],
        temperature=0
    )
    return response.choices[0].message.content.strip().splitlines()

# -- Annotate text with errors --
def annotate_text_with_errors(text: str, gpt_results: list[str]) -> str:
    ann = text
    color = "#e15759"
    for line in gpt_results:
        if "⇒" in line:
            err = line.split("⇒")[0].strip(" `")
            ann = re.sub(rf"\b{re.escape(err)}\b", f"<span style='background-color:{color}; color:#fff'>{err}</span>", ann, flags=re.I)
    return ann.replace("\n", "  \n")

# -- Main UI --
# Instruction language selection
inst_lang = st.sidebar.selectbox("", LANGUAGES, format_func=lambda x: TRANSLATIONS[x]["ui_language"])
# Text language selection
text_lang = st.selectbox(TRANSLATIONS[inst_lang]["select_language"], LANGUAGES)

st.title("📝 MultiLang Checker – Learn Language Education Academy")
connectors_by_level = DEFAULT_CONNECTORS.get(text_lang, {})

level = st.selectbox(TRANSLATIONS[inst_lang]["level"], ["A1","A2","B1","B2"])

tasks = ["Formal Letter","Informal Letter"]
if level in ("B1","B2"): tasks.append("Opinion Essay")

task_type = st.selectbox(TRANSLATIONS[inst_lang]["task_type"], tasks)

st.markdown("### " + TRANSLATIONS[inst_lang]["writing_tips"])
with st.expander(TRANSLATIONS[inst_lang]["writing_tips"]):
    tips = {
        "A1": TRANSLATIONS[inst_lang].get("tip_A1", ""),
        "A2": TRANSLATIONS[inst_lang].get("tip_A2", ""),
        "B1": TRANSLATIONS[inst_lang].get("tip_B1", ""),
        "B2": TRANSLATIONS[inst_lang].get("tip_B2", "")
    }
    st.markdown(tips[level] or "")

student_text = st.text_area(TRANSLATIONS[inst_lang]["write_prompt"], height=300)

if st.button(TRANSLATIONS[inst_lang]["submit_btn"]):
    if not student_text.strip(): st.warning(TRANSLATIONS[inst_lang].get("warning_enter_text", ""))
    else:
        with st.spinner("Processing…"):
            gpt_results = grammar_check_with_gpt(student_text, text_lang)
            words = re.findall(r"\w+", student_text.lower())
            avg_words = len(words) / max(1,len(re.split(r'[.!?]', student_text)))
            readability = "Easy" if avg_words<=12 else "Medium" if avg_words<=17 else "Hard"
            scores = {"content":10, "grammar":max(1,5-len(gpt_results)), "vocab":min(5,int((len(set(words))/len(words))*5)), "structure":5}
            total = sum(scores.values())

        st.markdown(f"**{TRANSLATIONS[inst_lang]['readability']}:** {readability} ({avg_words:.1f} w/s)")
        st.metric("Content", f"{scores['content']}/10")
        st.metric("Grammar", f"{scores['grammar']}/5")
        st.metric("Vocabulary", f"{scores['vocab']}/5")
        st.metric("Structure", f"{scores['structure']}/5")
        st.markdown(f"**Total: {total}/25**")

        if gpt_results:
            st.markdown(f"**{TRANSLATIONS[inst_lang]['grammar_suggestions']}:**")
            for line in gpt_results: st.markdown(f"- {line}")

        hints = sorted(connectors_by_level.get(level, []))[:4]
        st.info(f"{TRANSLATIONS[inst_lang]['try_connectors']}: {', '.join(hints)}…")

        annotated = annotate_text_with_errors(student_text, gpt_results)
        st.markdown(f"**{TRANSLATIONS[inst_lang]['annotated_text']}:**", unsafe_allow_html=True)
        st.markdown(annotated, unsafe_allow_html=True)

        feedback = (
            f"Feedback – {task_type} ({text_lang} {level})\n"
            f"Scores: {total}/25\nGrammar Suggestions:\n" + "\n".join(gpt_results)
        )
        st.download_button("💾 Download feedback", data=feedback, file_name="feedback.txt")
