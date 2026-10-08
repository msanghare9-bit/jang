"""Vérifie et assemble la banque de questions des matchs.

Sources : pedagogie/quiz/<domaine>_<niveau>_<n>.json  (n = 1, 2, 3…)
          chaque fichier : {"questions": [ {question}, ... ]}
Une question :
  {"q": "énoncé", "o": ["A", "B", "C", "D"], "r": 0, "e": "explication en français très simple",
   "t": "texte à lire (seulement pour « comprehension »)"}

    python3 pedagogie/outils/quiz_check.py                 vérifie tout et écrit contenus/quiz/*.json
    python3 pedagogie/outils/quiz_check.py --check FICHIER vérifie un seul fichier source
"""
import json
import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "pedagogie" / "quiz"
OUT = ROOT / "contenus" / "quiz"
DOMAINES = ["vocabulaire", "grammaire", "expressions", "comprehension", "culture", "synonymes", "antonymes", "francais_anglais"]
NIVEAUX = ["debutant", "intermediaire", "avance"]


def norm(s):
    t = unicodedata.normalize("NFD", s.lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]+", " ", t).strip()


def check_q(q, where, errs, domaine):
    if not isinstance(q, dict):
        errs.append(f"{where} : pas un objet")
        return
    extra = set(q) - {"q", "o", "r", "e", "t"}
    if extra:
        errs.append(f"{where} : clés inconnues {sorted(extra)}")
    if not isinstance(q.get("q"), str) or not (5 <= len(q["q"].strip()) <= 220):
        errs.append(f"{where} : « q » (5 à 220 caractères)")
    o = q.get("o")
    if not isinstance(o, list) or len(o) != 4 or not all(isinstance(x, str) and x.strip() for x in o):
        errs.append(f"{where} : « o » = 4 réponses non vides")
    else:
        if len({norm(x) for x in o}) != 4:
            errs.append(f"{where} : deux réponses identiques {o}")
        if any(len(x) > 80 for x in o):
            errs.append(f"{where} : réponse trop longue (80 max)")
    if not isinstance(q.get("r"), int) or not (0 <= q["r"] <= 3):
        errs.append(f"{where} : « r » = 0, 1, 2 ou 3")
    if not isinstance(q.get("e"), str) or not (3 <= len(q["e"].strip()) <= 200):
        errs.append(f"{where} : « e » explication (3 à 200 caractères)")
    if domaine == "comprehension":
        if not isinstance(q.get("t"), str) or not (20 <= len(q["t"]) <= 500):
            errs.append(f"{where} : « t » texte à lire (20 à 500 caractères) obligatoire en compréhension")
    elif "t" in q:
        errs.append(f"{where} : « t » seulement en compréhension")


def key(q):
    return norm(q.get("t", "")[:60] + " " + q.get("q", "")) + " => " + norm(q["o"][q["r"]]) if isinstance(q.get("o"), list) and isinstance(q.get("r"), int) and 0 <= q["r"] < len(q["o"]) else norm(q.get("q", ""))


def parse_name(p):
    m = re.fullmatch(r"(.+)_([a-z]+)_(\d+)", p.stem)
    if not m or m.group(1) not in DOMAINES or m.group(2) not in NIVEAUX:
        return None
    return m.group(1), m.group(2)


def load(p, errs):
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        errs.append(f"{p.name} : JSON invalide ({e})")
        return []
    qs = d.get("questions") if isinstance(d, dict) else None
    if not isinstance(qs, list):
        errs.append(f"{p.name} : il faut {{\"questions\": [...]}}")
        return []
    return qs


def main():
    args = sys.argv[1:]
    if args and args[0] == "--check":
        files = [pathlib.Path(a) if pathlib.Path(a).is_absolute() else ROOT / a for a in args[1:]]
        write = False
    else:
        files = sorted(SRC.glob("*.json"))
        write = True
    errs = []
    groups = {}
    for p in files:
        dn = parse_name(p)
        if not dn:
            errs.append(f"{p.name} : nom attendu <domaine>_<niveau>_<n>.json ({', '.join(DOMAINES)} ; {', '.join(NIVEAUX)})")
            continue
        for i, q in enumerate(load(p, errs), 1):
            check_q(q, f"{p.name} n°{i}", errs, dn[0])
            groups.setdefault(dn, []).append((p.name, i, q))
    # Doublons : dans un même domaine et niveau (et entre les fichiers donnés).
    for (d, n), items in groups.items():
        seen = {}
        for name, i, q in items:
            k = key(q)
            if k in seen:
                errs.append(f"{name} n°{i} : doublon de {seen[k]}")
            else:
                seen[k] = f"{name} n°{i}"
        # La bonne réponse ne doit pas être presque toujours au même endroit.
        pos = [q.get("r") for _, _, q in items if isinstance(q.get("r"), int)]
        if len(pos) >= 40:
            for r in range(4):
                share = pos.count(r) / len(pos)
                if share > 0.4:
                    errs.append(f"{d}/{n} : la bonne réponse est en position {r + 1} dans {share:.0%} des questions (mélange-les)")
    for (d, n), items in sorted(groups.items()):
        print(f"{d:14} {n:13} {len(items):5} questions")
    if errs:
        print(f"\n{len(errs)} problème(s) :")
        for e in errs[:200]:
            print(" -", e)
        if len(errs) > 200:
            print(f" … et {len(errs) - 200} autres")
        sys.exit(1)
    print("Tout est bon.")
    if not write:
        return
    OUT.mkdir(parents=True, exist_ok=True)
    index = {"version": 2, "domaines": DOMAINES, "niveaux": NIVEAUX, "fichiers": {}}
    for (d, n), items in sorted(groups.items()):
        name = f"{d}_{n}.json"
        (OUT / name).write_text(json.dumps({"questions": [q for _, _, q in items]}, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        index["fichiers"][f"{d}_{n}"] = {"fichier": name, "nombre": len(items)}
    (OUT / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("Fichiers écrits dans contenus/quiz/.")


if __name__ == "__main__":
    main()
