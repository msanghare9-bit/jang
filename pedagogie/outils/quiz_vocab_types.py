"""Questions de vocabulaire (débutant) : contraires, synonymes, sens en français, sens en anglais.

Écrit pedagogie/quiz/vocabulaire_debutant_2.json (200 questions), à partir de listes vérifiées.
    python3 pedagogie/outils/quiz_vocab_types.py
"""
import json
import pathlib
import random

ROOT = pathlib.Path(__file__).resolve().parents[2]
rnd = random.Random(2026)

# Contraires : (mot, contraire, sens du mot, sens du contraire)
CONTRAIRES = [
    ("big", "small", "grand", "petit"), ("hot", "cold", "chaud", "froid"), ("happy", "sad", "content", "triste"),
    ("fast", "slow", "rapide", "lent"), ("tall", "short", "grand (taille)", "petit (taille)"),
    ("old", "young", "vieux", "jeune"), ("rich", "poor", "riche", "pauvre"), ("open", "closed", "ouvert", "fermé"),
    ("clean", "dirty", "propre", "sale"), ("full", "empty", "plein", "vide"), ("heavy", "light", "lourd", "léger"),
    ("strong", "weak", "fort", "faible"), ("early", "late", "tôt", "tard"), ("easy", "difficult", "facile", "difficile"),
    ("day", "night", "jour", "nuit"), ("up", "down", "en haut", "en bas"), ("in", "out", "dedans", "dehors"),
    ("long", "short", "long", "court"), ("new", "old", "neuf", "vieux"), ("good", "bad", "bon", "mauvais"),
    ("right", "wrong", "juste", "faux"), ("first", "last", "premier", "dernier"), ("buy", "sell", "acheter", "vendre"),
    ("come", "go", "venir", "aller"), ("love", "hate", "aimer", "détester"), ("win", "lose", "gagner", "perdre"),
    ("push", "pull", "pousser", "tirer"), ("give", "take", "donner", "prendre"), ("start", "finish", "commencer", "finir"),
    ("laugh", "cry", "rire", "pleurer"), ("wet", "dry", "mouillé", "sec"), ("loud", "quiet", "bruyant", "calme"),
    ("cheap", "expensive", "pas cher", "cher"), ("thick", "thin", "épais", "mince"), ("near", "far", "près", "loin"),
    ("before", "after", "avant", "après"), ("always", "never", "toujours", "jamais"), ("inside", "outside", "à l'intérieur", "à l'extérieur"),
    ("boy", "girl", "garçon", "fille"), ("man", "woman", "homme", "femme"), ("brother", "sister", "frère", "sœur"),
    ("father", "mother", "père", "mère"), ("question", "answer", "question", "réponse"), ("black", "white", "noir", "blanc"),
    ("sweet", "bitter", "sucré", "amer"), ("hard", "soft", "dur", "mou"), ("left", "right", "gauche", "droite"),
    ("morning", "evening", "matin", "soir"), ("arrive", "leave", "arriver", "partir"), ("sit down", "stand up", "s'asseoir", "se lever"),
]

# Synonymes (débutant, sûrs) : (mot, synonyme, sens commun)
SYNONYMES = [
    ("big", "large", "grand"), ("small", "little", "petit"), ("happy", "glad", "content"), ("begin", "start", "commencer"),
    ("finish", "end", "finir"), ("fast", "quick", "rapide"), ("pretty", "beautiful", "joli"), ("shut", "close", "fermer"),
    ("speak", "talk", "parler"), ("hard", "difficult", "difficile"), ("sick", "ill", "malade"), ("mum", "mother", "maman"),
    ("dad", "father", "papa"), ("kid", "child", "enfant"), ("gift", "present", "cadeau"), ("hi", "hello", "salut"),
    ("bye", "goodbye", "au revoir"), ("buy", "purchase", "acheter"), ("look at", "watch", "regarder"),
    ("shop", "store", "magasin"), ("rubbish", "garbage", "ordures"), ("correct", "right", "juste"),
    ("fine", "well", "bien (santé)"), ("angry", "cross", "fâché"), ("afraid", "scared", "qui a peur"),
    ("smart", "clever", "intelligent"), ("unhappy", "sad", "triste"), ("enormous", "huge", "énorme"),
    ("road", "street", "rue, route"), ("sofa", "couch", "canapé"), ("film", "movie", "film"),
    ("autumn", "fall", "automne"), ("holiday", "vacation", "vacances"), ("taxi", "cab", "taxi"),
    ("pupil", "student", "élève"), ("quiet", "calm", "calme"), ("nice", "kind", "gentil"),
    ("photo", "picture", "photo"), ("bag", "sack", "sac"), ("job", "work", "travail"),
]

# Sens en français : (mot anglais, sens, catégorie)
FR = [
    ("goat", "chèvre", "animal"), ("sheep", "mouton", "animal"), ("cow", "vache", "animal"), ("chicken", "poulet", "animal"),
    ("horse", "cheval", "animal"), ("donkey", "âne", "animal"), ("fish", "poisson", "animal"), ("bird", "oiseau", "animal"),
    ("lion", "lion", "animal"), ("monkey", "singe", "animal"), ("rice", "riz", "nourriture"), ("bread", "pain", "nourriture"),
    ("milk", "lait", "nourriture"), ("egg", "œuf", "nourriture"), ("sugar", "sucre", "nourriture"), ("salt", "sel", "nourriture"),
    ("onion", "oignon", "nourriture"), ("mango", "mangue", "nourriture"), ("peanut", "arachide", "nourriture"), ("meat", "viande", "nourriture"),
    ("head", "tête", "corps"), ("hand", "main", "corps"), ("foot", "pied", "corps"), ("eye", "œil", "corps"),
    ("ear", "oreille", "corps"), ("mouth", "bouche", "corps"), ("nose", "nez", "corps"), ("arm", "bras", "corps"),
    ("leg", "jambe", "corps"), ("tooth", "dent", "corps"), ("chair", "chaise", "maison"), ("table", "table", "maison"),
    ("door", "porte", "maison"), ("window", "fenêtre", "maison"), ("bed", "lit", "maison"), ("kitchen", "cuisine", "maison"),
    ("roof", "toit", "maison"), ("key", "clé", "maison"), ("pot", "marmite", "maison"), ("spoon", "cuillère", "maison"),
    ("teacher", "professeur", "école"), ("pupil", "élève", "école"), ("pen", "stylo", "école"), ("pencil", "crayon", "école"),
    ("ruler", "règle", "école"), ("book", "livre", "école"), ("notebook", "cahier", "école"), ("blackboard", "tableau", "école"),
    ("schoolbag", "cartable", "école"), ("rubber", "gomme", "école"), ("rain", "pluie", "nature"), ("sun", "soleil", "nature"),
    ("moon", "lune", "nature"), ("star", "étoile", "nature"), ("tree", "arbre", "nature"), ("river", "fleuve", "nature"),
    ("sea", "mer", "nature"), ("sand", "sable", "nature"), ("wind", "vent", "nature"), ("sky", "ciel", "nature"),
]

# Sens en anglais : (définition simple, mot, sens en français)
EN = [
    ("a person who teaches pupils", "teacher", "professeur"), ("a person who makes bread", "baker", "boulanger"),
    ("a person who catches fish", "fisherman", "pêcheur"), ("a person who helps sick people in a hospital", "nurse", "infirmier, infirmière"),
    ("a person who drives a car, a bus or a taxi", "driver", "chauffeur"), ("a person who grows food on a farm", "farmer", "agriculteur"),
    ("a person who repairs cars", "mechanic", "mécanicien"), ("a person who makes clothes", "tailor", "tailleur"),
    ("a person who cooks food in a restaurant", "cook", "cuisinier"), ("a person who looks after sick people and is not a nurse", "doctor", "médecin"),
    ("the meal you eat in the morning", "breakfast", "petit-déjeuner"), ("the meal you eat at midday", "lunch", "déjeuner"),
    ("the meal you eat in the evening", "dinner", "dîner"), ("the room where you sleep", "bedroom", "chambre"),
    ("the room where you cook", "kitchen", "cuisine"), ("the room where you wash", "bathroom", "salle de bain"),
    ("the place where you buy food and sell things", "market", "marché"), ("the place where pupils learn", "school", "école"),
    ("the place where sick people go", "hospital", "hôpital"), ("the place where you can borrow books", "library", "bibliothèque"),
    ("the day after Monday", "Tuesday", "mardi"), ("the day before Saturday", "Friday", "vendredi"),
    ("the first month of the year", "January", "janvier"), ("the last month of the year", "December", "décembre"),
    ("the month after March", "April", "avril"), ("the season when it rains a lot in Senegal", "rainy season", "hivernage"),
    ("the brother of your father or your mother", "uncle", "oncle"), ("the sister of your father or your mother", "aunt", "tante"),
    ("the mother of your mother", "grandmother", "grand-mère"), ("the son of your uncle", "cousin", "cousin"),
    ("an animal that gives us milk", "cow", "vache"), ("a big animal with a long nose", "elephant", "éléphant"),
    ("a very tall animal with a long neck", "giraffe", "girafe"), ("an animal that lives in water and swims", "fish", "poisson"),
    ("a small animal that says « meow »", "cat", "chat"), ("an animal that says « woof »", "dog", "chien"),
    ("a fruit that is long and yellow", "banana", "banane"), ("a red fruit that is green inside? No: a big green fruit, red inside", "watermelon", "pastèque"),
    ("you use it to rub out pencil", "rubber", "gomme"), ("you use it to draw a straight line", "ruler", "règle"),
    ("you use it to cut paper", "scissors", "ciseaux"), ("you use it to open a door", "key", "clé"),
    ("you wear them on your feet", "shoes", "chaussures"), ("you wear it on your head", "hat", "chapeau"),
    ("you use it when it rains", "umbrella", "parapluie"), ("you sleep on it", "bed", "lit"),
    ("a boat used by fishermen in Senegal", "pirogue", "pirogue"), ("a big tree with a very thick trunk, common in Senegal", "baobab", "baobab"),
    ("the colour of the sky on a sunny day", "blue", "bleu"), ("the colour of grass", "green", "vert"),
]


# Mots proches : jamais proposés comme pièges l'un pour l'autre.
GROUPS = [
    {"in", "out", "inside", "outside"}, {"come", "go", "arrive", "leave"}, {"early", "late", "before", "after"},
    {"day", "night", "morning", "evening"}, {"man", "woman", "boy", "girl", "father", "mother", "brother", "sister", "mum", "dad", "kid", "child"},
    {"sweet", "bitter"}, {"hard", "soft", "easy", "difficult"}, {"start", "finish", "begin", "end"},
    {"happy", "glad", "sad", "unhappy", "angry", "cross", "afraid", "scared", "laugh", "cry", "love", "hate"},
    {"big", "small", "large", "little", "tall", "short", "long", "huge", "enormous"}, {"new", "old", "young"},
    {"loud", "quiet", "calm"}, {"push", "pull", "give", "take", "gift", "present"}, {"buy", "sell", "purchase", "cheap", "expensive"},
    {"first", "last"}, {"always", "never"}, {"near", "far"}, {"fast", "slow", "quick"}, {"thick", "thin"},
    {"wet", "dry"}, {"strong", "weak"}, {"heavy", "light"}, {"full", "empty"}, {"clean", "dirty"},
    {"open", "closed", "close", "shut"}, {"rich", "poor"}, {"hot", "cold"}, {"up", "down", "sit down", "stand up"},
    {"black", "white"}, {"question", "answer"}, {"left", "right", "correct", "wrong"},
    {"nice", "kind", "pretty", "beautiful", "smart", "clever", "good", "bad", "fine", "well", "sick", "ill"},
    {"speak", "talk"}, {"hi", "hello", "bye", "goodbye"}, {"look at", "watch"}, {"shop", "store"},
    {"road", "street"}, {"film", "movie", "photo", "picture"}, {"job", "work"}, {"pupil", "student"},
]


def near(*words):
    out = set(words)
    for g in GROUPS:
        if g & set(words):
            out |= g
    return out


def place(correct, wrong):
    opts = [correct] + wrong
    rnd.shuffle(opts)
    return opts, opts.index(correct)


def pick(pool, n, avoid):
    out = []
    cand = [p for p in pool if p not in avoid]
    rnd.shuffle(cand)
    for c in cand:
        if c not in out:
            out.append(c)
        if len(out) == n:
            break
    return out


qs = []

# 50 contraires
for w, a, fw, fa in CONTRAIRES:
    related = near(w, a)
    wrong = pick([p[1] for p in CONTRAIRES] + [p[0] for p in CONTRAIRES], 3, related)
    o, r = place(a, wrong)
    qs.append({"q": f"What is the opposite of « {w} »?", "o": o, "r": r,
               "e": f"Le contraire de {w} ({fw}), c'est {a} ({fa})."})

# 40 synonymes
for w, s, f in SYNONYMES:
    related = near(w, s)
    wrong = pick([p[1] for p in SYNONYMES] + [p[0] for p in SYNONYMES], 3, related)
    o, r = place(s, wrong)
    qs.append({"q": f"Which word means the same as « {w} »?", "o": o, "r": r,
               "e": f"{w.capitalize()} et {s} veulent dire la même chose : « {f} »."})

# 60 sens en français (pièges de la même catégorie)
for w, f, cat in FR:
    same = [p[1] for p in FR if p[2] == cat and p[1] != f]
    wrong = pick(same, 3, {f})
    o, r = place(f, wrong)
    qs.append({"q": f"Que veut dire « {w} » en français ?", "o": o, "r": r, "e": f"{w.capitalize()} = {f}."})

# 50 sens en anglais : on donne la définition, l'élève trouve le mot
EN_OK = [x for x in EN if "?" not in x[0]]
EN_OK.append(("a big green fruit, red inside, with black seeds", "watermelon", "pastèque"))
for d, w, f in EN_OK:
    wrong = pick([p[1] for p in EN_OK], 3, {w})
    o, r = place(w, wrong)
    qs.append({"q": f"Which word is it? « {d} »", "o": o, "r": r, "e": f"C'est {w} : {f}."})

assert len(qs) == 200, len(qs)
out = ROOT / "pedagogie" / "quiz" / "vocabulaire_debutant_2.json"
out.write_text(json.dumps({"questions": qs}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(len(qs), "questions écrites dans", out.name)
