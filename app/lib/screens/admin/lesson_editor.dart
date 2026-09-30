import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Création / modification d'une leçon : vidéos, texte, QCM.
class LessonEditor extends StatefulWidget {
  final Subject subject;
  final Chapter chapter;
  final Lesson? lesson;
  final int nextOrder;
  const LessonEditor({
    super.key,
    required this.subject,
    required this.chapter,
    this.lesson,
    required this.nextOrder,
  });

  @override
  State<LessonEditor> createState() => _LessonEditorState();
}

class _LessonEditorState extends State<LessonEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late List<Video> _videos;
  late List<QuizQuestion> _quiz;
  final _videoUrl = TextEditingController();
  final _videoTitle = TextEditingController();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final l = widget.lesson;
    _title = TextEditingController(text: l?.title ?? '');
    _body = TextEditingController(text: l?.body ?? '');
    _videos = List.of(l?.videos ?? const <Video>[]);
    _quiz = (l?.quiz ?? const <QuizQuestion>[]).map((q) => q.copy()).toList();
    _title.addListener(_touch);
    _body.addListener(_touch);
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _videoUrl.dispose();
    _videoTitle.dispose();
    super.dispose();
  }

  void _addVideo() {
    final id = youtubeIdFrom(_videoUrl.text);
    if (id == null) {
      showMessage(context, 'Lien YouTube non reconnu. Copie le lien de partage de la vidéo.');
      return;
    }
    setState(() {
      _videos.add(Video(youtubeId: id, title: _videoTitle.text.trim()));
      _videoUrl.clear();
      _videoTitle.clear();
      _dirty = true;
    });
  }

  void _moveVideo(int i, int j) {
    setState(() {
      final v = _videos.removeAt(i);
      _videos.insert(j, v);
      _dirty = true;
    });
  }

  void _moveQuestion(int i, int j) {
    setState(() {
      final q = _quiz.removeAt(i);
      _quiz.insert(j, q);
      _dirty = true;
    });
  }

  String? _validate() {
    if (_title.text.trim().isEmpty) return 'Donne un titre à la leçon.';
    for (var i = 0; i < _quiz.length; i++) {
      final q = _quiz[i];
      final filled = q.options.where((o) => o.trim().isNotEmpty).length;
      if (q.question.trim().isEmpty) return 'Question ${i + 1} : écris l\'énoncé.';
      if (filled < 2) return 'Question ${i + 1} : écris au moins deux propositions.';
      if (q.options[q.answer].trim().isEmpty) {
        return 'Question ${i + 1} : la bonne réponse choisie est vide.';
      }
    }
    return null;
  }

  void _save() {
    final error = _validate();
    if (error != null) {
      showMessage(context, error);
      return;
    }
    final repo = ContentRepo.instance;
    final id = widget.lesson?.id ?? repo.newId('lessons');
    final lesson = Lesson(
      id: id,
      examId: widget.subject.examId,
      subjectId: widget.subject.id,
      chapterId: widget.chapter.id,
      title: _title.text.trim(),
      order: widget.lesson?.order ?? widget.nextOrder,
      videos: _videos,
      body: _body.text.trimRight(),
      quiz: _quiz
          .map((q) => QuizQuestion(
                question: q.question.trim(),
                options: q.options.map((o) => o.trim()).toList(),
                answer: q.answer,
                explanation: q.explanation.trim(),
              ))
          .toList(),
    );
    repo.save('lessons', id, {...lesson.toMap(), 'status': 'published'});
    showMessage(context, 'Leçon enregistrée et publiée.');
    _leave();
  }

  void _leave() {
    setState(() => _dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _preview() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Aperçu du texte')),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(_title.text, style: titleStyle(24)),
              const SizedBox(height: 12),
              LessonText(_body.text, accent: JangColors.fromHex(widget.subject.color)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(widget.subject.color);
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirm(context, 'Quitter sans enregistrer ?',
            'Les modifications de cette leçon seront perdues.',
            ok: 'Quitter');
        if (leave && context.mounted) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.lesson == null ? 'Nouvelle leçon' : 'Modifier la leçon'),
          actions: [
            TextButton(onPressed: _save, child: const Text('Enregistrer')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Text('${widget.subject.name} · ${widget.chapter.title}', style: t.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Titre de la leçon'),
            ),

            // ---------- Vidéos ----------
            SectionTitle('Vidéos YouTube', color: color),
            if (_videos.isEmpty)
              Text('Aucune vidéo pour le moment.', style: t.bodySmall),
            for (var i = 0; i < _videos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                    child: Row(
                      children: [
                        Text('${i + 1}.', style: titleStyle(17, color: color)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_videos[i].title.isEmpty ? 'Sans titre' : _videos[i].title,
                                  style: t.titleSmall),
                              Text('youtu.be/${_videos[i].youtubeId}', style: t.bodySmall),
                            ],
                          ),
                        ),
                        IconButton(
                            tooltip: 'Monter',
                            onPressed: i > 0 ? () => _moveVideo(i, i - 1) : null,
                            icon: const Icon(Icons.arrow_upward)),
                        IconButton(
                            tooltip: 'Descendre',
                            onPressed: i < _videos.length - 1 ? () => _moveVideo(i, i + 1) : null,
                            icon: const Icon(Icons.arrow_downward)),
                        IconButton(
                            tooltip: 'Retirer',
                            onPressed: () => setState(() {
                                  _videos.removeAt(i);
                                  _dirty = true;
                                }),
                            icon: const Icon(Icons.delete_outline)),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Ajouter une vidéo', style: t.titleSmall),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _videoUrl,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                          labelText: 'Lien YouTube', hintText: 'https://youtu.be/...'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _videoTitle,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Titre affiché (facultatif)'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                        onPressed: _addVideo,
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter la vidéo')),
                  ],
                ),
              ),
            ),

            // ---------- Texte ----------
            SectionTitle('Texte de la leçon', color: color),
            Text(
              'Mise en forme : « # » titre, « ## » sous-titre, « - » liste, '
              '« > » encadré à retenir, **gras**, *italique*.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              minLines: 10,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: 'Texte',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: _preview,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Aperçu')),
            ),

            // ---------- QCM ----------
            SectionTitle('QCM', color: color),
            if (_quiz.isEmpty) Text('Aucune question pour le moment.', style: t.bodySmall),
            for (var i = 0; i < _quiz.length; i++)
              _QuestionEditor(
                key: ObjectKey(_quiz[i]),
                index: i,
                question: _quiz[i],
                color: color,
                onChanged: () {
                  if (!_dirty) setState(() => _dirty = true);
                },
                onUp: i > 0 ? () => _moveQuestion(i, i - 1) : null,
                onDown: i < _quiz.length - 1 ? () => _moveQuestion(i, i + 1) : null,
                onDelete: () async {
                  if (await confirm(context, 'Supprimer la question ${i + 1} ?', '',
                      ok: 'Supprimer')) {
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
            const SizedBox(height: 28),
            FilledButton(onPressed: _save, child: const Text('Enregistrer et publier')),
          ],
        ),
      ),
    );
  }
}

class _QuestionEditor extends StatefulWidget {
  final int index;
  final QuizQuestion question;
  final Color color;
  final VoidCallback onChanged;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onDelete;
  const _QuestionEditor({
    super.key,
    required this.index,
    required this.question,
    required this.color,
    required this.onChanged,
    this.onUp,
    this.onDown,
    required this.onDelete,
  });

  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Question ${widget.index + 1}',
                          style: titleStyle(17, color: widget.color))),
                  IconButton(
                      tooltip: 'Monter',
                      onPressed: widget.onUp,
                      icon: const Icon(Icons.arrow_upward)),
                  IconButton(
                      tooltip: 'Descendre',
                      onPressed: widget.onDown,
                      icon: const Icon(Icons.arrow_downward)),
                  IconButton(
                      tooltip: 'Supprimer',
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextField(
                  controller: _q,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Énoncé'),
                ),
              ),
              const SizedBox(height: 10),
              Text('Propositions — touche le rond de la bonne réponse',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 6),
                  child: Row(
                    children: [
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
                            labelText: 'Proposition ${letters[i]}',
                            filled: true,
                            fillColor: q.answer == i ? JangColors.successBg : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextField(
                  controller: _exp,
                  maxLines: null,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Explication (affichée si l\'élève se trompe)',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
