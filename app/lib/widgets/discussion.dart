import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/discussion_service.dart';
import '../theme.dart';
import 'common.dart';
import 'consent.dart';

String timeAgo(DateTime? d) {
  if (d == null) return 'à l\'instant';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays < 30) return 'il y a ${diff.inDays} j';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Questions et discussion publiques sous une leçon.
class DiscussionSection extends StatefulWidget {
  final Lesson lesson;
  final Color color;
  const DiscussionSection({super.key, required this.lesson, required this.color});

  @override
  State<DiscussionSection> createState() => _DiscussionSectionState();
}

class _DiscussionSectionState extends State<DiscussionSection> {
  Future<List<Comment>>? _future;
  final _text = TextEditingController();
  String _replyTo = '';
  String _replyName = '';
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _open() => setState(() => _future = DiscussionService.instance.forLesson(widget.lesson.id));

  Future<void> _send() async {
    if (!await ensureParentConsent(context)) return;
    setState(() => _sending = true);
    final err = await DiscussionService.instance.post(widget.lesson, _text.text, parentId: _replyTo);
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      showMessage(context, err);
      return;
    }
    _text.clear();
    setState(() {
      _replyTo = '';
      _replyName = '';
    });
    FocusScope.of(context).unfocus();
    showMessage(context, 'Message envoyé.');
    await Future.delayed(const Duration(milliseconds: 600));
    _open();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_future == null) {
      return OutlinedButton.icon(
        onPressed: _open,
        icon: const Icon(Icons.forum_outlined),
        label: const Text('Voir les questions et la discussion'),
      );
    }
    return FutureBuilder<List<Comment>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
              padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        }
        final all = snap.data!;
        final roots = all.where((c) => c.parentId.isEmpty).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                'Pose ta question ou aide les autres. Reste poli. '
                'Ne donne jamais ton numéro ni ton adresse.',
                style: t.bodySmall),
            const SizedBox(height: 10),
            if (roots.isEmpty)
              Text('Personne n\'a encore écrit. Sois le premier !', style: t.bodyMedium),
            for (final r in roots) ...[
              _bubble(context, r, all),
              for (final reply in all.where((c) => c.parentId == r.id))
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: _bubble(context, reply, all),
                ),
            ],
            const SizedBox(height: 10),
            if (_replyTo.isNotEmpty)
              Row(children: [
                Expanded(child: Text('Réponse à $_replyName', style: t.bodySmall)),
                TextButton(
                    onPressed: () => setState(() {
                          _replyTo = '';
                          _replyName = '';
                        }),
                    child: const Text('Annuler')),
              ]),
            TextField(
              controller: _text,
              minLines: 1,
              maxLines: 5,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _replyTo.isEmpty ? 'Ta question ou ton commentaire' : 'Ta réponse',
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: widget.color),
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
              label: Text(_sending ? 'Envoi…' : 'Envoyer'),
            ),
          ],
        );
      },
    );
  }

  Widget _bubble(BuildContext context, Comment c, List<Comment> all) {
    final t = Theme.of(context).textTheme;
    final me = AuthService.instance.profile.value;
    final mine = me?.uid == c.uid;
    final admin = me?.isAdmin == true;
    final hidden = c.reports >= DiscussionService.hideAfterReports && !admin && !mine;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
      decoration: BoxDecoration(
        color: c.isStaff ? JangColors.noteBg : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.isStaff ? JangColors.primary : JangColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(c.name, style: t.titleSmall),
            if (c.isStaff) ...[
              const SizedBox(width: 6),
              const Pill('Responsable', color: Colors.white, background: JangColors.primary),
            ],
            const SizedBox(width: 6),
            Expanded(child: Text(timeAgo(c.createdAt), style: t.bodySmall)),
            PopupMenuButton<String>(
              tooltip: 'Options',
              onSelected: (v) async {
                if (v == 'reply') {
                  setState(() {
                    _replyTo = c.parentId.isEmpty ? c.id : c.parentId;
                    _replyName = c.name;
                  });
                } else if (v == 'report') {
                  await DiscussionService.instance.report(c);
                  if (context.mounted) showMessage(context, 'Merci, le message a été signalé.');
                } else if (v == 'delete') {
                  if (await confirm(context, 'Supprimer ce message ?', '', ok: 'Supprimer')) {
                    await DiscussionService.instance.delete(c);
                    _open();
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'reply', child: Text('Répondre')),
                if (!mine) const PopupMenuItem(value: 'report', child: Text('Signaler')),
                if (mine || admin) const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ]),
          Text(hidden ? 'Message masqué après plusieurs signalements.' : c.text,
              style: hidden
                  ? t.bodySmall!.copyWith(fontStyle: FontStyle.italic)
                  : t.bodyMedium),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
