# Banque de questions des matchs (façon Kahoot)

Public : élèves sénégalais du collège et du lycée, francophones, qui apprennent l'anglais.
Ils lisent mal le français : les explications sont en **français très simple**, courtes, on tutoie.

## Format (un fichier = 200 questions)
`pedagogie/quiz/<domaine>_<niveau>_<n>.json` (n = 1 à 5) :
```json
{"questions": [
  {"q": "What colour is a banana?", "o": ["Blue", "Yellow", "Black", "Pink"], "r": 1,
   "e": "Une banane est jaune : yellow."}
]}
```
- `q` : la question (220 caractères max). `o` : exactement 4 réponses, toutes différentes, courtes
  (80 max). `r` : position de la bonne réponse (0 à 3). `e` : explication (200 max).
- `t` : seulement en **compréhension** : le petit texte en anglais à lire (20 à 500 caractères).
- **Une seule bonne réponse, sans discussion possible.** Les 3 autres sont fausses mais crédibles
  (même catégorie, même forme), jamais absurdes ni moqueuses.
- **Mélange la place de la bonne réponse** : environ 25 % en position 0, 1, 2 et 3.
- Pas de doublons, pas de questions presque identiques (change vraiment le contenu, pas seulement
  un mot). Varie les thèmes et les formes de questions.
- Vérifier : `python3 pedagogie/outils/quiz_check.py --check pedagogie/quiz/<domaine>_<niveau>_*.json`
  jusqu'à « Tout est bon. ».

## Niveaux
- **debutant** (6e–5e, A1) : mots très courants, phrases de 3 à 8 mots, présent simple, be/have,
  can, couleurs, nombres, famille, école, corps, nourriture, maison, jours, mois, heure, animaux,
  métiers simples, salutations. La question peut être en français simple (« Comment dit-on
  « chèvre » en anglais ? ») ou en anglais très simple.
- **intermediaire** (4e–3e, A2) : passé (simple, présent parfait de base), futur, comparatifs,
  modaux (should, must, have to), quantités, phrasal verbs très courants, conseils, sentiments,
  santé, voyages, sports, environnement, médias. Questions en anglais simple.
- **avance** (lycée, B1–B2) : temps variés, conditionnels, voix passive, discours rapporté,
  relatives, vocabulaire plus riche (société, économie, sciences, citoyenneté), expressions
  idiomatiques, nuances. Questions en anglais.

## Domaines
- **vocabulaire** : sens des mots, mot qui manque, intrus, contraire, synonyme, image décrite par
  des mots, familles de mots. Contexte sénégalais et africain bienvenu (marché, pirogue, baobab,
  thiéboudienne, lutte, taxi-brousse…).
- **grammaire** : une phrase à compléter ou à corriger (« She ___ to school every day. »). La
  règle est donnée simplement dans `e`, sans jargon (pas « gérondif », « prétérit » : dis « avec
  -ing », « au passé »…).
- **expressions** : ce qu'on dit dans une situation (saluer, s'excuser, demander son chemin,
  au téléphone, au marché, féliciter, refuser poliment…), et le sens d'expressions toutes faites.
  « Tu arrives en retard en classe. Tu dis : … ».
- **comprehension** : `t` = un petit texte en anglais (2 à 5 phrases au débutant, jusqu'à 8 à
  l'avancé : SMS, annonce, petite histoire, lettre, article, dialogue) ; `q` = une question sur le
  texte. Plusieurs questions peuvent porter sur des textes différents ; ne réutilise pas le même
  texte plus de 2 fois.
- **culture** : culture générale **en anglais**, au moins **60 % sur l'Afrique** (Sénégal en
  priorité : régions, villes, fleuves, histoire, Gorée, figures connues, fêtes, plats, musique,
  sport, faune ; puis toute l'Afrique : pays, capitales, géographie, histoire, inventions,
  personnalités, langues), le reste sur le monde (sciences, géographie, histoire, arts, sport).
  **Seulement des faits sûrs et qui ne changent pas** : pas de « président actuel », pas de
  chiffres de population précis, pas de records qui bougent, rien de politique ou religieux qui
  divise. Si tu as un doute sur un fait, ne mets pas la question. Le niveau joue sur l'anglais
  et la difficulté du fait (débutant : « What is the capital of Senegal? »).
