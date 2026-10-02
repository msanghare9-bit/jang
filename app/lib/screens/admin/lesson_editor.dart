import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../services/media_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/lesson_format.dart';
import '../lesson_screen.dart';

/// Création / modification d'une leçon : 4 onglets (Vidéos, Leçon, QCM, Révision).
class LessonEditor extends StatefulWidget {
  final Subject subject;
  final Lesson? lesson;
  final int nextOrder;
  const LessonEditor({
    super.key,
    required this.subject,
    this.lesson,
    required this.nextOrder,
  });

  @override
  State<LessonEditor> createState() => _LessonEditorState();
}

class _CardFields {
  final TextEditingController front;
  final TextEditingController back;
  String image;
  _CardFields(String f, String b, [this.image = ''])
      : front = TextEditingController(text: f),
        back = TextEditingController(text: b);
  void dispose() {
    front.dispose();
    back.dispose();
  }
}

class _LessonEditorState extends State<LessonEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late List<Video> _videos;
  late List<QuizQuestion> _quiz;
  final List<_CardFields> _cards = [];
  bool _hadDeck = false;
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
    if (l != null) _loadCards(l.id);
  }

  Future<void> _loadCards(String lessonId) async {
    final deck = await ContentRepo.instance.deck(lessonId);
    if (!mounted || deck == null) return;
    setState(() {
      _hadDeck = true;
      for (final c in deck.cards) {
        _cards.add(_CardFields(c.front, c.back, c.image));
      }
    });
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
    for (final c in _cards) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------- Vidéos ----------------

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

  // ---------------- Mise en forme du texte ----------------

  bool _uploading = false;

  /// Photo dans le texte : choisie, envoyée, puis insérée avec sa légende sur sa propre ligne.
  Future<void> _insertPhoto() async {
    final pos0 = _body.selection.baseOffset;
    setState(() => _uploading = true);
    String? id;
    try {
      id = await MediaService.instance.pickAndUpload(context);
    } catch (_) {
      if (mounted) showMessage(context, 'Envoi de la photo impossible. Vérifie ta connexion.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
    if (id == null || !mounted) return;
    final ctrl = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Légende de la photo', style: titleStyle(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          MediaImage(id!, height: 150, fit: BoxFit.contain, radius: 12),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Exemple : Une carotte'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Sans légende')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    final text = _body.text;
    var pos = pos0;
    if (pos < 0 || pos > text.length) pos = text.length;
    final before = pos == 0 || text[pos - 1] == '\n' ? '' : '\n';
    final after = pos < text.length && text[pos] == '\n' ? '' : '\n';
    final line = '[photo $id] ${caption ?? ''}'.trimRight();
    final insert = '$before$line$after';
    _body.value = TextEditingValue(
      text: text.replaceRange(pos, pos, insert),
      selection: TextSelection.collapsed(offset: pos + insert.length),
    );
  }

  /// Ajoute [prefix] au début de la ligne où se trouve le curseur.
  void _linePrefix(String prefix) {
    final text = _body.text;
    var pos = _body.selection.baseOffset;
    if (pos < 0 || pos > text.length) pos = text.length;
    final start = pos == 0 ? 0 : text.lastIndexOf('\n', pos - 1) + 1;
    final newText = text.replaceRange(start, start, prefix);
    _body.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
  }

  /// Entoure la sélection avec [mark] (gras ** ou traduction *).
  void _wrap(String mark, String example) {
    final text = _body.text;
    final sel = _body.selection;
    if (!sel.isValid || sel.isCollapsed) {
      var pos = sel.baseOffset;
      if (pos < 0 || pos > text.length) pos = text.length;
      final insert = '$mark$example$mark';
      _body.value = TextEditingValue(
        text: text.replaceRange(pos, pos, insert),
        selection: TextSelection(
            baseOffset: pos + mark.length, extentOffset: pos + mark.length + example.length),
      );
      showMessage(context, 'Astuce : sélectionne d\'abord des mots, puis touche le bouton.');
      return;
    }
    final chosen = text.substring(sel.start, sel.end);
    _body.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, '$mark$chosen$mark'),
      selection: TextSelection.collapsed(offset: sel.end + mark.length * 2),
    );
  }

  void _autoFormat() {
    final before = _body.text;
    final after = autoFormatLesson(before);
    if (after == before) {
      showMessage(context, 'Le texte est déjà bien mis en forme.');
      return;
    }
    _body.text = after;
    showMessage(context, 'Mise en forme faite. Vérifie avec « Voir comme un élève ».');
  }

  // ---------------- Révision ----------------

  Future<void> _bulkCards() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Ajout rapide', style: titleStyle(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Une carte par ligne : la question, une barre « | », puis la réponse.\n'
                'Exemple : Que veut dire « What should I do? » ? | Que dois-je faire ?'),
            const SizedBox(height: 10),
            TextField(controller: ctrl, minLines: 5, maxLines: 10),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Ajouter')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null) return;
    var n = 0;
    setState(() {
      for (final line in text.split('\n')) {
        final i = line.indexOf('|');
        if (i <= 0) continue;
        final f = line.substring(0, i).trim();
        final b = line.substring(i + 1).trim();
        if (f.isEmpty || b.isEmpty) continue;
        _cards.add(_CardFields(f, b));
        n++;
      }
      if (n > 0) _dirty = true;
    });
    if (mounted) showMessage(context, '$n carte${n > 1 ? 's' : ''} ajoutée${n > 1 ? 's' : ''}.');
  }

  // ---------------- Enregistrement ----------------

  String? _validate() {
    if (_title.text.trim().isEmpty) return 'Donne un titre à la leçon (onglet Leçon).';
    for (var i = 0; i < _quiz.length; i++) {
      final q = _quiz[i];
      final filled = q.options.where((o) => o.trim().isNotEmpty).length;
      if (q.question.trim().isEmpty) return 'QCM, question ${i + 1} : écris l\'énoncé.';
      if (filled < 2) return 'QCM, question ${i + 1} : écris au moins deux propositions.';
      if (q.options[q.answer].trim().isEmpty) {
        return 'QCM, question ${i + 1} : la bonne réponse choisie est vide.';
      }
    }
    return null;
  }

  Lesson _current(String id) => Lesson(
        id: id,
        examId: widget.subject.examId,
        subjectId: widget.subject.id,
        chapterId: widget.lesson?.chapterId ?? '',
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
                  image: q.image,
                ))
            .toList(),
      );

  void _save() {
    final error = _validate();
    if (error != null) {
      showMessage(context, error);
      return;
    }
    final repo = ContentRepo.instance;
    final id = widget.lesson?.id ?? repo.newId('lessons');
    repo.save('lessons', id, {..._current(id).toMap(), 'status': 'published'});
    final cards = [
      for (final c in _cards)
        if ((c.front.text.trim().isNotEmpty || c.image.isNotEmpty) && c.back.text.trim().isNotEmpty)
          Flashcard(front: c.front.text.trim(), back: c.back.text.trim(), image: c.image).toMap()
    ];
    if (cards.isNotEmpty || _hadDeck) {
      repo.save('flashcards', id, {
        'chapterId': id,
        'lessonId': id,
        'subjectId': widget.subject.id,
        'examId': widget.subject.examId,
        'cards': cards,
        'deleted': false,
      });
    }
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
        builder: (_) => LessonScreen(
          lesson: _current(widget.lesson?.id ?? 'apercu'),
          subject: widget.subject,
          preview: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(widget.subject.color);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirm(context, 'Quitter sans enregistrer ?',
            'Les modifications de cette leçon seront perdues.',
            ok: 'Quitter');
        if (leave && context.mounted) _leave();
      },
      child: DefaultTabController(
        length: 4,
        initialIndex: 1,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.lesson == null ? 'Nouvelle leçon' : 'Modifier la leçon'),
            actions: [
              TextButton(onPressed: _save, child: const Text('Enregistrer')),
            ],
            bottom: TabBar(
              labelColor: color,
              indicatorColor: color,
              tabs: const [
                Tab(text: 'Vidéos'),
                Tab(text: 'Leçon'),
                Tab(text: 'QCM'),
                Tab(text: 'Révision'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _videosTab(context, color),
              _textTab(context, color),
              _quizTab(context, color),
              _cardsTab(context, color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videosTab(BuildContext context, Color color) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        if (_videos.isEmpty) Text('Aucune vidéo pour le moment.', style: t.bodySmall),
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
      ],
    );
  }

  Widget _tool(String label, VoidCallback onTap, {Color? color, IconData? icon}) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: color ?? JangColors.text,
        side: BorderSide(color: color ?? JangColors.border, width: 1.5),
      ),
      onPressed: onTap,
      icon: Icon(icon ?? Icons.add, size: 18),
      label: Text(label),
    );
  }

  Widget _textTab(BuildContext context, Color color) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Text(widget.subject.name, style: t.bodySmall),
        const SizedBox(height: 8),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Titre de la leçon'),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _tool(_uploading ? 'Envoi…' : 'Photo', () {
              if (!_uploading) _insertPhoto();
            },
                color: JangColors.accent, icon: Icons.add_photo_alternate_outlined),
            _tool('Partie', () => _linePrefix('## '), icon: Icons.title),
            _tool('Puce', () => _linePrefix('- '), icon: Icons.format_list_bulleted),
            _tool('Gras', () => _wrap('**', 'mot important'), icon: Icons.format_bold),
            _tool('Traduction', () => _wrap('*', 'traduction'), icon: Icons.translate),
            _tool('À retenir', () => _linePrefix('À retenir : '),
                color: JangColors.primary, icon: Icons.star_outline),
            _tool('Exemple', () => _linePrefix('Exemple : '), icon: Icons.chat_bubble_outline),
            _tool('Attention', () => _linePrefix('Attention : '),
                color: JangColors.error, icon: Icons.warning_amber),
            _tool('Astuce', () => _linePrefix('Astuce : '),
                color: JangColors.warning, icon: Icons.lightbulb_outline),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: JangColors.primary),
          onPressed: _autoFormat,
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('Mise en forme automatique'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _body,
          minLines: 14,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            alignLabelWithHint: true,
            labelText: 'Texte de la leçon',
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _preview,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Voir comme un élève'),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => showFormatHelp(context),
          icon: const Icon(Icons.help_outline),
          label: const Text('Comment mettre en forme ?'),
        ),
      ],
    );
  }

  Widget _quizTab(BuildContext context, Color color) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
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
      ],
    );
  }

  Widget _cardsTab(BuildContext context, Color color) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Text(
            'Les cartes de révision aident l\'élève à retenir l\'essentiel : '
            'une question courte, puis la réponse.',
            style: t.bodySmall),
        const SizedBox(height: 10),
        for (var i = 0; i < _cards.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text('Carte ${i + 1}', style: t.titleSmall)),
                  IconButton(
                    tooltip: 'Supprimer la carte',
                    onPressed: () {
                      final removed = _cards[i];
                      setState(() {
                        _cards.removeAt(i);
                        _dirty = true;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(children: [
                    PhotoField(
                      image: _cards[i].image,
                      onChanged: (id) => setState(() {
                        _cards[i].image = id;
                        _dirty = true;
                      }),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cards[i].front,
                      maxLines: null,
                      onChanged: (_) => _touch(),
                      decoration: InputDecoration(
                          labelText: _cards[i].image.isEmpty
                              ? 'Question'
                              : 'Question (vide = « Qu\'est-ce que c\'est ? »)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cards[i].back,
                      maxLines: null,
                      onChanged: (_) => _touch(),
                      decoration: const InputDecoration(labelText: 'Réponse'),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _cards.add(_CardFields('', ''));
            _dirty = true;
          }),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter une carte'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _bulkCards,
          icon: const Icon(Icons.playlist_add),
          label: const Text('Ajout rapide : plusieurs cartes'),
        ),
      ],
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
              const SizedBox(height: 8),
              PhotoField(
                image: q.image,
                onChanged: (id) {
                  setState(() => q.image = id);
                  widget.onChanged();
                },
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
                    labelText: 'Explication (affichée après la réponse)',
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


/// Ajouter, voir ou retirer une photo (QCM, cartes de révision).
class PhotoField extends StatefulWidget {
  final String image;
  final ValueChanged<String> onChanged;
  const PhotoField({super.key, required this.image, required this.onChanged});

  @override
  State<PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends State<PhotoField> {
  bool _busy = false;

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final id = await MediaService.instance.pickAndUpload(context);
      if (id != null) widget.onChanged(id);
    } catch (e) {
      if (mounted) showMessage(context, 'Envoi de la photo impossible. Vérifie ta connexion.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Envoi de la photo…'),
        ]),
      );
    }
    if (widget.image.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Ajouter une photo'),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MediaImage(widget.image, height: 140, fit: BoxFit.contain, radius: 12),
      Row(children: [
        TextButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Changer'),
        ),
        TextButton.icon(
          onPressed: () => widget.onChanged(''),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Retirer'),
        ),
      ]),
    ]);
  }
}
