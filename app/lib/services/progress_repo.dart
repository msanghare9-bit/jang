import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

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
    final p = _byLesson[lesson.id];
    if (p != null && p.seen) return;
    _byLesson[lesson.id] = LessonProgress(
      lessonId: lesson.id,
      subjectId: lesson.subjectId,
      seen: true,
      lastScore: p?.lastScore,
      bestScore: p?.bestScore,
      total: p?.total ?? 0,
      attempts: p?.attempts ?? 0,
    );
    unawaited(_col(uid).doc(lesson.id).set({
      'subjectId': lesson.subjectId,
      'examId': lesson.examId,
      'seen': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('$e')));
    revision.value++;
  }

  void recordQuiz(Lesson lesson, int score, int total) {
    final uid = _uid;
    if (uid == null) return;
    unawaited(_markStudied());
    final p = _byLesson[lesson.id];
    final best = (p?.bestScore == null || score > p!.bestScore!) ? score : p.bestScore!;
    final attempts = (p?.attempts ?? 0) + 1;
    _byLesson[lesson.id] = LessonProgress(
      lessonId: lesson.id,
      subjectId: lesson.subjectId,
      seen: true,
      lastScore: score,
      bestScore: best,
      total: total,
      attempts: attempts,
    );
    unawaited(_col(uid).doc(lesson.id).set({
      'subjectId': lesson.subjectId,
      'examId': lesson.examId,
      'seen': true,
      'lastScore': score,
      'bestScore': best,
      'total': total,
      'attempts': attempts,
      'lastQuizAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('$e')));
    revision.value++;
  }
}
