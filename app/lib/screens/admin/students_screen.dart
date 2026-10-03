import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/discussion_service.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

String _dayLabel(String? day) {
  if (day == null || day.length != 10) return 'jamais';
  return '${day.substring(8)}/${day.substring(5, 7)}/${day.substring(0, 4)}';
}

/// Liste des élèves avec leur dernière activité et un résumé de leurs résultats.
class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _future = _load();
  String _search = '';
  String _sort = 'activity';

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _load() async {
    final s = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'student')
        .get(const GetOptions(source: Source.server));
    return s.docs;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Élèves')),
      body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: EmptyState(
                icon: Icons.cloud_off,
                title: 'Chargement impossible',
                message: 'Vérifie ta connexion internet.',
                action: FilledButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Réessayer')),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final q = _search.trim().toLowerCase();
          final list = snap.data!.where((d) {
            if (q.isEmpty) return true;
            final m = d.data();
            return '${m['name']} ${m['username']}'.toLowerCase().contains(q);
          }).toList();
          int avg(Map<String, dynamic> m) {
            final n = _i(m['quizLessons']);
            return n == 0 ? -1 : (_i(m['sumBestPct']) / n).round();
          }

          list.sort((a, b) {
            final x = a.data(), y = b.data();
            switch (_sort) {
              case 'name':
                return '${x['name']}'.toLowerCase().compareTo('${y['name']}'.toLowerCase());
              case 'score':
                return avg(y).compareTo(avg(x));
              default:
                return '${y['lastActiveDay'] ?? ''}'.compareTo('${x['lastActiveDay'] ?? ''}');
            }
          });
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              TextField(
                decoration: const InputDecoration(
                    labelText: 'Rechercher un élève', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final e in const {
                  'activity': 'Dernière activité',
                  'name': 'Nom',
                  'score': 'Moyenne',
                }.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _sort == e.key,
                    onSelected: (_) => setState(() => _sort = e.key),
                  ),
              ]),
              const SizedBox(height: 6),
              Text('${list.length} élève${list.length > 1 ? 's' : ''}', style: t.bodySmall),
              const SizedBox(height: 8),
              for (final d in list) _row(context, d),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final t = Theme.of(context).textTheme;
    final n = _i(m['quizLessons']);
    final avg = n == 0 ? null : (_i(m['sumBestPct']) / n).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          minVerticalPadding: 12,
          title: Text('${m['name'] ?? ''}', style: t.titleSmall),
          subtitle: Text(
            '${m['username'] ?? ''} · dernière activité : ${_dayLabel(m['lastActiveDay'] as String?)}\n'
            '${_i(m['lessonsSeen'])} leçon(s) ouverte(s) · $n exercices · '
            '${avg == null ? 'pas de moyenne' : 'moyenne $avg %'}',
            style: t.bodySmall,
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StudentDetailScreen(uid: d.id, data: m))),
        ),
      ),
    );
  }
}

/// Progression détaillée d'un élève, leçon par leçon.
class StudentDetailScreen extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;
  const StudentDetailScreen({super.key, required this.uid, required this.data});

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  late final Future<(List<LessonProgress>, List<Subject>, List<Lesson>)> _future = _load();
  late bool _blocked = widget.data['blocked'] == true;

  Future<void> _toggleBlock() async {
    final name = '${widget.data['name'] ?? 'cet élève'}';
    final block = !_blocked;
    if (!await confirm(
        context,
        block ? 'Bloquer $name ?' : 'Débloquer $name ?',
        block
            ? 'Il ne pourra plus écrire dans les discussions.'
            : 'Il pourra de nouveau écrire dans les discussions.',
        ok: block ? 'Bloquer' : 'Débloquer')) {
      return;
    }
    try {
      await DiscussionService.instance.setBlocked(widget.uid, block);
      if (!mounted) return;
      setState(() => _blocked = block);
      showMessage(context, block ? '$name est bloqué.' : '$name est débloqué.');
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    }
  }

  Future<(List<LessonProgress>, List<Subject>, List<Lesson>)> _load() async {
    final s = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('progress')
        .get(const GetOptions(source: Source.server));
    final repo = ContentRepo.instance;
    final subjects = <Subject>[];
    final lessons = <Lesson>[];
    for (final e in await repo.exams()) {
      subjects.addAll(await repo.subjects(e.id));
      lessons.addAll(await repo.lessonsOfExam(e.id));
    }
    return (s.docs.map(LessonProgress.fromDoc).toList(), subjects, lessons);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = widget.data;
    return Scaffold(
      appBar: AppBar(title: Text('${m['name'] ?? 'Élève'}')),
      body: FutureBuilder<(List<LessonProgress>, List<Subject>, List<Lesson>)>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
                child: EmptyState(
                    icon: Icons.cloud_off,
                    title: 'Chargement impossible',
                    message: 'Vérifie ta connexion internet.'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (progress, subjects, lessons) = snap.data!;
          final byLesson = {for (final p in progress) p.lessonId: p};
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text('Identifiant : ${m['username'] ?? ''}', style: t.bodyMedium),
              Text('Dernière activité : ${_dayLabel(m['lastActiveDay'] as String?)}',
                  style: t.bodyMedium),
              Text('Exercices faits (toutes tentatives) : ${_i(m['quizzesTaken'])}', style: t.bodyMedium),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _toggleBlock,
                icon: Icon(_blocked ? Icons.lock_open : Icons.block),
                label: Text(_blocked ? 'Débloquer (discussions)' : 'Bloquer dans les discussions'),
              ),
              if (progress.isEmpty)
                const EmptyState(
                    icon: Icons.hourglass_empty,
                    title: 'Aucune activité',
                    message: 'Cet élève n\'a encore ouvert aucune leçon.'),
              for (final s in subjects) ..._subject(context, s, lessons, byLesson),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _subject(BuildContext context, Subject s, List<Lesson> all,
      Map<String, LessonProgress> byLesson) {
    final lessons = all.where((l) => l.subjectId == s.id && byLesson.containsKey(l.id)).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (lessons.isEmpty) return const [];
    final color = JangColors.fromHex(s.color);
    final t = Theme.of(context).textTheme;
    return [
      SectionTitle(s.name, color: color),
      for (final l in lessons)
        Builder(builder: (context) {
          final p = byLesson[l.id]!;
          final ok = p.quizDone && p.bestScore! * 2 >= p.total;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Card(
              child: ListTile(
                title: Text(l.title, style: t.titleSmall),
                subtitle: Text(
                    p.quizDone
                        ? '${p.attempts} tentative(s) · dernière note ${p.lastScore}/${p.total}'
                        : 'Leçon ouverte, exercices pas encore faits',
                    style: t.bodySmall),
                trailing: p.quizDone
                    ? Pill('${p.bestScore}/${p.total}',
                        color: ok ? JangColors.success : JangColors.error,
                        background: ok ? JangColors.successBg : JangColors.errorBg)
                    : const Pill('Lue',
                        color: JangColors.textSecondary, background: JangColors.noteBg),
              ),
            ),
          );
        }),
    ];
  }
}
