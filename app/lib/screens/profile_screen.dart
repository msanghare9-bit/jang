import 'package:flutter/material.dart';

import 'inbox_screen.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/class_service.dart';
import '../services/content_repo.dart';
import '../services/github_service.dart';
import '../services/match_service.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets/class_section.dart' show showJoinClassDialog;
import '../widgets/common.dart';
import '../widgets/contact.dart';
import '../widgets/engagement.dart';
import '../widgets/fun.dart';
import 'home_screen.dart' show formatDate, showUpdateDialog;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<List<Exam>> _exams;

  @override
  void initState() {
    super.initState();
    _exams = ContentRepo.instance.exams();
    ContentRepo.instance.revision.addListener(_reload);
  }

  @override
  void dispose() {
    ContentRepo.instance.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _exams = ContentRepo.instance.exams());
  }

  Future<void> _sync({bool full = false}) async {
    final r = await ContentRepo.instance.sync(full: full);
    if (!mounted) return;
    showMessage(
        context,
        !r.ok
            ? 'Pas de connexion internet. Réessaie plus tard.'
            : (r.changed == 0 ? 'Tout est à jour.' : 'Contenu mis à jour.'));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ValueListenableBuilder<UserProfile?>(
        valueListenable: AuthService.instance.profile,
        builder: (context, p, _) {
          if (p == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              Text('Profil', style: titleStyle(26)),
              const CharacterSays('kocc',
                  'Moi c\'est Kocc Barma, ton prof. Je suis très sérieux… sauf quand je tombe de ma chaise. Change ton niveau ici si besoin !'),
              const SizedBox(height: 6),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.mail_outline, color: JangColors.primaryDark),
                  title: const Text('Mes messages', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Messages de tes profs et annonces'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxScreen())),
                ),
              ),
              const SizedBox(height: 6),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: titleStyle(21)),
                      const SizedBox(height: 4),
                      Text('Identifiant : ${p.username}', style: t.bodyMedium),
                      const SizedBox(height: 4),
                      Text(_roleLabel(p.role), style: t.bodySmall),
                    ],
                  ),
                ),
              ),
              if (!p.isStaff) _MatchSummary(uid: p.uid),
              if (!p.isStaff) _MyClasses(profile: p),
              const SectionTitle('Mon niveau'),
              FutureBuilder<List<Exam>>(
                future: _exams,
                builder: (context, snap) {
                  final exams = snap.data ?? const <Exam>[];
                  if (exams.isEmpty) {
                    return Text('Aucun niveau téléchargé pour le moment.', style: t.bodySmall);
                  }
                  return Column(
                    children: exams
                        .map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                child: ListTile(
                                  minVerticalPadding: 12,
                                  title: Text(e.name, style: t.titleMedium),
                                  trailing: e.id == p.examId
                                      ? const Icon(Icons.check_circle, color: JangColors.primary)
                                      : const Icon(Icons.radio_button_unchecked,
                                          color: JangColors.textSecondary),
                                  onTap: () => AuthService.instance.updateExam(e.id),
                                ),
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
              const SectionTitle('Contenu hors connexion'),
              Text(
                ContentRepo.instance.lastSyncAt == null
                    ? 'Le contenu n\'a pas encore été téléchargé.'
                    : 'Dernière mise à jour : ${formatDate(ContentRepo.instance.lastSyncAt!)}.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text('Les leçons et les exercices téléchargés restent disponibles sans internet.',
                  style: t.bodySmall),
              const SizedBox(height: 12),
              ValueListenableBuilder<bool>(
                valueListenable: ContentRepo.instance.syncing,
                builder: (context, syncing, _) => OutlinedButton.icon(
                  onPressed: syncing ? null : () => _sync(),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(syncing ? 'Mise à jour…' : 'Mettre à jour le contenu'),
                ),
              ),
              const SectionTitle('Application'),
              Text('Version installée : $appVersion ($appBuild)', style: t.bodyMedium),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await GithubService.instance.newerVersion(force: true);
                  if (!context.mounted) return;
                  if (r == null) {
                    showMessage(context, 'Tu as déjà la dernière version (ou pas de connexion).');
                  } else {
                    await showUpdateDialog(context, r);
                  }
                },
                icon: const Icon(Icons.system_update_outlined),
                label: const Text('Rechercher une mise à jour'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => shareApp(context),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Partager l\'application'),
              ),
              const SectionTitle('À propos'),
              Text('Jàng aide les élèves à apprendre leurs leçons, à leur rythme, même sans internet.',
                  style: t.bodyMedium),
              const SizedBox(height: 10),
              Text('Nous contacter', style: t.titleMedium),
              const SizedBox(height: 6),
              ContactCard(canEdit: p.isAdmin),
              const SizedBox(height: 28),
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                onPressed: () async {
                  if (await confirm(context, 'Se déconnecter ?',
                      'Tu devras saisir ton identifiant et ton mot de passe pour revenir.',
                      ok: 'Se déconnecter')) {
                    await AuthService.instance.signOut();
                  }
                },
                child: const Text('Se déconnecter'),
              ),
              const SizedBox(height: 20),
              Center(child: Text('Jàng $appVersion ($appBuild)', style: t.bodySmall)),
            ],
          );
        },
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Responsable';
      case 'teacher':
        return 'Professeur';
      default:
        return 'Élève';
    }
  }
}

/// Carte « Mes classes » de l'élève : ses classes, et le code pour entrer dans une nouvelle classe.
class _MatchSummary extends StatelessWidget {
  final String uid;
  const _MatchSummary({required this.uid});

  @override
  Widget build(BuildContext context) => FutureBuilder<List<(LiveMatch, MatchPlayer, bool)>>(
        future: MatchService.instance.historyFor(uid),
        builder: (context, snap) {
          if (snap.hasError) return const SizedBox.shrink();
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final games = snap.data!;
          final wins = games.where((g) => g.$3).length;
          final losses = games.length - wins;
          final percent = games.isEmpty ? 0 : (wins * 100 / games.length).round();
          final winStreak = games.takeWhile((g) => g.$3).length;
          const ranks = <(String, int)>[
            ('Jàngkat', 0),
            ('Boroom xam-xam', 5),
            ('Jàmbaar', 15),
            ('Njiit', 30),
            ('Damel', 60),
            ('Buur', 100),
          ];
          var rankIndex = 0;
          for (var i = 0; i < ranks.length; i++) {
            if (wins >= ranks[i].$2) rankIndex = i;
          }
          final nextRank = rankIndex + 1 < ranks.length ? ranks[rankIndex + 1] : null;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('Mes matchs'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 20, runSpacing: 12, children: [
                    _ProfileMatchStat(label: 'Joués', value: '${games.length}'),
                    _ProfileMatchStat(label: 'Gagnés', value: '$wins'),
                    _ProfileMatchStat(label: 'Perdus', value: '$losses'),
                    _ProfileMatchStat(label: 'Victoires', value: '$percent %'),
                    _ProfileMatchStat(label: 'Série', value: '$winStreak 🔥'),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: JangColors.successBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Titre : ${ranks[rankIndex].$1}',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: JangColors.successDark)),
                      if (nextRank != null)
                        Text('Encore ${nextRank.$2 - wins} victoire${nextRank.$2 - wins == 1 ? '' : 's'} pour devenir ${nextRank.$1}.'),
                      if (nextRank == null) const Text('Tu as atteint le rang le plus élevé !'),
                    ]),
                  ),
                ]),
              ),
            ),
          ]);
        },
      );
}

class _ProfileMatchStat extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileMatchStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 78,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: titleStyle(19, weight: 800)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

class _MyClasses extends StatelessWidget {
  final UserProfile profile;
  const _MyClasses({required this.profile});

  Future<void> _leave(BuildContext context, ClassRoom c) async {
    if (!await confirm(context, 'Quitter la classe ?',
        'Tu ne verras plus les leçons et les devoirs de ${c.name}. Tu pourras revenir avec le code.',
        ok: 'Quitter')) {
      return;
    }
    try {
      await ClassService.instance.leave(c, profile.uid);
      if (context.mounted) showMessage(context, 'Tu as quitté la classe ${c.name}.');
    } catch (_) {
      if (context.mounted) showMessage(context, 'Pas de connexion internet. Réessaie plus tard.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Mes classes'),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: ValueListenableBuilder<List<ClassRoom>>(
            valueListenable: ClassService.instance.mine,
            builder: (context, classes, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ton prof te donne un code. Une seule classe par matière.', style: t.bodyMedium),
                const SizedBox(height: 8),
                if (classes.isEmpty)
                  Text('Tu n\'es encore dans aucune classe.', style: t.bodySmall)
                else
                  for (final c in classes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        const Icon(Icons.groups_rounded, color: JangColors.primaryDark),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.subjectName.isEmpty ? c.name : '${c.subjectName} · ${c.name}',
                                style: t.titleMedium),
                            if (c.profName.isNotEmpty) Text('Prof : ${c.profName}', style: t.bodySmall),
                          ]),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: JangColors.errorDark),
                          onPressed: () => _leave(context, c),
                          child: const Text('Quitter'),
                        ),
                      ]),
                    ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => showJoinClassDialog(context),
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('Entrer dans une classe'),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

