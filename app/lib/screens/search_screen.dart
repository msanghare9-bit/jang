import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/jang_ui.dart';
import 'lesson_screen.dart';

/// Recherche par mot-clé dans toutes les leçons de Jàng (titre et contenu),
/// n'importe quel niveau — avec un filtre pour choisir un niveau précis.
/// L'élève peut ainsi aussi consulter les cours d'un autre niveau que le
/// sien, pas seulement chercher dans les siens.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _Result {
  final Lesson lesson;
  final Subject subject;
  final String levelName;
  final String snippet;
  _Result(this.lesson, this.subject, this.levelName, this.snippet);
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctl = TextEditingController();
  List<Exam> _exams = const [];
  List<Subject> _subjects = const [];
  List<Lesson> _lessons = const [];
  Map<String, String> _examNameOf = const {};
  List<_Result> _results = const [];
  String _level = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Charge les matières et les leçons de TOUS les niveaux, pas seulement
  /// celui de l'élève, pour qu'il puisse chercher ou parcourir n'importe
  /// quel niveau.
  Future<void> _load() async {
    final repo = ContentRepo.instance;
    final exams = await repo.exams();
    final subjects = <Subject>[];
    final lessons = <Lesson>[];
    final examNameOf = <String, String>{};
    for (final exam in exams) {
      examNameOf[exam.id] = exam.name;
      subjects.addAll(await repo.subjects(exam.id));
      lessons.addAll(await repo.lessonsOfExam(exam.id));
    }
    if (!mounted) return;
    setState(() {
      _exams = exams;
      _subjects = subjects;
      _lessons = lessons;
      _examNameOf = examNameOf;
      _level = AuthService.instance.profile.value?.examId ?? '';
      _loading = false;
    });
    _search(_ctl.text);
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâ]'), 'a')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('î', 'i')
      .replaceAll('ç', 'c');

  void _search(String query) {
    final q = _norm(query.trim());
    // Sans mot tapé, on ne liste les leçons que si un niveau précis est
    // choisi (sinon il y en aurait bien trop) : ça permet de PARCOURIR les
    // leçons d'un autre niveau, pas seulement de les chercher par mot.
    if (q.length < 2 && _level.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    final out = <_Result>[];
    for (final l in _lessons) {
      if (_level.isNotEmpty && l.examId != _level) continue;
      final subject = _subjects.where((s) => s.id == l.subjectId).firstOrNull;
      if (subject == null) continue;
      if (q.length < 2) {
        // Mode « parcourir » : toutes les leçons du niveau choisi.
        out.add(_Result(l, subject, _examNameOf[l.examId] ?? '', _preview(l.body)));
        continue;
      }
      final title = _norm(l.title);
      final body = _norm(l.body);
      if (title.contains(q)) {
        out.add(_Result(l, subject, _examNameOf[l.examId] ?? '', l.title));
      } else if (body.contains(q)) {
        final i = body.indexOf(q);
        final start = (i - 40).clamp(0, body.length);
        final end = (i + q.length + 60).clamp(0, l.body.length);
        var snippet = l.body.substring(start.clamp(0, l.body.length), end);
        snippet = snippet.replaceAll(RegExp(r'[#>*_\[\]]'), '').trim();
        out.add(_Result(l, subject, _examNameOf[l.examId] ?? '', '… $snippet …'));
      }
    }
    if (q.length < 2) {
      out.sort((a, b) => a.subject.name == b.subject.name
          ? a.lesson.title.compareTo(b.lesson.title)
          : a.subject.name.compareTo(b.subject.name));
    }
    setState(() => _results = out.take(q.length < 2 ? 200 : 40).toList());
  }

  static String _preview(String body) {
    final text = body.trim().replaceAll(RegExp(r'[#>*_\[\]]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return 'Sans texte';
    return text.length > 90 ? '${text.substring(0, 90)}…' : text;
  }

  @override
  Widget build(BuildContext context) {
    final myExamId = AuthService.instance.profile.value?.examId ?? '';
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          onChanged: _search,
          decoration: const InputDecoration(
            hintText: 'Chercher un cours, n’importe quel niveau…',
            border: InputBorder.none,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: DropdownButtonFormField<String>(
                  value: _level.isEmpty ? null : _level,
                  decoration: const InputDecoration(labelText: 'Niveau'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Tous les niveaux')),
                    for (final e in _exams) DropdownMenuItem(value: e.id, child: Text(e.name)),
                  ],
                  onChanged: (v) {
                    setState(() => _level = v ?? '');
                    _search(_ctl.text);
                  },
                ),
              ),
              Expanded(
                child: _ctl.text.trim().length < 2 && _level.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'Tape au moins 2 lettres pour chercher un cours, ou choisis un niveau '
                              'ci-dessus pour voir tous ses cours.',
                              textAlign: TextAlign.center),
                        ),
                      )
                    : _results.isEmpty
                        ? const Center(
                            child: EmptyState(
                              icon: Icons.search_off,
                              title: 'Aucun résultat',
                              message: 'Essaie un autre mot, ou change le niveau.',
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final r = _results[i];
                              final color = JangColors.fromHex(r.subject.color);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: color.withValues(alpha: 0.2),
                                    child: Text(subjectEmoji(r.subject.name), style: const TextStyle(fontSize: 18)),
                                  ),
                                  title: Text(r.lesson.title.isEmpty ? 'Sans titre' : r.lesson.title,
                                      style: const TextStyle(fontWeight: FontWeight.w800)),
                                  subtitle: Text('${r.levelName} · ${r.subject.name} · ${r.snippet}',
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      // Aperçu seulement pour un autre niveau que le sien : rien n'est
                                      // enregistré dans sa progression, qui reste celle de son niveau.
                                      builder: (_) => LessonScreen(
                                        lesson: r.lesson,
                                        subject: r.subject,
                                        preview: r.lesson.examId != myExamId,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ]),
    );
  }
}
