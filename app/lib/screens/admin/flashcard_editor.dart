import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Édition des flashcards d'un chapitre (flashcards/{chapterId}).
class FlashcardEditor extends StatefulWidget {
  final Subject subject;
  final Chapter chapter;
  const FlashcardEditor({super.key, required this.subject, required this.chapter});

  @override
  State<FlashcardEditor> createState() => _FlashcardEditorState();
}

class _CardFields {
  final TextEditingController front;
  final TextEditingController back;
  _CardFields(String f, String b)
      : front = TextEditingController(text: f),
        back = TextEditingController(text: b);
  void dispose() {
    front.dispose();
    back.dispose();
  }
}

class _FlashcardEditorState extends State<FlashcardEditor> {
  List<_CardFields>? _cards;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final deck = await ContentRepo.instance.deck(widget.chapter.id);
    if (!mounted) return;
    setState(() {
      _cards = [for (final c in deck?.cards ?? const <Flashcard>[]) _CardFields(c.front, c.back)];
      if (_cards!.isEmpty) _cards!.add(_CardFields('', ''));
    });
  }

  @override
  void dispose() {
    for (final c in _cards ?? const <_CardFields>[]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final cards = [
      for (final c in _cards!)
        if (c.front.text.trim().isNotEmpty && c.back.text.trim().isNotEmpty)
          Flashcard(front: c.front.text.trim(), back: c.back.text.trim()).toMap()
    ];
    ContentRepo.instance.save('flashcards', widget.chapter.id, {
      'chapterId': widget.chapter.id,
      'subjectId': widget.subject.id,
      'examId': widget.subject.examId,
      'cards': cards,
      'deleted': false,
    });
    setState(() => _dirty = false);
    showMessage(context, '${cards.length} carte${cards.length > 1 ? 's' : ''} enregistrée${cards.length > 1 ? 's' : ''}.');
  }

  /// Ajout rapide : une carte par ligne, « question | réponse ».
  Future<void> _bulk() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Ajout rapide', style: titleStyle(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Une carte par ligne. Sépare la question et la réponse par une barre « | ».\n'
                'Exemple : Capitale du Sénégal | Dakar'),
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
      _cards!.removeWhere((c) => c.front.text.trim().isEmpty && c.back.text.trim().isEmpty);
      for (final line in text.split('\n')) {
        final i = line.indexOf('|');
        if (i <= 0) continue;
        final f = line.substring(0, i).trim();
        final b = line.substring(i + 1).trim();
        if (f.isEmpty || b.isEmpty) continue;
        _cards!.add(_CardFields(f, b));
        n++;
      }
      if (n > 0) _dirty = true;
    });
    if (mounted) showMessage(context, '$n carte${n > 1 ? 's' : ''} ajoutée${n > 1 ? 's' : ''}. Pense à enregistrer.');
  }

  Future<void> _leave() async {
    if (!_dirty ||
        await confirm(context, 'Quitter sans enregistrer ?', 'Tes modifications seront perdues.',
            ok: 'Quitter')) {
      setState(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    final color = JangColors.fromHex(widget.subject.color);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Flashcards', style: titleStyle(20, color: Colors.white)),
          backgroundColor: color,
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: cards == null ? null : _save,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
        body: cards == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  Text(widget.chapter.title, style: titleStyle(21)),
                  const SizedBox(height: 4),
                  Text(
                      'Recto : une question courte. Verso : la réponse à retenir. '
                      'Les élèves revoient plus souvent les cartes qu\'ils ne savent pas.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _bulk,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Ajout rapide (plusieurs cartes)'),
                  ),
                  for (var i = 0; i < cards.length; i++)
                    Card(
                      margin: const EdgeInsets.only(top: 12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 4, 12),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                                child: Text('Carte ${i + 1}',
                                    style: Theme.of(context).textTheme.titleSmall)),
                            IconButton(
                              tooltip: 'Supprimer la carte',
                              onPressed: () => setState(() {
                                cards.removeAt(i).dispose();
                                _dirty = true;
                              }),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ]),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Column(children: [
                              TextField(
                                controller: cards[i].front,
                                minLines: 1,
                                maxLines: 3,
                                onChanged: (_) => _dirty = true,
                                decoration: const InputDecoration(labelText: 'Recto (question)'),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: cards[i].back,
                                minLines: 1,
                                maxLines: 5,
                                onChanged: (_) => _dirty = true,
                                decoration: const InputDecoration(labelText: 'Verso (réponse)'),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => cards.add(_CardFields('', ''))),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une carte'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(onPressed: _save, child: const Text('Enregistrer')),
                ],
              ),
      ),
    );
  }
}
