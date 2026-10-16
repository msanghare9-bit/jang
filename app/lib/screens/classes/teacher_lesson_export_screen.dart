import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/class_service.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Une leçon officielle de Jàng, avec son niveau et sa matière déjà résolus.
class _Entry {
  final Lesson lesson;
  final String levelName;
  final String subjectName;
  final Color color;
  const _Entry({
    required this.lesson,
    required this.levelName,
    required this.subjectName,
    required this.color,
  });
}

/// Permet au professeur d'ajouter à sa classe une leçon déjà publiée dans
/// Jàng — n'importe quel niveau, n'importe quelle matière, pas seulement
/// ceux de la classe : le professeur choisit librement avec la recherche et
/// les filtres.
class TeacherLessonExportScreen extends StatefulWidget {
  final ClassRoom classRoom;
  final UserProfile profile;
  const TeacherLessonExportScreen({super.key, required this.classRoom, required this.profile});

  @override
  State<TeacherLessonExportScreen> createState() => _TeacherLessonExportScreenState();
}

class _TeacherLessonExportScreenState extends State<TeacherLessonExportScreen> {
  final _search = TextEditingController();
  late Future<(List<_Entry>, Set<String>)> _future = _load();
  final Set<String> _busy = {};
  String _level = '';
  String _subject = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâ]'), 'a')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('î', 'i')
      .replaceAll('ç', 'c');

  /// Toutes les leçons officielles, tous niveaux et toutes matières, et les
  /// leçons déjà copiées dans cette classe.
  Future<(List<_Entry>, Set<String>)> _load() async {
    final repo = ContentRepo.instance;
    final entries = <_Entry>[];
    for (final exam in await repo.exams()) {
      final subjects = await repo.subjects(exam.id);
      final subjectById = {for (final s in subjects) s.id: s};
      final lessons = await repo.lessonsOfExam(exam.id);
      for (final lesson in lessons) {
        if (lesson.deleted || !lesson.visibleIn(exam.id)) continue;
        final subject = subjectById[lesson.subjectId];
        entries.add(_Entry(
          lesson: lesson,
          levelName: exam.name,
          subjectName: subject?.name ?? '',
          color: subject == null ? JangColors.snGreen : JangColors.fromHex(subject.color),
        ));
      }
    }
    var existing = <String>{};
    try {
      final items = await ClassService.instance.itemsOf(widget.classRoom.id);
      existing = items.map((item) => item.sourceLessonId).where((id) => id.isNotEmpty).toSet();
    } catch (_) {
      // Hors ligne : on affiche quand même les leçons.
    }
    return (entries, existing);
  }

  static String _preview(String body) {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return 'Sans texte';
    return text.length > 120 ? text.substring(0, 120) : text;
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
      setState(() {
        _busy.remove(lesson.id);
        _future = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter une leçon officielle')),
      body: FutureBuilder<(List<_Entry>, Set<String>)>(
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
          final (all, existing) = snap.data!;
          final levels = all.map((e) => e.levelName).where((s) => s.isNotEmpty).toSet().toList()..sort();
          final subjects = all
              .where((e) => _level.isEmpty || e.levelName == _level)
              .map((e) => e.subjectName)
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final q = _norm(_search.text.trim());
          final entries = all.where((e) {
            if (_level.isNotEmpty && e.levelName != _level) return false;
            if (_subject.isNotEmpty && e.subjectName != _subject) return false;
            if (q.length < 2) return true;
            return _norm(e.lesson.title).contains(q) || _norm(e.lesson.body).contains(q);
          }).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(children: [
                Text('Ajoute dans « ${widget.classRoom.name} » une leçon de n’importe quel niveau ou matière.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Chercher une leçon (titre ou contenu)…',
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _level.isEmpty ? null : _level,
                      decoration: const InputDecoration(labelText: 'Niveau'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Tous les niveaux')),
                        for (final l in levels) DropdownMenuItem(value: l, child: Text(l)),
                      ],
                      onChanged: (v) => setState(() {
                        _level = v ?? '';
                        _subject = '';
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _subject.isEmpty ? null : _subject,
                      decoration: const InputDecoration(labelText: 'Matière'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Toutes les matières')),
                        for (final s in subjects) DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: (v) => setState(() => _subject = v ?? ''),
                    ),
                  ),
                ]),
              ]),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: EmptyState(
                        icon: Icons.search_off,
                        title: 'Aucune leçon trouvée',
                        message: 'Essaie un autre mot, ou change le niveau ou la matière.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final lesson = e.lesson;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: e.color.withValues(alpha: 0.18),
                              child: Icon(Icons.menu_book_outlined, color: e.color),
                            ),
                            title: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                '${e.levelName} · ${e.subjectName}\n'
                                '${_preview(lesson.body)}\n'
                                '${lesson.videos.length} vidéo(s) · ${lesson.quiz.length} exercice(s)',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            isThreeLine: true,
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
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}
