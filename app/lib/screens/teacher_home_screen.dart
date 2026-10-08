import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/class_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'classes/class_screen.dart';
import 'classes/my_classes_screen.dart';
import 'classes/teacher_course_screen.dart';
import 'inbox_screen.dart';

/// Home page for teacher accounts.
class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  late Future<List<ClassRoom>> _classes = _load();

  Future<List<ClassRoom>> _load() {
    final p = AuthService.instance.profile.value;
    return p == null ? Future.value(const <ClassRoom>[]) : ClassService.instance.ofProf(p.uid);
  }

  void _refresh() {
    if (mounted) setState(() => _classes = _load());
  }

  @override
  Widget build(BuildContext context) {
    final profile = AuthService.instance.profile.value;
    final name = profile?.firstName ?? '';
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<ClassRoom>>(
          future: _classes,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final classes = snap.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: JangColors.snGreen,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.isEmpty ? 'Espace professeur' : 'Bonjour, $name',
                        style: titleStyle(24, color: Colors.white, weight: 800)),
                    const SizedBox(height: 6),
                    const Text('Tes classes, tes élèves et tes cours au même endroit.',
                        style: TextStyle(color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InboxScreen()),
                  ),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Messages reçus et envoyés'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('Mes classes', style: titleStyle(21, weight: 800))),
                  TextButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MyClassesScreen()),
                      );
                      _refresh();
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Tout voir'),
                  ),
                ]),
                if (classes.isEmpty)
                  const EmptyState(
                    icon: Icons.school_outlined,
                    title: 'Aucune classe attribuée',
                    message: 'Tes classes apparaîtront ici dès qu’elles seront associées à ton compte professeur.',
                  )
                else
                  for (final c in classes)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                              backgroundColor: JangColors.successBg,
                              child: Icon(Icons.school_outlined, color: JangColors.snGreen),
                            ),
                            title: Text(c.name, style: titleStyle(18, weight: 800)),
                            subtitle: Text('${c.subjectName} · ${c.students.length} élèves'),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ClassScreen(classRoom: c)),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => TeacherCourseScreen(classRoom: c)),
                              );
                              _refresh();
                            },
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('Kocc prépare un cours pour cette classe'),
                          ),
                        ]),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
