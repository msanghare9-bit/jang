import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'auth_service.dart';
import 'engagement_service.dart';

/// Discussion publique des leçons (collection comments).
class DiscussionService {
  DiscussionService._();
  static final instance = DiscussionService._();

  final _db = FirebaseFirestore.instance;
  static const maxPerHour = 5;
  static const hideAfterReports = 3;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('comments');

  Future<List<Comment>> forLesson(String lessonId) async {
    QuerySnapshot<Map<String, dynamic>> s;
    try {
      s = await _col
          .where('lessonId', isEqualTo: lessonId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      s = await _col.where('lessonId', isEqualTo: lessonId).get(const GetOptions(source: Source.cache));
    }
    final list = s.docs.map(Comment.fromDoc).toList()
      ..sort((a, b) => (a.createdAt ?? DateTime(2100)).compareTo(b.createdAt ?? DateTime(2100)));
    return list;
  }

  /// Renvoie un message d'erreur, ou null si l'envoi est accepté.
  Future<String?> post(Lesson lesson, String text, {String parentId = ''}) async {
    final p = AuthService.instance.profile.value;
    if (p == null) return 'Connecte-toi d\'abord.';
    if (p.blocked) return 'Ton compte ne peut plus écrire dans la discussion.';
    final t = text.trim();
    if (t.length < 2) return 'Écris un message un peu plus long.';
    if (t.length > 1000) return 'Message trop long (1000 caractères au maximum).';
    if (!p.isAdmin) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'posts_${p.uid}';
      final now = DateTime.now().millisecondsSinceEpoch;
      final recent = (prefs.getStringList(key) ?? const <String>[])
          .map(int.parse)
          .where((ms) => now - ms < const Duration(hours: 1).inMilliseconds)
          .toList();
      if (recent.length >= maxPerHour) {
        return 'Tu as déjà envoyé $maxPerHour messages cette heure-ci. Réessaie un peu plus tard.';
      }
      await prefs.setStringList(key, [...recent, now].map((e) => '$e').toList());
    }
    final staff = p.isAdmin;
    final batch = _db.batch();
    batch.set(_col.doc(), {
      'lessonId': lesson.id,
      'subjectId': lesson.subjectId,
      'examId': lesson.examId,
      'uid': p.uid,
      'name': staff ? 'Responsable' : p.publicName,
      'text': t,
      'parentId': parentId,
      'isStaff': staff,
      'reports': 0,
      // Une question d'élève attend une réponse ; les réponses n'attendent rien.
      'answered': parentId.isNotEmpty || staff,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (staff && parentId.isNotEmpty) {
      batch.update(_col.doc(parentId), {'answered': true});
    }
    unawaited(batch.commit());
    if (!staff && parentId.isEmpty) unawaited(EngagementService.instance.addTo('questions'));
    return null;
  }

  Future<bool> alreadyReported(String commentId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('reported') ?? const []).contains(commentId);
  }

  Future<void> report(Comment c) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('reported') ?? const <String>[];
    if (list.contains(c.id)) return;
    await prefs.setStringList('reported', [...list, c.id]);
    unawaited(_col.doc(c.id).update({'reports': FieldValue.increment(1)}));
  }

  Future<void> delete(Comment c) => _col.doc(c.id).delete();

  // ---------- Responsable ----------

  Future<List<Comment>> unanswered() async {
    final s = await _col.where('answered', isEqualTo: false).get(const GetOptions(source: Source.server));
    return s.docs.map(Comment.fromDoc).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  }

  Future<List<Comment>> reported() async {
    final s = await _col.where('reports', isGreaterThan: 0).get(const GetOptions(source: Source.server));
    return s.docs.map(Comment.fromDoc).toList()..sort((a, b) => b.reports.compareTo(a.reports));
  }

  Future<void> markAnswered(Comment c) => _col.doc(c.id).update({'answered': true});

  Future<void> clearReports(Comment c) => _col.doc(c.id).update({'reports': 0});

  Future<void> setBlocked(String uid, bool blocked) =>
      _db.collection('users').doc(uid).update({'blocked': blocked});
}
