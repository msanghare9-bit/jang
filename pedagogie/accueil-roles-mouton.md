# Accueil modifiable, profs par matière, et le mouton de l'élève

## 1. Modifier l'accueil depuis l'admin

Aujourd'hui, les messages de l'accueil (« Na nga def… », les bulles d'Awa, Modou, Gaïndé…)
sont écrits dans le code : pour les changer, il faut une nouvelle version de l'app. Ils
deviennent **modifiables depuis l'admin, sans nouvelle version**.

**Admin › Accueil** permet de modifier :

| Élément | Ce qu'on peut faire |
|---|---|
| **Message de bienvenue** | Écrire plusieurs messages. L'app en choisit un au hasard. On peut utiliser `{prénom}` et `{jours}` (la série de jours). |
| **Bulles des personnages** | Pour chaque personnage (Gaïndé, Awa, Modou, Doudou, Kocc Barma) : ajouter, modifier, supprimer ses petites phrases. |
| **Bannière du moment** | Un texte court, une couleur, un lien vers une mission ou une annonce. Avec une date de début et une date de fin (par exemple pour la Tabaski ou le BFEM blanc). |
| **Blocs de l'accueil** | Afficher ou cacher : le mouton, l'histoire, les révisions du jour, la bannière. |

- On peut viser **tous les élèves**, **un niveau**, **une matière** ou **une matière dans un niveau**
  (comme pour les annonces).
- Un **aperçu** montre l'accueil comme l'élève le verra avant de publier.
- Les textes doivent rester en **français très simple**.
- Technique : les textes sont rangés dans Firestore (`config/accueil`). L'app les lit au
  démarrage et les garde pour le hors-ligne. C'est gratuit.

## 2. Les profs : un admin et des profs par matière

Pour l'instant, **tu es le seul admin**. Tu pourras **ajouter des profs** quand tu le voudras,
pour une ou plusieurs matières.

| Rôle | Qui | Ce qu'il peut faire |
|---|---|---|
| **Admin** | Toi | Tout : contenus, accueil, annonces à tous, élèves, statistiques, **ajouter ou retirer des profs**, supprimer des élèves. |
| **Prof** | Un prof que tu ajoutes, pour une ou plusieurs matières, dans un ou plusieurs niveaux | Voir **ses** élèves et leurs progrès dans **sa** matière. Leur envoyer des messages. Faire des annonces **dans sa matière** (et ses niveaux). Modifier les contenus de sa matière **si tu lui en donnes le droit**. |
| **Élève** | Les élèves | L'app normale. |

- **Ajouter un prof** : Admin › Profs › « Ajouter un prof ». Tu choisis un élève déjà inscrit ou
  tu crées un compte (identifiant et mot de passe). Puis tu coches ses matières et ses niveaux
  (par exemple : Anglais en 6e et 5e).
- Tu peux **retirer** un prof ou changer ses matières à tout moment.
- Un prof **ne peut pas** supprimer d'élève, ni faire d'annonce à tous les élèves, ni ajouter
  d'autres profs.
- Les messages d'un prof sont signés de son nom (« M. Diallo, prof d'anglais »).
- Technique : chaque compte a un rôle (`admin`, `prof`, `eleve`) et, pour un prof, la liste de
  ses matières et niveaux. Les règles de sécurité de Firestore vérifient ce que chacun a le
  droit de lire et d'écrire. C'est gratuit.

## 3. Le mouton de l'élève (remplace la plante)

Sur l'accueil, la plante devient **un petit mouton que l'élève élève**. C'est très sénégalais :
tout le monde connaît la fierté d'avoir un beau mouton, comme un ladoum.

### Comment il grandit

- L'élève **donne un nom** à son mouton le premier jour.
- Le mouton **grandit à chaque mission terminée** (et un peu plus avec les exercices de fin
  d'unité).

| Étape | Après… | Le mouton |
|---|---|---|
| 1. Agneau | le début | tout petit, il tient à peine debout |
| 2. Petit mouton | 5 missions | il saute partout |
| 3. Jeune mouton | 12 missions | il a de petites cornes |
| 4. Beau mouton | 20 missions | grandes cornes, belle laine |
| 5. Ladoum champion | 30 missions (la fin de l'année) | énorme, majestueux, avec un collier |

- À la fin de chaque unité, l'élève gagne **un accessoire** pour son mouton : collier de
  perles, ruban, grelot, couverture brodée…
- **Il ne meurt jamais et ne rétrécit jamais.** Si l'élève ne vient pas pendant 3 jours :
  « Ton mouton a faim ! Une mission pour lui donner à manger ? »

### Comparer avec les autres

- Pour motiver, l'app compare avec **un camarade du même niveau, un peu en avance** :
  « Le mouton de Khady a grandi plus vite cette semaine ! On le rattrape ? »
- Et elle fête quand on dépasse quelqu'un : « Ton mouton a dépassé celui de Modou ! »
- **Pas de grand classement de toute la classe**, pour ne pas décourager les élèves qui ont
  du mal. On compare toujours avec quelqu'un de **proche**.
- On n'affiche que le **prénom**. Un élève peut choisir de cacher son prénom : il apparaît alors
  comme « un élève de ta classe ».
- La comparaison porte sur **la semaine** : tout le monde peut gagner, même celui qui a commencé
  en retard.

### Technique

- La taille du mouton = le nombre de missions terminées (déjà enregistré dans la progression).
- Pour comparer, l'app lit les compteurs de la semaine des élèves du même niveau (un seul
  chiffre par élève, pas leurs résultats). Gratuit.
- Le mouton est dessiné en SVG comme les autres personnages, avec ses 5 étapes et ses
  accessoires.
