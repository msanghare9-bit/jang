import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/discussion_service.dart';
import '../../services/student_admin_service.dart';

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
  String _filter = 'all';
  final Set<String> _selected = {};

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _load() async {
    final s = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'student')
        .get(const GetOptions(source: Source.server));
    final me = AuthService.instance.profile.value;
    // Un prof ne voit que les élèves de ses niveaux.
    return s.docs.where((d) {
      if (d.data()['deleted'] == true) return false;
      if (me == null || me.isAdmin || me.profExams.isEmpty) return true;
      return me.profExams.contains(d.data()['examId']);
    }).toList();
  }

  bool _absent(Map<String, dynamic> m) {
    final day = m['lastActiveDay'] as String?;
    if (day == null) return true;
    final d = DateTime.tryParse(day);
    return d == null || DateTime.now().difference(d).inDays >= 7;
  }

  Future<void> _messageSelected() async {
    final n = await composeMessage(context, _selected.toList(),
        '${_selected.length} élève${_selected.length > 1 ? 's' : ''}');
    if (n == null || !mounted) return;
    showMessage(context, 'Message envoyé à $n élève${n > 1 ? 's' : ''}.');
    setState(_selected.clear);
  }

  Future<void> _removeSelected(List<QueryDocumentSnapshot<Map<String, dynamic>>> all) async {
    final names = all.where((d) => _selected.contains(d.id)).map((d) => '${d.data()['name']}').toList();
    final label = names.length == 1 ? names.first : '${names.length} élèves';
    final choice = await confirmRemoval(context, names.length == 1 ? names.first : label);
    if (choice == null || !mounted) return;
    var authOk = true;
    for (final uid in _selected) {
      if (choice == 'delete') {
        authOk = await StudentAdminService.instance.delete(uid) && authOk;
      } else {
        await StudentAdminService.instance.setDisabled(uid, true);
      }
    }
    if (!mounted) return;
    showMessage(
        context,
        choice == 'disable'
            ? 'Compte désactivé.'
            : authOk
                ? 'Élève supprimé.'
                : 'Données effacées. Le compte de connexion sera supprimé quand le serveur sera configuré.');
    setState(() {
      _selected.clear();
      _future = _load();
    });
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
          final all = snap.data!;
          final list = all.where((d) {
            final m = d.data();
            if (_filter == 'absent' && (!_absent(m) || m['disabled'] == true)) return false;
            if (_filter == 'disabled' && m['disabled'] != true) return false;
            if (_filter == 'all' && m['disabled'] == true) return false;
            if (q.isEmpty) return true;
            return '${m['name']} ${m['username']}'.toLowerCase().contains(q);
          }).toList();
          final admin = AuthService.instance.profile.value?.isAdmin ?? false;
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
          return Column(children: [
            Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Wrap(spacing: 8, children: [
                for (final e in const {
                  'all': 'Tous',
                  'absent': 'Absents 7 jours',
                  'disabled': 'Désactivés',
                }.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _filter == e.key,
                    onSelected: (_) => setState(() => _filter = e.key),
                  ),
              ]),
              const SizedBox(height: 6),
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
              Text('Coche des élèves pour leur écrire ou les supprimer.', style: t.bodySmall),
              const SizedBox(height: 8),
              for (final d in list) _row(context, d),
            ],
          )),
            if (_selected.isNotEmpty)
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  color: JangColors.noteBg,
                  child: Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _messageSelected,
                        icon: const Icon(Icons.mail_outline),
                        label: Text('Écrire (${_selected.length})'),
                      ),
                    ),
                    if (admin) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _removeSelected(all),
                        style: OutlinedButton.styleFrom(foregroundColor: JangColors.errorDark),
                        child: const Text('Supprimer'),
                      ),
                    ],
                  ]),
                ),
              ),
          ]);
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
          leading: Checkbox(
            value: _selected.contains(d.id),
            onChanged: (v) => setState(() => v == true ? _selected.add(d.id) : _selected.remove(d.id)),
          ),
          title: Text('${m['name'] ?? ''}${m['disabled'] == true ? ' (désactivé)' : ''}', style: t.titleSmall),
          subtitle: Text(
            '${m['username'] ?? ''} · dernière activité : ${_dayLabel(m['lastActiveDay'] as String?)}\n'
            '${_i(m['lessonsSeen'])} leçon(s) ouverte(s) · $n exercices · '
            '${avg == null ? 'pas de moyenne' : 'moyenne $avg %'}',
            style: t.bodySmall,
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(
                context, MaterialPageRoute(builder: (_) => StudentDetailScreen(uid: d.id, data: m)));
            if (mounted) setState(() => _future = _load());
          },
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
  late bool _disabled = widget.data['disabled'] == true;

  Future<void> _toggleDisabled() async {
    final name = '${widget.data['name'] ?? 'cet élève'}';
    final off = !_disabled;
    if (!await confirm(context, off ? 'Désactiver $name ?' : 'Réactiver $name ?',
        off ? 'Il ne pourra plus se connecter. Ses résultats sont gardés.' : 'Il pourra de nouveau se connecter.',
        ok: off ? 'Désactiver' : 'Réactiver')) {
      return;
    }
    await StudentAdminService.instance.setDisabled(widget.uid, off);
    if (mounted) setState(() => _disabled = off);
  }

  Future<void> _delete() async {
    final name = '${widget.data['name'] ?? 'Élève'}';
    final choice = await confirmRemoval(context, name);
    if (choice == null || !mounted) return;
    if (choice == 'disable') {
      await StudentAdminService.instance.setDisabled(widget.uid, true);
      if (mounted) setState(() => _disabled = true);
      return;
    }
    final ok = await StudentAdminService.instance.delete(widget.uid);
    if (!mounted) return;
    showMessage(context, ok ? 'Élève supprimé.' : 'Données effacées. Compte de connexion à supprimer quand le serveur sera configuré.');
    Navigator.pop(context);
  }

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
              FilledButton.icon(
                onPressed: () async {
                  final n = await composeMessage(context, [widget.uid], '${m['name'] ?? 'l\'élève'}');
                  if (n != null && context.mounted) showMessage(context, 'Message envoyé.');
                },
                icon: const Icon(Icons.mail_outline),
                label: const Text('Envoyer un message'),
              ),
              if (AuthService.instance.profile.value?.isAdmin ?? false) ...[
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _toggleDisabled,
                  icon: Icon(_disabled ? Icons.lock_open : Icons.person_off_outlined),
                  label: Text(_disabled ? 'Réactiver le compte' : 'Désactiver le compte'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(foregroundColor: JangColors.errorDark),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer l\'élève'),
                ),
              ],
              const SizedBox(height: 6),
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
