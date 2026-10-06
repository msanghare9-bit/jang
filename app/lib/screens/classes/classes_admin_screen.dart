import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/class_service.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin/admin_widgets.dart';
import 'class_screen.dart';
import 'class_widgets.dart';

class _AdminData {
  final List<UserProfile> profs;
  final List<ClassRoom> classes;
  final List<Exam> exams;
  final Map<String, List<Subject>> subjects;

  /// Contenus créés, par auteur.
  final Map<String, List<ClassItem>> itemsByOwner;
  _AdminData(this.profs, this.classes, this.exams, this.subjects, this.itemsByOwner);

  String examName(String id) => exams.where((e) => e.id == id).firstOrNull?.name ?? '';

  int itemsOfClass(String classId) =>
      itemsByOwner.values.fold(0, (n, l) => n + l.where((i) => i.classId == classId).length);
}

/// Admin : les profs, leurs classes et ce qu'ils ont créé.
class ClassesAdminScreen extends StatefulWidget {
  const ClassesAdminScreen({super.key});

  @override
  State<ClassesAdminScreen> createState() => _ClassesAdminScreenState();
}

class _ClassesAdminScreenState extends State<ClassesAdminScreen> {
  final _service = ClassService.instance;
  late Future<_AdminData> _future = _load();

  @override
  void initState() {
    super.initState();
    _service.revision.addListener(_reload);
  }

  @override
  void dispose() {
    _service.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<_AdminData> _load() async {
    final repo = ContentRepo.instance;
    final exams = await repo.exams();
    final subjects = <String, List<Subject>>{};
    for (final e in exams) {
      subjects[e.id] = await repo.subjects(e.id);
    }
    final s = await FirebaseFirestore.instance.collection('users').where('role', whereIn: ['admin', 'prof']).get();
    final profs = s.docs.map(UserProfile.fromDoc).toList()
      ..sort((a, b) => a.isAdmin == b.isAdmin ? a.name.compareTo(b.name) : (a.isAdmin ? 1 : -1));
    final classes = await _service.all();
    final items = <String, List<ClassItem>>{};
    await Future.wait([
      for (final p in profs) _service.itemsOfOwner(p.uid).then((l) => items[p.uid] = l),
    ]);
    return _AdminData(profs, classes, exams, subjects, items);
  }

  Future<void> _create(_AdminData data) async {
    final r = await showDialog<_NewClass>(context: context, builder: (_) => _NewClassDialog(data: data));
    if (r == null || !mounted) return;
    try {
      final c = await _service.create(
        name: r.name,
        examId: r.examId,
        subjectName: r.subjectName,
        profUid: r.prof.uid,
        profName: r.prof.name,
      );
      if (!mounted) return;
      showMessage(context, 'Classe ${c.name} créée. Code : ${c.code}');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    }
  }

  Future<void> _rename(ClassRoom c) async {
    final name = await askText(context, 'Renommer la classe', 'Nom (ex. 6e B)', initial: c.name);
    if (name == null || name == c.name) return;
    try {
      await _service.update(c.id, {'name': name});
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    }
  }

  Future<void> _changeProf(ClassRoom c, _AdminData data) async {
    final p = await showDialog<UserProfile>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Prof de ${c.name}', style: titleStyle(20)),
        children: [
          for (final p in data.profs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(children: [
                Icon(p.uid == c.profUid ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: p.uid == c.profUid ? JangColors.primary : JangColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(child: Text(p.isAdmin ? '${p.name} (admin)' : p.name)),
              ]),
            ),
        ],
      ),
    );
    if (p == null || p.uid == c.profUid) return;
    try {
      await _service.update(c.id, {'profUid': p.uid, 'profName': p.name});
      if (mounted) showMessage(context, '${p.name} est maintenant le prof de ${c.name}.');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    }
  }

  Future<void> _delete(ClassRoom c) async {
    if (!await confirm(context, 'Supprimer la classe ${c.name} ?',
        'Les ${plural(c.students.length, 'élève')} ne seront plus dans cette classe. Leurs comptes sont gardés.',
        ok: 'Supprimer')) {
      return;
    }
    try {
      await _service.remove(c.id);
      if (mounted) showMessage(context, 'Classe supprimée.');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profs et classes')),
      body: FutureBuilder<_AdminData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return loadError(_reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final data = snap.data!;
          final profIds = {for (final p in data.profs) p.uid};
          final orphans = data.classes.where((c) => !profIds.contains(c.profUid)).toList();
          return Stack(children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text(
                    'Chaque classe a un prof et un code. Les élèves entrent avec le code, '
                    'ou le prof les ajoute avec leur nom d\'utilisateur.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                for (final p in data.profs)
                  if (!p.isAdmin || data.classes.any((c) => c.profUid == p.uid) || (data.itemsByOwner[p.uid]?.isNotEmpty ?? false))
                    _profCard(context, p, data),
                if (orphans.isNotEmpty) ...[
                  const SectionTitle('Classes sans prof'),
                  for (final c in orphans) _classTile(context, c, data),
                ],
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: FloatingActionButton.extended(
                  onPressed: () => _create(data),
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle classe'),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _profCard(BuildContext context, UserProfile p, _AdminData data) {
    final t = Theme.of(context).textTheme;
    final classes = data.classes.where((c) => c.profUid == p.uid).toList();
    final items = data.itemsByOwner[p.uid] ?? const <ClassItem>[];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: p.isAdmin ? JangColors.text : JangColors.noteBg,
              child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                  style: TextStyle(color: p.isAdmin ? Colors.white : JangColors.primaryDark)),
            ),
            title: Text(p.isAdmin ? '${p.name} (admin)' : p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${p.username} · ${plural(classes.length, 'classe')} · '
                '${plural(items.length, 'contenu')} créé${items.length > 1 ? 's' : ''}'),
          ),
          if (classes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Pas encore de classe.', style: t.bodySmall),
            ),
          for (final c in classes) _classTile(context, c, data, inCard: true),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: items.isEmpty
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => _OwnerItemsScreen(prof: p, items: items, classes: data.classes))),
              icon: const Icon(Icons.folder_open_outlined),
              label: Text('Tout ce qu\'il a créé (${items.length})'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _classTile(BuildContext context, ClassRoom c, _AdminData data, {bool inCard = false}) {
    final t = Theme.of(context).textTheme;
    final n = data.itemsOfClass(c.id);
    final tile = ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 0),
      leading: const Icon(Icons.groups_outlined, color: JangColors.primaryDark),
      title: Text(c.name, style: t.titleSmall),
      subtitle: Text(
        [
          if (data.examName(c.examId).isNotEmpty) data.examName(c.examId),
          c.subjectName,
          plural(c.students.length, 'élève'),
          plural(n, 'contenu'),
        ].join(' · '),
        style: t.bodySmall,
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Options',
        onSelected: (v) {
          switch (v) {
            case 'rename':
              _rename(c);
            case 'prof':
              _changeProf(c, data);
            case 'delete':
              _delete(c);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Renommer')),
          PopupMenuItem(value: 'prof', child: Text('Changer de prof')),
          PopupMenuItem(value: 'delete', child: Text('Supprimer')),
        ],
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassScreen(classRoom: c))),
    );
    return inCard ? tile : Card(margin: const EdgeInsets.only(bottom: 8), child: tile);
  }
}

/// Tout ce qu'un prof a créé.
class _OwnerItemsScreen extends StatelessWidget {
  final UserProfile prof;
  final List<ClassItem> items;
  final List<ClassRoom> classes;
  const _OwnerItemsScreen({required this.prof, required this.items, required this.classes});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('Créé par ${prof.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(plural(items.length, 'contenu'), style: t.bodySmall),
          const SizedBox(height: 8),
          for (final i in items)
            Builder(builder: (context) {
              final c = classes.where((c) => c.id == i.classId).firstOrNull;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(classItemIcon(i.type), color: JangColors.primaryDark),
                  title: Text(i.title.isEmpty ? '(sans titre)' : i.title, style: t.titleSmall),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${ClassItem.label(i.type)} · ${c?.name ?? 'classe supprimée'}', style: t.bodySmall),
                      VisibilityPill(i),
                    ]),
                  ),
                  trailing: c == null ? null : const Icon(Icons.chevron_right),
                  onTap: c == null
                      ? null
                      : () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => ItemResultsScreen(classRoom: c, item: i))),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _NewClass {
  final String name;
  final String examId;
  final String subjectName;
  final UserProfile prof;
  _NewClass(this.name, this.examId, this.subjectName, this.prof);
}

class _NewClassDialog extends StatefulWidget {
  final _AdminData data;
  const _NewClassDialog({required this.data});

  @override
  State<_NewClassDialog> createState() => _NewClassDialogState();
}

class _NewClassDialogState extends State<_NewClassDialog> {
  final _name = TextEditingController();
  String? _examId;
  String? _subject;
  String? _profUid;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Subject> get _subjects => widget.data.subjects[_examId] ?? const [];

  /// Profs de cette matière (et de ce niveau) d'abord.
  List<UserProfile> get _profs {
    final k = _subject == null ? '' : subjectKey(_subject!);
    bool fits(UserProfile p) =>
        p.profSubjects.contains(k) && (p.profExams.isEmpty || p.profExams.contains(_examId));
    final list = [...widget.data.profs];
    list.sort((a, b) => fits(a) == fits(b) ? a.name.compareTo(b.name) : (fits(a) ? -1 : 1));
    return list;
  }

  bool get _valid => _name.text.trim().isNotEmpty && _examId != null && _subject != null && _profUid != null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nouvelle classe', style: titleStyle(20)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nom (ex. 6e B)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _examId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Niveau'),
            items: [
              for (final e in widget.data.exams) DropdownMenuItem(value: e.id, child: Text(e.name)),
            ],
            onChanged: (v) => setState(() {
              _examId = v;
              _subject = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(_examId),
            value: _subject,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: 'Matière', helperText: _examId == null ? 'Choisis d\'abord le niveau.' : null),
            items: [
              for (final s in _subjects)
                DropdownMenuItem(value: s.name, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _examId == null ? null : (v) => setState(() => _subject = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _profUid,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Prof'),
            items: [
              for (final p in _profs)
                DropdownMenuItem(
                    value: p.uid,
                    child: Text(p.isAdmin ? '${p.name} (admin)' : p.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _profUid = v),
          ),
          const SizedBox(height: 10),
          Text('Un code est créé tout seul. Tu le donnes aux élèves.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(
                  context,
                  _NewClass(_name.text.trim(), _examId!, _subject!,
                      widget.data.profs.firstWhere((p) => p.uid == _profUid)))
              : null,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
