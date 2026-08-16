# Hand-written topical questions for the eval gold set (#42).
#
# The QUESTIONS are written by hand, because the point is to measure what a person
# actually types. The ANSWERS are not: each question names a `term` that is the
# canon's own technical vocabulary for the topic, and `mix pramana.evals.derive`
# verifies that term against the corpus before writing a case. A term that does not
# occur, or occurs so widely that accepting any passage containing it would measure
# nothing, is dropped with a reason rather than committed.
#
# `lang` is the language of the passages that should answer the question, NOT the
# language of the question. Every question here is in English, on purpose: the three
# groups below measure three genuinely different retrieval paths.
#
#   pli — English question, Pāli passage. Has a translation-vector layer to cross on.
#   lzh — English question, Chinese passage. NO translation layer exists; this path
#         depends entirely on BGE-M3's cross-lingual space, which the codebase has
#         said all along is unproven on Literary Chinese. Expect it to be worse, and
#         report it separately rather than averaging the two into one number.
#   lzh-native — the same question asked in Chinese. The control: it isolates how much
#         of any Chinese failure is cross-lingual rather than retrieval.
%{
  pali: [
    {"What are the four noble truths?", "ariyasaccaṁ"},
    {"How does the Buddha define right view?", "sammādiṭṭhi"},
    {"What is the noble eightfold path?", "aṭṭhaṅgiko maggo"},
    {"What is the origin of suffering?", "dukkhasamudayo"},
    {"What are the four establishments of mindfulness?", "satipaṭṭhān"},
    {"What are the seven factors of awakening?", "bojjhaṅg"},
    {"How is dependent origination explained?", "paṭiccasamuppād"},
    {"What are the five aggregates subject to clinging?", "pañcupādānakkhandhā"},
    {"How is mindfulness of breathing practised?", "ānāpānassati"},
    {"What are the divine abidings?", "brahmavihār"},
    {"What is clinging to rules and observances?", "sīlabbatupādān"},
    {"How should loving-kindness be developed?", "mettāsahagatena"},
    {"What does it mean to develop the faculties?", "indriyabhāvanā"},
    {"Are beings the owners of their actions?", "kammassakā"},
    {"What is craving, and how does it lead to rebirth?", "taṇhā"},
    {"What is said about nibbāna?", "nibbān"}
  ],
  chinese: [
    {"What are the four noble truths?", "四聖諦"},
    {"What is the truth of suffering?", "苦聖諦"},
    {"What is the noble eightfold path?", "八正道"},
    {"How is right view defined?", "正見"},
    {"What are the four foundations of mindfulness?", "四念處"},
    {"What are the seven factors of awakening?", "七覺支"},
    {"What is dependent origination?", "十二因緣"},
    {"What are the six sense bases?", "六入處"},
    {"How is mindfulness of breathing taught?", "安那般那"},
    {"What are the four immeasurable minds?", "四無量心"},
    {"What are the thirty-seven factors of awakening?", "三十七道品"},
    {"What is the samādhi of emptiness?", "空三昧"},
    {"What are the ten wholesome courses of action?", "十善業道"},
    {"What is loving-kindness, compassion, joy and equanimity?", "慈悲喜捨"}
  ],
  # The control group: identical topics, asked in the corpus's own language.
  chinese_native: [
    {"云何為四聖諦", "四聖諦"},
    {"何謂苦聖諦", "苦聖諦"},
    {"八正道是什麼", "八正道"},
    {"云何為正見", "正見"},
    {"四念處的修習", "四念處"},
    {"七覺支是哪七種", "七覺支"},
    {"十二因緣的內容", "十二因緣"},
    {"六入處是什麼", "六入處"},
    {"安那般那念的修法", "安那般那"},
    {"四無量心", "四無量心"},
    {"三十七道品", "三十七道品"},
    {"空三昧的意義", "空三昧"},
    {"十善業道", "十善業道"},
    {"慈悲喜捨四無量", "慈悲喜捨"}
  ]
}
