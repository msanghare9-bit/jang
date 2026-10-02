import 'package:flutter/material.dart';

import '../services/engagement_service.dart';
import '../services/github_service.dart';
import '../services/progress_repo.dart';
import '../services/stats_service.dart';
import '../screens/review_screen.dart';
import '../theme.dart';
import 'common.dart';

/// Message de partage de l'application.
String get shareText =>
    'J\'apprends avec l\'application Jàng : leçons, vidéos et QCM corrigés, même sans internet. '
    'Télécharge-la ici : ${GithubService.shareUrl}';

/// Ouvre WhatsApp ou les SMS avec le message de partage.
Future<void> shareApp(BuildContext context) async {
  final text = Uri.encodeComponent(shareText);
  await showModalBottomSheet<void>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text('Partager Jàng', style: titleStyle(20)),
          ),
          ListTile(
            minVerticalPadding: 14,
            leading: const Icon(Icons.chat_outlined, color: JangColors.primary),
            title: const Text('Par WhatsApp'),
            onTap: () {
              Navigator.pop(c);
              openLink('https://wa.me/?text=$text');
            },
          ),
          ListTile(
            minVerticalPadding: 14,
            leading: const Icon(Icons.sms_outlined, color: JangColors.primary),
            title: const Text('Par SMS'),
            onTap: () {
              Navigator.pop(c);
              openLink('sms:?body=$text');
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

/// Carte « Objectif de la semaine ».
class WeekGoalCard extends StatelessWidget {
  const WeekGoalCard({super.key});

  @override
  Widget build(BuildContext context) {
    final e = EngagementService.instance;
    final t = Theme.of(context).textTheme;
    return ValueListenableBuilder(
      valueListenable: e.revision,
      builder: (context, _, __) {
        final target = e.goalTarget;
        final type = e.goalType;
        final count = e.weekCount(type);
        final what = type == 'quiz' ? 'QCM' : 'leçon${target > 1 ? 's' : ''}';
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.track_changes, color: JangColors.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Objectif de la semaine', style: t.titleMedium)),
                  TextButton(
                    onPressed: () => showGoalDialog(context),
                    child: Text(target == 0 ? 'Choisir' : 'Modifier'),
                  ),
                ]),
                const SizedBox(height: 6),
                if (target == 0)
                  Text('Fixe-toi un objectif pour avancer chaque semaine.', style: t.bodyMedium)
                else ...[
                  Text(
                    count >= target
                        ? 'Bravo, objectif atteint : $count / $target $what.'
                        : '$count / $target $what cette semaine.',
                    style: t.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ProgressBar(value: count / target, color: JangColors.primary),
                  ),
                ],
                if (e.streak >= 2) ...[
                  const SizedBox(height: 8),
                  Text('Tu révises depuis ${e.streak} jours de suite.', style: t.bodySmall),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> showGoalDialog(BuildContext context) async {
  final e = EngagementService.instance;
  var type = e.goalType;
  var target = e.goalTarget == 0 ? 5 : e.goalTarget;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text('Mon objectif', style: titleStyle(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chaque semaine, je veux faire :'),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'lesson', label: Text('Leçons')),
                ButtonSegment(value: 'quiz', label: Text('QCM')),
              ],
              selected: {type},
              onSelectionChanged: (s) => set(() => type = s.first),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  tooltip: 'Moins',
                  onPressed: target > 1 ? () => set(() => target--) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 64,
                  child: Text('$target',
                      textAlign: TextAlign.center, style: titleStyle(28, color: JangColors.primary)),
                ),
                IconButton.outlined(
                  tooltip: 'Plus',
                  onPressed: target < 30 ? () => set(() => target++) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (e.goalTarget > 0)
            TextButton(
              onPressed: () {
                e.setGoal(type, 0);
                Navigator.pop(c, false);
              },
              child: const Text('Supprimer'),
            ),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Valider')),
        ],
      ),
    ),
  );
  if (ok == true) await e.setGoal(type, target);
}

/// « Ta plante » : elle grandit quand l'élève apprend chaque jour.
class PlantCard extends StatelessWidget {
  const PlantCard({super.key});

  @override
  Widget build(BuildContext context) {
    final e = EngagementService.instance;
    final t = Theme.of(context).textTheme;
    return ValueListenableBuilder(
      valueListenable: e.revision,
      builder: (context, _, __) {
        final s = e.streak;
        final days = e.daySet;
        final plant = s == 0 ? '🌰' : (s < 3 ? '🌱' : (s < 7 ? '🌿' : '🌳'));
        final title = s == 0
            ? 'Plante ta graine'
            : (s == 1 ? 'Ta plante a 1 jour' : 'Ta plante a $s jours');
        final now = DateTime.now();
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              Text(plant, style: const TextStyle(fontSize: 40)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: titleStyle(19, weight: 800)),
                  Text(s == 0 ? 'Apprends une leçon aujourd\'hui pour la faire pousser.'
                      : 'Apprends chaque jour pour l\'arroser.', style: t.bodySmall),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (var i = 6; i >= 0; i--)
                      Expanded(
                        child: Container(
                          height: 9,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: days.contains(StatsService.dayKey(now.subtract(Duration(days: i))))
                                ? JangColors.success
                                : JangColors.border,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                  ]),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Carte « Corriger mes erreurs », visible s'il y a des erreurs à revoir.
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ProgressRepo.instance.revision,
      builder: (context, _, __) {
        final n = ProgressRepo.instance.mistakesCount;
        if (n == 0) return const SizedBox.shrink();
        return Card(
          color: JangColors.errorBg,
          child: ListTile(
            minVerticalPadding: 14,
            leading: const Icon(Icons.replay, color: JangColors.error),
            title: Text('Corriger mes erreurs', style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text('$n question${n > 1 ? 's' : ''} à revoir'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ReviewScreen())),
          ),
        );
      },
    );
  }
}

/// Grille des badges (gagnés en couleur, les autres en gris).
class BadgeGrid extends StatelessWidget {
  const BadgeGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final e = EngagementService.instance;
    final t = Theme.of(context).textTheme;
    return ValueListenableBuilder(
      valueListenable: e.revision,
      builder: (context, _, __) {
        final earned = e.earnedIds;
        return LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth > 500 ? 4 : 3;
          final w = (box.maxWidth - (cols - 1) * 8) / cols;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in badgeDefs)
                SizedBox(
                  width: w,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => showMessage(
                        context,
                        earned.contains(b.id)
                            ? '${b.title} : ${b.description}. Gagné !'
                            : '${b.title} : ${b.description}.'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                      decoration: BoxDecoration(
                        color: earned.contains(b.id) ? JangColors.noteBg : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: earned.contains(b.id) ? JangColors.primary : JangColors.border),
                      ),
                      child: Column(children: [
                        Icon(b.icon,
                            size: 30,
                            color: earned.contains(b.id)
                                ? JangColors.primary
                                : JangColors.textSecondary.withValues(alpha: 0.4)),
                        const SizedBox(height: 6),
                        Text(b.title,
                            textAlign: TextAlign.center,
                            style: t.bodySmall!.copyWith(
                                fontWeight: FontWeight.w700,
                                color: earned.contains(b.id)
                                    ? JangColors.text
                                    : JangColors.textSecondary)),
                      ]),
                    ),
                  ),
                ),
            ],
          );
        });
      },
    );
  }
}

/// Affiche une félicitation quand un badge est gagné.
void showBadgeDialog(BuildContext context, BadgeDef b) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(b.icon, size: 48, color: JangColors.primary),
      title: Text('Félicitations, nouveau badge !', style: titleStyle(20), textAlign: TextAlign.center),
      content: Text('${b.title}\n${b.description}.\nTu peux être fier de toi, continue !', textAlign: TextAlign.center),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Super')),
      ],
    ),
  );
}
