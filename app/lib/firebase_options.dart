import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Paramètres du projet Firebase de Jàng (ces valeurs ne sont pas secrètes :
/// la protection des données est assurée par les règles de sécurité Firestore).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => kIsWeb ? web : android;

  // À remplacer par la configuration Web de l'application Firebase jang-ea5f3.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('JANG_FIREBASE_WEB_API_KEY'),
    appId: String.fromEnvironment('JANG_FIREBASE_WEB_APP_ID'),
    messagingSenderId: '931795301492',
    projectId: 'jang-ea5f3',
    authDomain: 'jang-ea5f3.firebaseapp.com',
    storageBucket: 'jang-ea5f3.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCbal9_LtoEZt0jm8KedzzwYb58KmxNE50',
    appId: '1:931795301492:android:280ff832a0665a41a5cd21',
    messagingSenderId: '931795301492',
    projectId: 'jang-ea5f3',
    storageBucket: 'jang-ea5f3.firebasestorage.app',
  );
}
