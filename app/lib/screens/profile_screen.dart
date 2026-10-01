import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../services/github_service.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets/common.dart';
import '../widgets/engagement.dart';
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
              const SizedBox(height: 14),
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
              Text('Les leçons et les QCM téléchargés restent disponibles sans internet.',
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
