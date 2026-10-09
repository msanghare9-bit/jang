# Jàng sur le web et iPhone

Le workflow GitHub Actions construit Flutter Web et déploie le site ainsi que les règles Firestore sur Firebase Hosting. Ce déploiement reste compatible avec le forfait gratuit **Spark** : il ne déploie pas de Cloud Functions. Les trois secrets suivants doivent être définis dans **Settings → Secrets and variables → Actions** du dépôt :

- `JANG_FIREBASE_WEB_API_KEY` : clé API de l'application Web Firebase du projet `jang-ea5f3`.
- `JANG_FIREBASE_WEB_APP_ID` : identifiant de l'application Web Firebase, au format `1:931795301492:web:…`.
- `FIREBASE_TOKEN` : jeton de déploiement Firebase CLI autorisé pour `jang-ea5f3`.

Dans Firebase Console, enregistrer une application Web pour `jang-ea5f3`, activer **Authentication → Sign-in method → Email/Password**, puis ajouter le domaine Firebase Hosting à **Authentication → Settings → Authorized domains**. Le site utilise Firestore et doit être servi en HTTPS.

Après avoir défini les secrets, lancer le workflow **Construire l'APK et Déployer le Web** depuis **Actions → Run workflow**. Le site sera disponible à `https://jang-ea5f3.web.app` si ce domaine par défaut Firebase Hosting est activé pour le projet.

Les réponses des questions restent dans les banques publiques actuelles. Pour les garder privées, il faudra plus tard déployer un backend séparé (par exemple un Cloudflare Worker gratuit) et connecter l'application à ce backend. Cela n'est pas nécessaire pour publier le site sur Spark.

Sur iPhone, ouvrir l'adresse dans Safari. Pour l'ajouter à l'écran d'accueil : bouton **Partager → Sur l'écran d'accueil**. Les notifications locales et rappels Android ne sont pas disponibles dans la version web; l'application reste accessible dans Safari.
