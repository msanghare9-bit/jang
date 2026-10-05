import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/content_repo.dart';
import '../../services/inbox_service.dart';
import '../../services/push_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Annonces : liste des annonces envoyées et bouton « Nouvelle annonce ».
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late Future<List<(Announcement, int)>> _future = InboxService.instance.sentAnnouncements();

  String _when(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final later = d.isAfter(DateTime.now());
    return '${later ? 'Programmée le' : 'Envoyée le'} ${two(d.day)}/${two(d.month)} à ${two(d.hour)}h${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Annonces')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final sent = await Navigator.push<bool>(
              context, MaterialPageRoute(builder: (_) => const NewAnnouncementScreen()));
          if (sent == true && mounted) setState(() => _future = InboxService.instance.sentAnnouncements());
        },
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Nouvelle annonce'),
      ),
      body: FutureBuilder<List<(Announcement, int)>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: EmptyState(icon: Icons.cloud_off, title: 'Chargement impossible', message: '${snap.error}'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(
                child: EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'Aucune annonce',
                    message: 'Écris ta première annonce avec le bouton en bas.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              for (final (a, read) in list)
                Card(
                  child: ListTile(
                    title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${a.text}\n${_when(a.sendAt)} · lue par $read élève${read > 1 ? 's' : ''}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                      onPressed: () async {
                        if (!await confirm(context, 'Supprimer cette annonce ?', 'Les élèves ne la verront plus.',
                            ok: 'Supprimer')) {
                          return;
                        }
                        await InboxService.instance.deleteAnnouncement(a.id);
                        if (mounted) setState(() => _future = InboxService.instance.sentAnnouncements());
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Écrire une annonce : pour qui, le message, quand.
class NewAnnouncementScreen extends StatefulWidget {
  const NewAnnouncementScreen({super.key});

  @override
  State<NewAnnouncementScreen> createState() => _NewAnnouncementScreenState();
}

class _NewAnnouncementScreenState extends State<NewAnnouncementScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  List<Exam> _exams = const [];
  final Map<String, String> _subjects = {}; // clé -> nom affiché
  String _target = 'all'; // all | exam | subject | both
  String _examId = '';
  String _subject = '';
  DateTime? _sendAt;
  int? _count;
  bool _sending = false;
  bool _push = false;

  UserProfile get _me => AuthService.instance.profile.value!;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final repo = ContentRepo.instance;
    var exams = await repo.exams();
    if (_me.isProf && _me.profExams.isNotEmpty) {
      exams = exams.where((e) => _me.profExams.contains(e.id)).toList();
    }
    for (final e in exams) {
      for (final s in await repo.subjects(e.id)) {
        final k = subjectKey(s.name);
        if (_me.isAdmin || _me.profSubjects.contains(k)) _subjects.putIfAbsent(k, () => s.name);
      }
    }
    final push = await PushService.instance.configured();
    if (!mounted) return;
    setState(() {
      _exams = exams;
      _push = push;
      // Un prof annonce dans sa matière.
      if (_me.isProf) {
        _target = 'subject';
        _subject = _subjects.keys.isEmpty ? '' : _subjects.keys.first;
      }
    });
    _recount();
  }

  String get _examFilter => (_target == 'exam' || _target == 'both') ? _examId : '';
  String get _subjectFilter => (_target == 'subject' || _target == 'both') ? _subject : '';

  bool get _valid {
    if (_title.text.trim().isEmpty || _text.text.trim().isEmpty) return false;
    if ((_target == 'exam' || _target == 'both') && _examId.isEmpty) return false;
    if ((_target == 'subject' || _target == 'both') && _subject.isEmpty) return false;
    return true;
  }

  /// Nombre d'élèves concernés (approximatif pour une matière : élèves des niveaux qui l'ont).
  Future<void> _recount() async {
    setState(() => _count = null);
    try {
      Query<Map<String, dynamic>> q =
          FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'student');
      if (_examFilter.isNotEmpty) q = q.where('examId', isEqualTo: _examFilter);
      final c = await q.count().get();
      if (mounted) setState(() => _count = c.count);
    } catch (_) {
      if (mounted) setState(() => _count = -1);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, firstDate: now, lastDate: now.add(const Duration(days: 120)), initialDate: now);
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    setState(() => _sendAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await InboxService.instance.announce(
        title: _title.text.trim(),
        text: _text.text.trim(),
        examId: _examFilter,
        subject: _subjectFilter,
        sendAt: _sendAt,
      );
      if (!mounted) return;
      showMessage(context, _sendAt == null ? 'Annonce envoyée.' : 'Annonce programmée.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _chips(Map<String, String> options, String value, ValueChanged<String> onPick) => Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final e in options.entries)
            ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => onPick(e.key)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle annonce')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const SectionTitle('1 · Pour qui ?'),
          _chips({
            if (_me.isAdmin) 'all': 'Tous les élèves',
            if (_me.isAdmin) 'exam': 'Un niveau',
            'subject': 'Une matière',
            'both': 'Une matière dans un niveau',
          }, _target, (v) {
            setState(() => _target = v);
            _recount();
          }),
          if (_target == 'exam' || _target == 'both') ...[
            const SizedBox(height: 10),
            Text('Niveau', style: t.titleSmall),
            const SizedBox(height: 4),
            _chips({for (final e in _exams) e.id: e.name}, _examId, (v) {
              setState(() => _examId = v);
              _recount();
            }),
          ],
          if (_target == 'subject' || _target == 'both') ...[
            const SizedBox(height: 10),
            Text('Matière', style: t.titleSmall),
            const SizedBox(height: 4),
            _chips(_subjects, _subject, (v) => setState(() => _subject = v)),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: JangColors.noteBg, borderRadius: BorderRadius.circular(12)),
            child: Text(
              _count == null
                  ? 'Calcul du nombre d\'élèves…'
                  : _count! < 0
                      ? 'Nombre d\'élèves inconnu (pas de connexion).'
                      : '${_subjectFilter.isNotEmpty ? 'Jusqu\'à ' : ''}$_count élève${_count! > 1 ? 's' : ''} recevront l\'annonce.',
              style: const TextStyle(fontWeight: FontWeight.w800, color: JangColors.primaryDark),
            ),
          ),
          const SectionTitle('2 · Le message'),
          TextField(
            controller: _title,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Titre', hintText: 'Ex. : Nouvelle unité ouverte'),
          ),
          TextField(
            controller: _text,
            maxLines: 4,
            maxLength: 400,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Message', hintText: 'Phrases courtes, en français simple.', border: OutlineInputBorder()),
          ),
          const SectionTitle('3 · Quand ?'),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Maintenant'), selected: _sendAt == null, onSelected: (_) => setState(() => _sendAt = null)),
            ChoiceChip(
              label: Text(_sendAt == null
                  ? 'Programmer'
                  : 'Le ${_sendAt!.day}/${_sendAt!.month} à ${_sendAt!.hour}h${_sendAt!.minute.toString().padLeft(2, '0')}'),
              selected: _sendAt != null,
              onSelected: (_) => _pickDate(),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
              _push
                  ? 'Les élèves reçoivent une notification sur leur téléphone, même si l\'app est fermée.'
                  : 'Les notifications push ne sont pas encore configurées : les élèves verront l\'annonce en ouvrant l\'app.',
              style: t.bodySmall),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _valid && !_sending ? _send : null,
            child: Text(_sending ? 'Envoi…' : (_sendAt == null ? 'Envoyer' : 'Programmer')),
          ),
        ],
      ),
    );
  }
}
