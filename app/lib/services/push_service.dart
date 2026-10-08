import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'auth_service.dart';
import 'content_repo.dart';

/// Nom de sujet (topic) accepté par Firebase Cloud Messaging.
String pushTopic(String raw) => raw.replaceAll(RegExp(r'[^a-zA-Z0-9_.~%-]'), '_');

/// Sujets d'une annonce : tous, un niveau, une matière, ou une matière dans un niveau.
String announcementTopic(String examId, String subject) {
  if (examId.isEmpty && subject.isEmpty) return 'tous';
  if (subject.isEmpty) return pushTopic('niveau_$examId');
  if (examId.isEmpty) return pushTopic('mat_$subject');
  return pushTopic('mat_${subject}_$examId');
}

/// Notifications push (Firebase Cloud Messaging).
///
/// Réception : le téléphone s'abonne à ses sujets (tous, son niveau, ses matières).
/// Envoi : l'app admin demande au petit serveur gratuit (Cloudflare Worker, adresse dans
/// config/app.pushUrl) d'envoyer la notification. Sans adresse, rien n'est envoyé, mais les
/// messages restent visibles dans l'app.
class PushService {
  PushService._();
  static final instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();
  bool _started = false;
  String? _pushUrl;

  /// Appelé quand on touche une notification : l'accueil ouvre « Mes messages ».
  final ValueNotifier<int> opened = ValueNotifier(0);

  Future<void> start(UserProfile profile) async {
    if (kIsWeb) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel('messages', 'Messages et annonces',
              description: 'Messages de ton prof et annonces', importance: Importance.high));
      final token = await fm.getToken();
      if (token != null) {
        unawaited(FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .update({'fcmToken': token}).catchError((_) {}));
      }
      await _subscribe(profile);
      if (_started) return;
      _started = true;
      fm.onTokenRefresh.listen((t) {
        final p = AuthService.instance.profile.value;
        if (p != null) {
          FirebaseFirestore.instance.collection('users').doc(p.uid).update({'fcmToken': t}).catchError((_) {});
        }
      });
      // App ouverte : Android n'affiche pas la notification, on la montre nous-mêmes.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        _local.show(
          m.hashCode,
          n.title,
          n.body,
          const NotificationDetails(
            android: AndroidNotificationDetails('messages', 'Messages et annonces',
                channelDescription: 'Messages de ton prof et annonces',
                importance: Importance.high,
                priority: Priority.high),
          ),
        );
        opened.value++;
      });
      FirebaseMessaging.onMessageOpenedApp.listen((_) => opened.value++);
      final initial = await fm.getInitialMessage();
      if (initial != null) opened.value++;
    } catch (e) {
      debugPrint('Notifications push indisponibles : $e');
    }
  }

  Future<void> _subscribe(UserProfile p) async {
    final want = <String>{'tous'};
    if (p.examId.isNotEmpty) {
      want.add(pushTopic('niveau_${p.examId}'));
      for (final s in await ContentRepo.instance.subjects(p.examId)) {
        final k = subjectKey(s.name);
        want.add(pushTopic('mat_$k'));
        want.add(pushTopic('mat_${k}_${p.examId}'));
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final muted = prefs.getBool('annonces_muted') ?? false;
    if (muted) want.clear();
    final had = (prefs.getStringList('push_topics') ?? const []).toSet();
    final fm = FirebaseMessaging.instance;
    for (final t in had.difference(want)) {
      await fm.unsubscribeFromTopic(t);
    }
    for (final t in want.difference(had)) {
      await fm.subscribeToTopic(t);
    }
    await prefs.setStringList('push_topics', want.toList());
  }

  /// L'élève coupe ou rallume les annonces (les messages du prof arrivent toujours).
  Future<void> setAnnouncementsMuted(bool muted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('annonces_muted', muted);
    final p = AuthService.instance.profile.value;
    if (p != null) await _subscribe(p);
  }

  Future<bool> announcementsMuted() async =>
      (await SharedPreferences.getInstance()).getBool('annonces_muted') ?? false;

  Future<String?> _url() async {
    if (_pushUrl != null) return _pushUrl;
    try {
      final d = await FirebaseFirestore.instance.collection('config').doc('app').get();
      final u = d.data()?['pushUrl'];
      if (u is String && u.startsWith('https://')) _pushUrl = u;
    } catch (_) {}
    return _pushUrl;
  }

  /// Vrai si l'envoi des notifications push est configuré.
  Future<bool> configured() async => (await _url()) != null;

  /// Demande au serveur d'envoyer une notification. Renvoie vrai si c'est parti.
  Future<bool> send(Map<String, dynamic> payload, {String path = '/send'}) async {
    if (kIsWeb) return false;
    final url = await _url();
    final token = await AuthService.instance.idToken();
    if (url == null || token == null) return false;
    try {
      final res = await http.post(Uri.parse('$url$path'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode(payload)).timeout(const Duration(seconds: 30));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Envoi de la notification impossible : $e');
      return false;
    }
  }
}
