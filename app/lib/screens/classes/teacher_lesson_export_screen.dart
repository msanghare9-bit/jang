import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/class_service.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Permet au professeur d'ajouter à sa classe une leçon déjà publiée dans Jàng.
class TeacherLessonExportScreen extends StatefulWidget {
  final ClassRoom classRoom;
  final UserProfile profile;
  const TeacherLessonExportScreen({super.key, required this.classRoom, required this.profile});

  @override
  State<TeacherLessonExportScreen> createState() => _TeacherLessonExportScreenState();
}

class _TeacherLessonExportScreenState extends State<TeacherLessonExportScreen> {
  late Future<List<Lesson>> _future = _load();
  final Set<String> _busy = {};

  Future<List<Lesson>> _load() async {
    final all = await ContentRepo.instance.lessonsOfExam(widget.classRoom.examId);
    final subjects = await ContentRepo.instance.subjects(widget.classRoom.examId);
    final matching = subjects.where((s) => subjectKey(s.name) == widget.classRoom.subject).map((s) => s.id).toSet();
    return all.where((l) => matching.contains(l.subjectId)).toList();
  }

  Future<void> _add(Lesson lesson) async {
    setState(() => _busy.add(lesson.id));
    try {
      await ClassService.instance.exportLesson(widget.classRoom, lesson, widget.profile);
      if (!mounted) return;
      showMessage(context, '« ${lesson.title} » a été ajouté à la classe.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showMessage(context, e.toString().replaceFirst('Exception: ', ''));
      setState(() => _busy.remove(lesson.id));
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Leçons officielles')),
        body: FutureBuilder<List<Lesson>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40),
                      const SizedBox(height: 12),
                      const Text('Impossible de charger les leçons.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => setState(() => _future = _load()),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final lessons = snap.data!;
            if (lessons.isEmpty) {
              return const EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'Aucune leçon disponible',
                message: 'Il n’y a pas encore de leçon publiée pour cette matière et ce niveau.',
              );
            }
            return FutureBuilder<List<ClassItem>>(
              future: ClassService.instance.itemsOf(widget.classRoom.id),
              builder: (context, itemsSnap) {
                if (!itemsSnap.hasData) return const Center(child: CircularProgressIndicator());
                final existing = itemsSnap.data!.map((item) => item.sourceLessonId).where((id) => id.isNotEmpty).toSet();
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('${widget.classRoom.subjectName} · ${widget.classRoom.name}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text('La copie sera visible uniquement par les élèves de cette classe.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    for (final lesson in lessons)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          leading: const CircleAvatar(
                            backgroundColor: JangColors.noteBg,
                            child: Icon(Icons.menu_book_outlined, color: JangColors.primaryDark),
                          ),
                          title: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              '${lesson.body.trim().isEmpty ? 'Sans texte' : lesson.body.trim().replaceAll(RegExp(r'\\s+'), ' ').substring(0, lesson.body.trim().length > 120 ? 120 : lesson.body.trim().length)}\n'
                              '${lesson.videos.length} vidéo(s) · ${lesson.quiz.length} exercice(s)',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: existing.contains(lesson.id)
                              ? const Icon(Icons.check_circle, color: JangColors.success)
                              : IconButton(
                                  tooltip: 'Ajouter à la classe',
                                  onPressed: _busy.contains(lesson.id) ? null : () => _add(lesson),
                                  icon: _busy.contains(lesson.id)
                                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.add_circle_outline),
                                ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      );
}
