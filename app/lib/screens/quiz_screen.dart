import 'package:flutter/material.dart';

import '../models.dart';
import '../services/media_service.dart';
import '../services/progress_repo.dart';
import '../theme.dart';
import '../widgets/cheer.dart';
import '../widgets/jang_ui.dart';

/// QCM : une question à la fois, réponse corrigée tout de suite.
class QuizScreen extends StatefulWidget {
  final Lesson lesson;
  final Subject subject;
  const QuizScreen({super.key, required this.lesson, required this.subject});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  static const _letters = ['A', 'B', 'C', 'D'];
  static const _colors = [JangColors.accent, JangColors.primary, JangColors.ocre, JangColors.success];

  late List<int?> _answers;
  int _index = 0;
  bool _finished = false;
  int _wrongRow = 0;
  String _cheer = '';
  String _endMessage = '';

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
      } else {
        _wrongRow++;
        _cheer = _wrongRow >= 3 ? Cheer.streakWrong() : Cheer.wrong();
      }
    });
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
    setState(() => _finished = true);
  }

  void _restart() {
    setState(() {
      _answers = List<int?>.filled(_quiz.length, null);
      _index = 0;
      _finished = false;
      _wrongRow = 0;
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
      body: _finished ? _results(context) : _question(context),
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
                    ? (_answers[i] == _quiz[i].answer ? JangColors.success : JangColors.accent)
                    : (i == _index && !_finished ? JangColors.ocre : JangColors.border),
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
    return Column(
      children: [
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
              for (var o = 0; o < q.options.length; o++)
                if (q.options[o].trim().isNotEmpty) _option(o, q, chosen),
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
                    color: correct ? JangColors.success : JangColors.accent,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(correct ? 'Waaw, bravo ! 🎉' : 'Presque !',
                          style: titleStyle(26, color: Colors.white, weight: 800)),
                      const SizedBox(height: 2),
                      Text(_cheer,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      if (!correct) ...[
                        const SizedBox(height: 6),
                        Text('Bonne réponse : ${q.options[q.answer]}',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      ],
                      if (q.explanation.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(q.explanation,
                            style: const TextStyle(color: Colors.white, fontSize: 15)),
                      ],
                      const SizedBox(height: 14),
                      ChunkyButton(
                        label: _index < _quiz.length - 1 ? 'Continuer' : 'Voir ma note',
                        color: Colors.white,
                        textColor: correct ? JangColors.successDark : JangColors.accentDark,
                        onPressed: _next,
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _option(int o, QuizQuestion q, int? chosen) {
    final answered = chosen != null;
    final isAnswer = o == q.answer;
    final isChosen = o == chosen;
    var border = JangColors.border;
    var bg = Colors.white;
    if (answered && isAnswer) {
      border = JangColors.success;
      bg = JangColors.successBg;
    } else if (answered && isChosen) {
      border = JangColors.accent;
      bg = JangColors.errorBg;
    }
    final dim = answered && !isAnswer && !isChosen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: dim ? 0.55 : 1,
        child: GestureDetector(
          onTap: answered ? null : () => _choose(o),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border, width: 2),
              boxShadow: [BoxShadow(color: border, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _colors[o],
                  borderRadius: BorderRadius.circular(11),
                ),
                child: answered && (isAnswer || isChosen)
                    ? Icon(isAnswer ? Icons.check_rounded : Icons.close_rounded,
                        color: JangColors.on(_colors[o]))
                    : Text(_letters[o],
                        style: titleStyle(20, color: JangColors.on(_colors[o]), weight: 800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(q.options[o],
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
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
        Center(child: Text(good ? '🏆' : '🌱', style: const TextStyle(fontSize: 72))),
        const SizedBox(height: 8),
        Center(child: Text('Ta note', style: Theme.of(context).textTheme.bodySmall)),
        Center(
          child: Text('$score / $total',
              style: titleStyle(52, color: good ? JangColors.success : JangColors.accent, weight: 800)),
        ),
        const SizedBox(height: 6),
        Text(_endMessage, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 22),
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_answers[i] == _quiz[i].answer ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: _answers[i] == _quiz[i].answer ? JangColors.success : JangColors.accent),
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

