import 'package:flutter/material.dart';

import '../models.dart';
import '../services/progress_repo.dart';
import '../theme.dart';
import '../widgets/cheer.dart';
import '../widgets/common.dart';

class QuizScreen extends StatefulWidget {
  final Lesson lesson;
  final Subject subject;
  const QuizScreen({super.key, required this.lesson, required this.subject});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late List<int?> _answers;
  bool _submitted = false;
  final _scroll = ScrollController();

  List<QuizQuestion> get _quiz => widget.lesson.quiz;

  // Messages choisis une seule fois à la correction (ils ne changent pas en faisant défiler).
  String _endMessage = '';
  List<String> _feedback = const [];

  @override
  void initState() {
    super.initState();
    _answers = List<int?>.filled(_quiz.length, null);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int get _score {
    var s = 0;
    for (var i = 0; i < _quiz.length; i++) {
      if (_answers[i] == _quiz[i].answer) s++;
    }
    return s;
  }

  void _submit() {
    final missing = _answers.where((a) => a == null).length;
    if (missing > 0) {
      showMessage(context,
          'Il reste $missing question${missing > 1 ? 's' : ''} sans réponse. Réponds à tout avant de soumettre.');
      return;
    }
    final before = ProgressRepo.instance.of(widget.lesson.id);
    final previousBest = before?.quizDone == true ? (before!.bestScore ?? 0) : -1;
    final score = _score;
    _endMessage = Cheer.quizEnd(score, _quiz.length,
        improved: previousBest >= 0 && score > previousBest);
    var wrongRow = 0;
    final feedback = <String>[];
    for (var i = 0; i < _quiz.length; i++) {
      if (_answers[i] == _quiz[i].answer) {
        wrongRow = 0;
        feedback.add(Cheer.right());
      } else {
        wrongRow++;
        feedback.add(wrongRow >= 3 ? Cheer.streakWrong() : Cheer.wrong());
      }
    }
    _feedback = feedback;
    ProgressRepo.instance.recordQuiz(
        widget.lesson, [for (var i = 0; i < _quiz.length; i++) _answers[i] == _quiz[i].answer]);
    setState(() => _submitted = true);
    _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  void _restart() {
    setState(() {
      _answers = List<int?>.filled(_quiz.length, null);
      _submitted = false;
    });
    _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(widget.subject.color);
    final answered = _answers.where((a) => a != null).length;
    return Scaffold(
      appBar: AppBar(
        title: Text('QCM', style: titleStyle(20, color: Colors.white)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(widget.lesson.title, style: titleStyle(22)),
          const SizedBox(height: 12),
          if (_submitted) _ScoreBanner(score: _score, total: _quiz.length, color: color, message: _endMessage),
          for (var i = 0; i < _quiz.length; i++) _question(context, i, color),
          const SizedBox(height: 8),
          if (!_submitted) ...[
            Text('$answered / ${_quiz.length} réponses',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: _submit,
              child: const Text('Soumettre mes réponses'),
            ),
          ] else ...[
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: _restart,
              child: const Text('Recommencer'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Retour à la leçon'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _question(BuildContext context, int i, Color color) {
    final q = _quiz[i];
    final t = Theme.of(context).textTheme;
    final chosen = _answers[i];
    final correct = chosen == q.answer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}. ', style: titleStyle(17, color: color)),
                  Expanded(child: Text(q.question, style: t.titleMedium)),
                  if (_submitted)
                    Icon(correct ? Icons.check_circle : Icons.cancel,
                        color: correct ? JangColors.success : JangColors.error),
                ],
              ),
              const SizedBox(height: 10),
              for (var o = 0; o < q.options.length; o++)
                if (q.options[o].trim().isNotEmpty) _option(context, i, o, color),
              if (_submitted && i < _feedback.length)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Text(_feedback[i],
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: correct ? JangColors.success : JangColors.textSecondary)),
                ),
              if (_submitted && !correct && q.explanation.trim().isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6, bottom: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: JangColors.noteBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Explication', style: t.titleSmall),
                      const SizedBox(height: 4),
                      LessonText(q.explanation, accent: color),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(BuildContext context, int qi, int oi, Color color) {
    final q = _quiz[qi];
    final selected = _answers[qi] == oi;
    Color border = JangColors.border;
    Color bg = Colors.white;
    Widget? mark;
    if (!_submitted) {
      if (selected) {
        border = color;
        bg = color.withValues(alpha: 0.08);
      }
    } else if (oi == q.answer) {
      border = JangColors.success;
      bg = JangColors.successBg;
      mark = const Text('Bonne réponse',
          style: TextStyle(color: JangColors.success, fontWeight: FontWeight.w700, fontSize: 13));
    } else if (selected) {
      border = JangColors.error;
      bg = JangColors.errorBg;
      mark = const Text('Ta réponse',
          style: TextStyle(color: JangColors.error, fontWeight: FontWeight.w700, fontSize: 13));
    }
    const letters = ['A', 'B', 'C', 'D'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border, width: selected || mark != null ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _submitted ? null : () => setState(() => _answers[qi] = oi),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected && !_submitted ? color : Colors.transparent,
                      border: Border.all(color: selected && !_submitted ? color : JangColors.border, width: 1.5),
                    ),
                    child: Text(letters[oi],
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected && !_submitted ? Colors.white : JangColors.textSecondary)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(q.options[oi], style: Theme.of(context).textTheme.bodyLarge),
                        if (mark != null) mark,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreBanner extends StatelessWidget {
  final int score;
  final int total;
  final Color color;
  final String message;
  const _ScoreBanner(
      {required this.score, required this.total, required this.color, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ta note', style: const TextStyle(color: Colors.white, fontSize: 15)),
          Text('$score / $total', style: titleStyle(40, color: Colors.white, weight: 800)),
          const SizedBox(height: 4),
          Text(message, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }
}
