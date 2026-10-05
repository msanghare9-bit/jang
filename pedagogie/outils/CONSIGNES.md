# Consignes pour écrire les missions d'anglais (6e à 3e)

À lire avant d'écrire un fichier dans `pedagogie/outils/unites/`.

## À lire d'abord
- `pedagogie/modele.md` : le modèle pédagogique (règles importantes).
- `pedagogie/syllabus/<niveau>.md` : la liste officielle des unités et des missions. **Suis-la
  exactement** : mêmes titres de missions, même « Je sais… », mêmes expressions clés, même
  ordre, même nombre de missions, même production d'unité.
- `pedagogie/outils/unites/6e_u1-2.py` : **le modèle à imiter**. Même niveau de détail, même ton.
- `pedagogie/outils/jang_lib.py` : les fonctions à utiliser (`mission`, `mot`, `r`, `q`, `aides`,
  `choix`, `ordre`, `trou`, `libre`, `tour`, `ex`, `unite`, `episode`, `case`, `perso`, `bulle`).
- `pedagogie/histoires/6e-unite1.md` : exemple du ton des histoires (très drôles, simples).

## Le fichier à écrire
```python
"""Parcours d'anglais de 5e, unités 1 à 3."""
from jang_lib import *  # noqa: F401,F403

NIVEAU = "5e"
u1 = [mission("5e-u1-m1", ...), ...]
unite1 = unite("5e-u1", "My big family", "production…", u1, lignes=[...], mots=[...], pieges=[...], exercices=[...])
...
UNITES = [unite1, unite2, unite3]
EPISODES = [episode("Titre drôle", "5e-u1-m2", [case(...), ...], ["mots", "du", "épisode"]), ...]
```
Vérifier : `python3 pedagogie/outils/build.py --check unites/<ton fichier>.py` (depuis la racine du
dépôt). **Corrige jusqu'à « Tout est bon. »** Ne modifie aucun autre fichier. Ne fais pas de commit.

## Une mission (6 temps)
1. **mots** : une image (`fond` + 3-4 emojis `objets`) et 6 à 8 mots en anglais : 4-5 bons, 2-3
   pièges. Chaque mot a une explication courte (« Oui ! « X », c'est … » / « « X », c'est …. Il
   n'y a pas de … Regarde encore ! »).
2. **scene** : 3 ou 4 répliques courtes (en + fr) entre 2 ou 3 personnages, qui montrent les
   expressions de la mission dans une situation de la vie au Sénégal. `gainde` : ce que Gaïndé
   se demande (curieux, drôle).
3. **questions** : 2 questions de compréhension (3 options, `rejouer` = n° de la réplique à
   réécouter, à partir de 0).
4. **marches** : exactement 4, dans cet ordre : `choix`, `ordre`, `trou`, `libre`. Gaïndé se
   trompe (au niveau de la classe, voir le syllabus : « Ce que fait Gaïndé ») et l'élève l'aide.
   Chaque marche a 4 `aides` (échelle de Kocc Barma, **jamais la réponse directe avant la 3e**) :
   question qui fait réfléchir → {rejouer: n, texte} → modèle « Moi, je dis : … » → sens.
   - `ordre` : `tuiles` mélangées, `cible` = la phrase sans ponctuation, `dit` = la phrase écrite.
   - `trou` : `accepte` = toutes les bonnes réponses possibles.
   - `libre` : `cles` = groupes de mots obligatoires ; dans un groupe, `a|b` = a ou b.
     Les clés doivent être courtes et sûres (ex. `["good at", "drawing|singing|dancing"]`).
5. **pourdevrai** : 1 ou 2 `tour` : un personnage parle à l'élève, l'élève répond pour de vrai.
   `cles` comme plus haut, `modele` = une bonne réponse (qui contient les clés), `reponse` = ce
   que le personnage répond après.
6. **carnet** : les expressions à garder (2 à 5).
- `jesais` : en français très simple, comme dans le syllabus (« dire ce que j'aime »).

## Fin d'unité
- `lignes` : une ligne par mission : (fonction en français simple, expressions en anglais
  séparées par « · »).
- `mots` : 7 à 12 mots (en, fr, wolof). Le wolof doit être correct ; si tu n'es pas sûr d'un mot,
  choisis un mot plus courant que tu connais bien.
- `pieges` : 3 erreurs fréquentes des élèves francophones (« I'm eleven. Pas « I have eleven years » »).
- `exercices` : exactement 10 QCM, 4 options toutes différentes, une explication courte.
- `production` : celle du syllabus, en français simple.

## Les histoires (un épisode toutes les 2 missions)
- Dans chaque unité : un épisode après la mission 2, après la 4, après la 6, et après la dernière
  mission si l'unité en a un nombre impair. `apres` = l'id de cette mission.
- Chaque épisode reprend **les expressions des 2 missions qui le précèdent**, et seulement
  elles (plus des mots très simples déjà vus). 3 à 5 cases, 1 à 3 personnages et 1 à 3 bulles
  par case, phrases anglaises très courtes.
- **Très drôle** : Gaïndé fait une grosse bêtise, un malentendu, un gag visuel ; chute à la
  dernière case. Les parenthèses dans `fr` peuvent décrire l'action : « (il s'assoit sur le
  chapeau de Kocc Barma) ».
- Positions : `x` des personnages 0 à 0.8 (gauche → droite), bulles `x` 0 à 0.7, `y` 0 à 0.6.
  Regarde les exemples pour placer les bulles près de celui qui parle.

## Ce qui existe dans l'app
- Fonds : cour, classe, maison, marche, mer, nuit, plage, terrain, bibliotheque.
- Personnages : gainde (le lionceau, apprend l'anglais), awa (fille, maligne), modou (garçon,
  drôle, fan de foot), doudou (le griot, musicien, tama), kocc (Kocc Barma, le jeune prof sage
  aux quatre touffes), mouton, bouc, pirogue, poisson.
- Animations (`anim`) : saute, balance, danse, danse2, tangue, immobile.

## Le français
Très simple : phrases courtes, mots courants, pas de mots de grammaire (pas de « gérondif »,
« prétérit », « comparatif »…). On dit « épeler ». On tutoie l'élève.
L'anglais est britannique simple (colour, mum), au niveau de la classe.
