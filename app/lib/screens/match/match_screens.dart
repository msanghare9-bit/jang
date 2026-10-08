import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/match_service.dart';
import 'xarit_screen.dart';
import 'tournament_screen.dart';
import '../../services/quiz_bank.dart';
import '../../theme.dart';
import '../../widgets/characters.dart';
import '../../widgets/cheer.dart';
import '../../widgets/jang_ui.dart';
import '../../widgets/say.dart';
import '../quiz_screen.dart';

// Réponses au style Jàng, sobres et lisibles.
const _shapes = ['A', 'B', 'C', 'D'];
const _tileColors = [Colors.white, Colors.white, Colors.white, Colors.white];

/// L'accueil des matchs : créer, rejoindre, ou jouer seul.
class MatchHomeScreen extends StatelessWidget {
  const MatchHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: JangColors.snGreen, borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              const CharacterView(Chars.lion, size: 76, moves: Moves.jump),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Joue contre tes amis !', style: titleStyle(22, color: Colors.white, weight: 800)),
                  const SizedBox(height: 4),
                  const Text('Les mêmes questions, en même temps. Le plus rapide gagne plus de points.',
                      style: TextStyle(color: Colors.white)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: JangColors.snGreen,
                child: Icon(Icons.history, color: Colors.white),
              ),
              title: const Text('Mon historique'),
              subtitle: const Text('Matchs joués, victoires et défaites'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MatchHistoryScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: JangColors.snGreen,
                  child: Icon(Icons.people_alt_outlined, color: Colors.white)),
              title: const Text('Mes Xarit'),
              subtitle: const Text('Ajoute tes amis et défie-les'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const XaritScreen())),
            ),
          ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: JangColors.snGreen,
                  child: Icon(Icons.account_tree_outlined, color: Colors.white)),
              title: const Text('Tournois'),
              subtitle: const Text('Joue jusqu’à la finale ou observe un match'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TournamentHomeScreen())),
            ),
          ),
          const SizedBox(height: 8),
          ChunkyButton(
            label: 'Créer un match',
            icon: Icons.add_circle_outline,
            color: JangColors.primary,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MatchSetupScreen())),
          ),
          const SizedBox(height: 10),
          ChunkyButton(
            label: 'Rejoindre avec un code',
            icon: Icons.login,
            onPressed: () => joinMatchDialog(context),
          ),
          const SizedBox(height: 10),
          ChunkyButton(
            label: 'Observer un match en direct',
            icon: Icons.visibility_outlined,
            outlined: true,
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const MatchFinderScreen())),
          ),
          const SizedBox(height: 10),
          ChunkyButton(
            label: 'M\'entraîner seul',
            icon: Icons.person_outline,
            outlined: true,
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const MatchSetupScreen(solo: true))),
          ),
        ],
      ),
    );
  }
}


/// Historique personnel des matchs terminés.
class MatchHistoryScreen extends StatefulWidget {
  const MatchHistoryScreen({super.key});

  @override
  State<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

class _MatchHistoryScreenState extends State<MatchHistoryScreen> {
  late Future<List<(LiveMatch, MatchPlayer, bool)>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<(LiveMatch, MatchPlayer, bool)>> _load() {
    final uid = AuthService.instance.profile.value?.uid ?? '';
    return MatchService.instance.historyFor(uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des matchs')),
      body: FutureBuilder<List<(LiveMatch, MatchPlayer, bool)>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Impossible de charger l’historique. Vérifie ta connexion puis réessaie.'),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final games = snap.data!;
          final wins = games.where((g) => g.$3).length;
          final losses = games.length - wins;
          final rate = games.isEmpty ? 0 : (wins * 100 / games.length).round();
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Ton bilan', style: titleStyle(20, weight: 800)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _HistoryStat(label: 'Joués', value: '${games.length}')),
                        Expanded(child: _HistoryStat(label: 'Gagnés', value: '$wins')),
                        Expanded(child: _HistoryStat(label: 'Perdus', value: '$losses')),
                        Expanded(child: _HistoryStat(label: 'Victoires', value: '$rate%')),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                if (games.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 36),
                    child: Center(child: Text('Tes matchs terminés apparaîtront ici.')),
                  )
                else
                  for (final game in games)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: JangColors.snGreen,
                          child: Icon(game.$3 ? Icons.emoji_events : Icons.sports_esports,
                              color: Colors.white),
                        ),
                        title: Text(game.$1.title.isEmpty ? 'Match' : game.$1.title),
                        subtitle: Text('${game.$3 ? 'Gagné' : 'Perdu'} · ${game.$2.score} points'),
                        trailing: Text(game.$1.createdAt == null
                            ? ''
                            : '${game.$1.createdAt!.day.toString().padLeft(2, '0')}/${game.$1.createdAt!.month.toString().padLeft(2, '0')}/${game.$1.createdAt!.year}'),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HistoryStat extends StatelessWidget {
  final String label;
  final String value;
  const _HistoryStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: titleStyle(20, color: JangColors.snGreen, weight: 900)),
        const SizedBox(height: 4),
        Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]);
}


/// Liste les matchs en cours que l’utilisateur peut demander à observer.
class MatchFinderScreen extends StatefulWidget {
  const MatchFinderScreen({super.key});

  @override
  State<MatchFinderScreen> createState() => _MatchFinderScreenState();
}

class _MatchFinderScreenState extends State<MatchFinderScreen> {
  late Future<List<LiveMatch>> _future = MatchService.instance.activeMatches();
  final Set<String> _busy = {};

  Future<void> _observe(LiveMatch match) async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    setState(() => _busy.add(match.id));
    try {
      await MatchService.instance.requestObservation(match.id, p);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MatchRoomScreen(matchId: match.id, spectator: true),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible d’envoyer la demande. Réessaie.')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(match.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.profile.value?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Matchs en direct')),
      body: FutureBuilder<List<LiveMatch>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Impossible de charger les matchs. Vérifie ta connexion puis actualise.'),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final matches = snap.data!.where((m) => m.hostUid != uid).toList();
          if (matches.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucun match en cours pour le moment. Réessaie plus tard.'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = MatchService.instance.activeMatches()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Choisis un match. Son hôte devra accepter ta demande.'),
                const SizedBox(height: 8),
                FutureBuilder<int>(
                  future: MatchService.instance.completedMatchCount(),
                  builder: (context, count) => Text(
                    '${count.data ?? '…'} matchs joués au total · ${matches.length} en cours',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: JangColors.snGreen),
                  ),
                ),
                const SizedBox(height: 10),
                for (final match in matches)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: JangColors.snGreen,
                        child: Icon(Icons.sensors, color: Colors.white),
                      ),
                      title: Text(match.title.isEmpty ? 'Match de ${match.hostName}' : match.title),
                      subtitle: StreamBuilder<List<MatchPlayer>>(
                        stream: MatchService.instance.players(match.id),
                        builder: (context, playersSnap) {
                          final players = playersSnap.data ?? const <MatchPlayer>[];
                          final names = players.map((p) => p.name).join(', ');
                          return Text(
                            'Hôte : ${match.hostName} · ${players.length} joueur${players.length == 1 ? '' : 's'}${names.isEmpty ? '' : ' : $names'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                      trailing: FilledButton(
                        onPressed: _busy.contains(match.id) ? null : () => _observe(match),
                        child: Text(_busy.contains(match.id) ? 'Envoi…' : 'Demander'),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Demande le code et entre dans le match.
Future<void> joinMatchDialog(BuildContext context) async {
  final p = AuthService.instance.profile.value;
  if (p == null) return;
  final ctrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rejoindre un match'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tape le code à 6 chiffres que ton ami te donne.'),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(hintText: '000000', counterText: ''),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Entrer')),
      ],
    ),
  );
  if (code == null || code.trim().isEmpty || !context.mounted) return;
  try {
    final (m, err) = await MatchService.instance.joinByCode(code, p);
    if (!context.mounted) return;
    if (m == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRoomScreen(matchId: m.id)));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pas de connexion. Il faut internet pour un match.')));
    }
  }
}

/// Choix du domaine, du niveau et du nombre de questions.
class MatchSetupScreen extends StatefulWidget {
  final bool solo;
  final String? friendUid;
  final String? friendName;
  const MatchSetupScreen({super.key, this.solo = false, this.friendUid, this.friendName});

  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  final Set<String> _domains = {...QuizBank.domains};
  String _level = QuizBank.levels.first;
  int _count = 10;
  String _opponent = 'aucun';
  bool _busy = false;

  Future<void> _go() async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      if (_domains.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Choisis au moins un domaine.')));
        return;
      }
      final qs = await QuizBank.instance.drawDomains(_domains.toList(), _level, _count);
      if (!mounted) return;
      if (qs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Les questions ne sont pas encore là. Vérifie ta connexion, ou choisis un autre domaine.')));
        return;
      }
      final domainTitle = _domains.map(QuizBank.domainLabel).join(' + ');
      final title = '$domainTitle · ${QuizBank.levelLabel(_level)}';
      if (widget.solo) {
        final subject = Subject(id: '', examId: p.examId, name: 'Anglais', color: '#00853F');
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => QuizScreen(
              lesson: Lesson(
                id: 'match_${_domains.join('_')}_$_level',
                examId: p.examId,
                subjectId: '',
                chapterId: '',
                title: title,
                quiz: [for (final q in qs) q.toQuiz()],
              ),
              subject: subject,
              opponentId: _opponent == 'aucun' ? null : _opponent,
            ),
          ),
        );
        return;
      }
      final m = await MatchService.instance
          .create(host: p, questions: qs, domain: _domains.join(','), level: _level, title: title);
      if (widget.friendUid != null) {
        await XaritService.instance.inviteToMatch(p, widget.friendUid!, m);
      }
      if (!mounted) return;
      await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MatchRoomScreen(matchId: m.id)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Pas de connexion. Réessaie quand tu as internet.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.solo ? 'M\'entraîner seul' : 'Créer un match')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text('Quel domaine ?', style: titleStyle(19, weight: 800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in QuizBank.domains)
              FilterChip(
                label: Text('${QuizBank.domainEmoji(d)} ${QuizBank.domainLabel(d)}'),
                selected: _domains.contains(d),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _domains.add(d);
                  } else {
                    _domains.remove(d);
                  }
                }),
              ),
          ]),
          const SizedBox(height: 18),
          Text('Quel niveau ?', style: titleStyle(19, weight: 800)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final (l, c) in [('debutant', '🟢'), ('intermediaire', '🟡'), ('avance', '🔴')])
                ButtonSegment(value: l, label: Text('$c ${QuizBank.levelLabel(l)}', style: const TextStyle(fontSize: 12))),
            ],
            selected: {_level},
            onSelectionChanged: (s) => setState(() => _level = s.first),
          ),
          const SizedBox(height: 18),
          Text('Combien de questions ?', style: titleStyle(19, weight: 800)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 5, label: Text('5')),
              ButtonSegment(value: 10, label: Text('10')),
              ButtonSegment(value: 15, label: Text('15')),
            ],
            selected: {_count},
            onSelectionChanged: (s) => setState(() => _count = s.first),
          ),
          if (widget.solo) ...[
            const SizedBox(height: 18),
            Text('Choisis ton partenaire', style: titleStyle(19, weight: 800)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (id, name, level) in [
                ('aucun', 'Jouer seul', 'À ton rythme'),
                ('gainde', 'Gaïndé', 'Débutant'),
                ('modou', 'Modou', 'Intermédiaire'),
                ('awa', 'Awa', 'Bonne élève'),
                ('kocc', 'Kocc', 'Excellent'),
              ])
                ChoiceChip(
                  label: Text('$name · $level'),
                  selected: _opponent == id,
                  onSelected: (_) => setState(() => _opponent = id),
                ),
            ]),
          ],
          const SizedBox(height: 24),
          ChunkyButton(
            label: _busy ? 'Un instant…' : (widget.solo ? 'Commencer' : 'Créer et avoir le code'),
            icon: Icons.play_arrow_rounded,
            color: JangColors.primary,
            onPressed: _busy ? null : _go,
          ),
        ],
      ),
    );
  }
}

/// La salle du match : attente, questions, corrections, podium.
/// Sert aussi au quiz en direct du prof (il mène sans jouer).
class MatchRoomScreen extends StatefulWidget {
  final String matchId;
  final bool spectator;
  final bool tournamentFree;
  const MatchRoomScreen({super.key, required this.matchId, this.spectator = false, this.tournamentFree = false});

  @override
  State<MatchRoomScreen> createState() => _MatchRoomScreenState();
}

class _MatchRoomScreenState extends State<MatchRoomScreen> {
  final _svc = MatchService.instance;
  StreamSubscription<LiveMatch>? _mSub;
  StreamSubscription<List<MatchPlayer>>? _pSub;
  LiveMatch? _m;
  List<MatchPlayer> _players = const [];
  Timer? _tick;
  StreamSubscription<MatchObserver?>? _oSub;
  MatchObserver? _observation;
  bool _observationLoaded = false;

  /// Moment où la question en cours est apparue sur ce téléphone.
  int _seenIndex = -2;
  DateTime _seenAt = DateTime.now();
  int? _myChoice;
  int _myPoints = 0;
  bool _hostAdvancing = false;

  String get _uid => AuthService.instance.profile.value?.uid ?? '';
  bool get _isHost => _m?.hostUid == _uid;
  bool get _plays => !widget.spectator && _m != null && (!_isHost || _m!.hostPlays || (_m!.tournamentId.isNotEmpty && _players.any((p) => p.uid == _uid)));

  @override
  void initState() {
    super.initState();
    _mSub = _svc.watch(widget.matchId).listen(_onMatch);
    if (widget.spectator) {
      _oSub = _svc.myObservation(widget.matchId, _uid).listen((o) {
        if (!mounted) return;
        setState(() {
          _observation = o;
          _observationLoaded = true;
        });
      });
    }
    _pSub = _svc.players(widget.matchId).listen((p) {
      if (!mounted) return;
      setState(() => _players = p);
      _maybeReveal();
    });
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_m?.state == LiveMatch.asking) {
        setState(() {});
        _maybeReveal();
      }
    });
  }

  void _onMatch(LiveMatch m) {
    if (!mounted) return;
    if (m.index != _seenIndex) {
      _seenIndex = m.index;
      _seenAt = DateTime.now();
      _myChoice = null;
      _myPoints = 0;
      _hostAdvancing = false;
    }
    final was = _m?.state;
    setState(() => _m = m);
    // Après la correction, l'hôte d'un match entre élèves passe tout seul à la suite.
    if (_isHost && m.hostPlays && m.state == LiveMatch.showing && was != LiveMatch.showing) {
      final idx = m.index;
      Future.delayed(const Duration(seconds: 6), () {
        final cur = _m;
        if (mounted && cur != null && cur.state == LiveMatch.showing && cur.index == idx) _svc.next(cur);
      });
    }
  }

  Duration get _elapsed => DateTime.now().difference(_seenAt);
  int get _left {
    final m = _m;
    if (m == null) return 0;
    return (m.seconds - _elapsed.inMilliseconds / 1000).ceil().clamp(0, m.seconds);
  }

  int get _answeredCount => _players.where((p) => p.answers.containsKey(_m?.index ?? -1)).length;

  /// L'hôte montre la correction quand le temps est fini ou quand tout le monde a répondu.
  void _maybeReveal() {
    final m = _m;
    if (m == null || !_isHost || m.state != LiveMatch.asking || _hostAdvancing) return;
    final everyone = _players.isNotEmpty && _answeredCount >= _players.length;
    if (_left <= 0 || everyone) {
      _hostAdvancing = true;
      _svc.reveal(m);
    }
  }

  Future<void> _answer(int i) async {
    final m = _m;
    if (m == null || _myChoice != null || _left <= 0) return;
    setState(() => _myChoice = i);
    try {
      final pts = await _svc.answer(m, _uid, i, _elapsed);
      if (mounted) setState(() => _myPoints = pts);
    } catch (_) {}
  }

  Future<bool> _confirmLeave() async {
    final m = _m;
    if (m == null || m.state == LiveMatch.over) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter le match ?'),
        content: Text(_isHost ? 'Le match va s\'arrêter pour tout le monde.' : 'Tu ne pourras plus revenir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rester')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitter')),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      if (_isHost) {
        await _svc.finish(m);
      } else if (m.state == LiveMatch.waiting) {
        await _svc.leave(m.id, _uid);
      }
    } catch (_) {}
    return true;
  }

  @override
  void dispose() {
    _mSub?.cancel();
    _pSub?.cancel();
    _oSub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return PopScope(
      canPop: m == null || m.state == LiveMatch.over,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: JangColors.snGreen,
        appBar: AppBar(
          backgroundColor: JangColors.snGreen,
          foregroundColor: Colors.white,
          title: Text(m?.title.isNotEmpty == true ? m!.title : 'Match'),
        ),
        body: m == null
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : widget.spectator && !widget.tournamentFree && (!_observationLoaded || _observation?.status == 'pending')
                ? _observationWaiting()
                : widget.spectator && !widget.tournamentFree && _observation?.status != 'accepted'
                    ? _observationRefused()
                    : Column(children: [
                        _ObserversPanel(matchId: widget.matchId, canManage: _isHost),
                        Expanded(
                          child: switch (m.state) {
                            LiveMatch.waiting => _lobby(m),
                            LiveMatch.asking => _question(m),
                            LiveMatch.showing => _correction(m),
                            _ => _podium(m),
                          },
                        ),
                      ]),
      ),
    );
  }

  Widget _observationWaiting() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Demande envoyée. Attends que l’hôte accepte pour regarder.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _observationRefused() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.visibility_off_outlined, color: Colors.white, size: 42),
            const SizedBox(height: 12),
            const Text('L’hôte n’a pas accepté la demande d’observation.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Retour'),
            ),
          ]),
        ),
      );

  // ---------- Salle d'attente ----------

  Widget _lobby(LiveMatch m) {
    final canStart = m.tournamentId.isNotEmpty ? _players.length >= 2 : (m.hostPlays ? _players.length >= 2 : _players.isNotEmpty);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
        child: Column(children: [
          const Text('CODE DU MATCH', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
          FittedBox(
            child: Text(m.code, style: titleStyle(56, weight: 800).copyWith(letterSpacing: 8)),
          ),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: m.code));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié.')));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copier le code'),
          ),
          Text(
            _isHost
                ? 'Donne ce code à tes amis. Ils touchent « Rejoindre avec un code ».'
                : 'Attends que ${m.hostName} lance le match.',
            textAlign: TextAlign.center,
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Text('${_players.length} joueur${_players.length > 1 ? 's' : ''}',
          style: titleStyle(20, color: Colors.white, weight: 800)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in _players)
          Chip(
            avatar: const Icon(Icons.check_circle, color: JangColors.success, size: 18),
            label: Text(p.uid == _uid ? '${p.name} (moi)' : p.name),
          ),
      ]),
      if (_isHost) ...[
        const SizedBox(height: 24),
        ChunkyButton(
          label: canStart ? 'Commencer !' : 'Il faut au moins ${m.tournamentId.isNotEmpty || m.hostPlays ? 2 : 1} joueur${m.tournamentId.isNotEmpty || m.hostPlays ? 's' : ''}',
          icon: Icons.play_arrow_rounded,
          color: JangColors.success,
          onPressed: canStart ? () => _svc.ask(m, 0) : null,
        ),
      ] else ...[
        const SizedBox(height: 30),
        const Center(child: CircularProgressIndicator(color: Colors.white)),
      ],
    ]);
  }

  // ---------- Question ----------

  Widget _question(LiveMatch m) {
    final q = m.current;
    if (q == null) return const SizedBox.shrink();
    final left = _left;
    return Column(children: [
      LinearProgressIndicator(
        value: m.seconds == 0 ? 0 : left / m.seconds,
        minHeight: 8,
        color: left <= 5 ? const Color(0xFFE21B3C) : JangColors.success,
        backgroundColor: Colors.white24,
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 16), children: [
          Row(children: [
            Text('Question ${m.index + 1} / ${m.questions.length}',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            const Spacer(),
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white,
              child: Text('$left', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (q.text.isNotEmpty) ...[
                SayText(q.text, style: const TextStyle(fontSize: 15, height: 1.35), size: 24),
                const Divider(height: 20),
              ],
              Text(q.question, style: titleStyle(21, weight: 800)),
            ]),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          if (_players.any((p) => p.reaction.isNotEmpty))
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in _players.where((p) => p.reaction.isNotEmpty))
                  Chip(
                    avatar: Text(p.reaction, style: const TextStyle(fontSize: 18)),
                    label: Text(p.name),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          if (_plays)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final emoji in ['👏', '😂', '🔥', '💪', '❤️'])
                  IconButton(
                    tooltip: 'Réagir $emoji',
                    onPressed: () => _svc.react(widget.matchId, _uid, emoji),
                    icon: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
              ],
            ),
          if (_plays)
            _tiles(q, reveal: false)
          else if (_isHost)
            _hostWatch(m)
          else
            _viewerWatch(m),
          if (_plays && _myChoice != null) ...[
            const SizedBox(height: 14),
            const Center(
              child: Text('Réponse envoyée ✓  Attends les autres…',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      ),
    ]);
  }

  Widget _hostWatch(LiveMatch m) => Column(children: [
        _tiles(m.current!, reveal: false, enabled: false),
        const SizedBox(height: 14),
        Text('$_answeredCount / ${_players.length} ont répondu',
            style: titleStyle(20, color: Colors.white, weight: 800)),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
          onPressed: () => _svc.reveal(m),
          child: const Text('Montrer la réponse maintenant'),
        ),
      ]);

  Widget _tiles(BankQuestion q, {required bool reveal, bool enabled = true}) {
    return Column(children: [
      for (var i = 0; i < 4; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Opacity(
            opacity: reveal ? (i == q.answer ? 1 : 0.45) : (_myChoice == null || _myChoice == i ? 1 : 0.55),
            child: Container(
              decoration: BoxDecoration(
                color: _tileColors[i],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: reveal && i == q.answer || _myChoice == i
                      ? JangColors.snGreen
                      : const Color(0xFFE5E7EB),
                  width: reveal && i == q.answer || _myChoice == i ? 2.5 : 1.5,
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: enabled && !reveal && _myChoice == null ? () => _answer(i) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: JangColors.snGreen,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(_shapes[i],
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(q.options[i],
                            style: const TextStyle(color: JangColors.text, fontWeight: FontWeight.w800, fontSize: 17)),
                      ),
                      if (reveal && i == q.answer) const Icon(Icons.check_circle, color: JangColors.snGreen),
                      if (!reveal && _myChoice == i) const Icon(Icons.radio_button_checked, color: JangColors.snGreen),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _viewerWatch(LiveMatch m) => Column(children: [
        _tiles(m.current!, reveal: false, enabled: false),
        const SizedBox(height: 10),
        Text('$_answeredCount / ${_players.length} ont répondu',
            style: titleStyle(18, color: Colors.white, weight: 800)),
      ]);

  // ---------- Correction ----------

  Widget _correction(LiveMatch m) {
    final q = m.current;
    if (q == null) return const SizedBox.shrink();
    final ok = _myChoice == q.answer;
    final right = _players.where((p) => p.answers[m.index]?.$2 == true).length;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 28), children: [
      if (_plays)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ok ? JangColors.success : (_myChoice == null ? Colors.grey.shade700 : const Color(0xFFE21B3C)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            CharacterView.of(ok ? 'gainde' : 'kocc', size: 56, moves: ok ? Moves.jump : Moves.sway),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ok ? "${Cheer.fromCharacter('gainde', true)} +$_myPoints" : (_myChoice == null ? Cheer.fromCharacter('kocc', false) : Cheer.fromCharacter('kocc', false)),
                style: titleStyle(24, color: Colors.white, weight: 800),
              ),
            ),
          ]),
        )
      else
        Text('$right / ${_players.length} ont trouvé', style: titleStyle(22, color: Colors.white, weight: 800)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q.question, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.check_circle, color: JangColors.success),
            const SizedBox(width: 6),
            Expanded(child: SayText(q.options[q.answer], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          ]),
          if (q.explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(q.explanation),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _report(q),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('Signaler une erreur'),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Text('Classement', style: titleStyle(19, color: Colors.white, weight: 800)),
      const SizedBox(height: 6),
      for (final (i, p) in _players.take(5).indexed) _rankRow(i, p),
      if (_isHost && !m.hostPlays) ...[
        const SizedBox(height: 16),
        ChunkyButton(
          label: m.isLast ? 'Voir le podium' : 'Question suivante',
          icon: Icons.arrow_forward_rounded,
          color: JangColors.success,
          onPressed: () => _svc.next(m),
        ),
      ] else ...[
        const SizedBox(height: 14),
        Center(
          child: Text(m.isLast ? 'Le podium arrive…' : 'La question suivante arrive…',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
        ),
      ],
    ]);
  }

  Widget _rankRow(int i, MatchPlayer p) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.uid == _uid ? const Color(0xFFFDEF42) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          SizedBox(
              width: 32,
              child: Text(i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}', style: const TextStyle(fontSize: 18))),
          Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text('${p.score}', style: const TextStyle(fontWeight: FontWeight.w900)),
        ]),
      );

  Future<void> _report(BankQuestion q) async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Signaler une erreur'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Qu\'est-ce qui ne va pas ? (facultatif)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Envoyer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await QuizBank.instance.report(q, p, note: ctrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Merci ! On va vérifier.')));
      }
    } catch (_) {}
  }

  // ---------- Podium ----------

  Widget _podium(LiveMatch m) {
    final rank = _players.indexWhere((p) => p.uid == _uid);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 28), children: [
      Center(child: Text('Podium', style: titleStyle(32, color: Colors.white, weight: 800))),
      const SizedBox(height: 10),
      for (final (i, p) in _players.take(3).indexed)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: [const Color(0xFFFFD54F), const Color(0xFFE0E0E0), const Color(0xFFD7A26B)][i],
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            Text(['🥇', '🥈', '🥉'][i], style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 10),
            Expanded(child: Text(p.name, style: titleStyle(22, weight: 800))),
            Text('${p.score}', style: titleStyle(22, weight: 800)),
          ]),
        ),
      if (_plays && rank >= 0) ...[
        const SizedBox(height: 10),
        Center(
          child: Text(
            rank == 0 ? 'Tu as gagné ! 🎉' : 'Tu es ${rank + 1}e sur ${_players.length}.',
            style: titleStyle(22, color: Colors.white, weight: 800),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text('Les questions', style: titleStyle(19, color: Colors.white, weight: 800)),
      const SizedBox(height: 6),
      for (final (i, q) in m.questions.indexed) _recapRow(i, q),
      if (_players.length > 3) ...[
        const SizedBox(height: 16),
        Text('Tout le classement', style: titleStyle(19, color: Colors.white, weight: 800)),
        const SizedBox(height: 6),
        for (final (i, p) in _players.indexed) _rankRow(i, p),
      ],
      const SizedBox(height: 16),
      ChunkyButton(label: 'Terminer', icon: Icons.check, onPressed: () => Navigator.pop(context)),
    ]);
  }

  Widget _recapRow(int i, BankQuestion q) {
    final me = _players.where((p) => p.uid == _uid).firstOrNull;
    final mine = me?.answers[i];
    final right = _players.where((p) => p.answers[i]?.$2 == true).length;
    final pct = _players.isEmpty ? 0 : (right * 100 / _players.length).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          !_plays ? Icons.bar_chart : (mine?.$2 == true ? Icons.check_circle : Icons.cancel),
          color: !_plays ? JangColors.primary : (mine?.$2 == true ? JangColors.success : JangColors.error),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i + 1}. ${q.question}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Réponse : ${q.options[q.answer]}', style: const TextStyle(color: JangColors.successDark)),
            if (_plays && mine != null && !mine.$2 && mine.$1 >= 0)
              Text('Toi : ${q.options[mine.$1]}', style: const TextStyle(color: JangColors.errorDark)),
            Text('$pct % ont trouvé', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

class _ObserversPanel extends StatelessWidget {
  final String matchId;
  final bool canManage;
  const _ObserversPanel({required this.matchId, required this.canManage});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MatchObserver>>(
        stream: MatchService.instance.observers(matchId, includePending: canManage),
        builder: (context, snap) {
          final all = snap.data ?? const <MatchObserver>[];
          final approved = all.where((o) => o.status == 'accepted').toList();
          final pending = canManage ? all.where((o) => o.status == 'pending').toList() : const <MatchObserver>[];
          if (approved.isEmpty && pending.isEmpty) return const SizedBox.shrink();
          return Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (approved.isNotEmpty)
                Text('Observateurs : ${approved.map((o) => o.name).join(', ')}',
                    style: const TextStyle(color: JangColors.snGreen, fontWeight: FontWeight.w800)),
              for (final o in pending)
                Row(children: [
                  Expanded(child: Text('${o.name} demande à observer')),
                  IconButton(
                    tooltip: 'Accepter',
                    onPressed: () => MatchService.instance.decideObservation(matchId, o.uid, accept: true),
                    icon: const Icon(Icons.check_circle, color: JangColors.snGreen),
                  ),
                  IconButton(
                    tooltip: 'Refuser',
                    onPressed: () => MatchService.instance.decideObservation(matchId, o.uid, accept: false),
                    icon: const Icon(Icons.cancel_outlined, color: JangColors.textSecondary),
                  ),
                ]),
            ]),
          );
        },
      );
}
