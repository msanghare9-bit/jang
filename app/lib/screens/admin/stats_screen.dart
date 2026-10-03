import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../services/github_service.dart';
import '../../services/stats_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'students_screen.dart';

/// Tableau de bord du responsable : téléchargements, comptes, activité, résultats.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<_Stats> _future = _load();
  final _db = FirebaseFirestore.instance;

  Future<int> _count(Query<Map<String, dynamic>> q) async {
    try {
      final s = await q.count().get();
      return s.count ?? 0;
    } catch (_) {
      return -1;
    }
  }

  Future<_Stats> _load() async {
    final now = DateTime.now();
    String day(int back) => StatsService.dayKey(now.subtract(Duration(days: back)));
    final users = _db.collection('users');

    final releasesF = GithubService.instance.releases().then<List<ReleaseInfo>?>((r) => r).catchError((_) => null);
    final studentsF = _count(users.where('role', isEqualTo: 'student'));
    final newWeekF = _count(users.where('createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(now.subtract(const Duration(days: 7)))));
    final todayF = _count(users.where('lastActiveDay', isGreaterThanOrEqualTo: day(0)));
    final weekF = _count(users.where('lastActiveDay', isGreaterThanOrEqualTo: day(6)));
    final monthF = _count(users.where('lastActiveDay', isGreaterThanOrEqualTo: day(29)));

    List<QueryDocumentSnapshot<Map<String, dynamic>>> days = const [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> lessonStats = const [];
    var ok = true;
    String? error;
    try {
      // Tri croissant sur l'identifiant (date) : aucun index spécial n'est nécessaire.
      days = (await _db
              .collection('statsDays')
              .where(FieldPath.documentId, isGreaterThanOrEqualTo: day(29))
              .get(const GetOptions(source: Source.server)))
          .docs;
    } catch (e) {
      error = '$e';
    }
    try {
      lessonStats =
          (await _db.collection('statsLessons').get(const GetOptions(source: Source.server))).docs;
    } catch (e) {
      error ??= '$e';
    }
    if (error != null && days.isEmpty && lessonStats.isEmpty) ok = false;
    if (error != null) debugPrint('Statistiques : $error');

    final repo = ContentRepo.instance;
    final exams = await repo.exams();
    final subjects = <Subject>[];
    final lessons = <Lesson>[];
    for (final e in exams) {
      subjects.addAll(await repo.subjects(e.id));
      lessons.addAll(await repo.lessonsOfExam(e.id));
    }

    return _Stats(
      online: ok,
      error: error,
      releases: await releasesF,
      students: await studentsF,
      newWeek: await newWeekF,
      activeToday: await todayF,
      activeWeek: await weekF,
      activeMonth: await monthF,
      days: {for (final d in days) d.id: d.data()},
      lessonStats: {for (final d in lessonStats) d.id: d.data()},
      subjects: subjects,
      lessons: lessons,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiques'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => setState(() => _future = _load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_Stats>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final s = snap.data!;
          final t = Theme.of(context).textTheme;
          if (!s.online) {
            final offline = (s.error ?? '').contains('unavailable');
            return Center(
              child: EmptyState(
                icon: offline ? Icons.cloud_off : Icons.error_outline,
                title: offline ? 'Pas de connexion' : 'Statistiques indisponibles',
                message: offline
                    ? 'Les statistiques ont besoin d\'internet. Réessaie une fois connecté.'
                    : 'Détail technique : ${s.error}',
                action: OutlinedButton(
                  onPressed: () => setState(() => _future = _load()),
                  child: const Text('Réessayer'),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ---------- Téléchargements ----------
              const SectionTitle('Téléchargements de l\'application'),
              if (s.releases == null)
                Text('Impossible de joindre GitHub pour le moment.', style: t.bodySmall)
              else ...[
                Row(children: [
                  Expanded(
                      child: StatTile(
                          value: '${s.releases!.fold<int>(0, (a, r) => a + r.downloads)}',
                          label: 'téléchargements au total')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatTile(
                          value: '${s.releases!.isEmpty ? 0 : s.releases!.first.downloads}',
                          label: 'de la dernière version')),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Compte les téléchargements par le lien. Un APK partagé par Bluetooth ou WhatsApp '
                  'n\'est pas compté : le nombre de comptes est plus fiable.',
                  style: t.bodySmall,
                ),
                if (s.releases!.length > 1)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Détail par version', style: t.titleSmall),
                    children: s.releases!
                        .map((r) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(r.name),
                              trailing: Text('${r.downloads}', style: t.titleSmall),
                            ))
                        .toList(),
                  ),
              ],

              // ---------- Élèves ----------
              const SectionTitle('Élèves'),
              Row(children: [
                Expanded(child: StatTile(value: _n(s.students), label: 'comptes élèves')),
                const SizedBox(width: 10),
                Expanded(child: StatTile(value: _n(s.newWeek), label: 'nouveaux (7 jours)')),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: StatTile(value: _n(s.activeToday), label: 'actifs aujourd\'hui')),
                const SizedBox(width: 10),
                Expanded(child: StatTile(value: _n(s.activeWeek), label: 'actifs (7 jours)')),
                const SizedBox(width: 10),
                Expanded(child: StatTile(value: _n(s.activeMonth), label: 'actifs (30 jours)')),
              ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const StudentsScreen())),
                icon: const Icon(Icons.people_outline),
                label: const Text('Voir la liste des élèves'),
              ),

              // ---------- Activité ----------
              const SectionTitle('Activité des 30 derniers jours'),
              _DailyChart(days: s.days),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: StatTile(
                        value: '${_sumDays(s.days, 'lessonViews')}', label: 'leçons ouvertes')),
                const SizedBox(width: 10),
                Expanded(child: StatTile(value: '${_sumDays(s.days, 'quizzes')}', label: 'Exercices faits')),
              ]),

              // ---------- Par matière ----------
              const SectionTitle('Par matière'),
              if (s.subjects.isEmpty) Text('Aucune matière.', style: t.bodySmall),
              for (final sub in s.subjects) _SubjectStats(subject: sub, stats: s),
            ],
          );
        },
      ),
    );
  }

  static String _n(int v) => v < 0 ? '–' : '$v';

  static int _sumDays(Map<String, Map<String, dynamic>> days, String key) =>
      days.values.fold<int>(0, (a, d) => a + ((d[key] as num?)?.toInt() ?? 0));
}

class _Stats {
  final bool online;
  final String? error;
  final List<ReleaseInfo>? releases;
  final int students, newWeek, activeToday, activeWeek, activeMonth;
  final Map<String, Map<String, dynamic>> days;
  final Map<String, Map<String, dynamic>> lessonStats;
  final List<Subject> subjects;
  final List<Lesson> lessons;
  _Stats({
    required this.online,
    this.error,
    required this.releases,
    required this.students,
    required this.newWeek,
    required this.activeToday,
    required this.activeWeek,
    required this.activeMonth,
    required this.days,
    required this.lessonStats,
    required this.subjects,
    required this.lessons,
  });
}

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const StatTile({super.key, required this.value, required this.label, this.color = JangColors.primary});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(children: [
          Text(value, style: titleStyle(24, color: color)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

/// Barres : élèves actifs par jour sur 30 jours.
class _DailyChart extends StatelessWidget {
  final Map<String, Map<String, dynamic>> days;
  const _DailyChart({required this.days});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final keys = [for (var i = 29; i >= 0; i--) StatsService.dayKey(now.subtract(Duration(days: i)))];
    final values = [for (final k in keys) _i(days[k]?['activeUsers'])];
    final maxV = values.fold<int>(0, (a, b) => b > a ? b : a);
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Élèves actifs par jour (maximum : $maxV)', style: t.bodySmall),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: Tooltip(
                        message: '${keys[i].substring(8)}/${keys[i].substring(5, 7)} : ${values[i]}',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          height: maxV == 0 ? 2 : 2 + 108 * values[i] / maxV,
                          decoration: BoxDecoration(
                            color: i == values.length - 1
                                ? JangColors.primary
                                : JangColors.primary.withValues(alpha: 0.45),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('il y a 30 jours', style: t.bodySmall),
                Text('aujourd\'hui', style: t.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectStats extends StatelessWidget {
  final Subject subject;
  final _Stats stats;
  const _SubjectStats({required this.subject, required this.stats});

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(subject.color);
    final lessons = stats.lessons.where((l) => l.subjectId == subject.id).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    var views = 0, attempts = 0, sumPct = 0, likes = 0, dislikes = 0;
    for (final l in lessons) {
      final d = stats.lessonStats[l.id];
      if (d == null) continue;
      likes += _i(d['likes']);
      dislikes += _i(d['dislikes']);
      views += _i(d['views']);
      attempts += _i(d['attempts']);
      sumPct += _i(d['sumPct']);
    }
    final avg = attempts == 0 ? null : (sumPct / attempts).round();
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          shape: const Border(),
          title: Text(subject.name, style: titleStyle(18, color: color)),
          subtitle: Text(
            '$views ouverture${views > 1 ? 's' : ''} de leçon · $attempts exercices'
            '${avg == null ? '' : ' · moyenne $avg %'}'
            '${likes + dislikes == 0 ? '' : ' · $likes j\'aime, $dislikes je n\'aime pas'}',
            style: t.bodySmall,
          ),
          children: [
            if (lessons.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Aucune leçon.', style: t.bodySmall)),
            for (final l in lessons) _lessonRow(context, l, color),
          ],
        ),
      ),
    );
  }

  Widget _lessonRow(BuildContext context, Lesson l, Color color) {
    final d = stats.lessonStats[l.id] ?? const {};
    final attempts = _i(d['attempts']);
    final avg = attempts == 0 ? null : (_i(d['sumPct']) / attempts).round();
    final t = Theme.of(context).textTheme;
    return ListTile(
      title: Text(l.title, style: t.titleSmall),
      subtitle: Text(
        '${_i(d['views'])} élève(s) l\'ont ouverte · ${_i(d['quizUsers'])} ont fait les exercices'
        '${avg == null ? '' : ' · moyenne $avg %'}'
        '${_i(d['likes']) + _i(d['dislikes']) == 0 ? '' : ' · ${_i(d['likes'])} j\'aime, ${_i(d['dislikes'])} je n\'aime pas'}',
        style: t.bodySmall,
      ),
      trailing: avg == null
          ? null
          : Pill('$avg %',
              color: avg >= 50 ? JangColors.success : JangColors.error,
              background: avg >= 50 ? JangColors.successBg : JangColors.errorBg),
      onTap: l.quiz.isEmpty
          ? null
          : () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => _LessonStatsScreen(lesson: l, data: d, color: color))),
    );
  }
}

/// Réussite question par question d'un QCM.
class _LessonStatsScreen extends StatelessWidget {
  final Lesson lesson;
  final Map<String, dynamic> data;
  final Color color;
  const _LessonStatsScreen({required this.lesson, required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final qs = (data['questions'] is Map) ? data['questions'] as Map : const {};
    final firstUsers = _i(data['quizUsers']);
    final firstAvg = firstUsers == 0 ? null : (_i(data['sumFirstPct']) / firstUsers).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Résultats des exercices')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(lesson.title, style: titleStyle(22)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: StatTile(value: '${_i(data['quizUsers'])}', label: 'élèves', color: color)),
            const SizedBox(width: 10),
            Expanded(child: StatTile(value: '${_i(data['attempts'])}', label: 'tentatives', color: color)),
            const SizedBox(width: 10),
            Expanded(
                child: StatTile(
                    value: firstAvg == null ? '–' : '$firstAvg %',
                    label: '1re tentative',
                    color: color)),
          ]),
          const SectionTitle('Réussite par question'),
          Text('Pourcentage de bonnes réponses, toutes tentatives confondues. '
              'Les questions les moins réussies signalent les notions à reprendre.',
              style: t.bodySmall),
          const SizedBox(height: 10),
          for (var i = 0; i < lesson.quiz.length; i++)
            _question(context, i, qs[StatsService.questionKey(lesson.quiz[i].question)]),
        ],
      ),
    );
  }

  Widget _question(BuildContext context, int i, dynamic q) {
    final n = q is Map ? _i(q['n']) : 0;
    final ok = q is Map ? _i(q['ok']) : 0;
    final pct = n == 0 ? null : (ok * 100 / n).round();
    final c = pct == null
        ? JangColors.textSecondary
        : (pct >= 70 ? JangColors.success : (pct >= 50 ? const Color(0xFF9A5A00) : JangColors.error));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${i + 1}. ${lesson.quiz[i].question}',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: ProgressBar(value: pct == null ? 0 : pct / 100, color: c)),
                const SizedBox(width: 10),
                Text(pct == null ? 'pas encore de réponse' : '$pct % ($ok/$n)',
                    style: TextStyle(color: c, fontWeight: FontWeight.w700)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
