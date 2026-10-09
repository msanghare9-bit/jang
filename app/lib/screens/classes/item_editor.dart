import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/lesson_format.dart';
import '../admin/mission_editor.dart';
import 'class_widgets.dart';

/// Une phrase à trous en cours de saisie.
class _GapFields {
  final TextEditingController before;
  final TextEditingController after;
  final TextEditingController answers;
  _GapFields(GapItem g)
      : before = TextEditingController(text: g.before),
        after = TextEditingController(text: g.after),
        answers = TextEditingController(text: g.answers.join(', '));

  GapItem toItem() => GapItem(
        before: before.text.trim(),
        after: after.text.trim(),
        answers: answers.text.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList(),
      );

  bool get isEmpty => before.text.trim().isEmpty && after.text.trim().isEmpty && answers.text.trim().isEmpty;

  void dispose() {
    before.dispose();
    after.dispose();
    answers.dispose();
  }
}

/// Création ou modification d'un contenu de classe (leçon, QCM, texte à trous, devoir, mission).
class ClassItemEditor extends StatefulWidget {
  final ClassRoom classRoom;

  /// null : nouveau contenu.
  final ClassItem? item;
  const ClassItemEditor({super.key, required this.classRoom, this.item});

  @override
  State<ClassItemEditor> createState() => _ClassItemEditorState();
}

class _ClassItemEditorState extends State<ClassItemEditor> {
  late String _type = widget.item?.type ?? ClassItem.lesson;
  late bool _public = widget.item?.isPublic ?? false;
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _body = TextEditingController(text: widget.item?.body ?? '');
  late final List<QuizQuestion> _quiz = [
    for (final q in widget.item?.quiz ?? const <QuizQuestion>[])
      QuizQuestion(
          question: q.question,
          options: [...q.options],
          answer: q.answer,
          explanation: q.explanation,
          image: q.image),
  ];
  late final List<_GapFields> _gaps = [
    for (final g in widget.item?.gapItems ?? const <GapItem>[]) _GapFields(g),
  ];
  late Map<String, dynamic> _mission = widget.item?.missionData ?? const {};
  bool _dirty = false;
  bool _busy = false;
  DateTime? _dueAt;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    _dueAt = widget.item?.dueAt;
    _title.addListener(_touch);
    _body.addListener(_touch);
    if (_type == ClassItem.mcq && _quiz.isEmpty) _quiz.add(QuizQuestion.empty());
    if (_type == ClassItem.gaps && _gaps.isEmpty) _gaps.add(_GapFields(GapItem()));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    for (final g in _gaps) {
      g.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _setType(String t) {
    setState(() {
      _type = t;
      _dirty = true;
      if (t == ClassItem.mcq && _quiz.isEmpty) _quiz.add(QuizQuestion.empty());
      if (t == ClassItem.gaps && _gaps.isEmpty) _gaps.add(_GapFields(GapItem()));
    });
  }

  List<QuizQuestion> _cleanQuiz() => _quiz
      .where((q) => q.question.trim().isNotEmpty || q.options.any((o) => o.trim().isNotEmpty))
      .toList();

  /// Vérifie le contenu ; renvoie un message simple, ou '' si tout va bien.
  String _check(String title, List<QuizQuestion> quiz, List<GapItem> gaps) {
    if (title.isEmpty) return 'Écris un titre.';
    for (var i = 0; i < quiz.length; i++) {
      final q = quiz[i];
      if (q.question.trim().isEmpty) return 'Question ${i + 1} : écris l\'énoncé.';
      if (q.options[q.answer].trim().isEmpty) return 'Question ${i + 1} : la bonne réponse est vide.';
      if (q.options.where((o) => o.trim().isNotEmpty).length < 2) {
        return 'Question ${i + 1} : écris au moins 2 propositions.';
      }
    }
    switch (_type) {
      case ClassItem.lesson:
        if (_body.text.trim().isEmpty) return 'Écris le texte de la leçon.';
      case ClassItem.mcq:
        if (quiz.isEmpty) return 'Ajoute au moins une question.';
      case ClassItem.gaps:
        if (gaps.isEmpty) return 'Ajoute au moins une phrase.';
        for (var i = 0; i < gaps.length; i++) {
          if (gaps[i].answers.isEmpty) return 'Phrase ${i + 1} : écris la bonne réponse.';
          if (gaps[i].before.isEmpty && gaps[i].after.isEmpty) return 'Phrase ${i + 1} : écris la phrase.';
        }
      case ClassItem.homework:
        if (_body.text.trim().isEmpty) return 'Écris la consigne du devoir.';
      case ClassItem.mission:
        if (_mission.isEmpty) return 'Prépare la mission avec le bouton « Préparer la mission ».';
    }
    return '';
  }

  Future<void> _save() async {
    final me = AuthService.instance.profile.value;
    if (me == null) return;
    var title = _title.text.trim();
    if (title.isEmpty && _type == ClassItem.mission) title = '${_mission['titre'] ?? ''}'.trim();
    final quiz = _type == ClassItem.lesson || _type == ClassItem.mcq ? _cleanQuiz() : <QuizQuestion>[];
    final gaps = _type == ClassItem.gaps ? [for (final g in _gaps) if (!g.isEmpty) g.toItem()] : <GapItem>[];
    final error = _check(title, quiz, gaps);
    if (error.isNotEmpty) {
      showMessage(context, error);
      return;
    }
    final c = widget.classRoom;
    final old = widget.item;
    setState(() => _busy = true);
    try {
      await ClassService.instance.saveItem(ClassItem(
        id: old?.id ?? '',
        classId: c.id,
        ownerUid: old?.ownerUid ?? me.uid,
        ownerName: old?.ownerName ?? me.name,
        examId: c.examId,
        subject: c.subject,
        type: _type,
        title: title,
        body: _type == ClassItem.lesson || _type == ClassItem.homework ? _body.text.trim() : '',
        quiz: quiz,
        gapItems: gaps,
        missionData: _type == ClassItem.mission ? _mission : const {},
        visibility: _public ? 'public' : 'prive',
        dueAt: _type == ClassItem.homework ? _dueAt : null,
      ));
      if (!mounted) return;
      showMessage(context, _isNew ? 'Contenu créé.' : 'Contenu enregistré.');
      _dirty = false;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, 'Échec : $e');
      }
    }
  }

  Future<void> _chooseDueAt() async {
    final now = DateTime.now();
    final current = _dueAt ?? now.add(const Duration(days: 1));
    final today = DateTime(now.year, now.month, now.day);
    final initialDay = DateTime(current.year, current.month, current.day);
    final day = await showDatePicker(
      context: context,
      initialDate: initialDay.isBefore(today) ? today : initialDay,
      firstDate: today,
      lastDate: DateTime(now.year + 5),
      locale: const Locale('fr'),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: 'Heure limite',
    );
    if (time == null) return;
    setState(() {
      _dueAt = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      _dirty = true;
    });
  }

  Widget _deadlinePicker() {
    final due = _dueAt;
    final label = due == null
        ? 'Aucune date limite'
        : '${due.day.toString().padLeft(2, '0')}/${due.month.toString().padLeft(2, '0')}/${due.year} à ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_available, color: JangColors.primary),
        title: const Text('Date limite du devoir'),
        subtitle: Text(label),
        trailing: due == null
            ? const Icon(Icons.chevron_right)
            : IconButton(
                tooltip: 'Supprimer la date limite',
                onPressed: () => setState(() {
                  _dueAt = null;
                  _dirty = true;
                }),
                icon: const Icon(Icons.close),
              ),
        onTap: _chooseDueAt,
      ),
    );
  }

  Future<void> _editMission() async {
    final initial = _mission.isNotEmpty ? _mission : MissionEditorScreen.blank('classe');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MissionEditorScreen(
          title: 'Mission avec Gaïndé',
          initial: Map<String, dynamic>.from(initial),
          onSave: (m) async {
            if (!mounted) return;
            setState(() {
              _mission = m;
              _dirty = true;
              if (_title.text.trim().isEmpty && '${m['titre'] ?? ''}'.trim().isNotEmpty) {
                _title.text = '${m['titre']}'.trim();
              }
            });
          },
        ),
      ),
    );
  }

  void _preview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(_title.text.trim().isEmpty ? 'Aperçu' : _title.text.trim())),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [LessonText(_body.text)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirm(context, 'Quitter sans enregistrer ?', 'Ce que tu as écrit sera perdu.',
            ok: 'Quitter');
        if (leave && context.mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_isNew ? 'Nouveau contenu' : 'Modifier')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Text('${widget.classRoom.name} · ${widget.classRoom.subjectName}', style: t.bodySmall),
            const SizedBox(height: 8),
            if (_isNew) ...[
              Text('Que veux-tu créer ?', style: titleStyle(18)),
              const SizedBox(height: 6),
              for (final type in ClassItem.types) _typeCard(type),
            ] else
              Card(
                color: JangColors.noteBg,
                child: ListTile(
                  leading: Icon(classItemIcon(_type), color: JangColors.primaryDark),
                  title: Text(ClassItem.label(_type), style: t.titleSmall),
                  subtitle: Text(classItemHelp(_type), style: t.bodySmall),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Titre'),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _public,
              onChanged: (v) => setState(() {
                _public = v;
                _dirty = true;
              }),
              title: Text(_public ? 'Public : partager avec élèves et professeurs' : 'Privé : seulement mes élèves',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  _public
                      ? 'Les élèves du niveau le voient dans leur matière. Les autres professeurs peuvent aussi le consulter dans « Cours partagés ».'
                      : 'Seuls les élèves de ${widget.classRoom.name} le voient.',
                  style: t.bodySmall),
            ),
            if (_type == ClassItem.homework) _deadlinePicker(),
            if (_type == ClassItem.homework) const SizedBox(height: 8),
            const Divider(),
            ..._fields(context),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_busy ? 'Enregistrement…' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeCard(String type) {
    final t = Theme.of(context).textTheme;
    final selected = _type == type;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: selected ? JangColors.noteBg : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? JangColors.primary : JangColors.border, width: 2),
      ),
      child: ListTile(
        onTap: () => _setType(type),
        leading: Icon(classItemIcon(type), color: selected ? JangColors.primaryDark : JangColors.textSecondary),
        title: Text(ClassItem.label(type), style: t.titleSmall),
        subtitle: Text(classItemHelp(type), style: t.bodySmall),
        trailing: selected ? const Icon(Icons.check_circle, color: JangColors.primary) : null,
      ),
    );
  }

  List<Widget> _fields(BuildContext context) {
    final t = Theme.of(context).textTheme;
    switch (_type) {
      case ClassItem.lesson:
        return [
          TextField(
            controller: _body,
            minLines: 10,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(alignLabelWithHint: true, labelText: 'Texte de la leçon'),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(
              onPressed: () => _body.text = autoFormatLesson(_body.text),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Mise en forme automatique'),
            ),
            OutlinedButton.icon(
              onPressed: _preview,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Voir comme un élève'),
            ),
          ]),
          TextButton.icon(
            onPressed: () => showFormatHelp(context),
            icon: const Icon(Icons.help_outline),
            label: const Text('Comment mettre en forme ?'),
          ),
          SectionTitle('Petit quiz à la fin (facultatif)'),
          ..._quizFields(context),
        ];
      case ClassItem.mcq:
        return [
          Text('Pour chaque question : 4 propositions. Touche le rond de la bonne réponse.', style: t.bodySmall),
          const SizedBox(height: 8),
          ..._quizFields(context),
        ];
      case ClassItem.gaps:
        return _gapFields(context);
      case ClassItem.homework:
        return [
          TextField(
            controller: _body,
            minLines: 5,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              alignLabelWithHint: true,
              labelText: 'La consigne',
              hintText: 'Ex. : Écris 5 phrases pour présenter ta famille.',
            ),
          ),
          const SizedBox(height: 6),
          Text('L\'élève écrit sa réponse dans l\'app. Tu la lis et tu la notes dans l\'onglet « Devoirs ».',
              style: t.bodySmall),
        ];
      case ClassItem.mission:
        final ready = _mission.isNotEmpty;
        return [
          Card(
            color: ready ? JangColors.successBg : JangColors.warningBg,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                ready
                    ? 'Mission prête : « ${'${_mission['titre'] ?? ''}'.trim().isEmpty ? 'sans titre' : _mission['titre']} ». '
                        'Tu peux encore la modifier.'
                    : 'La mission n\'est pas encore préparée.',
                style: t.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _editMission,
            icon: const Icon(Icons.pets),
            label: Text(ready ? 'Modifier la mission' : 'Préparer la mission'),
          ),
          const SizedBox(height: 6),
          Text('Après avoir enregistré la mission, reviens ici et appuie sur « Enregistrer ».',
              style: t.bodySmall),
        ];
    }
    return const [];
  }

  List<Widget> _quizFields(BuildContext context) => [
        for (var i = 0; i < _quiz.length; i++)
          _QuestionCard(
            key: ObjectKey(_quiz[i]),
            index: i,
            question: _quiz[i],
            onChanged: _touch,
            onDelete: () async {
              if (await confirm(context, 'Supprimer la question ${i + 1} ?', '', ok: 'Supprimer')) {
                setState(() {
                  _quiz.removeAt(i);
                  _dirty = true;
                });
              }
            },
          ),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _quiz.add(QuizQuestion.empty());
            _dirty = true;
          }),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter une question'),
        ),
      ];

  List<Widget> _gapFields(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return [
      Text(
          'Écris le début de la phrase, puis la fin. Le trou ___ est au milieu. '
          'S\'il y a plusieurs bonnes réponses, sépare-les par des virgules.',
          style: t.bodySmall),
      const SizedBox(height: 8),
      for (var i = 0; i < _gaps.length; i++)
        Card(
          key: ObjectKey(_gaps[i]),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('Phrase ${i + 1}', style: titleStyle(17, color: JangColors.primaryDark))),
                IconButton(
                  tooltip: 'Supprimer la phrase',
                  onPressed: () {
                    final g = _gaps[i];
                    setState(() {
                      _gaps.removeAt(i);
                      _dirty = true;
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) => g.dispose());
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(
                    controller: _gaps[i].before,
                    maxLines: null,
                    onChanged: (_) => setState(() => _dirty = true),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Avant le trou', hintText: 'Ex. : I'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _gaps[i].answers,
                    onChanged: (_) => setState(() => _dirty = true),
                    decoration: const InputDecoration(
                        labelText: 'Bonne(s) réponse(s)', hintText: 'Ex. : am, \'m'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _gaps[i].after,
                    maxLines: null,
                    onChanged: (_) => setState(() => _dirty = true),
                    decoration: const InputDecoration(labelText: 'Après le trou', hintText: 'Ex. : a student.'),
                  ),
                  const SizedBox(height: 8),
                  Text('L\'élève verra : ${_gaps[i].before.text.trim()} ___ ${_gaps[i].after.text.trim()}'.trim(),
                      style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                ]),
              ),
            ]),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _gaps.add(_GapFields(GapItem()));
          _dirty = true;
        }),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une phrase'),
      ),
    ];
  }
}

/// Une question à 4 choix : énoncé, propositions, bonne réponse, explication.
class _QuestionCard extends StatefulWidget {
  final int index;
  final QuizQuestion question;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  const _QuestionCard(
      {super.key, required this.index, required this.question, required this.onChanged, required this.onDelete});

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  late final TextEditingController _q;
  late final List<TextEditingController> _opts;
  late final TextEditingController _exp;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    _q = TextEditingController(text: q.question)
      ..addListener(() {
        q.question = _q.text;
        widget.onChanged();
      });
    _opts = List.generate(4, (i) {
      final c = TextEditingController(text: q.options[i]);
      c.addListener(() {
        q.options[i] = c.text;
        widget.onChanged();
      });
      return c;
    });
    _exp = TextEditingController(text: q.explanation)
      ..addListener(() {
        q.explanation = _exp.text;
        widget.onChanged();
      });
  }

  @override
  void dispose() {
    _q.dispose();
    for (final c in _opts) {
      c.dispose();
    }
    _exp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const letters = ['A', 'B', 'C', 'D'];
    final q = widget.question;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Question ${widget.index + 1}', style: titleStyle(17, color: JangColors.primaryDark))),
            IconButton(tooltip: 'Supprimer', onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline)),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TextField(
              controller: _q,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Énoncé'),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 10),
              child: Row(children: [
                IconButton(
                  tooltip: 'Bonne réponse',
                  onPressed: () {
                    setState(() => q.answer = i);
                    widget.onChanged();
                  },
                  icon: Icon(
                    q.answer == i ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: q.answer == i ? JangColors.success : JangColors.textSecondary,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _opts[i],
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Proposition ${letters[i]}${q.answer == i ? ' (bonne)' : ''}',
                      filled: true,
                      fillColor: q.answer == i ? JangColors.successBg : Colors.white,
                    ),
                  ),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TextField(
              controller: _exp,
              minLines: 2,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Explication (montrée après la réponse)', alignLabelWithHint: true),
            ),
          ),
        ]),
      ),
    );
  }
}
