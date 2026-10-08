import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../version.dart';

/// Vérification en arrière-plan (toutes les 6 heures environ, même application fermée).
@pragma('vm:entry-point')
Future<void> jangBackgroundCheck() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await UpdateNotifier.check();
}

/// Notifications « Nouvelles leçons » et « Mise à jour de l'application ».
class UpdateNotifier {
  UpdateNotifier._();

  static const _repo = 'msanghare9-bit/jang';
  static const _alarmId = 4242;

  /// Programme la vérification périodique. Sans effet en cas d'erreur.
  static Future<void> schedule() async {
    if (kIsWeb) return;
    try {
      await AndroidAlarmManager.initialize();
      await AndroidAlarmManager.periodic(
        const Duration(hours: 6),
        _alarmId,
        jangBackgroundCheck,
        startAt: DateTime.now().add(const Duration(minutes: 30)),
        rescheduleOnReboot: true,
      );
    } catch (e) {
      debugPrint('Vérification en arrière-plan indisponible : $e');
    }
    // Une première vérification tout de suite (enregistre l'état actuel).
    await check();
  }

  static Future<dynamic> _get(String path) async {
    final res = await http.get(Uri.parse('https://api.github.com/repos/$_repo$path'), headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'jang-app',
    }).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('GitHub ${res.statusCode}');
    return jsonDecode(res.body);
  }

  static Future<void> _notify(int id, String title, String body) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    await plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nouveautes',
          'Nouveautés',
          channelDescription: 'Nouvelles leçons et nouvelles versions de Jàng',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  /// Compare avec la dernière vérification et prévient l'élève s'il y a du nouveau.
  static Future<void> check() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await prefs.reload();
    } catch (e) {
      debugPrint('$e');
      return;
    }

    // 1. Nouvelles leçons : dernier changement du fichier des leçons sur GitHub.
    try {
      final list = await _get('/commits?path=contenus/lecons.json&per_page=1') as List;
      if (list.isNotEmpty) {
        final c = list.first as Map<String, dynamic>;
        final sha = (c['sha'] ?? '') as String;
        final message = (((c['commit'] as Map?)?['message']) ?? '') as String;
        final known = prefs.getString('notif_lessons_sha') ?? '';
        if (sha.isNotEmpty && sha != known) {
          await prefs.setString('notif_lessons_sha', sha);
          if (known.isNotEmpty) {
            final line = message.split('\n').first.trim();
            await _notify(301, 'Nouvelles leçons 📚',
                line.isEmpty ? 'De nouvelles leçons sont arrivées dans Jàng !' : '$line. Gaïndé t\'attend !');
          }
        }
      }
    } catch (e) {
      debugPrint('Leçons : $e');
    }

    // 2. Nouvelle version de l'application.
    try {
      final j = await _get('/releases/latest') as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '') as String;
      final m = RegExp(r'^v?([\d.]+)-(\d+)$').firstMatch(tag);
      if (m != null) {
        final build = int.parse(m.group(2)!);
        final told = prefs.getInt('notif_release_build') ?? 0;
        if (build > appBuild && build > told) {
          await prefs.setInt('notif_release_build', build);
          await _notify(302, 'Mise à jour ✨',
              'Jàng ${m.group(1)} est prête. Ouvre l\'application pour l\'installer.');
        }
      }
    } catch (e) {
      debugPrint('Version : $e');
    }
  }
}
