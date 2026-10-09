import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/jang_ui.dart';
import 'class_screen.dart';
import 'class_widgets.dart';

/// Les classes du prof connecté.
class MyClassesScreen extends StatefulWidget {
  const MyClassesScreen({super.key});

  @override
  State<MyClassesScreen> createState() => _MyClassesScreenState();
}

class _MyClassesScreenState extends State<MyClassesScreen> {
  late Future<(List<ClassRoom>, Map<String, String>)> _future = _load();

  @override
  void initState() {
    super.initState();
    ClassService.instance.revision.addListener(_reload);
  }

  @override
  void dispose() {
    ClassService.instance.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<(List<ClassRoom>, Map<String, String>)> _load() async {
    final me = AuthService.instance.profile.value;
    if (me == null) return (const <ClassRoom>[], const <String, String>{});
    final r = await Future.wait([ClassService.instance.ofProf(me.uid), examNames()]);
    return (r[0] as List<ClassRoom>, r[1] as Map<String, String>);
  }

  Future<void> _createClass() async {
    final me = AuthService.instance.profile.value;
    if (me == null || !me.isProf) return;
    final exams = await ContentRepo.instance.exams();
    if (!mounted) return;
    final result = await showDialog<(String, String, String)?>(
      context: context,
      builder: (_) => _CreateClassDialog(exams: exams, subjects: me.profSubjects),
    );
    if (result == null) return;
    try {
      await ClassService.instance.create(
        name: result.$1,
        examId: result.$2,
        subjectName: result.$3,
        profUid: me.uid,
        profName: me.name,
        school: me.school,
      );
      _reload();
      if (mounted) showMessage(context, 'La classe a été créée. Donne son code aux élèves.');
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible de créer la classe. Vérifie ta connexion.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes classes'),
        actions: [
          if (AuthService.instance.profile.value?.isProf == true)
            IconButton(tooltip: 'Ajouter une classe', onPressed: _createClass, icon: const Icon(Icons.add)),
        ],
      ),
      body: FutureBuilder<(List<ClassRoom>, Map<String, String>)>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return loadError(_reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (classes, exams) = snap.data!;
          if (classes.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.school_outlined,
                title: 'Pas encore de classe',
                message: 'Crée ta première classe avec le bouton + en haut de l’écran.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text('Touche une classe pour voir tes élèves, tes contenus et les devoirs.', style: t.bodySmall),
                const SizedBox(height: 10),
                for (final c in classes)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      minVerticalPadding: 12,
                      leading: CircleAvatar(
                        backgroundColor: JangColors.noteBg,
                        child: Text(subjectEmoji(c.subjectName)),
                      ),
                      title: Text(c.name, style: titleStyle(18)),
                      subtitle: Text(
                        [if (exams[c.examId] != null) exams[c.examId]!, c.subjectName, plural(c.students.length, 'élève')]
                            .join(' · '),
                        style: t.bodySmall,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ClassScreen(classRoom: c))),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CreateClassDialog extends StatefulWidget {
  final List<Exam> exams;
  final List<String> subjects;
  const _CreateClassDialog({required this.exams, required this.subjects});

  @override
  State<_CreateClassDialog> createState() => _CreateClassDialogState();
}

class _CreateClassDialogState extends State<_CreateClassDialog> {
  final _name = TextEditingController();
  String? _examId;
  String? _subject;

  @override
  void initState() {
    super.initState();
    _examId = widget.exams.firstOrNull?.id;
    _subject = widget.subjects.firstOrNull;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ajouter une classe'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nom de la classe', hintText: 'Ex. 6e A'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: widget.exams.any((e) => e.id == _examId) ? _examId : null,
            decoration: const InputDecoration(labelText: 'Niveau scolaire'),
            items: [for (final e in widget.exams) DropdownMenuItem(value: e.id, child: Text(e.name))],
            onChanged: (v) => setState(() => _examId = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: widget.subjects.contains(_subject) ? _subject : null,
            decoration: const InputDecoration(labelText: 'Matière'),
            items: [for (final s in widget.subjects) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (v) => setState(() => _subject = v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: _name.text.trim().isEmpty || _examId == null || _subject == null
                ? null
                : () => Navigator.pop(context, (_name.text.trim(), _examId!, _subject!)),
            child: const Text('Créer'),
          ),
        ],
      );
}
