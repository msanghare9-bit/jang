import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import 'stats_service.dart';
import 'inbox_service.dart';

/// Résumé du travail d'un élève, lu sur sa fiche (users/{uid}) : une seule lecture par élève.
class StudentSummary {
  final String uid;
  final String name;
  final String username;
  final String examId;
  final bool disabled;

  /// Dernier jour où l'élève a ouvert l'app (« 2026-10-06 »), vide s'il n'est jamais venu.
  final String lastActiveDay;
  final int lessonsSeen;
  final int quizLessons;
  final int sumBestPct;
  final int missionsDone;
  StudentSummary({
    required this.uid,
    required this.name,
    required this.username,
    required this.examId,
    this.disabled = false,
    this.lastActiveDay = '',
    this.lessonsSeen = 0,
    this.quizLessons = 0,
    this.sumBestPct = 0,
    this.missionsDone = 0,
  });

  /// Moyenne des meilleures notes aux quiz, en % (null : aucun quiz).
  int? get average => quizLessons == 0 ? null : (sumBestPct / quizLessons).round();

  /// Jours depuis la dernière venue (null : jamais venu).
  int? get daysAway {
    final d = DateTime.tryParse(lastActiveDay);
    if (d == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  }

  /// Travaille : venu dans les 7 derniers jours.
  bool get active => (daysAway ?? 999) <= 7;

  factory StudentSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    int n(String k) => m[k] is num ? (m[k] as num).toInt() : 0;
    String s(String k) => m[k] is String ? m[k] as String : '';
    return StudentSummary(
      uid: d.id,
      name: s('name'),
      username: s('username'),
      examId: s('examId'),
      disabled: m['disabled'] == true,
      lastActiveDay: s('lastActiveDay'),
      lessonsSeen: n('lessonsSeen'),
      quizLessons: n('quizLessons'),
      sumBestPct: n('sumBestPct'),
      missionsDone: n('missionsDone'),
    );
  }
}

/// Ce qu'un élève a fait d'un contenu de classe.
class ItemResult {
  final bool opened;
  final int? scorePct;
  final bool done;
  ItemResult({this.opened = false, this.scorePct, this.done = false});
}

/// Classes, contenus des profs et devoirs.
class ClassService {
  ClassService._();
  static final instance = ClassService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _classes => _db.collection('classes');
  CollectionReference<Map<String, dynamic>> get _items => _db.collection('classItems');

  /// Classes de l'élève connecté (mises à jour à la connexion et quand il entre ou sort).
  final ValueNotifier<List<ClassRoom>> mine = ValueNotifier(const []);
  final ValueNotifier<int> revision = ValueNotifier(0);

  // ---------- Classes ----------

  Future<void> loadMine(String uid) async {
    try {
      final s = await _classes.where('students', arrayContains: uid).get();
      mine.value = [for (final d in s.docs) ClassRoom.fromDoc(d)].where((c) => !c.deleted).toList();
    } catch (e) {
      debugPrint('Classes : $e');
    }
  }

  void clear() => mine.value = const [];

  /// La classe de l'élève dans cette matière (une seule par matière).
  ClassRoom? mineFor(String subjectName) {
    final k = subjectKey(subjectName);
    for (final c in mine.value) {
      if (c.subject == k) return c;
    }
    return null;
  }

  Future<List<ClassRoom>> all() async {
    final s = await _classes.get();
    return [for (final d in s.docs) ClassRoom.fromDoc(d)].where((c) => !c.deleted).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<List<ClassRoom>> ofProf(String uid) async {
    final s = await _classes.where('profUid', isEqualTo: uid).get();
    return [for (final d in s.docs) ClassRoom.fromDoc(d)].where((c) => !c.deleted).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<ClassRoom?> byId(String id) async {
    final d = await _classes.doc(id).get();
    return d.exists ? ClassRoom.fromDoc(d) : null;
  }

  static String _newCode() {
    const letters = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => letters[r.nextInt(letters.length)]).join();
  }

  /// Crée une classe (admin). Le code est tiré au hasard et vérifié.
  Future<ClassRoom> create({
    required String name,
    required String examId,
    required String subjectName,
    required String profUid,
    required String profName,
  }) async {
    var code = _newCode();
    for (var i = 0; i < 5; i++) {
      final s = await _classes.where('code', isEqualTo: code).limit(1).get();
      if (s.docs.isEmpty) break;
      code = _newCode();
    }
    final ref = _classes.doc();
    final c = ClassRoom(
      id: ref.id,
      name: name.trim(),
      examId: examId,
      subject: subjectKey(subjectName),
      subjectName: subjectName,
      profUid: profUid,
      profName: profName,
      code: code,
    );
    await ref.set({...c.toMap(), 'createdAt': FieldValue.serverTimestamp()});
    return c;
  }

  Future<void> update(String id, Map<String, Object?> fields) => _classes.doc(id).update(fields);

  Future<void> remove(String id) => _classes.doc(id).update({'deleted': true});

  Future<String> newCode(String id) async {
    final code = _newCode();
    await _classes.doc(id).update({'code': code});
    return code;
  }

  /// L'élève entre dans une classe avec son code. Il quitte sa classe de la même matière.
  /// Renvoie la classe, ou un message d'erreur simple.
  Future<(ClassRoom?, String)> join(String code, UserProfile p) async {
    final c0 = code.trim().toUpperCase().replaceAll(' ', '');
    if (c0.length < 4) return (null, 'Le code a 6 lettres ou chiffres.');
    final s = await _classes.where('code', isEqualTo: c0).limit(1).get();
    if (s.docs.isEmpty) return (null, 'Ce code ne correspond à aucune classe. Vérifie avec ton prof.');
    final c = ClassRoom.fromDoc(s.docs.first);
    if (c.deleted) return (null, 'Cette classe n\'existe plus.');
    for (final old in mine.value) {
      if (old.subject == c.subject && old.id != c.id) {
        await _classes.doc(old.id).update({'students': FieldValue.arrayRemove([p.uid])});
      }
    }
    await _classes.doc(c.id).update({'students': FieldValue.arrayUnion([p.uid])});
    await loadMine(p.uid);
    revision.value++;
    return (c, '');
  }

  Future<void> leave(ClassRoom c, String uid) async {
    await _classes.doc(c.id).update({'students': FieldValue.arrayRemove([uid])});
    await loadMine(uid);
    revision.value++;
  }

  /// Le prof ajoute un élève par son nom d'utilisateur. Renvoie un message d'erreur, ou ''.
  Future<String> addByUsername(ClassRoom c, String username) async {
    final u = username.trim().toLowerCase();
    if (u.isEmpty) return 'Écris le nom d\'utilisateur de l\'élève.';
    final s = await _db.collection('users').where('username', isEqualTo: u).limit(1).get();
    if (s.docs.isEmpty) return 'Aucun élève ne s\'appelle « $u ».';
    final uid = s.docs.first.id;
    // Une seule classe par matière : on le retire des autres classes de cette matière.
    final others = await _classes.where('students', arrayContains: uid).get();
    for (final d in others.docs) {
      final o = ClassRoom.fromDoc(d);
      if (o.subject == c.subject && o.id != c.id) {
        await _classes.doc(o.id).update({'students': FieldValue.arrayRemove([uid])});
      }
    }
    await _classes.doc(c.id).update({'students': FieldValue.arrayUnion([uid])});
    revision.value++;
    return '';
  }

  Future<void> removeStudent(ClassRoom c, String uid) async {
    await _classes.doc(c.id).update({'students': FieldValue.arrayRemove([uid])});
    revision.value++;
  }

  /// Fiches des élèves (par paquets de 30, la limite de Firestore).
  Future<List<StudentSummary>> students(List<String> uids) async {
    final out = <StudentSummary>[];
    for (var i = 0; i < uids.length; i += 30) {
      final part = uids.sublist(i, min(i + 30, uids.length));
      final s = await _db.collection('users').where(FieldPath.documentId, whereIn: part).get();
      out.addAll(s.docs.map(StudentSummary.fromDoc));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  // ---------- Contenus ----------

  Future<List<ClassItem>> itemsOf(String classId) async {
    final s = await _items.where('classId', isEqualTo: classId).get();
    return _sorted(s.docs);
  }

  /// Contenus publics des profs pour ce niveau et cette matière.
  Future<List<ClassItem>> publicItems(String examId, String subjectName) async {
    final s = await _items.where('visibility', isEqualTo: 'public').where('examId', isEqualTo: examId).get();
    final k = subjectKey(subjectName);
    return _sorted(s.docs).where((i) => i.subject == k).toList();
  }

  /// Tous les contenus créés par un prof (pour l'admin).
  Future<List<ClassItem>> itemsOfOwner(String uid) async {
    final s = await _items.where('ownerUid', isEqualTo: uid).get();
    return _sorted(s.docs);
  }

  List<ClassItem> _sorted(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final list = [for (final d in docs) ClassItem.fromDoc(d)].where((i) => !i.deleted).toList();
    list.sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
    return list;
  }

  /// Ce que l'élève voit dans une matière : les contenus de sa classe, puis les contenus publics.
  Future<(ClassRoom?, List<ClassItem>, List<ClassItem>)> forStudent(UserProfile p, Subject subject) async {
    final c = mineFor(subject.name);
    var own = <ClassItem>[];
    var pub = <ClassItem>[];
    try {
      if (c != null) own = await itemsOf(c.id);
      final ids = own.map((i) => i.id).toSet();
      pub = (await publicItems(p.examId, subject.name)).where((i) => !ids.contains(i.id)).toList();
    } catch (e) {
      debugPrint('Contenus de classe : $e');
    }
    return (c, own, pub);
  }

  /// Enregistre un contenu (nouveau si id est vide). Renvoie son identifiant.
  Future<String> saveItem(ClassItem item) async {
    final isNew = item.id.isEmpty;
    final ref = isNew ? _items.doc() : _items.doc(item.id);
    await ref.set({
      ...item.toMap(),
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    revision.value++;
    if (isNew) unawaited(_notifyClass(item));
    return ref.id;
  }

  /// Copie une leçon officielle dans la classe et consigne qui l’a exportée.
  Future<String> exportLesson(ClassRoom room, Lesson lesson, UserProfile prof) async {
    final existing = await itemsOf(room.id);
    if (existing.any((item) => item.sourceLessonId == lesson.id)) {
      throw Exception('Cette leçon est déjà dans la classe.');
    }
    final item = ClassItem(
      id: '',
      classId: room.id,
      ownerUid: prof.uid,
      ownerName: prof.name,
      examId: room.examId,
      subject: room.subject,
      type: ClassItem.lesson,
      title: lesson.title,
      sourceLessonId: lesson.id,
      sourceOwnerName: 'Contenu officiel Jàng',
      videos: lesson.videos,
      body: lesson.body,
      quiz: lesson.quiz,
      visibility: 'prive',
    );
    final itemId = await saveItem(item);
    await _db.collection('courseExports').add({
      'exportedBy': prof.uid,
      'exporterName': prof.publicName,
      'classId': room.id,
      'className': room.name,
      'school': room.school,
      'examId': room.examId,
      'subject': room.subjectName,
      'lessonId': lesson.id,
      'lessonTitle': lesson.title,
      'sourceOwnerName': 'Contenu officiel Jàng',
      'classItemId': itemId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return itemId;
  }

  Future<void> _notifyClass(ClassItem item) async {
    try {
      final classDoc = await _classes.doc(item.classId).get();
      if (!classDoc.exists) return;
      final room = ClassRoom.fromDoc(classDoc);
      if (room.students.isEmpty) return;
      final kind = ClassItem.label(item.type).toLowerCase();
      await InboxService.instance.send(
        room.students,
        '${room.profName.isEmpty ? 'Ton professeur' : room.profName} a ajouté '
        '« ${item.title} » ($kind) dans ${room.name}.',
      );
    } catch (e) {
      debugPrint('Notification du nouveau contenu impossible : $e');
    }
  }

  Future<void> deleteItem(ClassItem item) async {
    await _items.doc(item.id).update({'deleted': true});
    revision.value++;
  }

  // ---------- Devoirs ----------

  CollectionReference<Map<String, dynamic>> _rendus(String itemId) => _items.doc(itemId).collection('rendus');

  Future<Submission?> mySubmission(String itemId, String uid) async {
    final d = await _rendus(itemId).doc(uid).get();
    return d.exists ? Submission.fromDoc(d) : null;
  }

  Future<void> submit(ClassItem item, UserProfile p, String text) async {
    await _rendus(item.id).doc(p.uid).set({
      'name': p.name,
      'text': text.trim(),
      'classId': item.classId,
      'at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    revision.value++;
  }

  Future<List<Submission>> submissions(String itemId) async {
    final s = await _rendus(itemId).get();
    return [for (final d in s.docs) Submission.fromDoc(d)]
      ..sort((a, b) => (a.at ?? DateTime(3000)).compareTo(b.at ?? DateTime(3000)));
  }

  Future<void> grade(String itemId, String uid, {required String grade, required String comment}) async {
    await _rendus(itemId).doc(uid).update({
      'grade': grade.trim(),
      'comment': comment.trim(),
      'gradedAt': FieldValue.serverTimestamp(),
    });
    revision.value++;
  }

  // ---------- Suivi ----------

  /// Ce que chaque élève a fait de ce contenu : uid -> résultat.
  Future<Map<String, ItemResult>> results(ClassItem item, List<String> uids) async {
    final out = <String, ItemResult>{};
    if (item.type == ClassItem.homework) {
      for (final s in await submissions(item.id)) {
        out[s.uid] = ItemResult(opened: true, done: true);
      }
      return out;
    }
    final sub = item.type == ClassItem.mission ? 'missions' : 'progress';
    await Future.wait([
      for (final uid in uids)
        _db.collection('users').doc(uid).collection(sub).doc(item.progressId).get().then((d) {
          if (!d.exists) return;
          final m = d.data() ?? {};
          if (sub == 'missions') {
            out[uid] = ItemResult(opened: true, done: m['done'] == true);
          } else {
            final best = m['bestScore'], total = m['total'];
            final pct = best is num && total is num && total > 0 ? (best * 100 / total).round() : null;
            out[uid] = ItemResult(opened: m['seen'] == true || pct != null, scorePct: pct, done: pct != null);
          }
        }).catchError((Object e) {
          debugPrint('$e');
        }),
    ]);
    return out;
  }

  /// Questions d'un QCM ratées par les élèves : texte de la question -> nombre d'élèves.
  /// (La progression garde les questions ratées tant que l'élève ne les a pas réussies 2 fois.)
  Future<List<(String, int)>> missedQuestions(ClassItem item, List<String> uids) async {
    if (item.quiz.isEmpty) return const [];
    final byKey = {for (final q in item.quiz) StatsService.questionKey(q.question): q.question};
    final counts = <String, int>{};
    await Future.wait([
      for (final uid in uids)
        _db.collection('users').doc(uid).collection('progress').doc(item.progressId).get().then((d) {
          final mk = d.data()?['mistakes'];
          if (mk is! Map) return;
          for (final k in mk.keys) {
            final q = byKey['$k'];
            if (q != null) counts[q] = (counts[q] ?? 0) + 1;
          }
        }).catchError((Object e) {
          debugPrint('$e');
        }),
    ]);
    return counts.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  }
}
