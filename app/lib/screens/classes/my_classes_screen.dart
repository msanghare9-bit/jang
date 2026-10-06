import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes classes')),
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
                message: 'C\'est l\'admin qui crée les classes. Demande-lui de t\'en donner une.',
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
