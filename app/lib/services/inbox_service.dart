import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'auth_service.dart';
import 'push_service.dart';

/// Message d'un prof à un élève.
class InboxMessage {
  final String id;
  final String fromName;
  final String text;
  final DateTime? createdAt;
  final bool read;
  final String reply;
  InboxMessage(this.id, this.fromName, this.text, this.createdAt, this.read, this.reply);

  factory InboxMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final ts = m['createdAt'];
    return InboxMessage(
      d.id,
      (m['fromName'] as String?) ?? 'Ton prof',
      (m['text'] as String?) ?? '',
      ts is Timestamp ? ts.toDate() : null,
      m['readAt'] != null,
      (m['reply'] as String?) ?? '',
    );
  }
}

/// Annonce à un groupe d'élèves.
class Announcement {
  final String id;
  final String title;
  final String text;
  final String examId;
  final String subject;
  final String fromName;
  final DateTime? sendAt;
  Announcement(this.id, this.title, this.text, this.examId, this.subject, this.fromName, this.sendAt);

  factory Announcement.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final ts = m['sendAt'];
    return Announcement(
      d.id,
      (m['title'] as String?) ?? '',
      (m['text'] as String?) ?? '',
      (m['examId'] as String?) ?? '',
      (m['subject'] as String?) ?? '',
      (m['fromName'] as String?) ?? '',
      ts is Timestamp ? ts.toDate() : null,
    );
  }

  bool concerns(String examId, Set<String> subjects) =>
      (this.examId.isEmpty || this.examId == examId) && (subject.isEmpty || subjects.contains(subject));
}

/// Messages des profs aux élèves et annonces.
class InboxService {
  InboxService._();
  static final instance = InboxService._();

  final _db = FirebaseFirestore.instance;

  /// Augmente quand un message est lu ou envoyé : les pastilles se mettent à jour.
  final ValueNotifier<int> revision = ValueNotifier(0);

  CollectionReference<Map<String, dynamic>> _box(String uid) =>
      _db.collection('users').doc(uid).collection('messages');

  // ---------- Élève ----------

  Stream<List<InboxMessage>> myMessages(String uid) => _box(uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(InboxMessage.fromDoc).toList());

  Future<void> markRead(String uid, String id) async {
    unawaited(_box(uid).doc(id).update({'readAt': FieldValue.serverTimestamp()}).catchError((_) {}));
    revision.value++;
  }

  Future<void> reply(String uid, String id, String text) async {
    await _box(uid).doc(id).update({
      'reply': text,
      'replyAt': FieldValue.serverTimestamp(),
      'readAt': FieldValue.serverTimestamp(),
    });
    revision.value++;
  }

  /// Annonces déjà envoyées qui concernent l'élève (les 30 dernières).
  Future<List<Announcement>> myAnnouncements(UserProfile p, Set<String> subjects) async {
    try {
      final s = await _db
          .collection('annonces')
          .where('sendAt', isLessThanOrEqualTo: Timestamp.now())
          .orderBy('sendAt', descending: true)
          .limit(30)
          .get();
      return s.docs.map(Announcement.fromDoc).where((a) => a.concerns(p.examId, subjects)).toList();
    } catch (e) {
      debugPrint('Annonces indisponibles : $e');
      return const [];
    }
  }

  Future<Set<String>> readAnnouncements() async =>
      ((await SharedPreferences.getInstance()).getStringList('annonces_lues') ?? const []).toSet();

  Future<void> markAnnouncementRead(String uid, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList('annonces_lues') ?? const []).toSet()..add(id);
    await prefs.setStringList('annonces_lues', set.toList());
    unawaited(_db
        .collection('annonces')
        .doc(id)
        .collection('lus')
        .doc(uid)
        .set({'at': FieldValue.serverTimestamp()}).catchError((_) {}));
    revision.value++;
  }

  // ---------- Prof / admin ----------

  /// Envoie le même message à plusieurs élèves (et une notification push à chacun).
  Future<int> send(List<String> uids, String text) async {
    final me = AuthService.instance.profile.value;
    if (me == null || uids.isEmpty) return 0;
    final from = me.isAdmin ? me.name : (me.name.isEmpty ? 'Ton prof' : me.name);
    final batch = _db.batch();
    for (final uid in uids) {
      batch.set(_box(uid).doc(), {
        'fromUid': me.uid,
        'fromName': from,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    unawaited(PushService.instance
        .send({'type': 'message', 'uids': uids, 'title': 'Message de $from', 'body': text}));
    revision.value++;
    return uids.length;
  }

  /// Publie une annonce. Elle part tout de suite, ou à [sendAt] (le serveur s'en charge).
  Future<void> announce({
    required String title,
    required String text,
    required String examId,
    required String subject,
    DateTime? sendAt,
  }) async {
    final me = AuthService.instance.profile.value;
    if (me == null) return;
    final ref = _db.collection('annonces').doc();
    final now = DateTime.now();
    final later = sendAt != null && sendAt.isAfter(now);
    await ref.set({
      'title': title,
      'text': text,
      'examId': examId,
      'subject': subject,
      'fromUid': me.uid,
      'fromName': me.name,
      'createdAt': FieldValue.serverTimestamp(),
      'sendAt': Timestamp.fromDate(later ? sendAt : now),
      'pushed': false,
    });
    if (!later) {
      final ok = await PushService.instance.send({
        'type': 'annonce',
        'id': ref.id,
        'topic': announcementTopic(examId, subject),
        'title': title,
        'body': text,
      });
      if (ok) unawaited(ref.update({'pushed': true}).catchError((_) {}));
    }
  }

  /// Annonces envoyées par l'admin ou ce prof (les 50 dernières).
  Future<List<(Announcement, int)>> sentAnnouncements() async {
    final me = AuthService.instance.profile.value;
    if (me == null) return const [];
    Query<Map<String, dynamic>> q = _db.collection('annonces');
    if (!me.isAdmin) q = q.where('fromUid', isEqualTo: me.uid);
    final s = await q.limit(50).get();
    final list = s.docs.map(Announcement.fromDoc).toList()
      ..sort((a, b) => (b.sendAt ?? DateTime(0)).compareTo(a.sendAt ?? DateTime(0)));
    final out = <(Announcement, int)>[];
    for (final a in list) {
      var n = 0;
      try {
        final c = await _db.collection('annonces').doc(a.id).collection('lus').count().get();
        n = c.count ?? 0;
      } catch (_) {}
      out.add((a, n));
    }
    return out;
  }

  Future<void> deleteAnnouncement(String id) => _db.collection('annonces').doc(id).delete();
}
