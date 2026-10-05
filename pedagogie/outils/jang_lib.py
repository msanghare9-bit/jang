"""Fonctions communes pour écrire les missions d'anglais du collège (6e à 3e).

Chaque fichier de pedagogie/outils/unites/ utilise ces fonctions et définit :
  NIVEAU   = "5e"
  UNITES   = [unite1, unite2, ...]          (dans l'ordre)
  EPISODES = [episode(...), ...]            (dans l'ordre, chacun avec "apres" = id de mission)
Puis lancer :  python3 pedagogie/outils/build.py
"""

DIFFICILE = [
    "Comprendre la scène|C'est normal au début. Tu as pu réécouter : c'est comme ça qu'on apprend.",
    "L'ordre des mots|En anglais, l'ordre des mots est important. Tu vas le revoir souvent.",
    "Écrire seul|Écrire seul, c'est le plus dur. Et tu l'as fait !",
    "Parler au micro|Parler fait un peu peur au début. Plus tu parles, plus c'est facile.",
    "Rien !|Super ! La prochaine mission sera un peu plus dure.",
]


def mot(m, ok, pourquoi):
    return {"mot": m, "ok": ok, "pourquoi": pourquoi}


def r(qui, en, fr):
    return {"qui": qui, "en": en, "fr": fr}


def q(question, options, reponse, rejouer=-1):
    return {"question": question, "options": options, "reponse": reponse, "rejouer": rejouer}


def aides(question, rejouer, texte_rejouer, modele, sens):
    return [question, {"rejouer": rejouer, "texte": texte_rejouer}, modele, sens]


def choix(gainde, options, reponse, a):
    return {"type": "choix", "gainde": gainde, "options": options, "reponse": reponse, "aides": a}


def ordre(gainde, tuiles, cible, dit, a):
    return {"type": "ordre", "gainde": gainde, "tuiles": tuiles, "cible": cible, "dit": dit, "aides": a}


def trou(gainde, avant, apres, accepte, dit, a):
    return {"type": "trou", "gainde": gainde, "avant": avant, "apres": apres, "accepte": accepte, "dit": dit, "aides": a}


def libre(gainde, cles, a):
    return {"type": "libre", "gainde": gainde, "cles": cles, "aides": a}


def tour(qui, en, fr, cles, modele, reponse):
    return {"qui": qui, "en": en, "fr": fr, "cles": cles, "modele": modele, "reponse": reponse}


def mission(id, titre, jesais, expressions, mots, scene, questions, marches, pourdevrai, carnet, histoire=""):
    return {
        "id": id, "titre": titre, "histoire": histoire or titre, "jesais": jesais, "expressions": expressions,
        "mots": mots, "scene": scene, "questions": questions, "marches": marches,
        "pourdevrai": pourdevrai, "carnet": carnet, "difficile": DIFFICILE,
    }


def ex(question, options, reponse, explication):
    return {"question": question, "options": options, "reponse": reponse, "explication": explication}


def unite(id, titre, production, missions, lignes, mots, pieges, exercices):
    """lignes : [(fonction, en)] · mots : [(en, fr, wo)] · pieges : [str]"""
    return {
        "id": id, "titre": titre, "production": production, "missions": missions,
        "revision": {
            "lignes": [{"fonction": f, "en": e} for f, e in lignes],
            "mots": [{"en": e, "fr": f, "wo": w} for e, f, w in mots],
            "pieges": pieges,
        },
        "exercices": exercices,
    }


def perso(id, x, taille=90, anim=None, flip=False):
    p = {"id": id, "x": x, "taille": taille}
    if anim:
        p["anim"] = anim
    if flip:
        p["flip"] = True
    return p


def bulle(en, fr, x, y):
    return {"en": en, "fr": fr, "x": x, "y": y}


def case(fond, persos, bulles):
    return {"fond": fond, "persos": persos, "bulles": bulles}


def episode(titre, apres, cases, mots):
    """apres : id de la mission après laquelle l'épisode s'ouvre (ex. "5e-u1-m2")."""
    return {"titre": titre, "apres": apres, "cases": cases, "mots": mots}
