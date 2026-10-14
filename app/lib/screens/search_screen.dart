import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/jang_ui.dart';
import 'lesson_screen.dart';

/// Recherche par mot-clé dans toutes les leçons du niveau de l'élève (titre et contenu).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _Result {
  final Lesson lesson;
  final Subject subject;
  final String snippet;
  _Result(this.lesson, this.subject, this.snippet);
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctl = TextEditingController();
  List<Subject> _subjects = const [];
  List<Lesson> _lessons = const [];
  List<_Result> _results = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final examId = AuthService.instance.profile.value?.examId ?? '';
    if (examId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final repo = ContentRepo.instance;
    final subjects = await repo.subjects(examId);
    final lessons = await repo.lessonsOfExam(examId);
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _lessons = lessons;
      _loading = false;
    });
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
    if (q.length < 2) {
      setState(() => _results = const []);
      return;
    }
    final out = <_Result>[];
    for (final l in _lessons) {
      final subject = _subjects.where((s) => s.id == l.subjectId).firstOrNull;
      if (subject == null) continue;
      final title = _norm(l.title);
      final body = _norm(l.body);
      if (title.contains(q)) {
        out.add(_Result(l, subject, l.title));
      } else if (body.contains(q)) {
        final i = body.indexOf(q);
        final start = (i - 40).clamp(0, body.length);
        final end = (i + q.length + 60).clamp(0, l.body.length);
        var snippet = l.body.substring(start.clamp(0, l.body.length), end);
        snippet = snippet.replaceAll(RegExp(r'[#>*_\[\]]'), '').trim();
        out.add(_Result(l, subject, '… $snippet …'));
      }
    }
    setState(() => _results = out.take(40).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          onChanged: _search,
          decoration: const InputDecoration(
            hintText: 'Chercher une leçon…',
            border: InputBorder.none,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ctl.text.trim().length < 2
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Tape au moins 2 lettres pour chercher dans tes leçons.',
                        textAlign: TextAlign.center),
                  ),
                )
              : _results.isEmpty
                  ? const Center(
                      child: EmptyState(
                        icon: Icons.search_off,
                        title: 'Aucun résultat',
                        message: 'Essaie un autre mot.',
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
                            subtitle: Text('${r.subject.name} · ${r.snippet}',
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => LessonScreen(lesson: r.lesson, subject: r.subject)),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
