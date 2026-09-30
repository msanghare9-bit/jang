import 'package:firebase_core/firebase_core.dart';

/// Paramètres du projet Firebase de Jàng (ces valeurs ne sont pas secrètes :
/// la protection des données est assurée par les règles de sécurité Firestore).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCbal9_LtoEZt0jm8KedzzwYb58KmxNE50',
    appId: '1:931795301492:android:280ff832a0665a41a5cd21',
    messagingSenderId: '931795301492',
    projectId: 'jang-ea5f3',
    storageBucket: 'jang-ea5f3.firebasestorage.app',
  );
}
