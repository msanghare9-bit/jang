import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'engagement_service.dart';
import 'stats_service.dart';

/// Progression de l'élève, enregistrée sur son compte (users/{uid}/progress/{leçon}).
class ProgressRepo {
  ProgressRepo._();
  static final instance = ProgressRepo._();

  final _db = FirebaseFirestore.instance;
  final ValueNotifier<int> revision = ValueNotifier(0);
  final Map<String, LessonProgress> _byLesson = {};
  String? _uid;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('progress');

  Map<String, LessonProgress> get all => Map.unmodifiable(_byLesson);
  LessonProgress? of(String lessonId) => _byLesson[lessonId];

  /// Charge la progression depuis le téléphone, puis récupère les changements en ligne.
  Future<void> load(String uid) async {
    if (_uid != uid) _byLesson.clear();
    _uid = uid;
    try {
      final s = await _col(uid).get(const GetOptions(source: Source.cache));
      for (final d in s.docs) {
        _byLesson[d.id] = LessonProgress.fromDoc(d);
      }
      revision.value++;
    } catch (_) {}
    unawaited(_syncFromServer(uid));
  }

  Future<void> _syncFromServer(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'progress_sync_$uid';
    final last = prefs.getInt(key) ?? 0;
    try {
      Query<Map<String, dynamic>> q = _col(uid);
      if (last > 0) {
        q = q.where('updatedAt', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(last));
      }
      final s = await q.get(const GetOptions(source: Source.server)).timeout(
            const Duration(seconds: 30),
          );
      var maxTs = last;
      for (final d in s.docs) {
        _byLesson[d.id] = LessonProgress.fromDoc(d);
        final ts = d.data()['updatedAt'];
        if (ts is Timestamp && ts.millisecondsSinceEpoch > maxTs) {
          maxTs = ts.millisecondsSinceEpoch;
        }
      }
      await prefs.setInt(key, maxTs);
      if (s.docs.isNotEmpty) revision.value++;
    } catch (_) {}
  }

  void clear() {
    _uid = null;
    _byLesson.clear();
    revision.value++;
  }

  Future<void> _markStudied() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_study_at', DateTime.now().millisecondsSinceEpoch);
  }

  void markSeen(Lesson lesson) {
    final uid = _uid;
    if (uid == null) return;
    unawaited(_markStudied());
    unawaited(EngagementService.instance.logStudy('lesson', lesson.id));
    final p = _byLesson[lesson.id];
    if (p != null && p.seen) return;
    StatsService.instance.recordLessonView(lesson);
    _bumpUser(uid, {'lessonsSeen': 1});
    _byLesson[lesson.id] = (p ?? LessonProgress(lessonId: lesson.id, subjectId: lesson.subjectId))
        .copyWith(seen: true);
    unawaited(_col(uid).doc(lesson.id).set({
      'subjectId': lesson.subjectId,
      'examId': lesson.examId,
      'seen': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('$e')));
    revision.value++;
  }

  void _bumpUser(String uid, Map<String, int> fields) {
    unawaited(_db.collection('users').doc(uid).set({
      for (final e in fields.entries) e.key: FieldValue.increment(e.value),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('$e')));
  }

  void recordQuiz(Lesson lesson, List<bool> correct) {
    final uid = _uid;
    if (uid == null) return;
    unawaited(_markStudied());
    final score = correct.where((c) => c).length;
    final total = correct.length;
    final p = _byLesson[lesson.id];
    if (p == null || !p.seen) {
      StatsService.instance.recordLessonView(lesson);
      _bumpUser(uid, {'lessonsSeen': 1});
    }
    StatsService.instance.recordQuiz(lesson, correct, firstTime: p?.quizDone != true);
    // Résumé sur la fiche de l'élève : nombre de QCM faits et somme des meilleures notes (en %).
    final newPct = total == 0 ? 0 : (score * 100 / total).round();
    final oldPct = (p?.quizDone == true && p!.total > 0) ? (p.bestScore! * 100 / p.total).round() : null;
    final bestPct = oldPct == null || newPct > oldPct ? newPct : oldPct;
    _bumpUser(uid, {
      'quizzesTaken': 1,
      if (oldPct == null) 'quizLessons': 1,
      'sumBestPct': bestPct - (oldPct ?? 0),
    });
    final best = (p?.bestScore == null || score > p!.bestScore!) ? score : p.bestScore!;
    final attempts = (p?.attempts ?? 0) + 1;
    // Questions à revoir : une erreur entre dans la liste ; une bonne réponse la fait avancer.
    final mistakes = Map<String, int>.from(p?.mistakes ?? const {});
    final mistakeChanges = <String, Object>{};
    for (var i = 0; i < lesson.quiz.length && i < correct.length; i++) {
      final k = StatsService.questionKey(lesson.quiz[i].question);
      if (!correct[i]) {
        mistakes[k] = 0;
        mistakeChanges[k] = 0;
      } else if (mistakes.containsKey(k)) {
        final n = mistakes[k]! + 1;
        if (n >= 2) {
          mistakes.remove(k);
          mistakeChanges[k] = FieldValue.delete();
          unawaited(EngagementService.instance.addTo('mistakes_fixed'));
        } else {
          mistakes[k] = n;
          mistakeChanges[k] = n;
        }
      }
    }
    _byLesson[lesson.id] = LessonProgress(
      lessonId: lesson.id,
      subjectId: lesson.subjectId,
      seen: true,
      lastScore: score,
      bestScore: best,
      total: total,
      attempts: attempts,
      mistakes: mistakes,
      vote: p?.vote ?? 0,
    );
    unawaited(_col(uid).doc(lesson.id).set({
      'subjectId': lesson.subjectId,
      'examId': lesson.examId,
      'seen': true,
      'lastScore': score,
      'bestScore': best,
      'total': total,
      'attempts': attempts,
      if (mistakeChanges.isNotEmpty) 'mistakes': mistakeChanges,
      'lastQuizAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('$e')));
    unawaited(EngagementService.instance.logStudy('quiz', lesson.id));
    revision.value++;
  }

  /// Résultat d'une question en « Révision des erreurs ».
  void recordReview(Lesson lesson, String questionKey, bool ok) {
    final uid = _uid;
    final p = _byLesson[lesson.id];
    if (uid == null || p == null || !p.mistakes.containsKey(questionKey)) return;
    final mistakes = Map<String, int>.from(p.mistakes);
    Object change;
    if (!ok) {
      mistakes[questionKey] = 0;
      change = 0;
    } else {
      final n = mistakes[questionKey]! + 1;
      if (n >= 2) {
        mistakes.remove(questionKey);
        change = FieldValue.delete();
        unawaited(EngagementService.instance.addTo('mistakes_fixed'));
      } else {
        mistakes[questionKey] = n;
        change = n;
      }
    }
    _byLesson[lesson.id] = p.copyWith(mistakes: mistakes);
    unawaited(_col(uid).doc(lesson.id).set({
      'mistakes': {questionKey: change},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('$e')));
    unawaited(_markStudied());
    revision.value++;
  }

  /// Nombre total de questions à revoir.
  int get mistakesCount => _byLesson.values.fold(0, (a, p) => a + p.mistakes.length);

  /// Avis sur une leçon : 1, -1 ou 0 pour annuler.
  void vote(Lesson lesson, int value) {
    final uid = _uid;
    if (uid == null) return;
    final p = _byLesson[lesson.id] ??
        LessonProgress(lessonId: lesson.id, subjectId: lesson.subjectId, seen: true);
    final old = p.vote;
    if (old == value) return;
    _byLesson[lesson.id] = p.copyWith(vote: value);
    StatsService.instance.recordVote(lesson, old, value);
    unawaited(_col(uid).doc(lesson.id).set({
      'subjectId': lesson.subjectId,
      'examId': lesson.examId,
      'vote': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('$e')));
    revision.value++;
  }
}
