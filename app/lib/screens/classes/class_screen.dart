import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../match/match_screens.dart';
import '../../services/quiz_bank.dart';
import '../../services/match_service.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../../services/class_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin/students_screen.dart';
import 'class_widgets.dart';
import 'item_editor.dart';
import 'teacher_course_screen.dart';
import 'teacher_lesson_export_screen.dart';

/// Tout ce qu'il faut pour afficher une classe.
class _ClassData {
  final List<StudentSummary> students;
  final List<ClassItem> items;
  final Map<String, List<Submission>> submissions;
  _ClassData(this.students, this.items, this.submissions);

  List<ClassItem> get homeworks => items.where((i) => i.type == ClassItem.homework).toList();
  int get toGrade => submissions.values.fold(0, (n, l) => n + l.where((s) => !s.graded).length);
}

/// Une classe, vue par son prof (ou l'admin) : élèves, contenus, devoirs.
class ClassScreen extends StatefulWidget {
  final ClassRoom classRoom;
  const ClassScreen({super.key, required this.classRoom});

  @override
  State<ClassScreen> createState() => _ClassScreenState();
}

class _ClassScreenState extends State<ClassScreen> {
  final _service = ClassService.instance;
  late ClassRoom _c = widget.classRoom;
  late Future<_ClassData> _future = _load();
  String _examName = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _service.revision.addListener(_reload);
    examNames().then((m) {
      if (mounted) setState(() => _examName = m[_c.examId] ?? '');
    });
  }

  @override
  void dispose() {
    _service.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<_ClassData> _load() async {
    final fresh = await _service.byId(_c.id);
    if (fresh != null && mounted) _c = fresh;
    final results = await Future.wait([_service.students(_c.students), _service.itemsOf(_c.id)]);
    final students = results[0] as List<StudentSummary>;
    final items = results[1] as List<ClassItem>;
    final subs = <String, List<Submission>>{};
    await Future.wait([
      for (final i in items.where((i) => i.type == ClassItem.homework))
        _service.submissions(i.id).then((l) => subs[i.id] = l),
    ]);
    return _ClassData(students, items, subs);
  }

  Future<void> _newCode() async {
    if (!await confirm(context, 'Nouveau code ?',
        'L\'ancien code ne marchera plus. Les élèves déjà dans la classe restent dedans.',
        ok: 'Changer')) {
      return;
    }
    try {
      final code = await _service.newCode(_c.id);
      if (!mounted) return;
      setState(() => _c = _copy(code: code));
      showMessage(context, 'Nouveau code : $code');
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    }
  }

  ClassRoom _copy({String? code}) => ClassRoom(
        id: _c.id,
        name: _c.name,
        examId: _c.examId,
        subject: _c.subject,
        subjectName: _c.subjectName,
        profUid: _c.profUid,
        profName: _c.profName,
        school: _c.school,
        code: code ?? _c.code,
        students: _c.students,
      );

  Future<void> _addStudent() async {
    final ctrl = TextEditingController();
    String error = '';
    bool busy = false;
    final added = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Ajouter un élève', style: titleStyle(20)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Écris le nom d\'utilisateur de l\'élève (celui qu\'il utilise pour se connecter).'),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              autocorrect: false,
              decoration: InputDecoration(labelText: 'Nom d\'utilisateur', errorText: error.isEmpty ? null : error),
            ),
            const SizedBox(height: 8),
            Text('Les élèves peuvent aussi entrer seuls avec le code : ${_c.code}',
                style: Theme.of(c).textTheme.bodySmall),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setD(() => busy = true);
                      String e;
                      try {
                        e = await _service.addByUsername(_c, ctrl.text);
                      } catch (x) {
                        e = 'Échec : vérifie ta connexion internet.';
                      }
                      if (!c.mounted) return;
                      if (e.isEmpty) {
                        Navigator.pop(c, true);
                      } else {
                        setD(() {
                          error = e;
                          busy = false;
                        });
                      }
                    },
              child: Text(busy ? 'Un instant…' : 'Ajouter'),
            ),
          ],
        ),
      ),
    );
    if (added == true && mounted) showMessage(context, 'Élève ajouté à la classe.');
  }

  Future<void> _deleteItem(ClassItem item) async {
    if (!await confirm(context, 'Supprimer « ${item.title} » ?',
        'Tes élèves ne le verront plus.', ok: 'Supprimer')) {
      return;
    }
    try {
      await _service.deleteItem(item);
      if (mounted) showMessage(context, 'Contenu supprimé.');
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    }
  }

  void _openEditor(ClassItem? item) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => ClassItemEditor(classRoom: _c, item: item)));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(title: Text(_c.name)),
        body: FutureBuilder<_ClassData>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;
            return NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(child: _header(context)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsDelegate(TabBar(labelPadding: const EdgeInsets.symmetric(horizontal: 4), tabs: [
                    Tab(text: data == null ? 'Élèves' : 'Élèves (${data.students.length})'),
                    Tab(text: data == null ? 'Contenus' : 'Contenus (${data.items.length})'),
                    Tab(text: data == null || data.toGrade == 0 ? 'Devoirs' : 'Devoirs (${data.toGrade})'),
                  ])),
                ),
              ],
              body: snap.hasError
                  ? loadError(_reload)
                  : data == null
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(children: [
                          _studentsTab(context, data),
                          _itemsTab(context, data),
                          _homeworkTab(context, data),
                        ]),
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        color: JangColors.noteBg,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              [if (_examName.isNotEmpty) _examName, _c.subjectName, 'Prof : ${_c.profName}'].join(' · '),
              style: t.bodyMedium,
            ),
            const SizedBox(height: 10),
            const Text('Code de la classe', style: TextStyle(fontWeight: FontWeight.w700)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SelectableText(_c.code,
                  style: titleStyle(40, color: JangColors.primaryDark, weight: 800).copyWith(letterSpacing: 6)),
            ),
            Text('Donne ce code à tes élèves : ils l\'écrivent dans l\'app pour entrer dans la classe.',
                style: t.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _c.code));
                  if (context.mounted) showMessage(context, 'Code copié.');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copier'),
              ),
              OutlinedButton.icon(
                onPressed: _newCode,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Nouveau code'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ---------- Élèves ----------

  Widget _studentsTab(BuildContext context, _ClassData data) {
    final t = Theme.of(context).textTheme;
    final list = data.students.where((s) {
      if (_filter == 'active') return s.active;
      if (_filter == 'inactive') return !s.active;
      return true;
    }).toList();
    final working = data.students.where((s) => s.active).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        FilledButton.icon(
          onPressed: _addStudent,
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Ajouter un élève'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final e in {
            'all': 'Tous (${data.students.length})',
            'active': 'Travaillent ($working)',
            'inactive': 'Ne travaillent pas (${data.students.length - working})',
          }.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _filter == e.key,
              onSelected: (_) => setState(() => _filter = e.key),
            ),
        ]),
        const SizedBox(height: 4),
        Text('« Travaillent » : venus dans les 7 derniers jours.', style: t.bodySmall),
        const SizedBox(height: 8),
        if (list.isEmpty)
          EmptyState(
            icon: Icons.groups_outlined,
            title: data.students.isEmpty ? 'Pas encore d\'élève' : 'Personne ici',
            message: data.students.isEmpty
                ? 'Donne le code ${_c.code} à tes élèves, ou ajoute-les avec leur nom d\'utilisateur.'
                : null,
          ),
        for (final s in list)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              minVerticalPadding: 10,
              leading: Icon(Icons.circle, size: 14, color: s.active ? JangColors.success : JangColors.error),
              title: Text(s.name.isEmpty ? s.username : s.name, style: t.titleSmall),
              subtitle: Text(
                '${presenceLabel(s)}\n'
                '${s.average == null ? 'Pas de quiz' : 'Moyenne ${s.average} %'} · '
                '${plural(s.missionsDone, 'mission')} · ${plural(s.lessonsSeen, 'leçon')} ouverte${s.lessonsSeen > 1 ? 's' : ''}',
                style: t.bodySmall,
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ClassStudentScreen(classRoom: _c, student: s, items: data.items))),
            ),
          ),
      ],
    );
  }

  // ---------- Contenus ----------

  Widget _itemsTab(BuildContext context, _ClassData data) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        FilledButton.icon(
          onPressed: () => _openEditor(null),
          icon: const Icon(Icons.add),
          label: const Text('Créer un contenu'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TeacherCourseScreen(classRoom: _c)),
          ),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Kocc : préparer un cours complet'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final profile = AuthService.instance.profile.value;
            if (profile == null) return;
            final added = await Navigator.push<bool>(context,
              MaterialPageRoute(builder: (_) => TeacherLessonExportScreen(classRoom: _c, profile: profile)));
            if (added == true) _reload();
          },
          icon: const Icon(Icons.library_add_outlined),
          label: const Text('Ajouter une leçon officielle'),
        ),
        const SizedBox(height: 10),
        if (data.items.isEmpty)
          const EmptyState(
            icon: Icons.library_add_outlined,
            title: 'Pas encore de contenu',
            message: 'Crée une leçon, un QCM, un texte à trous, un devoir ou une mission pour ta classe.',
          ),
        for (final i in data.items)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.only(left: 14, right: 2),
              leading: Icon(classItemIcon(i.type), color: JangColors.primaryDark),
              title: Text(i.title.isEmpty ? '(sans titre)' : i.title, style: t.titleSmall),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(ClassItem.label(i.type), style: t.bodySmall),
                  VisibilityPill(i),
                ]),
              ),
              trailing: PopupMenuButton<String>(
                tooltip: 'Options',
                onSelected: (v) => v == 'edit' ? _openEditor(i) : _deleteItem(i),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Modifier')),
                  PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                ],
              ),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ItemResultsScreen(classRoom: _c, item: i))),
            ),
          ),
      ],
    );
  }

  // ---------- Devoirs ----------

  Widget _homeworkTab(BuildContext context, _ClassData data) {
    final t = Theme.of(context).textTheme;
    final hw = data.homeworks;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (hw.isEmpty)
          EmptyState(
            icon: Icons.assignment_outlined,
            title: 'Pas de devoir',
            message: 'Crée un contenu de type « Devoir » : tes élèves y répondent et tu les corriges ici.',
            action: OutlinedButton.icon(
                onPressed: () => _openEditor(null), icon: const Icon(Icons.add), label: const Text('Créer')),
          )
        else
          Text(
            data.toGrade == 0
                ? 'Tout est corrigé. Bravo !'
                : '${plural(data.toGrade, 'rendu')} à corriger.',
            style: titleStyle(17, color: data.toGrade == 0 ? JangColors.successDark : JangColors.warning),
          ),
        const SizedBox(height: 8),
        for (final i in hw)
          Builder(builder: (context) {
            final subs = data.submissions[i.id] ?? const <Submission>[];
            final todo = subs.where((s) => !s.graded).length;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.assignment_outlined, color: JangColors.primaryDark),
                title: Text(i.title, style: t.titleSmall),
                subtitle: Text(
                    '${plural(subs.length, 'rendu')} sur ${plural(data.students.length, 'élève')}'
                    '${todo > 0 ? ' · $todo à corriger' : ''}',
                    style: t.bodySmall),
                trailing: todo > 0
                    ? Pill('$todo', color: JangColors.warning, background: JangColors.warningBg)
                    : const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => HomeworkRendusScreen(item: i, classRoom: _c))),
              ),
            );
          }),
      ],
    );
  }
}

class _TabsDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabsDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Material(color: Theme.of(context).scaffoldBackgroundColor, child: tabBar);

  @override
  bool shouldRebuild(_TabsDelegate old) => old.tabBar != tabBar;
}

/// Pastille d'état d'un élève sur un contenu.
Widget _resultPill(ClassItem item, ItemResult? r, {Submission? sub}) {
  if (item.type == ClassItem.homework) {
    if (sub == null && r == null) {
      return const Pill('Pas rendu', color: JangColors.errorDark, background: JangColors.errorBg);
    }
    if (sub != null && sub.grade.isNotEmpty) {
      return Pill(sub.grade, color: JangColors.successDark, background: JangColors.successBg);
    }
    return Pill(sub?.graded == true ? 'Corrigé' : 'Rendu',
        color: JangColors.primaryDark, background: JangColors.noteBg);
  }
  if (r == null || !r.opened) {
    return const Pill('Pas ouvert', color: JangColors.errorDark, background: JangColors.errorBg);
  }
  if (r.scorePct != null) {
    final ok = r.scorePct! >= 50;
    return Pill('${r.scorePct} %',
        color: ok ? JangColors.successDark : JangColors.errorDark,
        background: ok ? JangColors.successBg : JangColors.errorBg);
  }
  if (r.done) return const Pill('Fait', color: JangColors.successDark, background: JangColors.successBg);
  return const Pill('Ouvert', color: JangColors.primaryDark, background: JangColors.noteBg);
}

/// Fiche d'un élève dans la classe : ce qu'il a fait de chaque contenu.
class ClassStudentScreen extends StatefulWidget {
  final ClassRoom classRoom;
  final StudentSummary student;
  final List<ClassItem> items;
  const ClassStudentScreen({super.key, required this.classRoom, required this.student, required this.items});

  @override
  State<ClassStudentScreen> createState() => _ClassStudentScreenState();
}

class _ClassStudentScreenState extends State<ClassStudentScreen> {
  late Future<(Map<String, ItemResult>, Map<String, Submission>)> _future = _load();

  Future<(Map<String, ItemResult>, Map<String, Submission>)> _load() async {
    final uid = widget.student.uid;
    final res = <String, ItemResult>{};
    final subs = <String, Submission>{};
    await Future.wait([
      for (final i in widget.items)
        if (i.type == ClassItem.homework)
          ClassService.instance.mySubmission(i.id, uid).then((s) {
            if (s != null) subs[i.id] = s;
          })
        else
          ClassService.instance.results(i, [uid]).then((m) {
            final r = m[uid];
            if (r != null) res[i.id] = r;
          }),
    ]);
    return (res, subs);
  }

  Future<void> _remove() async {
    final s = widget.student;
    if (!await confirm(context, 'Retirer ${s.name} de la classe ?',
        'Son compte et ses résultats sont gardés. Il pourra revenir avec le code.',
        ok: 'Retirer')) {
      return;
    }
    try {
      await ClassService.instance.removeStudent(widget.classRoom, s.uid);
      if (!mounted) return;
      showMessage(context, '${s.name} n\'est plus dans la classe.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    }
  }

  Future<void> _openFull() async {
    try {
      final d = await FirebaseFirestore.instance.collection('users').doc(widget.student.uid).get();
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => StudentDetailScreen(uid: widget.student.uid, data: d.data() ?? {})));
    } catch (e) {
      if (mounted) showMessage(context, 'Chargement impossible. Vérifie ta connexion internet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = widget.student;
    return Scaffold(
      appBar: AppBar(title: Text(s.name.isEmpty ? s.username : s.name)),
      body: FutureBuilder<(Map<String, ItemResult>, Map<String, Submission>)>(
        future: _future,
        builder: (context, snap) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                color: s.active ? JangColors.successBg : JangColors.warningBg,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(presenceLabel(s), style: titleStyle(18)),
                    const SizedBox(height: 4),
                    Text('Nom d\'utilisateur : ${s.username}', style: t.bodyMedium),
                    Text(s.average == null ? 'Pas encore de quiz' : 'Moyenne aux quiz : ${s.average} %',
                        style: t.bodyMedium),
                    Text('Missions finies : ${s.missionsDone}', style: t.bodyMedium),
                    Text('Leçons ouvertes : ${s.lessonsSeen}', style: t.bodyMedium),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _openFull,
                icon: const Icon(Icons.insights_outlined),
                label: const Text('Voir toute sa progression'),
              ),
              SectionTitle('Dans ta classe (${widget.items.length})'),
              if (snap.hasError)
                loadError(() => setState(() => _future = _load()))
              else if (!snap.hasData)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else ...[
                if (widget.items.isEmpty) Text('Pas encore de contenu dans la classe.', style: t.bodySmall),
                for (final i in widget.items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: Icon(classItemIcon(i.type), color: JangColors.primaryDark),
                      title: Text(i.title, style: t.titleSmall),
                      subtitle: Text(ClassItem.label(i.type), style: t.bodySmall),
                      trailing: _resultPill(i, snap.data!.$1[i.id], sub: snap.data!.$2[i.id]),
                      onTap: i.type == ClassItem.homework && snap.data!.$2[i.id] != null
                          ? () async {
                              final changed = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => GradeScreen(item: i, submission: snap.data!.$2[i.id]!)));
                              if (changed == true && mounted) setState(() => _future = _load());
                            }
                          : null,
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _remove,
                style: OutlinedButton.styleFrom(foregroundColor: JangColors.errorDark),
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Retirer de la classe'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Résultats d'un contenu : qui l'a ouvert, qui l'a fait, la moyenne.
class ItemResultsScreen extends StatefulWidget {
  final ClassRoom classRoom;
  final ClassItem item;
  const ItemResultsScreen({super.key, required this.classRoom, required this.item});

  @override
  State<ItemResultsScreen> createState() => _ItemResultsScreenState();
}

class _ItemResultsScreenState extends State<ItemResultsScreen> {
  late Future<(List<StudentSummary>, Map<String, ItemResult>, Map<String, Submission>)> _future = _load();

  Future<(List<StudentSummary>, Map<String, ItemResult>, Map<String, Submission>)> _load() async {
    final s = ClassService.instance;
    final students = await s.students(widget.classRoom.students);
    final uids = [for (final st in students) st.uid];
    final res = await s.results(widget.item, uids);
    final subs = <String, Submission>{};
    if (widget.item.type == ClassItem.homework) {
      for (final x in await s.submissions(widget.item.id)) {
        subs[x.uid] = x;
      }
    }
    return (students, res, subs);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final item = widget.item;
    final hw = item.type == ClassItem.homework;
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: FutureBuilder<(List<StudentSummary>, Map<String, ItemResult>, Map<String, Submission>)>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return loadError(() => setState(() => _future = _load()));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (students, res, subs) = snap.data!;
          final n = students.length;
          final opened = students.where((s) => res[s.uid]?.opened == true).length;
          final done = students.where((s) => res[s.uid]?.done == true).length;
          final scores = [for (final s in students) res[s.uid]?.scorePct].whereType<int>().toList();
          final avg = scores.isEmpty ? null : (scores.reduce((a, b) => a + b) / scores.length).round();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Icon(classItemIcon(item.type), color: JangColors.primaryDark),
                Text(ClassItem.label(item.type), style: t.bodyMedium),
                VisibilityPill(item),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                if (!hw) _stat('Ouvert', '$opened/$n'),
                _stat(hw ? 'Rendu' : 'Fait', '$done/$n'),
                if (!hw && item.type != ClassItem.mission) _stat('Moyenne', avg == null ? '—' : '$avg %'),
                if (hw) _stat('À corriger', '${subs.values.where((s) => !s.graded).length}'),
              ]),
              if (item.isPublic)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Ce contenu est public : ici, on ne compte que les élèves de ta classe.',
                      style: t.bodySmall),
                ),
              if (hw) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => HomeworkRendusScreen(item: item, classRoom: widget.classRoom))),
                  icon: const Icon(Icons.rate_review_outlined),
                  label: const Text('Corriger les rendus'),
                ),
              ],
              if (item.quiz.isNotEmpty) _QuizLive(classRoom: widget.classRoom, item: item, uids: [for (final st in students) st.uid]),
              SectionTitle('Élève par élève ($n)'),
              if (n == 0) Text('Pas encore d\'élève dans la classe.', style: t.bodySmall),
              for (final s in students)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    title: Text(s.name.isEmpty ? s.username : s.name, style: t.titleSmall),
                    subtitle: Text(presenceLabel(s), style: t.bodySmall),
                    trailing: _resultPill(item, res[s.uid], sub: subs[s.uid]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Card(
          color: JangColors.noteBg,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Column(children: [
              FittedBox(child: Text(value, style: titleStyle(22, color: JangColors.primaryDark, weight: 800))),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

/// Les rendus d'un devoir.
class HomeworkRendusScreen extends StatefulWidget {
  final ClassItem item;
  final ClassRoom classRoom;
  const HomeworkRendusScreen({super.key, required this.item, required this.classRoom});

  @override
  State<HomeworkRendusScreen> createState() => _HomeworkRendusScreenState();
}

class _HomeworkRendusScreenState extends State<HomeworkRendusScreen> {
  late Future<List<Submission>> _future = ClassService.instance.submissions(widget.item.id);

  void _reload() => setState(() => _future = ClassService.instance.submissions(widget.item.id));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title)),
      body: FutureBuilder<List<Submission>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return loadError(_reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final subs = [...snap.data!]..sort((a, b) => a.graded == b.graded ? 0 : (a.graded ? 1 : -1));
          final todo = subs.where((s) => !s.graded).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                color: JangColors.noteBg,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Consigne', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(widget.item.body),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                  '${plural(subs.length, 'rendu')} sur ${plural(widget.classRoom.students.length, 'élève')}'
                  ' · ${todo == 0 ? 'tout est corrigé' : '$todo à corriger'}',
                  style: t.bodyMedium),
              const SizedBox(height: 8),
              if (subs.isEmpty)
                const EmptyState(
                    icon: Icons.hourglass_empty, title: 'Pas encore de rendu', message: 'Les élèves n\'ont rien envoyé.'),
              for (final s in subs)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(s.name, style: t.titleSmall),
                    subtitle: Text(s.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                    trailing: s.graded
                        ? Pill(s.grade.isEmpty ? 'Corrigé' : s.grade,
                            color: JangColors.successDark, background: JangColors.successBg)
                        : const Pill('À corriger', color: JangColors.warning, background: JangColors.warningBg),
                    onTap: () async {
                      final changed = await Navigator.push<bool>(context,
                          MaterialPageRoute(builder: (_) => GradeScreen(item: widget.item, submission: s)));
                      if (changed == true) _reload();
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Lire le rendu d'un élève, donner une note et un commentaire.
class GradeScreen extends StatefulWidget {
  final ClassItem item;
  final Submission submission;
  const GradeScreen({super.key, required this.item, required this.submission});

  @override
  State<GradeScreen> createState() => _GradeScreenState();
}

class _GradeScreenState extends State<GradeScreen> {
  late final _grade = TextEditingController(text: widget.submission.grade);
  late final _comment = TextEditingController(text: widget.submission.comment);
  bool _busy = false;

  @override
  void dispose() {
    _grade.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_grade.text.trim().isEmpty && _comment.text.trim().isEmpty) {
      showMessage(context, 'Écris une note ou un commentaire.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ClassService.instance
          .grade(widget.item.id, widget.submission.uid, grade: _grade.text, comment: _comment.text);
      if (!mounted) return;
      showMessage(context, 'Correction envoyée à ${widget.submission.name}.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, 'Échec : $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = widget.submission;
    final at = s.at;
    return Scaffold(
      appBar: AppBar(title: Text(s.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(widget.item.title, style: titleStyle(18)),
          if (at != null)
            Text('Rendu le ${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}/${at.year}',
                style: t.bodySmall),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(s.text.isEmpty ? '(rendu vide)' : s.text, style: t.bodyLarge),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _grade,
            decoration: const InputDecoration(labelText: 'Note (ex. 15/20)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            minLines: 3,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Commentaire pour l\'élève', alignLabelWithHint: true),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(_busy ? 'Envoi…' : 'Enregistrer la correction'),
          ),
        ],
      ),
    );
  }
}


/// QCM du prof : le lancer en direct en classe, revoir les directs, et les questions les plus ratées.
class _QuizLive extends StatefulWidget {
  final ClassRoom classRoom;
  final ClassItem item;
  final List<String> uids;
  const _QuizLive({required this.classRoom, required this.item, required this.uids});

  @override
  State<_QuizLive> createState() => _QuizLiveState();
}

class _QuizLiveState extends State<_QuizLive> {
  late final Future<(List<LiveMatch>, List<(String, int)>)> _future = _load();
  bool _busy = false;

  Future<(List<LiveMatch>, List<(String, int)>)> _load() async {
    final lives = (await MatchService.instance.ofClass(widget.classRoom.id))
        .where((m) => m.itemId == widget.item.id)
        .toList();
    final missed = await ClassService.instance.missedQuestions(widget.item, widget.uids);
    return (lives, missed);
  }

  Future<void> _launch() async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final m = await MatchService.instance.create(
        host: p,
        questions: [for (final q in widget.item.quiz) BankQuestion.fromQuiz(q)],
        hostPlays: false,
        title: widget.item.title,
        classId: widget.classRoom.id,
        itemId: widget.item.id,
      );
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRoomScreen(matchId: m.id)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Il faut internet pour un quiz en direct.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF46178F)),
        onPressed: _busy ? null : _launch,
        icon: const Icon(Icons.bolt),
        label: Text(_busy ? 'Un instant…' : 'Lancer en direct en classe'),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Les élèves entrent le code dans « Match ». Tu vois qui répond et le classement.', style: t.bodySmall),
      ),
      FutureBuilder<(List<LiveMatch>, List<(String, int)>)>(
        future: _future,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) return const SizedBox.shrink();
          final (lives, missed) = data;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (missed.isNotEmpty) ...[
              const SectionTitle('Les questions les plus ratées'),
              for (final (q, n) in missed.take(5))
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline, color: JangColors.errorDark),
                    title: Text(q, style: t.bodyMedium),
                    trailing: Text('$n élève${n > 1 ? 's' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
            if (lives.isNotEmpty) ...[
              const SectionTitle('Quiz en direct'),
              for (final m in lives)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: const Icon(Icons.bolt, color: Color(0xFF46178F)),
                    title: Text(m.createdAt == null
                        ? 'Quiz en direct'
                        : 'Le ${m.createdAt!.day}/${m.createdAt!.month} à ${m.createdAt!.hour}h${m.createdAt!.minute.toString().padLeft(2, '0')}'),
                    subtitle: Text(m.state == LiveMatch.over ? 'Terminé : voir le podium et les réponses' : 'En cours'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRoomScreen(matchId: m.id))),
                  ),
                ),
            ],
          ]);
        },
      ),
    ]);
  }
}
