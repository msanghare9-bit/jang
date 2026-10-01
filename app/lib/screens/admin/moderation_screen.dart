import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../services/discussion_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/discussion.dart' show timeAgo;

/// Questions des élèves à traiter et messages signalés.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  late Future<(List<Comment>, List<Comment>, Map<String, Lesson>)> _future = _load();

  Future<(List<Comment>, List<Comment>, Map<String, Lesson>)> _load() async {
    final s = DiscussionService.instance;
    final open = (await s.unanswered()).where((c) => c.parentId.isEmpty && !c.isStaff).toList();
    final reported = await s.reported();
    final lessons = <String, Lesson>{};
    for (final c in [...open, ...reported]) {
      if (lessons.containsKey(c.lessonId)) continue;
      final l = await ContentRepo.instance.lesson(c.lessonId);
      if (l != null) lessons[c.lessonId] = l;
    }
    return (open, reported, lessons);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _reply(Comment c, Lesson? lesson) async {
    if (lesson == null) {
      showMessage(context, 'Leçon introuvable sur ce téléphone.');
      return;
    }
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Répondre', style: titleStyle(20)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c.name} : ${c.text}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            minLines: 3,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Ta réponse (publique)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('Publier')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.trim().isEmpty) return;
    final err = await DiscussionService.instance.post(lesson, text, parentId: c.id);
    if (!mounted) return;
    showMessage(context, err ?? 'Réponse publiée.');
    _reload();
  }

  Future<void> _block(Comment c) async {
    if (!await confirm(context, 'Bloquer ${c.name} ?',
        'Cet élève ne pourra plus écrire dans les discussions. Tu peux le débloquer depuis sa fiche.',
        ok: 'Bloquer')) {
      return;
    }
    await DiscussionService.instance.setBlocked(c.uid, true);
    if (mounted) showMessage(context, '${c.name} est bloqué.');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Questions des élèves'),
          actions: [
            IconButton(tooltip: 'Actualiser', onPressed: _reload, icon: const Icon(Icons.refresh)),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'À répondre'), Tab(text: 'Signalés')]),
        ),
        body: FutureBuilder<(List<Comment>, List<Comment>, Map<String, Lesson>)>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: EmptyState(
                  icon: Icons.error_outline,
                  title: 'Chargement impossible',
                  message: '${snap.error}',
                  action: OutlinedButton(onPressed: _reload, child: const Text('Réessayer')),
                ),
              );
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (open, reported, lessons) = snap.data!;
            return TabBarView(children: [
              _list(
                open,
                lessons,
                empty: 'Aucune question en attente.',
                actions: (c, l) => [
                  FilledButton(onPressed: () => _reply(c, l), child: const Text('Répondre')),
                  TextButton(
                    onPressed: () async {
                      await DiscussionService.instance.markAnswered(c);
                      _reload();
                    },
                    child: const Text('Ignorer'),
                  ),
                ],
              ),
              _list(
                reported,
                lessons,
                empty: 'Aucun message signalé.',
                actions: (c, l) => [
                  TextButton(
                    onPressed: () async {
                      await DiscussionService.instance.clearReports(c);
                      _reload();
                    },
                    child: const Text('Garder'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await DiscussionService.instance.delete(c);
                      _reload();
                    },
                    child: const Text('Supprimer'),
                  ),
                  TextButton(onPressed: () => _block(c), child: const Text('Bloquer l\'élève')),
                ],
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _list(List<Comment> items, Map<String, Lesson> lessons,
      {required String empty, required List<Widget> Function(Comment, Lesson?) actions}) {
    if (items.isEmpty) {
      return Center(child: EmptyState(icon: Icons.check_circle_outline, title: empty));
    }
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        for (final c in items)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lessons[c.lessonId]?.title ?? 'Leçon supprimée', style: t.bodySmall),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: Text(c.name, style: t.titleSmall)),
                    Text(timeAgo(c.createdAt), style: t.bodySmall),
                  ]),
                  const SizedBox(height: 4),
                  Text(c.text),
                  if (c.reports > 0) ...[
                    const SizedBox(height: 4),
                    Text('${c.reports} signalement${c.reports > 1 ? 's' : ''}',
                        style: t.bodySmall!.copyWith(color: JangColors.error)),
                  ],
                  Wrap(spacing: 4, children: actions(c, lessons[c.lessonId])),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Journal des questions posées au tuteur IA (50 dernières).
class TutorLogsScreen extends StatelessWidget {
  const TutorLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tuteur IA : journal')),
      body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('tutorLogs')
            .orderBy('createdAt', descending: true)
            .limit(50)
            .get(const GetOptions(source: Source.server)),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: EmptyState(
                    icon: Icons.error_outline,
                    title: 'Chargement impossible',
                    message: '${snap.error}'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
                child: EmptyState(
                    icon: Icons.psychology_alt_outlined,
                    title: 'Aucune question pour le moment'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              for (final d in docs)
                Builder(builder: (context) {
                  final m = d.data();
                  final ts = m['createdAt'];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      title: Text('${m['question'] ?? ''}', style: t.titleSmall),
                      subtitle: Text(
                          '${m['name'] ?? ''} · ${m['lessonTitle'] ?? ''} · '
                          '${timeAgo(ts is Timestamp ? ts.toDate() : null)}'
                          '${m['simpler'] == true ? ' · plus simple' : ''}',
                          style: t.bodySmall),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text('${m['answer'] ?? ''}')],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
