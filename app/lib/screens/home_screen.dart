import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../services/progress_repo.dart';
import '../services/stats_service.dart';
import '../services/github_service.dart';
import '../theme.dart';
import '../widgets/characters.dart';
import '../widgets/cheer.dart';
import '../widgets/fun.dart';
import '../widgets/moonwalk.dart';
import '../widgets/common.dart';
import '../widgets/engagement.dart';
import '../widgets/jang_ui.dart';
import '../services/engagement_service.dart';
import 'admin/admin_home.dart';
import 'profile_screen.dart';
import 'progress_screen.dart';
import 'sheep_screen.dart';
import 'inbox_screen.dart';
import '../services/home_config_service.dart';
import '../services/push_service.dart';
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
    PushService.instance.opened.addListener(_onPush);
    if (p != null) PushService.instance.start(p);
  }

  void _onPush() {
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxScreen()));
  }

  @override
  void dispose() {
    EngagementService.instance.newBadge.removeListener(_onBadge);
    PushService.instance.opened.removeListener(_onPush);
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
    final admin = profile.isStaff;
    final pages = <Widget>[
      const SubjectsTab(),
      const ProgressScreen(),
      if (admin) const AdminHome(),
      const ProfileScreen(),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
          icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Accueil'),
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
  late String _welcome = Cheer.welcome(_firstName(), EngagementService.instance.streak);
  late (String, String, bool) _tip = _tips[DateTime.now().hour % _tips.length];
  HomeConfig _config = HomeConfig();

  static const _tips = <(String, String, bool)>[
    ('awa', 'Salut ! Une petite leçon aujourd\'hui ? Diambar nga, tu peux le faire !', true),
    ('modou', 'Ma pirogue attend tes bonnes réponses pour partir à la pêche. Boul bayi !', false),
    ('doudou', 'Mon tama est prêt 🥁 Fais 8/10 et je joue rien que pour toi !', true),
    ('kocc', 'C\'est moi, Kocc Barma ! J\'ai encore glissé sur une peau de banane… mais je suis là si tu as une question.', false),
    ('gainde', 'MIAOU ! … euh, je voulais dire ROAR ! Viens apprendre avec moi : comprendre nga bou bax !', true),
    ('awa', 'Toutes les 2 missions, un nouvel épisode de « Mon histoire » s\'ouvre. Va voir dans ta matière !', false),
  ];

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
    _applyConfig(await HomeConfigService.instance.forExam(exam.id));
    return _SubjectsData(exams: exams, exam: exam, subjects: subjects, lessons: lessons);
  }

  /// Messages et bulles choisis par l'admin (sinon, ceux de l'app).
  void _applyConfig(HomeConfig c) {
    _config = c;
    if (c.welcome.isNotEmpty) {
      _welcome = HomeConfigService.fill(
          HomeConfigService.pick(c.welcome), _firstName(), EngagementService.instance.streak);
    }
    if (c.tips.isNotEmpty) {
      final t = HomeConfigService.pick(c.tips);
      _tip = (t.id, HomeConfigService.fill(t.text, _firstName(), EngagementService.instance.streak),
          DateTime.now().second.isEven);
    }
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
    final top = MediaQuery.of(context).padding.top;
    return FutureBuilder<_SubjectsData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        final name = _firstName();
        return Stack(children: [
          RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              WaxHeader(
                color: JangColors.primary,
                padding: EdgeInsets.fromLTRB(20, top + 12, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (data.exam != null) Chip2(data.exam!.name),
                      const Spacer(),
                      ValueListenableBuilder(
                        valueListenable: EngagementService.instance.revision,
                        builder: (context, _, __) =>
                            Chip2('🔥 ${EngagementService.instance.streak} j'),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name.isEmpty ? 'Na nga def ?' : 'Na nga def, $name ?',
                              style: titleStyle(30, color: Colors.white, weight: 800)),
                          const SizedBox(height: 2),
                          Text(_welcome,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        ]),
                      ),
                      const CharacterView(Chars.lion, size: 96, moves: Moves.dance),
                    ]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SyncStatus(),
                    const SizedBox(height: 4),
                    const InboxCard(),
                    if (_config.show('banniere') && (_config.banner?.active ?? false))
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: JangColors.warningBg,
                          border: Border.all(color: JangColors.ocre, width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(_config.banner!.text,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    CharacterSays(_tip.$1, _tip.$2, right: _tip.$3),
                    const SizedBox(height: 4),
                    if (data.exam != null) ...[
                      if (_config.show('mouton')) ...[
                        const SheepCard(),
                        const SizedBox(height: 10),
                      ],
                      if (_config.show('revisions')) ...[
                        const ReviewCard(),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (data.exams.isEmpty)
                      EmptyState(
                        icon: Icons.cloud_download_outlined,
                        title: 'Aucun contenu sur ce téléphone',
                        message:
                            'Connecte-toi à internet puis appuie sur « Télécharger » pour récupérer les leçons.',
                        action: ChunkyButton(label: 'Télécharger', onPressed: _refresh),
                      )
                    else if (data.exam == null) ...[
                      Text('Choisis ton niveau', style: titleStyle(22, weight: 800)),
                      const SizedBox(height: 10),
                      ...data.exams.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ChunkyButton(
                              label: e.name,
                              color: JangColors.primary,
                              onPressed: () => AuthService.instance.updateExam(e.id),
                            ),
                          )),
                    ] else if (data.subjects.isEmpty)
                      const EmptyState(
                          icon: Icons.hourglass_empty,
                          title: 'Pas encore de matière',
                          message: 'Les matières apparaîtront ici dès qu\'elles seront publiées.')
                    else ...[
                      Text('Mes matières', style: titleStyle(22, weight: 800)),
                      const SizedBox(height: 10),
                      ...data.subjects.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _SubjectCard(
                              subject: s,
                              lessons: data.lessons.where((l) => l.subjectId == s.id).toList(),
                            ),
                          )),
                    ],
                    if (data.exam != null && _config.show('objectif')) ...[
                      const SizedBox(height: 4),
                      const WeekGoalCard(),
                    ],
                    const SizedBox(height: 14),
                    ChunkyButton(
                      label: 'Partager Jàng avec un ami',
                      icon: Icons.share_outlined,
                      outlined: true,
                      color: JangColors.primary,
                      onPressed: () => shareApp(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
          GaindeMoonwalk(name: name),
        ]);
      },
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
    final fg = JangColors.on(color);
    return ValueListenableBuilder(
      valueListenable: ProgressRepo.instance.revision,
      builder: (context, _, __) {
        final done = lessons.where((l) => ProgressRepo.instance.of(l.id)?.seen == true).length;
        final total = lessons.length;
        final pct = total == 0 ? 0.0 : done / total;
        return GestureDetector(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => SubjectScreen(subject: subject))),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: JangColors.darker(color, 0.15), offset: const Offset(0, 5))],
            ),
            child: Row(
              children: [
                Transform.rotate(
                  angle: -0.1,
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(subjectEmoji(subject.name), style: const TextStyle(fontSize: 30)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subject.name, style: titleStyle(22, color: fg, weight: 800)),
                      Text(
                        total == 0
                            ? 'Bientôt des leçons'
                            : '$total leçon${total > 1 ? 's' : ''} · $done vue${done > 1 ? 's' : ''}',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(alignment: Alignment.center, children: [
                    CircularProgressIndicator(
                      value: pct,
                      strokeWidth: 5,
                      color: fg,
                      backgroundColor: fg.withValues(alpha: 0.25),
                    ),
                    Text('${(pct * 100).round()}%',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
                  ]),
                ),
              ],
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
