import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'admin_widgets.dart';
import 'flashcard_editor.dart';
import 'lesson_editor.dart';
import 'moderation_screen.dart';
import 'stats_screen.dart';

/// Onglet « Gestion » du responsable : examens > matières > chapitres > leçons.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> with RepoListener<AdminHome> {
  List<Exam>? _exams;

  @override
  Future<void> load() async {
    final e = await ContentRepo.instance.exams();
    if (mounted) setState(() => _exams = e);
  }

  Future<void> _addExam() async {
    final name = await askText(context, 'Nouvel examen', 'Nom (ex. : Bac L)');
    if (name == null) return;
    final repo = ContentRepo.instance;
    final id = repo.newId('exams');
    repo.save('exams', id, Exam(id: id, name: name, order: _exams?.length ?? 0).toMap());
  }

  @override
  Widget build(BuildContext context) {
    final exams = _exams;
    return SafeArea(
      child: exams == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                Text('Gestion du contenu', style: titleStyle(26)),
                const SizedBox(height: 6),
                Text(
                    'Ce que tu enregistres ici est publié pour les élèves. Sans connexion, '
                    'l\'envoi se fait automatiquement dès le retour d\'internet.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const StatsScreen())),
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Statistiques d\'utilisation'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const ModerationScreen())),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Questions des élèves'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const TutorLogsScreen())),
                  icon: const Icon(Icons.psychology_alt_outlined),
                  label: const Text('Journal du tuteur IA'),
                ),
                const SectionTitle('Examens'),
                if (exams.isEmpty)
                  EmptyState(
                    icon: Icons.school_outlined,
                    title: 'Aucun examen',
                    message: 'Commence par créer le BFEM avec ses quatre matières.',
                    action: FilledButton(
                      onPressed: () => ContentRepo.instance.seedBfem(),
                      child: const Text('Créer le BFEM'),
                    ),
                  ),
                for (var i = 0; i < exams.length; i++)
                  AdminRow(
                    title: exams[i].name,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => AdminExamScreen(exam: exams[i]))),
                    onUp: i > 0 ? () => swapIn(context, 'exams', exams, i, i - 1) : null,
                    onDown: i < exams.length - 1
                        ? () => swapIn(context, 'exams', exams, i, i + 1)
                        : null,
                    onEdit: () async {
                      final n = await askText(context, 'Renommer l\'examen', 'Nom',
                          initial: exams[i].name);
                      if (n != null) ContentRepo.instance.save('exams', exams[i].id, {'name': n});
                    },
                    onDelete: () async {
                      if (await confirm(context, 'Supprimer ${exams[i].name} ?',
                          'L\'examen et tout son contenu ne seront plus visibles par les élèves.',
                          ok: 'Supprimer')) {
                        ContentRepo.instance.remove('exams', exams[i].id);
                      }
                    },
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: _addExam, icon: const Icon(Icons.add), label: const Text('Ajouter un examen')),
              ],
            ),
    );
  }
}

class AdminExamScreen extends StatefulWidget {
  final Exam exam;
  const AdminExamScreen({super.key, required this.exam});

  @override
  State<AdminExamScreen> createState() => _AdminExamScreenState();
}

class _AdminExamScreenState extends State<AdminExamScreen> with RepoListener<AdminExamScreen> {
  List<Subject>? _subjects;

  @override
  Future<void> load() async {
    final s = await ContentRepo.instance.subjects(widget.exam.id);
    if (mounted) setState(() => _subjects = s);
  }

  Future<void> _edit([Subject? s]) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => SubjectDialog(subject: s),
    );
    if (result == null) return;
    final repo = ContentRepo.instance;
    final id = s?.id ?? repo.newId('subjects');
    repo.save('subjects', id, {
      'examId': widget.exam.id,
      'name': result.$1,
      'color': result.$2,
      if (s == null) 'order': _subjects?.length ?? 0,
      if (s == null) 'deleted': false,
    });
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _subjects;
    return Scaffold(
      appBar: AppBar(title: Text(widget.exam.name)),
      body: subjects == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                const SectionTitle('Matières'),
                if (subjects.isEmpty)
                  Text('Aucune matière pour cet examen.', style: Theme.of(context).textTheme.bodySmall),
                for (var i = 0; i < subjects.length; i++)
                  AdminRow(
                    title: subjects[i].name,
                    color: JangColors.fromHex(subjects[i].color),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AdminSubjectScreen(subject: subjects[i]))),
                    onUp: i > 0 ? () => swapIn(context, 'subjects', subjects, i, i - 1) : null,
                    onDown: i < subjects.length - 1
                        ? () => swapIn(context, 'subjects', subjects, i, i + 1)
                        : null,
                    onEdit: () => _edit(subjects[i]),
                    onDelete: () async {
                      if (await confirm(context, 'Supprimer ${subjects[i].name} ?',
                          'La matière et ses leçons ne seront plus visibles par les élèves.',
                          ok: 'Supprimer')) {
                        ContentRepo.instance.remove('subjects', subjects[i].id);
                      }
                    },
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une matière')),
              ],
            ),
    );
  }
}

/// Échange l'ordre de deux éléments d'une liste triée (examens, matières, chapitres, leçons).
void swapIn(BuildContext context, String collection, List<dynamic> items, int a, int b) {
  final ia = items[a];
  final ib = items[b];
  // Si deux éléments ont le même ordre, on utilise leur position dans la liste.
  final oa = ia.order == ib.order ? a : ia.order as int;
  final ob = ia.order == ib.order ? b : ib.order as int;
  ContentRepo.instance.swapOrder(collection, ia.id as String, oa, ib.id as String, ob);
}

class AdminSubjectScreen extends StatefulWidget {
  final Subject subject;
  const AdminSubjectScreen({super.key, required this.subject});

  @override
  State<AdminSubjectScreen> createState() => _AdminSubjectScreenState();
}

class _AdminSubjectScreenState extends State<AdminSubjectScreen>
    with RepoListener<AdminSubjectScreen> {
  List<Chapter>? _chapters;
  List<Lesson> _lessons = const [];

  @override
  Future<void> load() async {
    final repo = ContentRepo.instance;
    final c = await repo.chapters(widget.subject.id);
    final l = await repo.lessonsOfSubject(widget.subject.id);
    if (mounted) {
      setState(() {
        _chapters = c;
        _lessons = l;
      });
    }
  }

  Future<void> _editChapter([Chapter? c]) async {
    final title = await askText(context, c == null ? 'Nouveau chapitre' : 'Renommer le chapitre',
        'Titre du chapitre',
        initial: c?.title);
    if (title == null) return;
    final repo = ContentRepo.instance;
    final id = c?.id ?? repo.newId('chapters');
    repo.save('chapters', id, {
      'examId': widget.subject.examId,
      'subjectId': widget.subject.id,
      'title': title,
      if (c == null) 'order': _chapters?.length ?? 0,
      if (c == null) 'deleted': false,
    });
  }

  void _openLesson(Chapter chapter, Lesson? lesson, int nextOrder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LessonEditor(
          subject: widget.subject,
          chapter: chapter,
          lesson: lesson,
          nextOrder: nextOrder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapters = _chapters;
    final color = JangColors.fromHex(widget.subject.color);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name, style: titleStyle(20, color: Colors.white)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: chapters == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                if (chapters.isEmpty)
                  const EmptyState(
                      icon: Icons.list_alt,
                      title: 'Aucun chapitre',
                      message: 'Crée un premier chapitre, puis ajoute-lui des leçons.'),
                for (var i = 0; i < chapters.length; i++) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                          child: Text('${i + 1}. ${chapters[i].title}',
                              style: titleStyle(19, color: color))),
                      PopupMenuButton<String>(
                        tooltip: 'Options du chapitre',
                        onSelected: (v) async {
                          if (v == 'edit') _editChapter(chapters[i]);
                          if (v == 'up' && i > 0) swapIn(context, 'chapters', chapters, i, i - 1);
                          if (v == 'down' && i < chapters.length - 1) {
                            swapIn(context, 'chapters', chapters, i, i + 1);
                          }
                          if (v == 'delete' &&
                              await confirm(context, 'Supprimer ce chapitre ?',
                                  'Ses leçons ne seront plus visibles par les élèves.',
                                  ok: 'Supprimer')) {
                            ContentRepo.instance.remove('chapters', chapters[i].id);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Renommer')),
                          if (i > 0) const PopupMenuItem(value: 'up', child: Text('Monter')),
                          if (i < chapters.length - 1)
                            const PopupMenuItem(value: 'down', child: Text('Descendre')),
                          const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                        ],
                      ),
                    ],
                  ),
                  ..._lessonRows(chapters[i]),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              FlashcardEditor(subject: widget.subject, chapter: chapters[i])),
                    ),
                    icon: const Icon(Icons.style_outlined),
                    label: const Text('Flashcards du chapitre'),
                  ),
                  TextButton.icon(
                    onPressed: () => _openLesson(chapters[i], null,
                        _lessons.where((l) => l.chapterId == chapters[i].id).length),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une leçon'),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => _editChapter(),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un chapitre'),
                ),
              ],
            ),
    );
  }

  List<Widget> _lessonRows(Chapter chapter) {
    final lessons = _lessons.where((l) => l.chapterId == chapter.id).toList();
    return [
      for (var j = 0; j < lessons.length; j++)
        AdminRow(
          title: lessons[j].title,
          subtitle:
              '${lessons[j].videos.length} vidéo(s) · ${lessons[j].quiz.length} question(s) de QCM',
          onTap: () => _openLesson(chapter, lessons[j], j),
          onUp: j > 0 ? () => swapIn(context, 'lessons', lessons, j, j - 1) : null,
          onDown: j < lessons.length - 1 ? () => swapIn(context, 'lessons', lessons, j, j + 1) : null,
          onDelete: () async {
            if (await confirm(context, 'Supprimer « ${lessons[j].title} » ?',
                'Les élèves ne verront plus cette leçon.',
                ok: 'Supprimer')) {
              ContentRepo.instance.remove('lessons', lessons[j].id);
            }
          },
        ),
    ];
  }
}
