import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../services/inbox_service.dart';
import '../services/push_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/characters.dart';
import '../widgets/common.dart';

/// « Mes messages » : messages des profs et annonces.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late Future<(List<Announcement>, Set<String>)> _ann = _loadAnnouncements();
  bool? _muted;

  @override
  void initState() {
    super.initState();
    PushService.instance.announcementsMuted().then((m) {
      if (mounted) setState(() => _muted = m);
    });
  }

  Future<(List<Announcement>, Set<String>)> _loadAnnouncements() async {
    final p = AuthService.instance.profile.value!;
    final subjects = {
      for (final s in await ContentRepo.instance.subjects(p.examId)) subjectKey(s.name),
    };
    final list = await InboxService.instance.myAnnouncements(p, subjects);
    return (list, await InboxService.instance.readAnnouncements());
  }

  Future<void> _reply(InboxMessage m, String preset) async {
    final uid = AuthService.instance.profile.value!.uid;
    var text = preset;
    if (preset.isEmpty) {
      final c = TextEditingController();
      final r = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Ma question', style: titleStyle(20)),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLines: 4,
            maxLength: 400,
            decoration: const InputDecoration(hintText: 'Écris ta question à ton prof'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Envoyer')),
          ],
        ),
      );
      if (r == null || r.isEmpty) return;
      text = r;
    }
    await InboxService.instance.reply(uid, m.id, text);
    if (mounted) showMessage(context, 'Réponse envoyée.');
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthService.instance.profile.value!;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes messages')),
      body: StreamBuilder<List<InboxMessage>>(
        stream: InboxService.instance.myMessages(p.uid),
        builder: (context, snap) {
          final messages = snap.data ?? const <InboxMessage>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              const SectionTitle('Messages de mes profs'),
              if (snap.connectionState == ConnectionState.waiting && messages.isEmpty)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (messages.isEmpty)
                Text('Pas encore de message.', style: t.bodyMedium),
              for (final m in messages) _messageCard(context, p.uid, m),
              const SectionTitle('Annonces'),
              FutureBuilder<(List<Announcement>, Set<String>)>(
                future: _ann,
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final (list, read) = snap.data!;
                  if (list.isEmpty) return Text('Pas encore d\'annonce.', style: t.bodyMedium);
                  return Column(children: [
                    for (final a in list)
                      Card(
                        color: read.contains(a.id) ? null : JangColors.noteBg,
                        child: ListTile(
                          leading: const Icon(Icons.campaign_outlined, color: JangColors.primaryDark),
                          title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text('${a.text}\n${a.fromName}'),
                          isThreeLine: true,
                          onTap: () async {
                            await InboxService.instance.markAnnouncementRead(p.uid, a.id);
                            if (mounted) setState(() => _ann = _loadAnnouncements());
                          },
                        ),
                      ),
                  ]);
                },
              ),
              const SizedBox(height: 12),
              if (_muted != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: !_muted!,
                  onChanged: (v) async {
                    setState(() => _muted = !v);
                    await PushService.instance.setAnnouncementsMuted(!v);
                  },
                  title: const Text('Recevoir les annonces sur mon téléphone'),
                  subtitle: const Text('Les messages de ton prof arrivent toujours.'),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _messageCard(BuildContext context, String uid, InboxMessage m) {
    if (!m.read) InboxService.instance.markRead(uid, m.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EBFF),
        border: Border.all(color: const Color(0xFF8B5CF6), width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CharacterView(Chars.kocc, size: 44, moves: Moves.still),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Message de ${m.fromName}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF6D3FD6))),
          ),
        ]),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Text(m.text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        if (m.reply.isNotEmpty)
          Text('Ma réponse : ${m.reply}', style: const TextStyle(fontWeight: FontWeight.w700))
        else
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: () => _reply(m, 'Merci !'), child: const Text('Merci !')),
            OutlinedButton(onPressed: () => _reply(m, ''), child: const Text('J\'ai une question')),
          ]),
      ]),
    );
  }
}

/// Carte « Message de ton prof » sur l'accueil (seulement s'il y a un message non lu).
class InboxCard extends StatelessWidget {
  const InboxCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AuthService.instance.profile.value;
    if (p == null) return const SizedBox.shrink();
    return StreamBuilder<List<InboxMessage>>(
      stream: InboxService.instance.myMessages(p.uid),
      builder: (context, snap) {
        final unread = (snap.data ?? const <InboxMessage>[]).where((m) => !m.read).toList();
        if (unread.isEmpty) return const SizedBox.shrink();
        final m = unread.first;
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxScreen())),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1EBFF),
              border: Border.all(color: const Color(0xFF8B5CF6), width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              const CharacterView(Chars.kocc, size: 52, moves: Moves.sway),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      unread.length > 1
                          ? '${unread.length} messages de ton prof'
                          : 'Un message de ${m.fromName}',
                      style: titleStyle(17, weight: 800)),
                  Text(m.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        );
      },
    );
  }
}
