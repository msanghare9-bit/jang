import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../services/progress_repo.dart';
import '../services/stats_service.dart';
import '../services/github_service.dart';
import '../theme.dart';
import '../widgets/cheer.dart';
import '../widgets/common.dart';
import '../widgets/engagement.dart';
import '../services/engagement_service.dart';
import 'admin/admin_home.dart';
import 'profile_screen.dart';
import 'progress_screen.dart';
import 'subject_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _autoSync();
    final p = AuthService.instance.profile.value;
    if (p != null) StatsService.instance.recordActive(p);
    _checkUpdate();
    EngagementService.instance.newBadge.addListener(_onBadge);
  }

  @override
  void dispose() {
    EngagementService.instance.newBadge.removeListener(_onBadge);
    super.dispose();
  }

  void _onBadge() {
    final b = EngagementService.instance.newBadge.value;
    if (b == null || !mounted) return;
    EngagementService.instance.newBadge.value = null;
    showBadgeDialog(context, b);
  }

  Future<void> _checkUpdate() async {
    final r = await GithubService.instance.newerVersion();
    if (r == null || !mounted) return;
    await showUpdateDialog(context, r);
  }

  Future<void> _autoSync() async {
    final r = await ContentRepo.instance.sync(minInterval: const Duration(minutes: 30));
    if (!mounted) return;
    if (r.ok && r.changed > 0 && !r.skipped) {
      showMessage(context, 'Contenu mis à jour.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = AuthService.instance.profile.value!;
    final admin = profile.isAdmin;
    final pages = <Widget>[
      const SubjectsTab(),
      const ProgressScreen(),
      if (admin) const AdminHome(),
      const ProfileScreen(),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
          icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Matières'),
      const NavigationDestination(
          icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progrès'),
      if (admin)
        const NavigationDestination(
            icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: 'Gestion'),
      const NavigationDestination(
          icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
    ];
    final index = _tab.clamp(0, pages.length - 1);
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: destinations,
      ),
    );
  }
}

/// Onglet « Matières » : les matières du niveau choisi par l'élève.
class SubjectsTab extends StatefulWidget {
  const SubjectsTab({super.key});

  @override
  State<SubjectsTab> createState() => _SubjectsTabState();
}

class _SubjectsTabState extends State<SubjectsTab> {
  late Future<_SubjectsData> _future;
  late final String _welcome = Cheer.welcome(_firstName(), EngagementService.instance.streak);

  @override
  void initState() {
    super.initState();
    _future = _load();
    ContentRepo.instance.revision.addListener(_reload);
    AuthService.instance.profile.addListener(_reload);
  }

  @override
  void dispose() {
    ContentRepo.instance.revision.removeListener(_reload);
    AuthService.instance.profile.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<_SubjectsData> _load() async {
    final repo = ContentRepo.instance;
    final profile = AuthService.instance.profile.value;
    final exams = await repo.exams();
    var examId = profile?.examId ?? '';
    if (exams.isNotEmpty && !exams.any((e) => e.id == examId)) {
      if (exams.length == 1) {
        examId = exams.first.id;
        AuthService.instance.updateExam(examId);
      } else {
        return _SubjectsData(exams: exams, exam: null, subjects: const [], lessons: const []);
      }
    }
    final exam = exams.where((e) => e.id == examId).firstOrNull;
    if (exam == null) {
      return _SubjectsData(exams: exams, exam: null, subjects: const [], lessons: const []);
    }
    final subjects = await repo.subjects(exam.id);
    final lessons = await repo.lessonsOfExam(exam.id);
    return _SubjectsData(exams: exams, exam: exam, subjects: subjects, lessons: lessons);
  }

  Future<void> _refresh() async {
    final r = await ContentRepo.instance.sync();
    if (!mounted) return;
    if (!r.ok) {
      showMessage(context, 'Pas de connexion : le contenu déjà téléchargé reste disponible.');
    } else {
      showMessage(context, r.changed == 0 ? 'Tout est à jour.' : 'Contenu mis à jour.');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_SubjectsData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final data = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              children: [
                Text('Bonjour ${_firstName()}', style: titleStyle(26)),
                const SizedBox(height: 4),
                Text(_welcome, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: JangColors.primary)),
                const SizedBox(height: 2),
                Text(
                  data.exam == null ? 'Choisis ton niveau pour commencer.' : 'Niveau : ${data.exam!.name}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge!
                      .copyWith(color: JangColors.textSecondary),
                ),
                const SizedBox(height: 8),
                const _SyncStatus(),
                const SizedBox(height: 12),
                if (data.exam != null) ...[
                  const ReviewCard(),
                  const WeekGoalCard(),
                  const SizedBox(height: 8),
                ],
                if (data.exams.isEmpty)
                  EmptyState(
                    icon: Icons.cloud_download_outlined,
                    title: 'Aucun contenu sur ce téléphone',
                    message:
                        'Connecte-toi à internet puis appuie sur « Télécharger » pour récupérer les leçons.',
                    action: FilledButton(onPressed: _refresh, child: const Text('Télécharger')),
                  )
                else if (data.exam == null)
                  ...data.exams.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: OutlinedButton(
                          onPressed: () => AuthService.instance.updateExam(e.id),
                          child: Text(e.name),
                        ),
                      ))
                else if (data.subjects.isEmpty)
                  const EmptyState(
                      icon: Icons.hourglass_empty,
                      title: 'Pas encore de matière',
                      message: 'Les matières apparaîtront ici dès qu\'elles seront publiées.')
                else
                  ...data.subjects.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SubjectCard(
                          subject: s,
                          lessons: data.lessons.where((l) => l.subjectId == s.id).toList(),
                        ),
                      )),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => shareApp(context),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Partager Jàng avec un ami'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _firstName() {
    final n = AuthService.instance.profile.value?.name.trim() ?? '';
    return n.isEmpty ? '' : n.split(' ').first;
  }
}

class _SubjectsData {
  final List<Exam> exams;
  final Exam? exam;
  final List<Subject> subjects;
  final List<Lesson> lessons;
  _SubjectsData({required this.exams, required this.exam, required this.subjects, required this.lessons});
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ContentRepo.instance.syncing,
      builder: (context, syncing, _) {
        final style = Theme.of(context).textTheme.bodySmall;
        if (syncing) {
          return Row(children: [
            const SizedBox(
                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('Recherche de nouveaux contenus…', style: style),
          ]);
        }
        final last = ContentRepo.instance.lastSyncAt;
        if (last == null) return const SizedBox.shrink();
        return Text('Dernière mise à jour : ${formatDate(last)}. Tire vers le bas pour actualiser.',
            style: style);
      },
    );
  }
}

String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} à ${two(d.hour)}h${two(d.minute)}';
}

class _SubjectCard extends StatelessWidget {
  final Subject subject;
  final List<Lesson> lessons;
  const _SubjectCard({required this.subject, required this.lessons});

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(subject.color);
    return ValueListenableBuilder(
      valueListenable: ProgressRepo.instance.revision,
      builder: (context, _, __) {
        final done = lessons.where((l) => ProgressRepo.instance.of(l.id)?.quizDone == true).length;
        final total = lessons.length;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => SubjectScreen(subject: subject))),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 8, color: color),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subject.name, style: titleStyle(21, color: color)),
                          const SizedBox(height: 6),
                          Text(
                            total == 0
                                ? 'Aucune leçon pour le moment'
                                : '$done / $total leçon${total > 1 ? 's' : ''} avec QCM fait',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (total > 0) ...[
                            const SizedBox(height: 10),
                            ProgressBar(value: done / total, color: color),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(Icons.chevron_right, color: JangColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showUpdateDialog(BuildContext context, ReleaseInfo r) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Nouvelle version', style: titleStyle(20)),
      content: Text(
          '${r.name.isEmpty ? 'Une nouvelle version' : r.name} est disponible. '
          'Appuie sur « Installer » : le fichier se télécharge, puis ouvre-le pour mettre à jour. '
          'Ta progression est conservée.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Plus tard')),
        FilledButton(
          onPressed: () {
            Navigator.pop(c);
            openLink(GithubService.apkUrl);
          },
          child: const Text('Installer'),
        ),
      ],
    ),
  );
}
