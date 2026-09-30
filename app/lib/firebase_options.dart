import 'package:firebase_core/firebase_core.dart';

/// Paramètres du projet Firebase de Jàng (ces valeurs ne sont pas secrètes :
/// la protection des données est assurée par les règles de sécurité Firestore).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '__API_KEY__',
    appId: '__APP_ID__',
    messagingSenderId: '__SENDER_ID__',
    projectId: '__PROJECT_ID__',
    storageBucket: '__PROJECT_ID__.firebasestorage.app',
  );
}
