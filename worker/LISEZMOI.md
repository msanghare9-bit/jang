# Notifications push de Jàng (gratuit)

Ce petit serveur envoie les notifications push (messages des profs et annonces) et supprime
les comptes des élèves. Il tourne sur **Cloudflare Workers**, gratuit jusqu'à 100 000
utilisations par jour, **sans carte bancaire**. Firebase reste sur l'offre gratuite.

Sans ce serveur, l'app marche quand même : les élèves voient les messages et les annonces en
ouvrant l'app. Le serveur ajoute seulement la notification sur le téléphone.

## À faire une seule fois (environ 15 minutes)

### 1. La clé secrète de Firebase

1. Ouvre la console Firebase, projet **jang-ea5f3**.
2. Roue dentée › **Paramètres du projet** › onglet **Comptes de service**.
3. Clique sur **Générer une nouvelle clé privée**. Un fichier `.json` se télécharge.
4. Garde ce fichier secret : ne le mets jamais sur GitHub.

### 2. Le compte Cloudflare

1. Crée un compte gratuit sur https://dash.cloudflare.com (une adresse e-mail suffit).

### 3. Mettre le serveur en ligne

Sur un ordinateur avec Node.js :

```bash
cd worker
npx wrangler login              # ouvre le navigateur pour se connecter à Cloudflare
npx wrangler deploy             # met le serveur en ligne
npx wrangler secret put SERVICE_ACCOUNT
# colle tout le contenu du fichier .json de l'étape 1, puis Entrée
```

À la fin de `deploy`, Cloudflare affiche une adresse comme
`https://jang-push.<ton-nom>.workers.dev`.

### 4. Donner l'adresse à l'app

Dans la console Firebase › **Firestore** › collection `config` › document `app`
(crée-le s'il n'existe pas) : ajoute le champ texte

```
pushUrl = https://jang-push.<ton-nom>.workers.dev
```

C'est tout. Dans l'app admin, l'écran « Nouvelle annonce » indique maintenant que les élèves
recevront une notification sur leur téléphone.

## Ce que fait le serveur

| Route | Qui | Rôle |
|---|---|---|
| `POST /send` (annonce) | admin, ou prof dans ses matières | notification à un groupe (tous, un niveau, une matière, une matière dans un niveau) |
| `POST /send` (message) | admin, prof | notification à un ou plusieurs élèves |
| `POST /delete-user` | admin | supprime le compte de connexion d'un élève |
| toutes les 5 minutes | — | envoie les annonces programmées et ce qui a été retenu la nuit |

- **Pas de notification la nuit** : entre 21 h et 7 h (heure de Dakar), tout attend 7 h.
- Le serveur vérifie le jeton de connexion de la personne et son rôle avant d'agir.
