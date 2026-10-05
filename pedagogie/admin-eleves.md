# Espace admin : aider, annoncer, supprimer

Trois nouvelles actions dans **Admin › Élèves** : **envoyer un message** à un élève pour
l'aider, **faire une annonce** à un groupe d'élèves, et **supprimer** un élève. Toutes
envoient des **notifications push**. Elles valent pour toutes les classes (collège et lycée).

## Ce qui existe déjà

- La liste des élèves, avec recherche et tri (activité, nom, résultats).
- La fiche d'un élève : identifiant, dernière activité, résultats par leçon.
- « Bloquer dans les discussions ».

## 1. Envoyer un message

### Côté prof (admin)

- Depuis la **fiche d'un élève** : bouton « Envoyer un message ».
- Depuis la **liste** : on coche plusieurs élèves (par exemple tous ceux qui ne sont pas venus
  depuis 7 jours), puis « Envoyer un message ».
- **Messages tout prêts**, modifiables avant l'envoi :
  - « Bravo pour ton travail ! Continue comme ça. »
  - « Je vois que la mission « … » est difficile. Tu veux de l'aide ? »
  - « On ne t'a pas vu depuis quelques jours. Gaïndé t'attend ! »
  - « Pense à faire les exercices de l'unité. »
- Le prénom de l'élève et le nom de la mission sont ajoutés automatiquement quand c'est utile.
- Le prof voit si l'élève **a lu** le message, et sa réponse.

### Côté élève

- À l'ouverture de l'app, une carte **« Message de ton prof »** s'affiche sur l'accueil,
  apportée par Jàngalekat.
- Le message reste dans **Moi › Mes messages**.
- L'élève peut répondre en un geste : « Merci ! », « J'ai une question » (il écrit sa
  question), ou un message vocal.
- Une **notification push** arrive sur le téléphone, même si l'app est fermée.

### Règles

- Seul l'admin (le prof) peut écrire à un élève. **Pas de messages privés entre élèves.**
- Les messages sont courts, bienveillants et en **français très simple**.
- Tous les messages sont gardés (pour pouvoir les relire en cas de problème).

### Technique

- Les messages sont rangés dans le compte de l'élève (`users/{élève}/messages`).
- L'élève reçoit une **notification push**, même quand l'app est fermée (voir plus bas).

## 2. Faire une annonce

Une annonce est un message du prof à **un groupe d'élèves**. Le prof choisit à qui :

| Pour qui ? | Exemple |
|---|---|
| **Tous les élèves** | « L'app est mise à jour : découvre les nouvelles histoires ! » |
| **Un niveau** | « 3e : le BFEM blanc commence lundi. » |
| **Une matière** (tous les niveaux) | « Anglais : un nouveau jeu de cartes de révision est disponible. » |
| **Une matière dans un niveau** | « Anglais 4e : l'unité « Climate » est ouverte. » |

- Avant l'envoi, l'app indique **combien d'élèves** recevront l'annonce.
- Le prof peut envoyer **maintenant** ou **programmer** l'annonce (date et heure).
- Côté élève : notification push, puis l'annonce s'affiche sur l'accueil et reste dans
  **Moi › Mes messages**.
- Le prof voit combien d'élèves l'ont lue.
- Une annonce n'a pas de réponse (pour les questions, l'élève passe par les messages).

## 3. Les notifications push

Les messages et les annonces arrivent sur le téléphone **même quand l'app est fermée**.

- Toucher la notification ouvre directement le message ou l'annonce dans Jàng.
- Les rappels du soir qui existent déjà continuent comme avant.
- L'élève peut couper les annonces dans ses réglages, mais pas les messages de son prof.
- Pas de notifications la nuit : celles envoyées entre 21 h et 7 h attendent 7 h.

### Technique

- On ajoute **Firebase Cloud Messaging** (`firebase_messaging`) à l'app.
- Chaque téléphone s'abonne à des **sujets** qui correspondent à ses choix :
  `tous`, `niveau_4e`, `matiere_anglais`, `anglais_4e`… Une annonce est envoyée au bon sujet.
- L'envoi se fait par une **petite fonction sur le serveur** (Firebase Cloud Functions),
  déclenchée quand le prof enregistre un message ou une annonce. L'app admin ne peut pas
  envoyer de push directement.
- Cela demande un projet Firebase avec la facturation activée (le coût reste très faible
  pour quelques milliers d'élèves).

## 4. Supprimer un élève

Deux niveaux, pour éviter les erreurs :

| Action | Ce qui se passe | Réversible ? |
|---|---|---|
| **Désactiver** | L'élève ne peut plus se connecter. Ses résultats sont gardés. Il disparaît des statistiques. | Oui : « Réactiver » |
| **Supprimer définitivement** | Le compte, les résultats, les messages et les enregistrements de l'élève sont effacés. | Non |

- **Confirmation** avant de supprimer : le prof doit taper le prénom de l'élève.
- On peut aussi sélectionner plusieurs élèves (par exemple des comptes de test) et les
  désactiver ou les supprimer ensemble.
- Chaque suppression est notée dans un journal (qui, quand), sans garder les données de l'élève.

### Technique (pour plus tard)

- « Désactiver » se fait directement depuis l'app admin.
- « Supprimer définitivement » le compte de connexion demande une petite fonction sur le
  serveur (Firebase ne permet pas de supprimer le compte d'un autre utilisateur depuis
  l'app). En attendant, on peut effacer les données et désactiver le compte.
