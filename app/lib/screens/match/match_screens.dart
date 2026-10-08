import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/match_service.dart';
import '../../services/quiz_bank.dart';
import '../../theme.dart';
import '../../widgets/characters.dart';
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
          const SizedBox(height: 16),
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
  const MatchSetupScreen({super.key, this.solo = false});

  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  String _domain = QuizBank.mixed;
  String _level = QuizBank.levels.first;
  int _count = 10;
  bool _busy = false;

  Future<void> _go() async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final qs = await QuizBank.instance.draw(_domain, _level, _count);
      if (!mounted) return;
      if (qs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Les questions ne sont pas encore là. Vérifie ta connexion, ou choisis un autre domaine.')));
        return;
      }
      final title = '${QuizBank.domainLabel(_domain)} · ${QuizBank.levelLabel(_level)}';
      if (widget.solo) {
        final subject = Subject(id: '', examId: p.examId, name: 'Anglais', color: '#46178F');
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => QuizScreen(
              lesson: Lesson(
                id: 'match_${_domain}_$_level',
                examId: p.examId,
                subjectId: '',
                chapterId: '',
                title: title,
                quiz: [for (final q in qs) q.toQuiz()],
              ),
              subject: subject,
            ),
          ),
        );
        return;
      }
      final m = await MatchService.instance
          .create(host: p, questions: qs, domain: _domain, level: _level, title: title);
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
            for (final d in [QuizBank.mixed, ...QuizBank.domains])
              ChoiceChip(
                label: Text('${QuizBank.domainEmoji(d)} ${QuizBank.domainLabel(d)}'),
                selected: _domain == d,
                onSelected: (_) => setState(() => _domain = d),
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
  const MatchRoomScreen({super.key, required this.matchId});

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

  /// Moment où la question en cours est apparue sur ce téléphone.
  int _seenIndex = -2;
  DateTime _seenAt = DateTime.now();
  int? _myChoice;
  int _myPoints = 0;
  bool _hostAdvancing = false;

  String get _uid => AuthService.instance.profile.value?.uid ?? '';
  bool get _isHost => _m?.hostUid == _uid;
  bool get _plays => _m != null && (!_isHost || _m!.hostPlays);

  @override
  void initState() {
    super.initState();
    _mSub = _svc.watch(widget.matchId).listen(_onMatch);
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
            : switch (m.state) {
                LiveMatch.waiting => _lobby(m),
                LiveMatch.asking => _question(m),
                LiveMatch.showing => _correction(m),
                _ => _podium(m),
              },
      ),
    );
  }

  // ---------- Salle d'attente ----------

  Widget _lobby(LiveMatch m) {
    final canStart = m.hostPlays ? _players.length >= 2 : _players.isNotEmpty;
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
          label: canStart ? 'Commencer !' : 'Il faut au moins ${m.hostPlays ? 2 : 1} joueur${m.hostPlays ? 's' : ''}',
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
          if (_plays) _tiles(q, reveal: false) else _hostWatch(m),
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
                ok ? 'Juste ! +$_myPoints' : (_myChoice == null ? 'Trop tard !' : 'Raté…'),
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
