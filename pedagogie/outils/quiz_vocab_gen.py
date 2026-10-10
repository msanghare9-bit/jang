"""Questions de vocabulaire « contraires, synonymes, sens en français, sens en anglais », pour un niveau.

Données : pedagogie/quiz/donnees/vocab_<niveau>.py, qui définit :
  CONTRAIRES = [(mot, contraire, sens du mot, sens du contraire), ...]
  SYNONYMES  = [(mot, synonyme, sens commun en français), ...]
  FR         = [(mot anglais, sens en français, catégorie), ...]   (au moins 4 mots par catégorie)
  EN         = [(définition simple en anglais, mot, sens en français), ...]
  GROUPS     = [{mots proches qui ne doivent jamais être pièges l'un pour l'autre}, ...]
Au total : exactement 500 entrées.

    python3 pedagogie/outils/quiz_vocab_gen.py debutant      → pedagogie/quiz/vocabulaire_debutant_3.json
    python3 pedagogie/outils/quiz_vocab_gen.py intermediaire → pedagogie/quiz/vocabulaire_intermediaire_6.json
    python3 pedagogie/outils/quiz_vocab_gen.py avance        → pedagogie/quiz/vocabulaire_avance_6.json
"""
import json
import pathlib
import random
import runpy
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
NUM = {"debutant": 3, "intermediaire": 6, "avance": 6}


def build(niveau):
    d = runpy.run_path(str(ROOT / "pedagogie" / "quiz" / "donnees" / f"vocab_{niveau}.py"))
    contraires, synonymes, fr, en = d["CONTRAIRES"], d["SYNONYMES"], d["FR"], d["EN"]
    groups = [set(g) for g in d.get("GROUPS", [])]
    rnd = random.Random(f"jang-{niveau}")
    errs = []

    def near(*words):
        out = set(words)
        for g in groups:
            if g & set(words):
                out |= g
        return out

    def pick(pool, n, avoid, where):
        cand = sorted({p for p in pool if p not in avoid})
        rnd.shuffle(cand)
        if len(cand) < n:
            errs.append(f"{where} : pas assez de pièges possibles")
            return cand + ["?"] * (n - len(cand))
        return cand[:n]

    def place(correct, wrong):
        opts = [correct] + wrong
        rnd.shuffle(opts)
        return opts, opts.index(correct)

    qs = []
    # Les contraires et synonymes se servent des mêmes mots comme pièges.
    pool_words = {w for p in contraires for w in p[:2]} | {w for p in synonymes for w in p[:2]}
    for w, a, fw, fa in contraires:
        o, r = place(a, pick(pool_words, 3, near(w, a), f"contraire de {w}"))
        qs.append({"q": f"What is the opposite of « {w} »?", "o": o, "r": r,
                   "e": f"Le contraire de {w} ({fw}), c'est {a} ({fa})."})
    for w, s, f in synonymes:
        o, r = place(s, pick(pool_words, 3, near(w, s), f"synonyme de {w}"))
        qs.append({"q": f"Which word means the same as « {w} »?", "o": o, "r": r,
                   "e": f"{w[0].upper() + w[1:]} et {s} veulent dire la même chose : « {f} »."})
    for w, f, cat in fr:
        same = [p[1] for p in fr if p[2] == cat]
        o, r = place(f, pick(same, 3, {f}, f"sens de {w}"))
        qs.append({"q": f"Que veut dire « {w} » en français ?", "o": o, "r": r,
                   "e": f"{w[0].upper() + w[1:]} = {f}."})
    en_words = [p[1] for p in en]
    for definition, w, f in en:
        o, r = place(w, pick(en_words, 3, near(w), f"définition de {w}"))
        qs.append({"q": f"Which word is it? « {definition} »", "o": o, "r": r, "e": f"C'est {w} : {f}."})

    if len(qs) != 500:
        errs.append(f"{len(qs)} questions au lieu de 500 "
                    f"(contraires {len(contraires)}, synonymes {len(synonymes)}, fr {len(fr)}, en {len(en)})")
    keys = {}
    for q in qs:
        k = (q["q"].lower(), q["o"][q["r"]].lower())
        if k in keys:
            errs.append(f"doublon : {q['q']}")
        keys[k] = 1
    if errs:
        print("Problèmes :")
        for e in errs:
            print(" -", e)
        sys.exit(1)
    out = ROOT / "pedagogie" / "quiz" / f"vocabulaire_{niveau}_{NUM[niveau]}.json"
    out.write_text(json.dumps({"questions": qs}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(len(qs), "questions écrites dans", out.name)


if __name__ == "__main__":
    build(sys.argv[1])
