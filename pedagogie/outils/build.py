"""Assemble les missions du collège et leurs histoires, puis vérifie tout.

    python3 pedagogie/outils/build.py            écrit les fichiers (après vérification)
    python3 pedagogie/outils/build.py --check    vérifie seulement
    python3 pedagogie/outils/build.py --check unites/5e_u1-3.py   vérifie un seul fichier

Écrit : contenus/missions.json, app/assets/missions.json,
        contenus/histoires.json, app/assets/histoires.json (saisons 6e à 3e).
"""
import json
import pathlib
import re
import runpy
import sys
import unicodedata

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))

NIVEAUX = ["6e", "5e", "4e", "3e"]
SAISONS = {
    "6e": "Un lionceau à l'école",
    "5e": "Les vacances au village",
    "4e": "La pirogue de Kayar",
    "3e": "Radio Jàng",
}
FONDS = {"cour", "classe", "maison", "marche", "mer", "nuit", "plage", "terrain", "bibliotheque"}
PERSOS = {"gainde", "awa", "modou", "doudou", "kocc", "mouton", "bouc", "pirogue", "poisson"}
ANIMS = {"saute", "balance", "danse", "danse2", "tangue", "immobile"}


def norm(s):
    """Même normalisation que normAnswer() dans l'app."""
    t = re.sub("[’`']", "", s.lower())
    t = "".join(c for c in unicodedata.normalize("NFD", t) if unicodedata.category(c) != "Mn")
    t = re.sub(r"[^a-z0-9 ]", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def has_keys(answer, keys):
    a = f" {norm(answer)} "
    return all(any(k.strip() and f" {norm(k)} " in a for k in g.split("|")) for g in keys)


class Errors(list):
    def add(self, where, msg):
        self.append(f"{where} : {msg}")


def check_aides(e, where, aides):
    if not isinstance(aides, list) or len(aides) != 4:
        e.add(where, "« aides » doit avoir 4 marches (question, rejouer, modèle, sens)")
        return
    if not isinstance(aides[1], dict) or "rejouer" not in aides[1]:
        e.add(where, "la 2e aide doit être {'rejouer': n, 'texte': ...}")
    for i in (0, 2, 3):
        if not isinstance(aides[i], str) or not aides[i].strip():
            e.add(where, f"aide {i + 1} vide")


def check_mission(e, m, nrep):
    w = m.get("id", "?")
    for k in ["id", "titre", "jesais", "expressions", "mots", "scene", "questions", "marches", "pourdevrai", "carnet"]:
        if not m.get(k):
            e.add(w, f"« {k} » manque ou est vide")
    mots = m.get("mots", {})
    liste = mots.get("liste", [])
    if not (5 <= len(liste) <= 10):
        e.add(w, f"mots.liste : {len(liste)} mots (il en faut 5 à 10)")
    if sum(1 for x in liste if x.get("ok")) < 3 or sum(1 for x in liste if not x.get("ok")) < 2:
        e.add(w, "mots.liste : au moins 3 bons mots et 2 pièges")
    for x in liste:
        if not x.get("pourquoi"):
            e.add(w, f"mot « {x.get('mot')} » sans explication")
    if mots.get("fond") not in FONDS:
        e.add(w, f"mots.fond « {mots.get('fond')} » inconnu ({', '.join(sorted(FONDS))})")
    sc = m.get("scene", {})
    if sc.get("fond") not in FONDS:
        e.add(w, f"scene.fond « {sc.get('fond')} » inconnu")
    persos = sc.get("persos", [])
    for p in persos:
        if p not in PERSOS:
            e.add(w, f"personnage « {p} » inconnu ({', '.join(sorted(PERSOS))})")
    rep = sc.get("repliques", [])
    if not (2 <= len(rep) <= 6):
        e.add(w, f"scene : {len(rep)} répliques (2 à 6)")
    for r in rep:
        if r.get("qui") not in persos:
            e.add(w, f"réplique de « {r.get('qui')} » qui n'est pas dans scene.persos")
        if not r.get("en") or not r.get("fr"):
            e.add(w, "réplique sans en/fr")
    for i, q in enumerate(m.get("questions", [])):
        o = q.get("options", [])
        if not (2 <= len(o) <= 4) or not (0 <= q.get("reponse", -1) < len(o)):
            e.add(w, f"question {i + 1} : réponse hors des options")
        if q.get("rejouer", -1) >= len(rep):
            e.add(w, f"question {i + 1} : rejouer {q.get('rejouer')} mais seulement {len(rep)} répliques")
    marches = m.get("marches", [])
    types = [s.get("type") for s in marches]
    if types != ["choix", "ordre", "trou", "libre"]:
        e.add(w, f"marches : il faut choix, ordre, trou, libre dans cet ordre (trouvé {types})")
    for i, s in enumerate(marches):
        ws = f"{w} marche {i + 1} ({s.get('type')})"
        if not s.get("gainde"):
            e.add(ws, "phrase de Gaïndé vide")
        check_aides(e, ws, s.get("aides"))
        a = s.get("aides") or []
        if len(a) > 1 and isinstance(a[1], dict) and a[1].get("rejouer", -1) >= len(rep):
            e.add(ws, f"rejouer {a[1].get('rejouer')} mais seulement {len(rep)} répliques")
        t = s.get("type")
        if t == "choix":
            o = s.get("options", [])
            if len(o) < 2 or not (0 <= s.get("reponse", -1) < len(o)):
                e.add(ws, "réponse hors des options")
        elif t == "ordre":
            tu, ci = s.get("tuiles", []), s.get("cible", "")
            if sorted(norm(" ".join(tu)).split()) != sorted(norm(ci).split()):
                e.add(ws, f"les tuiles {tu} ne forment pas « {ci} »")
            if norm(" ".join(tu)) == norm(ci):
                e.add(ws, "les tuiles sont déjà dans le bon ordre : mélange-les")
            if not s.get("dit"):
                e.add(ws, "« dit » manque")
        elif t == "trou":
            if not s.get("accepte") or not s.get("dit"):
                e.add(ws, "« accepte » et « dit » obligatoires")
        elif t == "libre":
            if not s.get("cles"):
                e.add(ws, "« cles » vide")
    for i, t in enumerate(m.get("pourdevrai", [])):
        wt = f"{w} pour de vrai {i + 1}"
        # « cles » peut être vide quand toute réponse est bonne (ex. épeler son prénom).
        for k in ["qui", "en", "fr", "modele", "reponse"]:
            if not t.get(k):
                e.add(wt, f"« {k} » vide")
        if t.get("qui") and t["qui"] not in PERSOS:
            e.add(wt, f"personnage « {t['qui']} » inconnu")
        if t.get("modele") and t.get("cles") and not has_keys(t["modele"], t["cles"]):
            e.add(wt, f"le modèle « {t['modele']} » ne contient pas les clés {t['cles']}")
    for s in marches:
        if s.get("type") == "libre":
            model = s["aides"][2] if len(s.get("aides", [])) > 2 and isinstance(s["aides"][2], str) else ""
            # le modèle est souvent « Moi, je dis : « ... » » : on vérifie seulement si les clés y sont
            if model and s.get("cles") and not has_keys(model, s["cles"]) and not has_keys(s["aides"][3], s["cles"]):
                e.add(f"{w} marche libre", f"ni le modèle ni le sens ne contiennent les clés {s['cles']}")


def check_unite(e, u, niveau, n):
    w = u.get("id", "?")
    if w != f"{niveau}-u{n}":
        e.add(w, f"id attendu « {niveau}-u{n} »")
    for k in ["titre", "production", "missions", "revision", "exercices"]:
        if not u.get(k):
            e.add(w, f"« {k} » manque")
    for j, m in enumerate(u.get("missions", []), 1):
        if m.get("id") != f"{niveau}-u{n}-m{j}":
            e.add(w, f"mission {j} : id « {m.get('id')} », attendu « {niveau}-u{n}-m{j} »")
        check_mission(e, m, j)
    rv = u.get("revision", {})
    if len(rv.get("lignes", [])) < 3 or len(rv.get("mots", [])) < 5 or len(rv.get("pieges", [])) < 2:
        e.add(w, "revision : au moins 3 lignes, 5 mots, 2 pièges")
    for x in rv.get("mots", []):
        if not (x.get("en") and x.get("fr") and x.get("wo")):
            e.add(w, f"mot de révision incomplet : {x}")
    ex = u.get("exercices", [])
    if len(ex) != 10:
        e.add(w, f"{len(ex)} exercices (il en faut 10)")
    for i, x in enumerate(ex, 1):
        if len(x.get("options", [])) != 4 or not (0 <= x.get("reponse", -1) < 4) or not x.get("explication"):
            e.add(w, f"exercice {i} : 4 options, une réponse et une explication")
        if len(set(x.get("options", []))) != len(x.get("options", [])):
            e.add(w, f"exercice {i} : deux options identiques")


def check_episodes(e, eps, ids, niveau):
    last = -1
    for i, ep in enumerate(eps, 1):
        w = f"{niveau} épisode {i} « {ep.get('titre')} »"
        a = ep.get("apres")
        if a not in ids:
            e.add(w, f"« apres » = {a!r} n'est pas une mission de ce niveau")
        elif ids.index(a) <= last:
            e.add(w, "« apres » doit venir après la mission de l'épisode précédent")
        else:
            last = ids.index(a)
        cases = ep.get("cases", [])
        if not (3 <= len(cases) <= 6):
            e.add(w, f"{len(cases)} cases (3 à 6)")
        for c in cases:
            if c.get("fond") not in FONDS:
                e.add(w, f"fond « {c.get('fond')} » inconnu")
            if not (1 <= len(c.get("persos", [])) <= 3):
                e.add(w, "1 à 3 personnages par case")
            for p in c.get("persos", []):
                if p.get("id") not in PERSOS:
                    e.add(w, f"personnage « {p.get('id')} » inconnu")
                if p.get("anim") and p["anim"] not in ANIMS:
                    e.add(w, f"animation « {p['anim']} » inconnue ({', '.join(sorted(ANIMS))})")
                if not (0 <= p.get("x", -1) <= 0.8):
                    e.add(w, "x d'un personnage entre 0 et 0.8")
            if not (1 <= len(c.get("bulles", [])) <= 4):
                e.add(w, "1 à 4 bulles par case")
            for b in c.get("bulles", []):
                if not b.get("en") or not b.get("fr"):
                    e.add(w, "bulle sans en/fr")
                if not (0 <= b.get("x", -1) <= 0.7 and 0 <= b.get("y", -1) <= 0.6):
                    e.add(w, "bulle : x entre 0 et 0.7, y entre 0 et 0.6")
        if not ep.get("mots"):
            e.add(w, "« mots » vide")


def load(files):
    par = {n: {"unites": [], "episodes": []} for n in NIVEAUX}
    for f in files:
        g = runpy.run_path(str(f))
        n = g["NIVEAU"]
        par[n]["unites"] += g["UNITES"]
        par[n]["episodes"] += g["EPISODES"]
    for n in NIVEAUX:
        par[n]["unites"].sort(key=lambda u: int(u["id"].split("-u")[1]))
        order = {f"{n}-u{int(u['id'].split('-u')[1])}-m{j}": k for k, (u, j) in enumerate(
            (u, j) for u in par[n]["unites"] for j in range(1, len(u["missions"]) + 1))}
        par[n]["episodes"].sort(key=lambda ep: order.get(ep.get("apres"), 10 ** 6))
    return par


def main():
    args = sys.argv[1:]
    only_check = "--check" in args
    picked = [HERE / a if not pathlib.Path(a).is_absolute() else pathlib.Path(a) for a in args if a != "--check"]
    files = picked or sorted((HERE / "unites").glob("*.py"))
    par = load(files)
    e = Errors()
    for n in NIVEAUX:
        ids = []
        for u in par[n]["unites"]:
            k = int(u["id"].split("-u")[1])
            check_unite(e, u, n, k)
            ids += [m["id"] for m in u["missions"]]
        if len(ids) != len(set(ids)):
            e.add(n, "deux missions ont le même id")
        check_episodes(e, par[n]["episodes"], ids, n)
        if picked:
            continue
        nums = [int(u["id"].split("-u")[1]) for u in par[n]["unites"]]
        if nums and nums != list(range(1, len(nums) + 1)):
            e.add(n, f"unités {nums} : il en manque")
    for n in NIVEAUX:
        if par[n]["unites"]:
            nm = sum(len(u["missions"]) for u in par[n]["unites"])
            print(f"{n} : {len(par[n]['unites'])} unités, {nm} missions, {len(par[n]['episodes'])} épisodes")
    if e:
        print(f"\n{len(e)} problème(s) :")
        for x in e:
            print(" -", x)
        sys.exit(1)
    print("Tout est bon.")
    if only_check or picked:
        return

    data = {"version": 1, "parcours": [
        {"matiere": "anglais", "niveau": n, "saison": SAISONS[n], "unites": par[n]["unites"]}
        for n in NIVEAUX if par[n]["unites"]]}
    for p in [ROOT / "contenus" / "missions.json", ROOT / "app" / "assets" / "missions.json"]:
        p.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    hist = json.loads((ROOT / "contenus" / "histoires.json").read_text(encoding="utf-8"))
    saisons = [s for s in hist["saisons"] if not (s.get("matiere") == "anglais" and s.get("niveau") in NIVEAUX)]
    college = [{"matiere": "anglais", "niveau": n, "titre": SAISONS[n], "episodes": par[n]["episodes"]}
               for n in NIVEAUX if par[n]["episodes"]]
    hist["saisons"] = college + saisons
    for p in [ROOT / "contenus" / "histoires.json", ROOT / "app" / "assets" / "histoires.json"]:
        p.write_text(json.dumps(hist, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("Fichiers écrits.")


if __name__ == "__main__":
    main()
