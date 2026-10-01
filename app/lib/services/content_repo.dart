import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Accès au contenu (niveaux, matières, chapitres, leçons).
///
/// Pour rester dans le quota gratuit et fonctionner hors connexion :
/// - l'affichage lit toujours la copie enregistrée sur le téléphone (cache Firestore) ;
/// - la synchronisation ne télécharge que les documents modifiés depuis la dernière fois
///   (champ `updatedAt`).
class ContentRepo {
  ContentRepo._();
  static final instance = ContentRepo._();

  final _db = FirebaseFirestore.instance;
  static const collections = ['exams', 'subjects', 'chapters', 'lessons', 'flashcards'];

  /// Augmente à chaque changement de contenu : les écrans l'écoutent pour se rafraîchir.
  final ValueNotifier<int> revision = ValueNotifier(0);
  final ValueNotifier<bool> syncing = ValueNotifier(false);
  DateTime? lastSyncAt;
  Future<SyncResult>? _running;

  static const _cache = GetOptions(source: Source.cache);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('last_sync_at');
    if (ms != null) lastSyncAt = DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void notifyChanged() => revision.value++;

  /// Télécharge les nouveautés. [minInterval] évite de relancer trop souvent.
  Future<SyncResult> sync({bool full = false, Duration? minInterval}) {
    if (_running != null) return _running!;
    if (!full && minInterval != null && lastSyncAt != null) {
      if (DateTime.now().difference(lastSyncAt!) < minInterval) {
        return Future.value(SyncResult(changed: 0, ok: true, skipped: true));
      }
    }
    _running = _doSync(full).whenComplete(() => _running = null);
    return _running!;
  }

  Future<SyncResult> _doSync(bool full) async {
    syncing.value = true;
    final prefs = await SharedPreferences.getInstance();
    var changed = 0;
    try {
      for (final c in collections) {
        final key = 'sync_$c';
        final last = full ? 0 : (prefs.getInt(key) ?? 0);
        Query<Map<String, dynamic>> q = _db.collection(c);
        if (last > 0) {
          q = q.where('updatedAt', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(last));
        }
        final snap =
            await q.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 40));
        var maxTs = last;
        for (final d in snap.docs) {
          final ts = d.data()['updatedAt'];
          if (ts is Timestamp && ts.millisecondsSinceEpoch > maxTs) {
            maxTs = ts.millisecondsSinceEpoch;
          }
        }
        changed += snap.docs.length;
        await prefs.setInt(key, maxTs);
      }
      lastSyncAt = DateTime.now();
      await prefs.setInt('last_sync_at', lastSyncAt!.millisecondsSinceEpoch);
      if (changed > 0) notifyChanged();
      return SyncResult(changed: changed, ok: true);
    } catch (e) {
      debugPrint('Synchronisation impossible : $e');
      return SyncResult(changed: changed, ok: false);
    } finally {
      syncing.value = false;
    }
  }

  // ---------- Lecture (depuis le téléphone) ----------

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _cached(
      Query<Map<String, dynamic>> q) async {
    try {
      final s = await q.get(_cache);
      return s.docs;
    } catch (_) {
      return const [];
    }
  }

  Future<List<Exam>> exams() async {
    final docs = await _cached(_db.collection('exams'));
    final list = docs.map(Exam.fromDoc).where((e) => !e.deleted).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  Future<Exam?> exam(String id) async {
    final all = await exams();
    for (final e in all) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<List<Subject>> subjects(String examId) async {
    final docs = await _cached(_db.collection('subjects').where('examId', isEqualTo: examId));
    final list = docs.map(Subject.fromDoc).where((e) => !e.deleted).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  Future<List<Chapter>> chapters(String subjectId) async {
    final docs =
        await _cached(_db.collection('chapters').where('subjectId', isEqualTo: subjectId));
    final list = docs.map(Chapter.fromDoc).where((e) => !e.deleted).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  Future<List<Lesson>> lessonsOfSubject(String subjectId) async {
    final docs =
        await _cached(_db.collection('lessons').where('subjectId', isEqualTo: subjectId));
    final list = docs.map(Lesson.fromDoc).where((e) => !e.deleted).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  Future<List<Lesson>> lessonsOfExam(String examId) async {
    final docs = await _cached(_db.collection('lessons').where('examId', isEqualTo: examId));
    return docs.map(Lesson.fromDoc).where((e) => !e.deleted).toList();
  }

  Future<Lesson?> lesson(String id) async {
    try {
      final d = await _db.collection('lessons').doc(id).get(_cache);
      if (!d.exists) return null;
      final l = Lesson.fromDoc(d);
      return l.deleted ? null : l;
    } catch (_) {
      return null;
    }
  }

  Future<FlashcardDeck?> deck(String chapterId) async {
    try {
      final d = await _db.collection('flashcards').doc(chapterId).get(_cache);
      if (!d.exists) return null;
      final deck = FlashcardDeck.fromDoc(d);
      return deck.deleted ? null : deck;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, FlashcardDeck>> decksOfSubject(String subjectId) async {
    final docs =
        await _cached(_db.collection('flashcards').where('subjectId', isEqualTo: subjectId));
    return {
      for (final d in docs.map(FlashcardDeck.fromDoc).where((d) => !d.deleted && d.cards.isNotEmpty))
        d.chapterId: d
    };
  }

  // ---------- Écriture (responsable) ----------

  String newId(String collection) => _db.collection(collection).doc().id;

  /// Enregistre sans attendre la réponse du serveur (fonctionne aussi hors connexion :
  /// l'envoi se fera dès que le téléphone sera connecté).
  void save(String collection, String id, Map<String, dynamic> data) {
    final payload = {...data, 'updatedAt': FieldValue.serverTimestamp()};
    unawaited(_db
        .collection(collection)
        .doc(id)
        .set(payload, SetOptions(merge: true))
        .catchError((e) => debugPrint('Écriture refusée : $e')));
    notifyChanged();
  }

  void remove(String collection, String id) => save(collection, id, {'deleted': true});

  /// Échange l'ordre de deux éléments voisins.
  void swapOrder(String collection, String idA, int orderA, String idB, int orderB) {
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();
    batch.set(_db.collection(collection).doc(idA), {'order': orderB, 'updatedAt': now},
        SetOptions(merge: true));
    batch.set(_db.collection(collection).doc(idB), {'order': orderA, 'updatedAt': now},
        SetOptions(merge: true));
    unawaited(batch.commit().catchError((e) => debugPrint('Écriture refusée : $e')));
    notifyChanged();
  }

  /// Crée un premier niveau avec quatre matières (utile au premier lancement).
  Future<void> seedFirstLevel(String name) async {
    final examId = newId('exams');
    save('exams', examId, Exam(id: examId, name: name, order: 0).toMap());
    const subjects = [
      ['Français', '#8C2F39'],
      ['Mathématiques', '#1F4E8C'],
      ['Anglais', '#9A5A00'],
      ['SVT', '#5B3F8C'],
    ];
    for (var i = 0; i < subjects.length; i++) {
      final id = newId('subjects');
      save(
          'subjects',
          id,
          Subject(id: id, examId: examId, name: subjects[i][0], color: subjects[i][1], order: i)
              .toMap());
    }
  }
}

class SyncResult {
  final int changed;
  final bool ok;
  final bool skipped;
  SyncResult({required this.changed, required this.ok, this.skipped = false});
}
