import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'admin_widgets.dart';
import 'lesson_editor.dart';
import 'moderation_screen.dart';
import 'stats_screen.dart';

/// Onglet « Gestion » du responsable : niveaux > matières > leçons.
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
    final name = await askText(context, 'Nouveau niveau', 'Nom (ex. : 3e, Terminale, Anglais débutant)');
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
                  label: const Text('Questions posées à Jàngalekat'),
                ),
                const SectionTitle('Niveaux'),
                if (exams.isEmpty)
                  EmptyState(
                    icon: Icons.school_outlined,
                    title: 'Aucun niveau',
                    message: 'Commence par créer un niveau avec quatre matières (français, maths, anglais, SVT).',
                    action: FilledButton(
                      onPressed: () async {
                        final n = await askText(context, 'Premier niveau', 'Nom (ex. : 3e)');
                        if (n != null) ContentRepo.instance.seedFirstLevel(n);
                      },
                      child: const Text('Créer un niveau'),
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
                      final n = await askText(context, 'Renommer le niveau', 'Nom',
                          initial: exams[i].name);
                      if (n != null) ContentRepo.instance.save('exams', exams[i].id, {'name': n});
                    },
                    onDelete: () async {
                      if (await confirm(context, 'Supprimer ${exams[i].name} ?',
                          'Le niveau et tout son contenu ne seront plus visibles par les élèves.',
                          ok: 'Supprimer')) {
                        ContentRepo.instance.remove('exams', exams[i].id);
                      }
                    },
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: _addExam, icon: const Icon(Icons.add), label: const Text('Ajouter un niveau')),
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
                  Text('Aucune matière pour ce niveau.', style: Theme.of(context).textTheme.bodySmall),
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

/// Échange l'ordre de deux éléments d'une liste triée (niveaux, matières, chapitres, leçons).
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
  List<Lesson>? _lessons;
  Map<String, FlashcardDeck> _decks = const {};
  bool _migrated = false;

  @override
  Future<void> load() async {
    final repo = ContentRepo.instance;
    if (!_migrated) {
      _migrated = true;
      // Les anciennes leçons rangées par chapitres deviennent une simple liste.
      if (await repo.migrateSubject(widget.subject)) return; // load() sera rappelé
    }
    final l = await repo.lessonsOfSubject(widget.subject.id);
    final d = await repo.decksOfSubject(widget.subject.id);
    if (mounted) {
      setState(() {
        _lessons = l;
        _decks = d;
      });
    }
  }

  void _openLesson(Lesson? lesson) {
    final lessons = _lessons ?? const <Lesson>[];
    final next = lessons.isEmpty ? 0 : lessons.map((l) => l.order).reduce((a, b) => a > b ? a : b) + 1;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LessonEditor(subject: widget.subject, lesson: lesson, nextOrder: next),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lessons = _lessons;
    final color = JangColors.fromHex(widget.subject.color);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name, style: titleStyle(20, color: Colors.white)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: lessons == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                Text('${lessons.length} leçon${lessons.length > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                if (lessons.isEmpty)
                  const EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: 'Aucune leçon',
                      message: 'Ajoute une première leçon avec le bouton ci-dessous.'),
                for (var i = 0; i < lessons.length; i++) _row(lessons, i, color),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _openLesson(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une leçon'),
                ),
                const SizedBox(height: 10),
                Text('Le menu ⋮ de chaque leçon : Modifier, Monter, Descendre, Supprimer.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
    );
  }

  Widget _row(List<Lesson> lessons, int i, Color color) {
    final l = lessons[i];
    final deck = _decks[l.id];
    final tags = <(String, bool)>[
      l.videos.isEmpty
          ? ('Pas de vidéo', false)
          : ('${l.videos.length} vidéo${l.videos.length > 1 ? 's' : ''}', true),
      l.body.trim().isEmpty ? ('Pas de texte', false) : ('Leçon', true),
      l.quiz.isEmpty ? ('Pas de QCM', false) : ('QCM ${l.quiz.length}', true),
      deck == null ? ('Pas de révision', false) : ('Révision ${deck.cards.length}', true),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openLesson(l),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: Text('${i + 1}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.title.isEmpty ? 'Sans titre' : l.title,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final t in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: t.$2 ? JangColors.noteBg : const Color(0xFFEEF1EE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(t.$1,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: t.$2 ? JangColors.primary : JangColors.textSecondary)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Options de la leçon',
                onSelected: (v) async {
                  if (v == 'edit') _openLesson(l);
                  if (v == 'up' && i > 0) swapIn(context, 'lessons', lessons, i, i - 1);
                  if (v == 'down' && i < lessons.length - 1) {
                    swapIn(context, 'lessons', lessons, i, i + 1);
                  }
                  if (v == 'delete' &&
                      await confirm(context, 'Supprimer « ${l.title} » ?',
                          'Les élèves ne verront plus cette leçon.',
                          ok: 'Supprimer')) {
                    ContentRepo.instance.remove('lessons', l.id);
                    if (deck != null) ContentRepo.instance.remove('flashcards', l.id);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                  if (i > 0) const PopupMenuItem(value: 'up', child: Text('Monter')),
                  if (i < lessons.length - 1)
                    const PopupMenuItem(value: 'down', child: Text('Descendre')),
                  const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
