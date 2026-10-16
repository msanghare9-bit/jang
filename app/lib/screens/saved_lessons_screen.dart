import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../services/saved_lessons_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/jang_ui.dart';
import 'lesson_screen.dart';

class _Entry {
  final Lesson lesson;
  final Subject subject;
  final String levelName;
  const _Entry(this.lesson, this.subject, this.levelName);
}

/// Espace personnel de l'élève : les leçons qu'il a choisi de garder pour
/// les relire, de n'importe quel niveau.
class SavedLessonsScreen extends StatefulWidget {
  const SavedLessonsScreen({super.key});

  @override
  State<SavedLessonsScreen> createState() => _SavedLessonsScreenState();
}

class _SavedLessonsScreenState extends State<SavedLessonsScreen> {
  late Future<List<_Entry>> _future = _load();

  Future<List<_Entry>> _load() async {
    final repo = ContentRepo.instance;
    final ids = await SavedLessonsService.instance.ids();
    final out = <_Entry>[];
    final examNames = <String, String>{};
    final subjectsByExam = <String, List<Subject>>{};
    for (final id in ids) {
      final lesson = await repo.lesson(id);
      if (lesson == null) {
        // Leçon supprimée depuis : on la retire discrètement de l'espace.
        await SavedLessonsService.instance.remove(id);
        continue;
      }
      examNames[lesson.examId] ??= (await repo.exam(lesson.examId))?.name ?? '';
      subjectsByExam[lesson.examId] ??= await repo.subjects(lesson.examId);
      final subject = subjectsByExam[lesson.examId]!.where((s) => s.id == lesson.subjectId).firstOrNull;
      if (subject == null) continue;
      out.add(_Entry(lesson, subject, examNames[lesson.examId] ?? ''));
    }
    return out;
  }

  Future<void> _removeAt(_Entry e) async {
    await SavedLessonsService.instance.remove(e.lesson.id);
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final myExamId = AuthService.instance.profile.value?.examId ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Mes leçons gardées')),
      body: FutureBuilder<List<_Entry>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final entries = snap.data!;
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: EmptyState(
                  icon: Icons.bookmark_border,
                  title: 'Tu n\'as gardé aucune leçon',
                  message:
                      'Ouvre une leçon, appuie sur l\'icône 🔖 en haut, et elle apparaît ici. '
                      'Tu peux la retrouver quand tu veux, même si elle n\'est pas de ta classe.',
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: entries.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(4, 12, 4, 10),
                  child: Text(
                    'Les leçons que tu as gardées pour les relire, de n\'importe quelle classe.',
                    style: TextStyle(fontWeight: FontWeight.w600, color: JangColors.textSecondary),
                  ),
                );
              }
              final e = entries[i - 1];
              final color = JangColors.fromHex(e.subject.color);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.2),
                    child: Text(subjectEmoji(e.subject.name), style: const TextStyle(fontSize: 18)),
                  ),
                  title: Text(e.lesson.title.isEmpty ? 'Sans titre' : e.lesson.title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${e.levelName} · ${e.subject.name}'),
                  trailing: IconButton(
                    tooltip: 'Enlever cette leçon',
                    icon: const Icon(Icons.bookmark_remove_outlined),
                    onPressed: () => _removeAt(e),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LessonScreen(
                        lesson: e.lesson,
                        subject: e.subject,
                        preview: e.lesson.examId != myExamId,
                      ),
                    ),
                  ).then((_) => setState(() => _future = _load())),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
