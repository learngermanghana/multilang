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
    except Exception:
        api_key = None
if not api_key:
    st.error("❌ OpenAI API key missing. Set OPENAI_API_KEY env var or secrets.toml under [general].")
    st.stop()
openai.api_key = api_key
client = openai.OpenAI(api_key=api_key)

# --- Languages & Connectors ---
LANGUAGES = ["English","German","French","Spanish","Italian","Portuguese"]
DEFAULT_CONNECTORS = {
    "German": {"A1":{"und","aber","weil"},"A2":{"deshalb","deswegen","trotzdem"},"B1":{"jedoch","allerdings"},"B2":{"dennoch","demzufolge"}},
    "French": {"A1":{"et","mais"},"A2":{"cependant","donc"},"B1":{"néanmoins","ainsi"},"B2":{"toutefois","en conclusion"}},
    "Spanish": {"A1":{"y","pero"},"A2":{"sin embargo","por ejemplo"},"B1":{"no obstante","por lo tanto"},"B2":{"no obstante","finalmente"}},
    "Italian": {"A1":{"e","ma"},"A2":{"tuttavia","quindi"},"B1":{"pertanto","inoltre"},"B2":{"sebbene","infine"}},
    "Portuguese": {"A1":{"e","mas"},"A2":{"entretanto","por exemplo"},"B1":{"contudo","portanto"},"B2":{"embora","finalmente"}},
    "English": {"A1":{"and","but"},"A2":{"however","for example"},"B1":{"nevertheless","moreover"},"B2":{"although","in conclusion"}}
}

# --- Translation Labels ---
TRANSLATIONS = {
    "English": {"ui_language":"Instruction language","select_language":"Choose writing language","level":"Select your level","task_type":"Select task type","writing_tips":"Writing Tips & Language Switch","write_prompt":"Write your letter or essay below:","submit":"Submit for Feedback","readability":"Readability","grammar_suggestions":"Grammar Suggestions","try_connectors":"Try connectors like","annotated":"Annotated Text","why_scores":"Why these scores?"},
    "German": {"ui_language":"Anleitungssprache","select_language":"Schriftsprache wählen","level":"Niveau wählen","task_type":"Aufgabentyp","writing_tips":"Schreibtipps & Sprachwechsel","write_prompt":"Text hier eingeben:","submit":"Senden","readability":"Lesbarkeit","grammar_suggestions":"Grammatikvorschläge","try_connectors":"Konnektoren wie","annotated":"Annotierter Text","why_scores":"Warum diese Bewertungen?"},
    "French": {"ui_language":"Langue d'instruction","select_language":"Choisir la langue","level":"Niveau","task_type":"Type de tâche","writing_tips":"Conseils & Changer langue","write_prompt":"Écrivez votre texte :","submit":"Soumettre","readability":"Lisibilité","grammar_suggestions":"Suggestions","try_connectors":"Connecteurs :","annotated":"Texte annoté","why_scores":"Pourquoi ces notes ?"},
    "Spanish": {"ui_language":"Idioma de instrucción","select_language":"Seleccione idioma","level":"Nivel","task_type":"Tipo de tarea","writing_tips":"Consejos & Cambio idioma","write_prompt":"Escriba su texto :","submit":"Enviar","readability":"Legibilidad","grammar_suggestions":"Sugerencias","try_connectors":"Conectores como","annotated":"Texto anotado","why_scores":"¿Por qué estas puntuaciones?"},
    "Italian": {"ui_language":"Lingua istruzione","select_language":"Seleziona lingua","level":"Livello","task_type":"Tipo compito","writing_tips":"Suggerimenti & Cambio lingua","write_prompt":"Inserisci testo :","submit":"Invia","readability":"Leggibilità","grammar_suggestions":"Suggerimenti","try_connectors":"Connettori :","annotated":"Testo annotato","why_scores":"Perché questi punteggi?"},
    "Portuguese": {"ui_language":"Idioma instrução","select_language":"Selecionar idioma","level":"Nível","task_type":"Tipo tarefa","writing_tips":"Dicas & Mudar idioma","write_prompt":"Escreva seu texto :","submit":"Enviar","readability":"Legibilidade","grammar_suggestions":"Sugestões","try_connectors":"Conectores :","annotated":"Texto anotado","why_scores":"Por que essas pontuações?"}
}

# --- GPT Check ---
def grammar_check_with_gpt(text, lang):
    prompt = (f"You are a {lang} tutor. Check below text for errors. Return lines:`<err>`⇒`<sug>` — `<eng expl>`\n\nText:\n{text}")
    resp = client.chat.completions.create(model="gpt-3.5-turbo",messages=[{"role":"user","content":prompt}],temperature=0)
    return resp.choices[0].message.content.splitlines()

# --- Annotate ---
def annotate_text(text, results):
    for line in results:
        if "⇒" in line:
            err=line.split("⇒")[0].strip(" `")
            text=re.sub(re.escape(err),f"<span style='background:#e15759;color:#fff'>{err}</span>",text,flags=re.IGNORECASE)
    return text.replace("\n","  \n")

# --- UI ---
inst=st.sidebar.selectbox("",LANGUAGES,format_func=lambda x:TRANSLATIONS[x]["ui_language"])
write_lang=st.sidebar.selectbox(TRANSLATIONS[inst]["select_language"],LANGUAGES)

st.title("📝 Letter Coach – Multilingual Letter Correction for Real Exam Practice")

lvl=st.selectbox(TRANSLATIONS[inst]["level"],["A1","A2","B1","B2"])
types=["Formal Letter","Informal Letter"]+( ["Opinion Essay"] if lvl in ("B1","B2") else [])
task=st.selectbox(TRANSLATIONS[inst]["task_type"],types)

st.markdown("### "+TRANSLATIONS[inst]["writing_tips"])
with st.expander(TRANSLATIONS[inst]["writing_tips"]):
    st.markdown("- Use sidebar to switch instruction & writing languages.")
    if lvl=="A1": st.markdown("- Simple present-tense sentences. Keep it short.")
    elif lvl=="A2": st.markdown("- Use connectors (weil, denn). Add time expressions.")
    elif lvl=="B1": st.markdown("- Present pros & cons. Vary structures.")
    else: st.markdown("- Support opinions w/ examples. Use passive.")

txt=st.text_area(TRANSLATIONS[inst]["write_prompt"],height=300)

if st.button(TRANSLATIONS[inst]["submit"]):
    if not txt.strip(): st.warning("Enter text before submitting.")
    else:
        res=grammar_check_with_gpt(txt,write_lang)
        words=re.findall(r"\w+",txt.lower())
        ur=len(set(words))/len(words) if words else 0
        sents=re.split(r'[.!?]',txt)
        avg=len(words)/max(1,len([s for s in sents if s.strip()]))
        read="Easy" if avg<=12 else "Medium" if avg<=17 else "Hard"
        scores={'content':10,'grammar':max(1,5-len(res)),'vocab':min(5,int(ur*5)),'structure':5}
        total=sum(scores.values())
        st.markdown(f"**{TRANSLATIONS[inst]['readability']}:** {read} ({avg:.1f} w/s)")
        st.metric("Content",f"{scores['content']}/10")
        st.metric("Grammar",f"{scores['grammar']}/5")
        st.metric("Vocabulary",f"{scores['vocab']}/5")
        st.metric("Structure",f"{scores['structure']}/5")
        st.markdown(f"**Total: {total}/25**")
        st.markdown(f"**{TRANSLATIONS[inst]['why_scores']}**")
        st.markdown(f"- 📖 Content: fixed = {scores['content']}/10")
        st.markdown(f"- ✏️ Grammar: {len(res)} errors ⇒ {scores['grammar']}/5")
        st.markdown(f"- 💬 Vocabulary: ratio {ur:.2f}, penalties ⇒ {scores['vocab']}/5")
        st.markdown(f"- 🔧 Structure: fixed = {scores['structure']}/5")
        if res:
            st.markdown(f"**{TRANSLATIONS[inst]['grammar_suggestions']}:**")
            for line in res: st.markdown(f"- {line}")
        hints=sorted(DEFAULT_CONNECTORS[write_lang][lvl])[:4]
        st.info(f"{TRANSLATIONS[inst]['try_connectors']}: {', '.join(hints)}…")
        ann=annotate_text(txt,res)
        st.markdown(f"**{TRANSLATIONS[inst]['annotated']}:**",unsafe_allow_html=True)
        st.markdown(ann,unsafe_allow_html=True)
        fb=(f"Feedback – {task} ({write_lang} {lvl})\nScores: {total}/25\nGrammar Suggestions:\n"+"\n".join(res))
        st.download_button("💾 Download feedback",data=fb,file_name="feedback.txt")
