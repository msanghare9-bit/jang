import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../screens/classes/gap_screen.dart';
import '../screens/classes/homework_screen.dart';
import '../screens/lesson_screen.dart';
import '../screens/mission/mission_screen.dart';
import '../screens/quiz_screen.dart';
import '../services/auth_service.dart';
import '../services/class_service.dart';
import '../services/mission_service.dart';
import '../services/progress_repo.dart';
import '../theme.dart';
import 'common.dart';

/// Dans une matière : les contenus de la classe de l'élève, puis ceux partagés par d'autres profs.
/// Rien pour un prof ou un admin (ils ont leurs écrans).
class ClassSection extends StatefulWidget {
  final Subject subject;

  /// Marges autour de la section (seulement quand elle est affichée).
  final EdgeInsets padding;
  const ClassSection({super.key, required this.subject, this.padding = EdgeInsets.zero});

  @override
  State<ClassSection> createState() => _ClassSectionState();
}

class _Data {
  final ClassRoom? room;
  final List<ClassItem> own;
  final List<ClassItem> shared;
  final Map<String, Submission?> rendus;
  _Data(this.room, this.own, this.shared, this.rendus);
}

class _ClassSectionState extends State<ClassSection> {
  Future<_Data>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    ClassService.instance.revision.addListener(_reload);
  }

  @override
  void dispose() {
    ClassService.instance.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<_Data>? _load() {
    final p = AuthService.instance.profile.value;
    if (p == null || p.isStaff) return null;
    return () async {
      final (room, own, shared) = await ClassService.instance.forStudent(p, widget.subject);
      final rendus = <String, Submission?>{};
      await Future.wait([
        for (final i in [...own, ...shared])
          if (i.type == ClassItem.homework)
            ClassService.instance
                .mySubmission(i.id, p.uid)
                .then((s) => rendus[i.id] = s)
                .catchError((Object e) => rendus[i.id] = null),
      ]);
      return _Data(room, own, shared, rendus);
    }();
  }

  Future<void> _open(ClassItem item) async {
    final s = widget.subject;
    final Widget screen = switch (item.type) {
      ClassItem.mcq => QuizScreen(lesson: item.asLesson(s), subject: s),
      ClassItem.gaps => GapScreen(item: item, subject: s),
      ClassItem.homework => HomeworkScreen(item: item, subject: s),
      ClassItem.mission =>
        MissionScreen(mission: Mission.fromMap({...item.missionData, 'id': item.progressId}), subject: s),
      _ => LessonScreen(lesson: item.asLesson(s), subject: s),
    };
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (item.type == ClassItem.homework) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthService.instance.profile.value;
    if (p == null || p.isStaff || _future == null) return const SizedBox.shrink();
    return FutureBuilder<_Data>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: Listenable.merge([ProgressRepo.instance.revision, MissionService.instance.revision]),
          builder: (context, _) => Padding(padding: widget.padding, child: _content(context, d)),
        );
      },
    );
  }

  Widget _content(BuildContext context, _Data d) {
    final room = d.room;
    final color = JangColors.fromHex(widget.subject.color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (room != null) ...[
          Row(children: [
            Icon(Icons.groups_rounded, color: JangColors.darker(color, 0.1)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ma classe : ${room.name}${room.profName.isEmpty ? '' : ' · ${room.profName}'}',
                style: titleStyle(18, weight: 800),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (d.own.isEmpty)
            Text('Ton prof n\'a encore rien mis ici.', style: Theme.of(context).textTheme.bodySmall)
          else
            for (final i in d.own) _tile(i, d, color),
        ] else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showJoinClassDialog(context),
              icon: const Icon(Icons.vpn_key_outlined),
              label: const Text('Tu as un code de classe ?'),
            ),
          ),
        if (d.shared.isNotEmpty) ...[
          SizedBox(height: room != null ? 14 : 4),
          Text('Partagé par d\'autres profs', style: titleStyle(18, weight: 800)),
          const SizedBox(height: 8),
          for (final i in d.shared) _tile(i, d, color, showOwner: true),
        ],
      ],
    );
  }

  static IconData _icon(String type) => switch (type) {
        ClassItem.mcq => Icons.quiz_rounded,
        ClassItem.gaps => Icons.edit_note_rounded,
        ClassItem.homework => Icons.assignment_rounded,
        ClassItem.mission => Icons.rocket_launch_rounded,
        _ => Icons.menu_book_rounded,
      };

  /// État de l'élève pour ce contenu : (texte, fait ?).
  (String, bool) _state(ClassItem i, _Data d) {
    if (i.type == ClassItem.homework) {
      final s = d.rendus[i.id];
      if (s == null) return ('À faire', false);
      if (s.graded) return (s.grade.isEmpty ? 'Corrigé' : 'Corrigé : ${s.grade}', true);
      return ('Rendu', true);
    }
    if (i.type == ClassItem.mission) {
      return MissionService.instance.isDone(i.progressId) ? ('Fait', true) : ('À faire', false);
    }
    final pr = ProgressRepo.instance.of(i.progressId);
    if (pr != null && pr.quizDone) return ('${(pr.bestScore! * 100 / pr.total).round()} %', true);
    if (i.type == ClassItem.lesson && pr?.seen == true) return ('Fait', true);
    return ('À faire', false);
  }

  Widget _tile(ClassItem i, _Data d, Color color, {bool showOwner = false}) {
    final (label, done) = _state(i, d);
    final isNew = !done && i.createdAt != null && DateTime.now().difference(i.createdAt!).inDays < 7;
    final sub = [
      ClassItem.label(i.type),
      if (showOwner && i.ownerName.isNotEmpty) i.ownerName,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _open(i),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(_icon(i.type), color: JangColors.darker(color, 0.12)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.title.isEmpty ? ClassItem.label(i.type) : i.title,
                      style: titleStyle(16.5, weight: 800), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(sub, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const SizedBox(width: 6),
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                if (isNew) ...[
                  const Pill('Nouveau', color: Colors.white, background: JangColors.error),
                  const SizedBox(height: 4),
                ],
                Pill(label,
                    color: done ? JangColors.successDark : JangColors.warning,
                    background: done ? JangColors.successBg : JangColors.warningBg),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Dialogue « Entrer dans une classe » : l'élève tape le code donné par son prof.
Future<void> showJoinClassDialog(BuildContext context) async {
  final p = AuthService.instance.profile.value;
  if (p == null) return;
  final ctl = TextEditingController();
  var busy = false;
  var error = '';
  final room = await showDialog<ClassRoom>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        Future<void> go() async {
          if (busy) return;
          setState(() {
            busy = true;
            error = '';
          });
          try {
            final (r, err) = await ClassService.instance.join(ctl.text, p);
            if (!c.mounted) return;
            if (r != null) {
              Navigator.pop(c, r);
              return;
            }
            setState(() => error = err);
          } catch (_) {
            if (c.mounted) setState(() => error = 'Pas de connexion internet. Réessaie plus tard.');
          }
          if (c.mounted) setState(() => busy = false);
        }

        return AlertDialog(
          title: Text('Entrer dans une classe', style: titleStyle(20)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ton prof te donne un code. Une seule classe par matière.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
              ],
              style: titleStyle(24, weight: 800).copyWith(letterSpacing: 4),
              decoration: const InputDecoration(labelText: 'Le code (6 lettres ou chiffres)', counterText: ''),
              onSubmitted: (_) => go(),
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(error, style: const TextStyle(color: JangColors.errorDark, fontWeight: FontWeight.w800)),
            ],
          ]),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: busy ? null : go,
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Entrer'),
            ),
          ],
        );
      },
    ),
  );
  // Le contrôleur n'est pas libéré ici : le dialogue l'utilise encore pendant qu'il se ferme.
  if (room != null && context.mounted) {
    showMessage(context,
        'Bravo ! Tu es dans la classe ${room.name}${room.subjectName.isEmpty ? '' : ' (${room.subjectName})'}.');
  }
}
