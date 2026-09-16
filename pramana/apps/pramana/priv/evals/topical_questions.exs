# Hand-written topical questions for the eval gold set (#42, #44).
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
#
# ## `topic`, and the two different questions it lets us ask
#
# The third element, where present, is a topic slug shared between the Pāli and Chinese
# groups. It exists because those two groups ask the SAME question of different canons,
# and there are two honest ways to score that:
#
#   per-tradition reachability — "can an English query reach the PĀLI witness of this?"
#                                A correct Chinese answer is a miss, because the
#                                question was whether that canon is reachable.
#   answered-at-all            — "did the user get a good answer from anywhere?"
#                                Either canon counts. This is what a reader cares about.
#
# Both are real; neither is a substitute for the other. Before the topic link existed,
# only the first was computable, and it made the retriever look worse than it was every
# time it answered correctly from the other tradition (#43).
#
# `chinese_native` deliberately carries NO topic: it is asked in Chinese, so folding it
# into an "was the English speaker answered" figure would inflate it with a path that
# scores 100% for reasons having nothing to do with cross-lingual retrieval.
%{
  pali: [
    {"What are the four noble truths?", "ariyasaccaṁ", "four-noble-truths"},
    {"How does the Buddha define right view?", "sammādiṭṭhi", "right-view"},
    {"What is the noble eightfold path?", "aṭṭhaṅgiko maggo", "eightfold-path"},
    {"What is the origin of suffering?", "dukkhasamudayo", "origin-of-suffering"},
    {"What are the four establishments of mindfulness?", "satipaṭṭhān", "satipatthana"},
    {"What are the seven factors of awakening?", "bojjhaṅg", "seven-factors"},
    {"How is dependent origination explained?", "paṭiccasamuppād", "dependent-origination"},
    {"What are the five aggregates subject to clinging?", "pañcupādānakkhandhā", "aggregates"},
    {"How is mindfulness of breathing practised?", "ānāpānassati", "mindfulness-of-breathing"},
    {"What are the divine abidings?", "brahmavihār", "divine-abidings"},
    {"What is clinging to rules and observances?", "sīlabbatupādān", nil},
    {"How should loving-kindness be developed?", "mettāsahagatena", "loving-kindness"},
    {"What does it mean to develop the faculties?", "indriyabhāvanā", nil},
    {"Are beings the owners of their actions?", "kammassakā", nil},
    {"What is craving, and how does it lead to rebirth?", "taṇhā", nil},
    {"What is said about nibbāna?", "nibbān", nil}
  ],
  chinese: [
    {"What are the four noble truths?", "四聖諦", "four-noble-truths"},
    {"What is the truth of suffering?", "苦聖諦", nil},
    {"What is the noble eightfold path?", "八正道", "eightfold-path"},
    {"How is right view defined?", "正見", "right-view"},
    {"What are the four foundations of mindfulness?", "四念處", "satipatthana"},
    {"What are the seven factors of awakening?", "七覺支", "seven-factors"},
    {"What is dependent origination?", "十二因緣", "dependent-origination"},
    {"What are the six sense bases?", "六入處", nil},
    {"How is mindfulness of breathing taught?", "安那般那", "mindfulness-of-breathing"},
    {"What are the four immeasurable minds?", "四無量心", "divine-abidings"},
    {"What are the thirty-seven factors of awakening?", "三十七道品", nil},
    {"What is the samādhi of emptiness?", "空三昧", nil},
    {"What are the ten wholesome courses of action?", "十善業道", nil},
    {"What is loving-kindness, compassion, joy and equanimity?", "慈悲喜捨", "loving-kindness"}
  ],
  # The control group: identical topics, asked in the corpus's own language.
  chinese_native: [
    {"云何為四聖諦", "四聖諦", nil},
    {"何謂苦聖諦", "苦聖諦", nil},
    {"八正道是什麼", "八正道", nil},
    {"云何為正見", "正見", nil},
    {"四念處的修習", "四念處", nil},
    {"七覺支是哪七種", "七覺支", nil},
    {"十二因緣的內容", "十二因緣", nil},
    {"六入處是什麼", "六入處", nil},
    {"安那般那念的修法", "安那般那", nil},
    {"四無量心", "四無量心", nil},
    {"三十七道品", "三十七道品", nil},
    {"空三昧的意義", "空三昧", nil},
    {"十善業道", "十善業道", nil},
    {"慈悲喜捨四無量", "慈悲喜捨", nil}
  ],
  # The Tibetan group. Each term is the Kangyur's own vocabulary for the topic, and each
  # is a PROPOSAL: `mix pramana.evals.derive` counts it in the corpus and refuses to
  # write a case for a term that does not occur or that occurs so widely it would measure
  # nothing. A term guessed wrong is therefore reported and dropped, never committed as
  # ground truth — which is what makes it defensible to propose them at all.
  tibetan: [
    {"What are the four noble truths?", "འཕགས་པའི་བདེན་པ་བཞི", "four-noble-truths"},
    {"What is the noble eightfold path?", "འཕགས་པའི་ལམ་ཡན་ལག་བརྒྱད", "eightfold-path"},
    {"How is right view defined?", "ཡང་དག་པའི་ལྟ་བ", "right-view"},
    {"How is dependent origination explained?", "རྟེན་ཅིང་འབྲེལ་བར་འབྱུང་བ", "dependent-origination"},
    {"What are the five aggregates?", "ཕུང་པོ་ལྔ", "aggregates"},
    {"What are the four establishments of mindfulness?", "དྲན་པ་ཉེ་བར་གཞག་པ", "satipatthana"},
    {"What are the factors of awakening?", "བྱང་ཆུབ་ཀྱི་ཡན་ལག", "seven-factors"},
    {"What are the divine abidings?", "ཚངས་པའི་གནས་པ", "divine-abidings"},
    {"What is the perfection of wisdom?", "ཤེས་རབ་ཀྱི་ཕ་རོལ་ཏུ་ཕྱིན་པ", nil},
    {"What is emptiness?", "སྟོང་པ་ཉིད", nil},
    {"What is said about nirvāṇa?", "མྱ་ངན་ལས་འདས་པ", nil},
    {"What is the awakening mind?", "བྱང་ཆུབ་ཀྱི་སེམས", nil}
  ]
}
