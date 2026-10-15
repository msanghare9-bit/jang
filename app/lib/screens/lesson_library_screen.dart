import 'package:flutter/material.dart';

import '../models.dart';
import '../services/class_service.dart';
import '../services/content_repo.dart';
import '../services/lesson_pdf_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/jang_ui.dart';
import 'lesson_screen.dart';

/// Une ligne de résultat : soit une leçon officielle de Jàng (n'importe quel
/// niveau), soit un cours partagé par un professeur (toujours public).
class _Entry {
  final String title;
  final String levelName;
  final String subjectName;
  final String ownerLabel;
  final Color color;
  final Lesson? lesson;
  final Subject? subject;
  final ClassItem? item;
  const _Entry({
    required this.title,
    required this.levelName,
    required this.subjectName,
    required this.ownerLabel,
    required this.color,
    this.lesson,
    this.subject,
    this.item,
  });

  String get body => lesson?.body ?? item?.body ?? '';
}

/// Accès direct, depuis l'accueil du professeur, à TOUTES les leçons de
/// Jàng (n'importe quel niveau) et aux cours partagés entre professeurs —
/// avec recherche et filtres, et un téléchargement en PDF en un geste.
class LessonLibraryScreen extends StatefulWidget {
  const LessonLibraryScreen({super.key});

  @override
  State<LessonLibraryScreen> createState() => _LessonLibraryScreenState();
}

class _LessonLibraryScreenState extends State<LessonLibraryScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  List<_Entry> _all = const [];
  String _level = '';
  String _subject = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

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

  Future<void> _load() async {
    final repo = ContentRepo.instance;
    final entries = <_Entry>[];
    final exams = await repo.exams();
    // Pour retrouver le nom de la matière d'un cours partagé (qui ne
    // connaît que sa clé, ex. « anglais ») et le nom de son niveau.
    final subjectsByExam = <String, List<Subject>>{};
    final examNames = <String, String>{};
    for (final exam in exams) {
      examNames[exam.id] = exam.name;
      final subjects = await repo.subjects(exam.id);
      subjectsByExam[exam.id] = subjects;
      final lessons = await repo.lessonsOfExam(exam.id);
      for (final lesson in lessons) {
        final subject = subjects.where((s) => s.id == lesson.subjectId).firstOrNull;
        if (subject == null) continue;
        entries.add(_Entry(
          title: lesson.title.isEmpty ? 'Sans titre' : lesson.title,
          levelName: exam.name,
          subjectName: subject.name,
          ownerLabel: 'Jàng',
          color: JangColors.fromHex(subject.color),
          lesson: lesson,
          subject: subject,
        ));
      }
    }
    try {
      final shared = await ClassService.instance.sharedTeacherItems();
      for (final item in shared) {
        final subjects = subjectsByExam[item.examId] ?? const [];
        final subject = subjects.where((s) => subjectKey(s.name) == item.subject).firstOrNull;
        entries.add(_Entry(
          title: item.title.isEmpty ? 'Sans titre' : item.title,
          levelName: examNames[item.examId] ?? '',
          subjectName: subject?.name ?? item.subject,
          ownerLabel: item.ownerName.isEmpty ? 'Un professeur' : item.ownerName,
          color: subject == null ? JangColors.snGreen : JangColors.fromHex(subject.color),
          item: item,
        ));
      }
    } catch (_) {
      // Les cours partagés ne sont pas indispensables : on affiche au moins
      // les leçons officielles de Jàng si cette partie échoue.
    }
    if (!mounted) return;
    setState(() {
      _all = entries;
      _loading = false;
    });
  }

  List<_Entry> get _filtered {
    final q = _norm(_search.text.trim());
    return _all.where((e) {
      if (_level.isNotEmpty && e.levelName != _level) return false;
      if (_subject.isNotEmpty && e.subjectName != _subject) return false;
      if (q.length < 2) return true;
      return _norm(e.title).contains(q) || _norm(e.body).contains(q);
    }).toList();
  }

  Future<void> _download(_Entry e) async {
    try {
      if (e.lesson != null) {
        await LessonPdfService.shareLesson(e.lesson!, subjectName: e.subjectName, levelName: e.levelName);
      } else if (e.item != null) {
        await LessonPdfService.shareClassItem(e.item!, levelName: e.levelName);
      }
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible de préparer le PDF. Réessayez.');
    }
  }

  void _open(_Entry e) {
    if (e.lesson != null && e.subject != null) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => LessonScreen(lesson: e.lesson!, subject: e.subject!, preview: true)));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(e.title),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${e.levelName} · ${e.subjectName} · ${e.ownerLabel}'),
            const SizedBox(height: 12),
            if (e.body.isNotEmpty) Text(e.body),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _download(e);
            },
            icon: const Icon(Icons.download_outlined),
            label: const Text('Télécharger en PDF'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final levels = _all.map((e) => e.levelName).where((s) => s.isNotEmpty).toSet().toList()..sort();
    final subjects = _all
        .where((e) => _level.isEmpty || e.levelName == _level)
        .map((e) => e.subjectName)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final results = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('Télécharger une fiche de cours')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Chercher un cours (titre ou contenu)…',
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
                child: results.isEmpty
                    ? const Center(
                        child: EmptyState(
                          icon: Icons.search_off,
                          title: 'Aucun cours trouvé',
                          message: 'Essaie un autre mot, ou change le niveau ou la matière.',
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final e = results[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: e.color.withValues(alpha: 0.18),
                                child: Icon(
                                  e.lesson != null ? Icons.menu_book_outlined : Icons.groups_outlined,
                                  color: e.color,
                                ),
                              ),
                              title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text('${e.levelName} · ${e.subjectName} · ${e.ownerLabel}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  tooltip: 'Télécharger en PDF',
                                  onPressed: () => _download(e),
                                  icon: const Icon(Icons.download_outlined),
                                ),
                                const Icon(Icons.open_in_new),
                              ]),
                              onTap: () => _open(e),
                            ),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}
