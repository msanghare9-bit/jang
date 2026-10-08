import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
  final String tournamentId;

  /// Quiz du prof pour sa classe : la classe et le contenu (vide sinon).
  final String classId;
  final String itemId;
  final DateTime? createdAt;
  final DateTime? askedAt;
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
    this.tournamentId = '',
    this.classId = '',
    this.itemId = '',
    this.createdAt,
    this.askedAt,
  });

  BankQuestion? get current => index >= 0 && index < questions.length ? questions[index] : null;
  bool get isLast => index >= questions.length - 1;

  factory LiveMatch.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final ts = m['createdAt'];
    final asked = m['askedAt'];
    final revealed = m['revealedAnswers'] is Map ? m['revealedAnswers'] as Map : const {};
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
        for (final (i, q) in (m['questions'] as List? ?? const []).indexed)
          if (q is Map)
            BankQuestion.fromMap({
              ...q,
              if (revealed['$i'] is Map) ...revealed['$i'] as Map,
            }),
      ],
      domain: '${m['domaine'] ?? ''}',
      level: '${m['niveau'] ?? ''}',
      title: '${m['title'] ?? ''}',
      tournamentId: '${m['tournamentId'] ?? ''}',
      classId: '${m['classId'] ?? ''}',
      itemId: '${m['itemId'] ?? ''}',
      createdAt: ts is Timestamp ? ts.toDate() : null,
      askedAt: asked is Timestamp ? asked.toDate() : null,
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
        for (final rawIndex in (m['answeredIndices'] as List? ?? const []))
          if (rawIndex is num)
            rawIndex.toInt(): (
              -1,
              (m['correctIndices'] as List? ?? const []).contains(rawIndex),
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
  final _functions = FirebaseFunctions.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('matchs');

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    final result = await _functions.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

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
    String tournamentId = '',
    String classId = '',
    String itemId = '',
  }) async {
    final created = await _call('createMatch', {
      'hostName': host.publicName,
      'hostPlays': hostPlays,
      'questions': [for (final q in questions) q.toMap()],
      'domain': domain,
      'level': level,
      'title': title,
      'tournamentId': tournamentId,
      'classId': classId,
      'itemId': itemId,
    });
    final match = await getOnce('${created['id']}');
    if (match == null) throw Exception('Le match n’a pas pu être créé.');
    return match;
  }

  /// Rejoindre avec le code. Renvoie le match, ou un message d'erreur simple.
  Future<(LiveMatch?, String)> joinByCode(String code, UserProfile p) async {
    final c = code.replaceAll(RegExp(r'\D'), '');
    if (c.length != 6) return (null, 'Le code a 6 chiffres.');
    final s = await _col.where('code', isEqualTo: c).where('open', isEqualTo: true).limit(1).get();
    if (s.docs.isEmpty) return (null, 'Aucun match avec ce code. Vérifie le code avec ton ami.');
    final m = LiveMatch.fromDoc(s.docs.first);
    final me = await _col.doc(m.id).collection('joueurs').doc(p.uid).get();
    if (!me.exists) {
      if (m.state != LiveMatch.waiting) return (null, 'Ce match a déjà commencé.');
      try {
        await _call('joinMatch', {'matchId': m.id, 'name': p.publicName});
      } on FirebaseFunctionsException catch (e) {
        return (null, e.message ?? 'Impossible de rejoindre ce match.');
      }
    }
    return (m, '');
  }

  Future<void> _join(String id, UserProfile p) async {
    await _call('joinMatch', {'matchId': id, 'name': p.publicName});
  }

  Future<void> leave(String id, String uid) => _col.doc(id).collection('joueurs').doc(uid).delete();

  /// Enregistre une réaction emoji du joueur connecté.
  Future<void> react(String matchId, String uid, String emoji) =>
      _col.doc(matchId).collection('joueurs').doc(uid).update({'reaction': emoji});

  Future<LiveMatch?> getOnce(String id) async {
    final doc = await _col.doc(id).get();
    return doc.exists ? LiveMatch.fromDoc(doc) : null;
  }

  /// Les matchs d’un tournoi acceptent les spectateurs directement.
  Future<void> requestTournamentObservation(String matchId, UserProfile p) async {
    final match = await getOnce(matchId);
    if (match == null || match.tournamentId.isEmpty ||
        ![LiveMatch.waiting, LiveMatch.asking, LiveMatch.showing].contains(match.state)) {
      throw Exception('Ce match de tournoi n’est pas disponible.');
    }
    final player = await _col.doc(matchId).collection('joueurs').doc(p.uid).get();
    if (player.exists) throw Exception('Tu joues déjà dans ce match.');
    final ref = _col.doc(matchId).collection('observateurs').doc(p.uid);
    final existing = await ref.get();
    if (existing.exists && existing.data()?['status'] == 'accepted') return;
    await ref.set({
      'name': p.publicName,
      'status': 'accepted',
      'tournament': true,
      'requestedAt': FieldValue.serverTimestamp(),
    });
  }

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

  /// Matchs actifs actualisés en temps réel pour l’écran d’observation.
  Stream<List<LiveMatch>> watchActiveMatches() => _col
      .where('open', isEqualTo: true)
      .snapshots()
      .map((snap) {
        final list = [
          for (final doc in snap.docs)
            if (doc.data()['state'] == LiveMatch.asking || doc.data()['state'] == LiveMatch.showing)
              LiveMatch.fromDoc(doc),
        ];
        list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
        return list;
      });

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

  Stream<List<MatchObserver>> observers(String matchId, {bool includePending = false}) {
    Query<Map<String, dynamic>> query = _col.doc(matchId).collection('observateurs');
    if (!includePending) query = query.where('status', isEqualTo: 'accepted');
    return query.snapshots().map((snap) => snap.docs.map(MatchObserver.fromDoc).toList());
  }

  Stream<MatchObserver?> myObservation(String matchId, String uid) => _col
      .doc(matchId)
      .collection('observateurs')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? MatchObserver.fromDoc(doc) : null);

  Future<void> requestObservation(String matchId, UserProfile p) async {
    final ref = _col.doc(matchId).collection('observateurs').doc(p.uid);
    await ref.delete();
    await ref.set({
      'name': p.publicName,
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> decideObservation(String matchId, String uid, {required bool accept}) =>
      _col.doc(matchId).collection('observateurs').doc(uid).update({
        'status': accept ? 'accepted' : 'refused',
      });

  // ---------- L'hôte mène le match ----------

  Future<void> ask(LiveMatch m, int index) async {
    await _call('advanceMatch', {'matchId': m.id});
  }

  Future<void> reveal(LiveMatch m) async {
    await _call('revealMatchQuestion', {'matchId': m.id});
  }

  Future<void> finish(LiveMatch m) async {
    await _call('finishMatch', {'matchId': m.id});
  }

  /// Passe à la suite : le serveur fixe l'heure de départ et termine le match.
  Future<void> next(LiveMatch m) async {
    await _call('advanceMatch', {'matchId': m.id});
  }

  // ---------- Le joueur répond ----------

  /// Score sur 20 : les points correspondent à la part du temps restant.
  /// Exemple : réponse à 7 s sur 20 s = 13 points.
  static int points(bool ok, Duration took, int seconds) {
    if (!ok || seconds <= 0) return 0;
    final remaining = 1 - (took.inMilliseconds / (seconds * 1000)).clamp(0.0, 1.0);
    return (20 * remaining).round();
  }

  Future<int> answer(LiveMatch m, String uid, int choice, Duration took) async {
    final result = await _call('submitMatchAnswer', {
      'matchId': m.id,
      'index': m.index,
      'choice': choice,
    });
    return (result['points'] as num?)?.toInt() ?? 0;
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
