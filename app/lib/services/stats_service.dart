import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Compteurs d'utilisation, envoyés par chaque téléphone.
///
/// - statsDays/{AAAA-MM-JJ} : élèves actifs, nouveaux comptes, leçons ouvertes, QCM faits.
/// - statsLessons/{leçon}   : élèves ayant ouvert la leçon, ayant fait le QCM, tentatives,
///                            somme des pourcentages, réussite par question.
/// Les écritures utilisent des incréments : elles fonctionnent aussi hors connexion.
class StatsService {
  StatsService._();
  static final instance = StatsService._();

  final _db = FirebaseFirestore.instance;

  static String dayKey([DateTime? d]) {
    final x = d ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${x.year}-${two(x.month)}-${two(x.day)}';
  }

  /// Identifiant stable d'une question (ne change pas si l'ordre des questions change).
  static String questionKey(String question) {
    var h = 0x811c9dc5;
    for (final c in question.trim().toLowerCase().codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return 'q${h.toRadixString(16).padLeft(8, '0')}';
  }

  void _inc(String collection, String id, Map<String, Object> fields) {
    final data = <String, Object>{
      for (final e in fields.entries) e.key: FieldValue.increment(e.value as num),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    unawaited(_db
        .collection(collection)
        .doc(id)
        .set(data, SetOptions(merge: true))
        .catchError((e) => debugPrint('Statistiques : $e')));
  }

  /// À appeler à chaque ouverture : compte l'élève une seule fois par jour.
  Future<void> recordActive(UserProfile profile) async {
    final today = dayKey();
    final prefs = await SharedPreferences.getInstance();
    final key = 'active_day_${profile.uid}';
    if (prefs.getString(key) == today) return;
    await prefs.setString(key, today);
    if (profile.role == 'student') _inc('statsDays', today, {'activeUsers': 1});
    unawaited(_db.collection('users').doc(profile.uid).set({
      'lastActiveDay': today,
      'lastActiveAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('$e')));
  }

  void recordNewUser() => _inc('statsDays', dayKey(), {'newUsers': 1});

  /// Première ouverture d'une leçon par cet élève.
  void recordLessonView(Lesson lesson) {
    _inc('statsDays', dayKey(), {'lessonViews': 1});
    _db.collection('statsLessons').doc(lesson.id).set({
      'examId': lesson.examId,
      'subjectId': lesson.subjectId,
      'views': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('Statistiques : $e'));
  }

  /// Un QCM soumis. [correct] indique pour chaque question si la réponse était juste.
  void recordQuiz(Lesson lesson, List<bool> correct, {required bool firstTime}) {
    _inc('statsDays', dayKey(), {'quizzes': 1});
    final total = correct.length;
    final score = correct.where((c) => c).length;
    final pct = total == 0 ? 0 : (score * 100 / total).round();
    final questions = <String, Object>{};
    for (var i = 0; i < lesson.quiz.length && i < correct.length; i++) {
      final k = questionKey(lesson.quiz[i].question);
      questions[k] = {
        'n': FieldValue.increment(1),
        'ok': FieldValue.increment(correct[i] ? 1 : 0),
      };
    }
    _db.collection('statsLessons').doc(lesson.id).set({
      'examId': lesson.examId,
      'subjectId': lesson.subjectId,
      'attempts': FieldValue.increment(1),
      'sumPct': FieldValue.increment(pct),
      if (firstTime) 'quizUsers': FieldValue.increment(1),
      if (firstTime) 'sumFirstPct': FieldValue.increment(pct),
      'questions': questions,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('Statistiques : $e'));
  }
}
