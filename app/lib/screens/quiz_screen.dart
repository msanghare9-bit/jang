import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/engagement_service.dart';
import '../services/media_service.dart';
import '../services/progress_repo.dart';
import '../services/sound_service.dart';
import '../services/story_service.dart';
import '../theme.dart';
import '../widgets/characters.dart';
import '../widgets/cheer.dart';
import '../widgets/fun.dart';
import '../widgets/jang_ui.dart';

/// Exercices : une question à la fois, réponse corrigée tout de suite.
class QuizScreen extends StatefulWidget {
  final Lesson lesson;
  final Subject subject;
  const QuizScreen({super.key, required this.lesson, required this.subject});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  // Tuiles façon Kahoot : rouge ▲, bleu ◆, jaune ●, vert ■.
  static const _shapes = ['▲', '◆', '●', '■'];
  static const _colors = [Color(0xFFE21B3C), Color(0xFF1368CE), Color(0xFFD89E00), Color(0xFF26890C)];

  late List<int?> _answers;
  int _index = 0;
  bool _finished = false;
  int _wrongRow = 0;
  String _cheer = '';
  String _endMessage = '';
  String _title = '';
  bool _celebrate = false;
  String? _newEpisode;
  int _xp = 0;
  static final _rand = Random();
  static const _rightTitles = ['Comprendre nga bou bax !', 'Diambar nga ! 🎉', 'Waaw, bravo ! 🎉'];

  int get _correctCount {
    var s = 0;
    for (var i = 0; i < _quiz.length; i++) {
      if (_answers[i] != null && _answers[i] == _quiz[i].answer) s++;
    }
    return s;
  }

  List<QuizQuestion> get _quiz => widget.lesson.quiz;

  @override
  void initState() {
    super.initState();
    _answers = List<int?>.filled(_quiz.length, null);
  }

  int get _score {
    var s = 0;
    for (var i = 0; i < _quiz.length; i++) {
      if (_answers[i] == _quiz[i].answer) s++;
    }
    return s;
  }

  void _choose(int option) {
    if (_answers[_index] != null) return;
    final ok = option == _quiz[_index].answer;
    setState(() {
      _answers[_index] = option;
      if (ok) {
        _wrongRow = 0;
        _cheer = Cheer.right();
        _title = _rightTitles[_rand.nextInt(_rightTitles.length)];
      } else {
        _wrongRow++;
        _cheer = _wrongRow >= 3 ? Cheer.streakWrong() : Cheer.wrong();
        _title = 'Boul bayi ! Dina bax !';
      }
    });
    if (ok) SoundService.instance.splash();
  }

  void _next() {
    if (_index < _quiz.length - 1) {
      setState(() => _index++);
      return;
    }
    final before = ProgressRepo.instance.of(widget.lesson.id);
    final previousBest = before?.quizDone == true ? (before!.bestScore ?? 0) : -1;
    final score = _score;
    _endMessage =
        Cheer.quizEnd(score, _quiz.length, improved: previousBest >= 0 && score > previousBest);
    ProgressRepo.instance.recordQuiz(
        widget.lesson, [for (var i = 0; i < _quiz.length; i++) _answers[i] == _quiz[i].answer]);
    _xp = score * 10;
    EngagementService.instance.addTo('xp', _xp);
    final great = _quiz.isNotEmpty && score * 10 >= _quiz.length * 8;
    if (great) SoundService.instance.tama();
    setState(() {
      _finished = true;
      _celebrate = great;
      _newEpisode = null;
    });
    StoryService.instance.newlyUnlocked(widget.subject).then((title) {
      if (mounted && title != null) setState(() => _newEpisode = title);
    });
  }

  void _restart() {
    setState(() {
      _answers = List<int?>.filled(_quiz.length, null);
      _index = 0;
      _finished = false;
      _wrongRow = 0;
      _celebrate = false;
      _newEpisode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Quitter',
          icon: const Icon(Icons.close_rounded, color: JangColors.textSecondary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: _beads(),
      ),
      body: !_finished
          ? _question(context)
          : _celebrate
              ? Celebration(
                  score: _score,
                  total: _quiz.length,
                  xp: _xp,
                  episode: _newEpisode,
                  onContinue: () => setState(() => _celebrate = false),
                )
              : _results(context),
    );
  }

  /// Perles de progression : vertes (juste), terre (faux), ocre (en cours).
  Widget _beads() {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(children: [
        for (var i = 0; i < _quiz.length; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: _answers[i] != null
                    ? (_answers[i] == _quiz[i].answer ? JangColors.success : JangColors.error)
                    : (i == _index && !_finished ? JangColors.primary : JangColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _question(BuildContext context) {
    final q = _quiz[_index];
    final chosen = _answers[_index];
    final answered = chosen != null;
    final correct = chosen == q.answer;
    final fbColor = correct ? JangColors.successDark : JangColors.errorDark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
          child: PirogueTrack(steps: _quiz.length, position: _correctCount),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            children: [
              Text('Question ${_index + 1} sur ${_quiz.length}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(q.question, style: titleStyle(24, weight: 800)),
              if (q.image.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: JangColors.border, width: 2),
                  ),
                  child: MediaImage(q.image, height: 180, fit: BoxFit.contain, radius: 18),
                ),
              ],
              const SizedBox(height: 16),
              _grid(q, chosen),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, a) => SizeTransition(sizeFactor: a, child: child),
          child: !answered
              ? const SizedBox(key: ValueKey('vide'), width: double.infinity)
              : Container(
                  key: ValueKey('fb$_index'),
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                      20, 18, 20, 18 + MediaQuery.of(context).padding.bottom),
                  decoration: BoxDecoration(
                    color: correct ? JangColors.successBg : JangColors.errorBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        CharacterView.of(correct ? 'awa' : 'modou',
                            size: 54, moves: correct ? Moves.jump : Moves.sway),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_title.isEmpty ? (correct ? 'Bravo !' : 'Presque !') : _title,
                              style: titleStyle(24, color: fbColor, weight: 800)),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text(_cheer,
                          style: TextStyle(color: fbColor, fontWeight: FontWeight.w700, fontSize: 16)),
                      if (!correct) ...[
                        const SizedBox(height: 6),
                        Text('Bonne réponse : ${q.options[q.answer]}',
                            style: TextStyle(color: fbColor, fontWeight: FontWeight.w800, fontSize: 16)),
                      ],
                      if (q.explanation.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(q.explanation, style: TextStyle(color: fbColor, fontSize: 15)),
                      ],
                      const SizedBox(height: 14),
                      ChunkyButton(
                        label: _index < _quiz.length - 1 ? 'CONTINUER' : 'VOIR MA NOTE',
                        color: correct ? JangColors.success : JangColors.error,
                        onPressed: _next,
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// Grandes tuiles colorées façon Kahoot, deux par ligne.
  Widget _grid(QuizQuestion q, int? chosen) {
    final idx = [for (var o = 0; o < q.options.length && o < 4; o++) if (q.options[o].trim().isNotEmpty) o];
    return Column(children: [
      for (var r = 0; r < idx.length; r += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _option(idx[r], q, chosen)),
              const SizedBox(width: 12),
              Expanded(child: r + 1 < idx.length ? _option(idx[r + 1], q, chosen) : const SizedBox()),
            ]),
          ),
        ),
    ]);
  }

  Widget _option(int o, QuizQuestion q, int? chosen) {
    final answered = chosen != null;
    final isAnswer = o == q.answer;
    final isChosen = o == chosen;
    final color = _colors[o];
    final dim = answered && !isAnswer;
    return Opacity(
      opacity: dim ? (isChosen ? 0.75 : 0.35) : 1,
      child: GestureDetector(
        onTap: answered ? null : () => _choose(o),
        child: Container(
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: JangColors.darker(color, 0.12), offset: const Offset(0, 6))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(
              alignment: Alignment.topLeft,
              child: answered && (isAnswer || isChosen)
                  ? Icon(isAnswer ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: Colors.white, size: 30)
                  : Text(_shapes[o], style: const TextStyle(color: Colors.white, fontSize: 26, height: 1)),
            ),
            Expanded(
              child: Center(
                child: Text(q.options[o],
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final score = _score;
    final total = _quiz.length;
    final good = score * 2 >= total;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Center(
          child: CharacterView.of(good ? 'doudou' : 'modou',
              size: 110, moves: good ? Moves.jump : Moves.sway),
        ),
        if (!good)
          Center(
            child: Text('Boul bayi ! Dina bax !',
                style: titleStyle(20, color: JangColors.warning, weight: 800)),
          ),
        const SizedBox(height: 8),
        Center(child: Text('Ta note', style: Theme.of(context).textTheme.bodySmall)),
        Center(
          child: Text('$score / $total',
              style: titleStyle(52, color: good ? JangColors.success : JangColors.error, weight: 800)),
        ),
        const SizedBox(height: 6),
        Text(_endMessage, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        if (_xp > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('⭐ +$_xp XP', textAlign: TextAlign.center, style: titleStyle(18, weight: 800)),
          ),
        if (_newEpisode != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JangColors.warningBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JangColors.ocre, width: 2),
            ),
            child: Text('📖 Nouvel épisode débloqué : « $_newEpisode ». '
                'Va le lire dans « Mon histoire », en haut de la liste des leçons.',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        const SizedBox(height: 22),
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_answers[i] == _quiz[i].answer ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: _answers[i] == _quiz[i].answer ? JangColors.success : JangColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${_quiz[i].question}\n',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(
                      text: 'Réponse : ${_quiz[i].options[_quiz[i].answer]}',
                      style: const TextStyle(color: JangColors.textSecondary)),
                ])),
              ),
            ]),
          ),
        const SizedBox(height: 18),
        ChunkyButton(label: 'Recommencer', color: JangColors.accent, onPressed: _restart),
        const SizedBox(height: 10),
        ChunkyButton(
          label: 'Retour à la leçon',
          outlined: true,
          color: JangColors.primary,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

