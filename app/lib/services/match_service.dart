import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models.dart';
import 'quiz_bank.dart';

/// Un match en direct (matchs/{id}) : tout le monde voit la même question en même temps.
class LiveMatch {
  static const waiting = 'attente';
  static const asking = 'question';
  static const showing = 'correction';
  static const over = 'fini';

  final String id;
  final String code;
  final String hostUid;
  final String hostName;

  /// L'hôte joue aussi (match entre élèves) ou regarde seulement (quiz du prof).
  final bool hostPlays;
  final String state;
  final int index;
  final int seconds;
  final List<BankQuestion> questions;
  final String domain;
  final String level;
  final String title;

  /// Quiz du prof pour sa classe : la classe et le contenu (vide sinon).
  final String classId;
  final String itemId;
  final DateTime? createdAt;
  LiveMatch({
    required this.id,
    required this.code,
    required this.hostUid,
    required this.hostName,
    required this.hostPlays,
    required this.state,
    required this.index,
    required this.seconds,
    required this.questions,
    this.domain = '',
    this.level = '',
    this.title = '',
    this.classId = '',
    this.itemId = '',
    this.createdAt,
  });

  BankQuestion? get current => index >= 0 && index < questions.length ? questions[index] : null;
  bool get isLast => index >= questions.length - 1;

  factory LiveMatch.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final ts = m['createdAt'];
    return LiveMatch(
      id: d.id,
      code: '${m['code'] ?? ''}',
      hostUid: '${m['hostUid'] ?? ''}',
      hostName: '${m['hostName'] ?? ''}',
      hostPlays: m['hostPlays'] != false,
      state: '${m['state'] ?? waiting}',
      index: m['index'] is num ? (m['index'] as num).toInt() : -1,
      seconds: m['seconds'] is num ? (m['seconds'] as num).toInt() : 20,
      questions: [
        for (final q in (m['questions'] as List? ?? const []))
          if (q is Map) BankQuestion.fromMap(q),
      ],
      domain: '${m['domaine'] ?? ''}',
      level: '${m['niveau'] ?? ''}',
      title: '${m['title'] ?? ''}',
      classId: '${m['classId'] ?? ''}',
      itemId: '${m['itemId'] ?? ''}',
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// Un joueur et ses réponses (matchs/{id}/joueurs/{uid}).
class MatchPlayer {
  final String uid;
  final String name;
  final int score;
  final String reaction;

  /// Question -> (choix, juste ?).
  final Map<int, (int, bool)> answers;
  MatchPlayer(this.uid, this.name, this.score, this.answers, this.reaction);

  factory MatchPlayer.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final a = m['answers'] is Map ? m['answers'] as Map : const {};
    return MatchPlayer(
      d.id,
      '${m['name'] ?? ''}',
      m['score'] is num ? (m['score'] as num).toInt() : 0,
      {
        for (final e in a.entries)
          if (int.tryParse('${e.key}') != null && e.value is Map)
            int.parse('${e.key}'): (
              ((e.value as Map)['c'] as num?)?.toInt() ?? -1,
              (e.value as Map)['ok'] == true,
            ),
      },
      '${m['reaction'] ?? ''}',
    );
  }
}

class MatchObserver {
  final String uid;
  final String name;
  final String status;

  const MatchObserver({required this.uid, required this.name, required this.status});

  factory MatchObserver.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return MatchObserver(
      uid: doc.id,
      name: '${data['name'] ?? 'Joueur'}',
      status: '${data['status'] ?? 'pending'}',
    );
  }
}

class MatchService {
  MatchService._();
  static final instance = MatchService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('matchs');

  static const maxPlayers = 40;

  /// Crée un match et renvoie son identifiant. Le code a 6 chiffres.
  Future<LiveMatch> create({
    required UserProfile host,
    required List<BankQuestion> questions,
    bool hostPlays = true,
    int seconds = 20,
    String domain = '',
    String level = '',
    String title = '',
    String classId = '',
    String itemId = '',
  }) async {
    final r = Random.secure();
    var code = '';
    for (var i = 0; i < 6; i++) {
      code = List.generate(6, (_) => r.nextInt(10)).join();
      final s = await _col.where('code', isEqualTo: code).where('open', isEqualTo: true).limit(1).get();
      if (s.docs.isEmpty) break;
    }
    final ref = _col.doc();
    await ref.set({
      'code': code,
      'open': true,
      'hostUid': host.uid,
      'hostName': host.publicName,
      'hostPlays': hostPlays,
      'state': LiveMatch.waiting,
      'index': -1,
      'seconds': seconds,
      'questions': [for (final q in questions) q.toMap()],
      'domaine': domain,
      'niveau': level,
      'title': title,
      'classId': classId,
      'itemId': itemId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (hostPlays) await _join(ref.id, host);
    final d = await ref.get();
    return LiveMatch.fromDoc(d);
  }

  /// Rejoindre avec le code. Renvoie le match, ou un message d'erreur simple.
  Future<(LiveMatch?, String)> joinByCode(String code, UserProfile p) async {
    final c = code.replaceAll(RegExp(r'\D'), '');
    if (c.length != 6) return (null, 'Le code a 6 chiffres.');
    final s = await _col.where('code', isEqualTo: c).where('open', isEqualTo: true).limit(1).get();
    if (s.docs.isEmpty) return (null, 'Aucun match avec ce code. Vérifie le code avec ton ami.');
    final m = LiveMatch.fromDoc(s.docs.first);
    if (m.state != LiveMatch.waiting) {
      final me = await _col.doc(m.id).collection('joueurs').doc(p.uid).get();
      if (!me.exists) return (null, 'Ce match a déjà commencé.');
      return (m, '');
    }
    final count = await _col.doc(m.id).collection('joueurs').count().get();
    if ((count.count ?? 0) >= maxPlayers) return (null, 'Ce match est plein ($maxPlayers joueurs).');
    await _join(m.id, p);
    return (m, '');
  }

  Future<void> _join(String id, UserProfile p) => _col.doc(id).collection('joueurs').doc(p.uid).set({
        'uid': p.uid,
        'name': p.publicName,
        'score': 0,
        'answers': {},
        'at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> leave(String id, String uid) => _col.doc(id).collection('joueurs').doc(uid).delete();

  /// Enregistre une réaction emoji du joueur connecté.
  Future<void> react(String matchId, String uid, String emoji) =>
      _col.doc(matchId).collection('joueurs').doc(uid).update({'reaction': emoji});

  Stream<LiveMatch> watch(String id) => _col.doc(id).snapshots().where((d) => d.exists).map(LiveMatch.fromDoc);

  Stream<List<MatchPlayer>> players(String id) => _col
      .doc(id)
      .collection('joueurs')
      .snapshots()
      .map((s) => [for (final d in s.docs) MatchPlayer.fromDoc(d)]..sort((a, b) => b.score.compareTo(a.score)));

  Future<int> completedMatchCount() async {
    final result = await _col.where('state', isEqualTo: LiveMatch.over).count().get();
    return result.count ?? 0;
  }

  /// Matchs qui ont commencé et restent ouverts à l’observation.
  Future<List<LiveMatch>> activeMatches() async {
    final snap = await _col.where('open', isEqualTo: true).get();
    final list = [
      for (final doc in snap.docs)
        if (doc.data()['state'] == LiveMatch.asking || doc.data()['state'] == LiveMatch.showing)
          LiveMatch.fromDoc(doc),
    ];
    list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return list;
  }

  Stream<List<MatchObserver>> observers(String matchId) => _col
      .doc(matchId)
      .collection('observateurs')
      .snapshots()
      .map((snap) => snap.docs.map(MatchObserver.fromDoc).toList());

  Stream<MatchObserver?> myObservation(String matchId, String uid) => _col
      .doc(matchId)
      .collection('observateurs')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? MatchObserver.fromDoc(doc) : null);

  Future<void> requestObservation(String matchId, UserProfile p) =>
      _col.doc(matchId).collection('observateurs').doc(p.uid).set({
        'name': p.publicName,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });

  Future<void> decideObservation(String matchId, String uid, {required bool accept}) =>
      _col.doc(matchId).collection('observateurs').doc(uid).update({
        'status': accept ? 'accepted' : 'refused',
      });

  // ---------- L'hôte mène le match ----------

  Future<void> ask(LiveMatch m, int index) => _col.doc(m.id).update({
        'state': LiveMatch.asking,
        'index': index,
        'askedAt': FieldValue.serverTimestamp(),
      });

  Future<void> reveal(LiveMatch m) => _col.doc(m.id).update({'state': LiveMatch.showing});

  Future<void> finish(LiveMatch m) => _col.doc(m.id).update({'state': LiveMatch.over, 'open': false});

  /// Passe à la suite : question suivante, ou fin du match.
  Future<void> next(LiveMatch m) => m.isLast ? finish(m) : ask(m, m.index + 1);

  // ---------- Le joueur répond ----------

  /// Score sur 20 : les points correspondent à la part du temps restant.
  /// Exemple : réponse à 7 s sur 20 s = 13 points.
  static int points(bool ok, Duration took, int seconds) {
    if (!ok || seconds <= 0) return 0;
    final remaining = 1 - (took.inMilliseconds / (seconds * 1000)).clamp(0.0, 1.0);
    return (20 * remaining).round();
  }

  Future<int> answer(LiveMatch m, String uid, int choice, Duration took) async {
    final q = m.current;
    if (q == null) return 0;
    final ok = choice == q.answer;
    final pts = points(ok, took, m.seconds);
    await _col.doc(m.id).collection('joueurs').doc(uid).update({
      'answers.${m.index}': {'c': choice, 'ok': ok, 'ms': took.inMilliseconds},
      'score': FieldValue.increment(pts),
    });
    return pts;
  }

  // ---------- Suivi du prof ----------

  /// Les quiz en direct d'une classe (les plus récents d'abord).
  Future<List<LiveMatch>> ofClass(String classId) async {
    final s = await _col.where('classId', isEqualTo: classId).get();
    final list = [for (final d in s.docs) LiveMatch.fromDoc(d)];
    list.sort((a, b) => (b.createdAt ?? DateTime(3000)).compareTo(a.createdAt ?? DateTime(3000)));
    return list;
  }

  Future<List<MatchPlayer>> playersOnce(String id) async {
    final s = await _col.doc(id).collection('joueurs').get();
    return [for (final d in s.docs) MatchPlayer.fromDoc(d)]..sort((a, b) => b.score.compareTo(a.score));
  }

  /// Historique des matchs terminés auxquels le joueur a participé.
  Future<List<(LiveMatch, MatchPlayer, bool)>> historyFor(String uid) async {
    final rows = await _db.collectionGroup('joueurs').where('uid', isEqualTo: uid).get();
    final entries = <(LiveMatch, MatchPlayer, bool)>[];
    for (final row in rows.docs) {
      final matchRef = row.reference.parent.parent;
      if (matchRef == null) continue;
      final matchDoc = await matchRef.get();
      if (!matchDoc.exists) continue;
      final match = LiveMatch.fromDoc(matchDoc);
      if (match.state != LiveMatch.over) continue;
      final players = await playersOnce(match.id);
      final me = players.where((p) => p.uid == uid).firstOrNull;
      if (me == null) continue;
      final won = players.isNotEmpty && me.score == players.first.score;
      entries.add((match, me, won));
    }
    entries.sort((a, b) =>
        (b.$1.createdAt ?? DateTime(1970)).compareTo(a.$1.createdAt ?? DateTime(1970)));
    return entries;
  }
}
