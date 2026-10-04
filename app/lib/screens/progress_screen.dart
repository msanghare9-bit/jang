import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../services/progress_repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/engagement.dart';
import '../widgets/fun.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late Future<(List<Subject>, List<Lesson>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    ContentRepo.instance.revision.addListener(_reload);
    AuthService.instance.profile.addListener(_reload);
  }

  @override
  void dispose() {
    ContentRepo.instance.revision.removeListener(_reload);
    AuthService.instance.profile.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<(List<Subject>, List<Lesson>)> _load() async {
    final examId = AuthService.instance.profile.value?.examId ?? '';
    final repo = ContentRepo.instance;
    return (await repo.subjects(examId), await repo.lessonsOfExam(examId));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<(List<Subject>, List<Lesson>)>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (subjects, lessons) = snap.data!;
          return ValueListenableBuilder(
            valueListenable: ProgressRepo.instance.revision,
            builder: (context, _, __) {
              final progress = ProgressRepo.instance;
              final allDone = lessons.where((l) => progress.of(l.id)?.quizDone == true).toList();
              final avg = _average(allDone.map((l) => progress.of(l.id)!).toList());
              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  Text('Ma progression', style: titleStyle(26)),
                  CharacterSays(
                    'doudou',
                    allDone.isEmpty
                        ? 'Je suis Doudou, le griot. Je chanterai tes exploits… dès que tu auras fait tes premiers exercices 🥁'
                        : (avg ?? 0) >= 80
                            ? 'Gathié ngalama ! ${allDone.length} exercice${allDone.length > 1 ? 's' : ''} et $avg % de moyenne : je compose une chanson sur toi 🥁'
                            : 'Tu as déjà fait ${allDone.length} exercice${allDone.length > 1 ? 's' : ''}. Boul bayi ! Vise 80 % et mon tama résonnera 🥁',
                    right: true,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                          child: _Stat(
                              value: '${lessons.where((l) => progress.of(l.id)?.seen == true).length}',
                              label: 'leçons ouvertes')),
                      const SizedBox(width: 10),
                      Expanded(child: _Stat(value: '${allDone.length}', label: 'Exercices faits')),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _Stat(value: avg == null ? '–' : '$avg %', label: 'moyenne exercices')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const ReviewCard(),
                  const WeekGoalCard(),
                  const SectionTitle('Mes badges'),
                  const BadgeGrid(),
                  const SectionTitle('Par matière'),
                  if (subjects.isEmpty)
                    const EmptyState(
                        icon: Icons.insights_outlined,
                        title: 'Rien pour le moment',
                        message: 'Ta progression apparaîtra ici dès que tu auras fait des leçons.'),
                  for (final s in subjects) _subjectRow(context, s, lessons),
                ],
              );
            },
          );
        },
      ),
    );
  }

  int? _average(List<LessonProgress> ps) {
    final valid = ps.where((p) => p.total > 0 && p.bestScore != null).toList();
    if (valid.isEmpty) return null;
    final sum = valid.fold<double>(0, (a, p) => a + p.bestScore! / p.total);
    return (sum / valid.length * 100).round();
  }

  Widget _subjectRow(BuildContext context, Subject s, List<Lesson> all) {
    final color = JangColors.fromHex(s.color);
    final lessons = all.where((l) => l.subjectId == s.id).toList();
    final progress = ProgressRepo.instance;
    final done = lessons.where((l) => progress.of(l.id)?.quizDone == true).toList();
    final avg = _average(done.map((l) => progress.of(l.id)!).toList());
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(s.name, style: titleStyle(19, color: color))),
                  if (avg != null) Text('$avg %', style: titleStyle(19, color: color)),
                ],
              ),
              const SizedBox(height: 6),
              Text('${done.length} / ${lessons.length} exercices faits',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              ProgressBar(value: lessons.isEmpty ? 0 : done.length / lessons.length, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          children: [
            Text(value, style: titleStyle(26, color: JangColors.primary)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
