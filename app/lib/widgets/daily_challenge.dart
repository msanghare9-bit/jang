import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../services/engagement_service.dart';
import '../services/stats_service.dart';
import '../theme.dart';
import 'common.dart';

/// Carte « Défi du jour » sur l'accueil : une question tirée au hasard (mais la même
/// toute la journée) parmi les exercices du niveau de l'élève. Répondre compte aussi
/// pour la série de jours consécutifs.
class DailyChallengeCard extends StatefulWidget {
  const DailyChallengeCard({super.key});

  @override
  State<DailyChallengeCard> createState() => _DailyChallengeCardState();
}

class _DailyChallengeCardState extends State<DailyChallengeCard> {
  late Future<(Lesson, QuizQuestion)?> _future = _pick();
  int? _chosen;

  Future<(Lesson, QuizQuestion)?> _pick() async {
    final examId = AuthService.instance.profile.value?.examId ?? '';
    if (examId.isEmpty) return null;
    final lessons = (await ContentRepo.instance.lessonsOfExam(examId))
        .where((l) => l.quiz.isNotEmpty)
        .toList();
    if (lessons.isEmpty) return null;
    // Graine basée sur le jour : le même défi pour tout le monde, toute la journée.
    final seed = StatsService.dayKey().hashCode;
    final li = seed.abs() % lessons.length;
    final lesson = lessons[li];
    final qi = (seed ~/ 7).abs() % lesson.quiz.length;
    return (lesson, lesson.quiz[qi]);
  }

  String get _id => StatsService.dayKey();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Lesson, QuizQuestion)?>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        if (!snap.hasData || data == null) return const SizedBox.shrink();
        final (lesson, q) = data;
        final done = EngagementService.instance.doneToday('challenge', _id);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: JangColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.bolt_rounded, color: JangColors.warning),
              const SizedBox(width: 6),
              Text('Défi du jour', style: titleStyle(17, weight: 800)),
              const Spacer(),
              Text(lesson.title, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ]),
            const SizedBox(height: 8),
            if (done && _chosen == null)
              const Text('Bravo, tu as déjà fait le défi d\'aujourd\'hui ! Reviens demain pour un nouveau.')
            else ...[
              Text(q.question, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (var i = 0; i < q.options.length; i++)
                if (q.options[i].trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: _chosen == null
                          ? Colors.white
                          : (i == q.answer
                              ? JangColors.successBg
                              : (i == _chosen ? JangColors.errorBg : Colors.white)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: JangColors.border),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _chosen != null
                            ? null
                            : () {
                                setState(() => _chosen = i);
                                EngagementService.instance.logStudy('challenge', _id);
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          child: Text(q.options[i]),
                        ),
                      ),
                    ),
                  ),
              if (_chosen != null)
                Text(
                  _chosen == q.answer ? 'Bravo, bonne réponse !' : 'Pas tout à fait. On réessaie demain !',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _chosen == q.answer ? JangColors.success : JangColors.primary),
                ),
            ],
          ]),
        );
      },
    );
  }
}
