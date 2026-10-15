import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/class_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'classes/class_screen.dart';
import 'classes/my_classes_screen.dart';
import 'classes/teacher_course_screen.dart';
import 'inbox_screen.dart';
import 'jang_courses_screen.dart';
import 'lesson_library_screen.dart';
import 'match/tournament_screen.dart';
import 'teacher_resources_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboarding());
  }

  Future<void> _maybeShowOnboarding() async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'prof_onboarding_seen_${p.uid}';
    if (prefs.getBool(key) ?? false) return;
    await prefs.setBool(key, true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Bienvenue sur Jàng, ${p.name.split(' ').first} !', style: titleStyle(19)),
        content: const SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Voici l\'essentiel pour commencer :'),
            SizedBox(height: 10),
            _OnboardStep(1, 'Créez une classe', 'Onglet « Mes classes » : donnez un nom, choisissez le niveau et la matière. Un code à 6 caractères est généré pour vos élèves.'),
            _OnboardStep(2, 'Partagez le code', 'Donnez ce code à vos élèves : ils l\'entrent dans l\'appli pour rejoindre votre classe.'),
            _OnboardStep(3, 'Ajoutez du contenu', 'Dans votre classe : leçons, QCM, devoirs, ou demandez à Kocc Barma de préparer un cours pour vous.'),
            _OnboardStep(4, 'Suivez vos élèves', 'Le tableau de bord de la classe montre qui avance bien et qui a besoin d\'aide.'),
          ]),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Compris, je commence !')),
        ],
      ),
    );
  }

  void _refresh() {
    if (mounted) setState(() => _classes = _load());
  }

  Future<void> _organizeTournament(List<ClassRoom> classes) async {
    if (classes.isEmpty) {
      showMessage(context, 'Créez d’abord une classe pour inviter vos élèves au tournoi.');
      return;
    }
    var selected = classes.first;
    final room = await showDialog<ClassRoom>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Choisir une classe'),
          content: DropdownButtonFormField<String>(
            value: selected.id,
            decoration: const InputDecoration(labelText: 'Classe participante'),
            items: [
              for (final room in classes)
                DropdownMenuItem(value: room.id, child: Text('${room.name} · ${room.subjectName}')),
            ],
            onChanged: (id) => setDialogState(() => selected = classes.firstWhere((c) => c.id == id)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, selected), child: const Text('Continuer')),
          ],
        ),
      ),
    );
    if (room == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ClassTournamentsScreen(classRoom: room)));
  }

  /// Point d'entrée depuis l'accueil : le professeur choisit d'abord la
  /// classe (le niveau), puis arrive sur l'écran où il indique le thème du
  /// cours à Kocc.
  Future<void> _openCoursePrep(List<ClassRoom> classes) async {
    if (classes.isEmpty) {
      showMessage(context, 'Créez d’abord une classe pour préparer un cours avec Kocc.');
      return;
    }
    if (classes.length == 1) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherCourseScreen(classRoom: classes.first)));
      _refresh();
      return;
    }
    var selected = classes.first;
    final room = await showDialog<ClassRoom>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Pour quelle classe ?'),
          content: DropdownButtonFormField<String>(
            value: selected.id,
            decoration: const InputDecoration(labelText: 'Classe (niveau)'),
            items: [
              for (final room in classes)
                DropdownMenuItem(value: room.id, child: Text('${room.name} · ${room.subjectName}')),
            ],
            onChanged: (id) => setDialogState(() => selected = classes.firstWhere((c) => c.id == id)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, selected), child: const Text('Continuer')),
          ],
        ),
      ),
    );
    if (room == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherCourseScreen(classRoom: room)));
    _refresh();
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
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name.isEmpty ? 'Espace professeur' : 'Bienvenue, $name',
                          style: titleStyle(24, color: Colors.white, weight: 800)),
                      const SizedBox(height: 6),
                      const Text('Retrouvez vos classes, vos élèves et vos cours au même endroit.',
                          style: TextStyle(color: Colors.white)),
                    ])),
                    IconButton(
                    tooltip: 'Messages reçus et envoyés',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: JangColors.snGreen,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const InboxScreen()),
                    ),
                    icon: const Icon(Icons.mail_outline),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _openCoursePrep(classes),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Préparer un cours avec Kocc'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () => _organizeTournament(classes),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Organiser un tournoi avec mes élèves'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JangCoursesScreen()),
                  ),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Cours de Jàng'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LessonLibraryScreen()),
                  ),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Télécharger une fiche de cours'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TeacherResourcesScreen()),
                  ),
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('Ressources et conseils'),
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
                    message: 'Vos classes apparaîtront ici dès qu’elles seront associées à votre compte professeur.',
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
                            label: const Text('Demander un cours complet à Kocc'),
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

/// Une étape du guide d'accueil des nouveaux profs.
class _OnboardStep extends StatelessWidget {
  final int n;
  final String title;
  final String text;
  const _OnboardStep(this.n, this.title, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: JangColors.snGreen,
          child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(text, style: const TextStyle(fontSize: 13.5)),
          ]),
        ),
      ]),
    );
  }
}
