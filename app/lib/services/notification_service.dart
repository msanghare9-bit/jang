import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Rappel quotidien : un message différent chaque jour de la semaine, à 18 h.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _done = false;

  // Indice = jour de la semaine (1 = lundi … 7 = dimanche), 0 inutilisé.
  static const _messages = [
    '',
    'Gaïndé t\'attend ! Nouvelle semaine, nouvelle leçon 🦁',
    '10 minutes de révision aujourd\'hui ? Tes fiches t\'attendent 📚',
    'La pirogue de Modou t\'attend : 10 bonnes réponses pour une belle pêche 🐟',
    'Tu ne comprends pas une leçon ? Demande à Kocc Barma, ton prof 📘',
    'Doudou a sorti son tama : fais tes exercices pour l\'entendre 🥁',
    'Le week-end commence : une petite révision avant de te reposer ? 😊',
    'Prépare ta semaine : révise une leçon aujourd\'hui 🌱',
  ];

  /// Programme les rappels (une fois par lancement). Sans effet en cas d'erreur.
  Future<void> init() async {
    if (_done) return;
    _done = true;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Dakar'));
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      for (var d = 0; d < 7; d++) {
        await _plugin.cancel(100 + d);
      }
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'rappel_quotidien',
          'Rappel quotidien',
          channelDescription: 'Un petit rappel chaque jour pour travailler',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      final now = tz.TZDateTime.now(tz.local);
      final today18 = tz.TZDateTime(tz.local, now.year, now.month, now.day, 18);
      for (var d = 0; d < 7; d++) {
        var when = today18.add(Duration(days: d));
        if (when.isBefore(now)) when = when.add(const Duration(days: 7));
        await _plugin.zonedSchedule(
          100 + d,
          'Jàng',
          _messages[when.weekday],
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    } catch (e) {
      debugPrint('Rappels indisponibles : $e');
    }
  }
}
