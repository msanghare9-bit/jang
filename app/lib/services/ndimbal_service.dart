import 'package:cloud_firestore/cloud_firestore.dart';

/// Jokers « Ndimbal » obtenus après cinq victoires en match classique.
class NdimbalService {
  NdimbalService._();
  static final instance = NdimbalService._();

  CollectionReference<Map<String, dynamic>> _tokens(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('ndimbals');

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _valid(String uid) async {
    final now = DateTime.now();
    final docs = (await _tokens(uid).get()).docs;
    final valid = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final expired = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in docs) {
      final raw = doc.data()['expiresAt'];
      final expiresAt = raw is Timestamp ? raw.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      (expiresAt.isAfter(now) ? valid : expired).add(doc);
    }
    if (expired.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in expired) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    valid.sort((a, b) {
      final ta = a.data()['expiresAt'] as Timestamp;
      final tb = b.data()['expiresAt'] as Timestamp;
      return ta.compareTo(tb);
    });
    return valid;
  }

  Future<int> availableCount(String uid) async => (await _valid(uid)).length;

  /// Crée la récompense une seule fois, à partir d'un résultat de match achevé.
  Future<bool> awardForWin({required String uid, required String matchId, required int wins}) async {
    if (wins == 0 || wins % 5 != 0) return false;
    final db = FirebaseFirestore.instance;
    final match = db.collection('matchs').doc(matchId);
    final award = db.collection('users').doc(uid).collection('matchRewards').doc(matchId);
    final token = _tokens(uid).doc(matchId);
    return db.runTransaction((tx) async {
      final existing = await tx.get(award);
      if (existing.exists) return false;
      final matchSnap = await tx.get(match);
      final data = matchSnap.data() ?? const <String, dynamic>{};
      final winners = (data['winnerUids'] as List? ?? const []).whereType<String>();
      if (data['state'] != 'fini' || '${data['tournamentId'] ?? ''}'.isNotEmpty || !winners.contains(uid)) {
        return false;
      }
      final now = Timestamp.now();
      tx.set(award, {'sourceMatch': matchId, 'milestone': wins, 'at': now});
      tx.set(token, {
        'sourceMatch': matchId,
        'earnedAt': now,
        'expiresAt': Timestamp.fromDate(now.toDate().add(const Duration(days: 7))),
      });
      return true;
    });
  }

  /// Consomme un seul jeton; un jeton expiré ne peut pas être utilisé.
  Future<bool> consume(String uid) async {
    final db = FirebaseFirestore.instance;
    for (final doc in await _valid(uid)) {
      final used = await db.runTransaction((tx) async {
        final fresh = await tx.get(doc.reference);
        if (!fresh.exists) return false;
        final raw = fresh.data()?['expiresAt'];
        if (raw is! Timestamp || !raw.toDate().isAfter(DateTime.now())) {
          tx.delete(doc.reference);
          return false;
        }
        tx.delete(doc.reference);
        return true;
      });
      if (used) return true;
    }
    return false;
  }
}
