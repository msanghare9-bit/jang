import 'package:flutter/material.dart';

import '../models.dart';
import '../services/content_repo.dart';
import '../services/media_service.dart';
import '../services/progress_repo.dart';
import '../services/stats_service.dart';
import '../theme.dart';
import '../widgets/cheer.dart';
import '../widgets/common.dart';

class _ReviewItem {
  final Lesson lesson;
  final QuizQuestion question;
  final String key;
  _ReviewItem(this.lesson, this.question, this.key);
}

/// Corriger mes erreurs : les questions ratées, une par une.
/// Une question sort de la liste après deux bonnes réponses de suite.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late Future<List<_ReviewItem>> _future = _load();
  int _index = 0;
  int? _chosen;
  String _cheer = '';
  int _wrongRow = 0;
  int _ok = 0;

  Future<List<_ReviewItem>> _load() async {
    final items = <_ReviewItem>[];
    for (final p in ProgressRepo.instance.all.values) {
      if (p.mistakes.isEmpty) continue;
      final lesson = await ContentRepo.instance.lesson(p.lessonId);
      if (lesson == null) continue;
      for (final q in lesson.quiz) {
        final k = StatsService.questionKey(q.question);
        if (p.mistakes.containsKey(k)) items.add(_ReviewItem(lesson, q, k));
      }
    }
    items.shuffle();
    return items.take(15).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Corriger mes erreurs')),
      body: FutureBuilder<List<_ReviewItem>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Aucune erreur à revoir',
                message: 'Bravo ! Les questions que tu rates aux exercices apparaîtront ici.',
              ),
            );
          }
          if (_index >= items.length) return _summary(context, items.length);
          return _question(context, items[_index], items.length);
        },
      ),
    );
  }

  Widget _summary(BuildContext context, int n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$_ok / $n', style: titleStyle(44, color: JangColors.primary, weight: 800)),
          const SizedBox(height: 8),
          Text(Cheer.quizEnd(_ok, n), textAlign: TextAlign.center, style: titleStyle(18)),
          const SizedBox(height: 8),
          const Text(
              'Une question disparaît de la liste quand tu la réussis deux fois de suite.',
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => setState(() {
              _future = _load();
              _index = 0;
              _ok = 0;
              _chosen = null;
            }),
            child: const Text('Continuer à réviser'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Terminer')),
        ]),
      ),
    );
  }

  Widget _question(BuildContext context, _ReviewItem item, int n) {
    final q = item.question;
    final t = Theme.of(context).textTheme;
    final answered = _chosen != null;
    const letters = ['A', 'B', 'C', 'D'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('Question ${_index + 1} sur $n · ${item.lesson.title}', style: t.bodySmall),
        const SizedBox(height: 8),
        ProgressBar(value: _index / n, color: JangColors.primary),
        const SizedBox(height: 16),
        Text(q.question, style: t.titleMedium),
        if (q.image.isNotEmpty) ...[
          const SizedBox(height: 10),
          MediaImage(q.image, height: 160, fit: BoxFit.contain),
        ],
        const SizedBox(height: 14),
        for (var i = 0; i < q.options.length; i++)
          if (q.options[i].trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: !answered
                    ? Colors.white
                    : (i == q.answer
                        ? JangColors.successBg
                        : (i == _chosen ? JangColors.errorBg : Colors.white)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: !answered
                        ? JangColors.border
                        : (i == q.answer
                            ? JangColors.success
                            : (i == _chosen ? JangColors.error : JangColors.border)),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: answered
                      ? null
                      : () {
                          final ok = i == q.answer;
                          ProgressRepo.instance.recordReview(item.lesson, item.key, ok);
                          setState(() {
                            _chosen = i;
                            if (ok) {
                              _ok++;
                              _wrongRow = 0;
                              _cheer = Cheer.right();
                            } else {
                              _wrongRow++;
                              _cheer = _wrongRow >= 3 ? Cheer.streakWrong() : Cheer.wrong();
                            }
                          });
                        },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Text('${letters[i]}.  ', style: t.titleSmall),
                        Expanded(child: Text(q.options[i], style: t.bodyLarge)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        if (answered) ...[
          const SizedBox(height: 6),
          Text(_cheer,
              style: titleStyle(18,
                  color: _chosen == q.answer ? JangColors.success : JangColors.primary)),
          if (q.explanation.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration:
                  BoxDecoration(color: JangColors.noteBg, borderRadius: BorderRadius.circular(8)),
              child: LessonText(q.explanation),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() {
              _index++;
              _chosen = null;
            }),
            child: Text(_index + 1 < n ? 'Question suivante' : 'Voir mon résultat'),
          ),
        ],
      ],
    );
  }
}
