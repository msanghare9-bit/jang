import 'package:flutter/material.dart';

import '../models.dart';
import '../services/tutor_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/consent.dart';

/// « Jàngalekat » (intelligence artificielle) d'une leçon.
class TutorScreen extends StatefulWidget {
  final Lesson lesson;
  final Subject subject;
  const TutorScreen({super.key, required this.lesson, required this.subject});

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _Exchange {
  final String question;
  final String? answer;
  final String? error;
  final bool simpler;
  _Exchange(this.question, {this.answer, this.error, this.simpler = false});
}

class _TutorScreenState extends State<TutorScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<_Exchange> _items = [];
  bool _busy = false;
  int? _remaining;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask({String? simplerOf, String? question}) async {
    final q = question ?? _text.text.trim();
    if (q.length < 3) {
      showMessage(context, 'Écris ta question.');
      return;
    }
    if (!await ensureParentConsent(context)) return;
    setState(() => _busy = true);
    final r = await TutorService.instance.ask(widget.lesson, q, previousAnswer: simplerOf);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _remaining = r.remaining ?? _remaining;
      _items.add(_Exchange(q, answer: r.answer, error: r.error, simpler: simplerOf != null));
      if (r.answer != null && simplerOf == null) _text.clear();
    });
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(widget.subject.color);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Jàngalekat', style: titleStyle(20, color: Colors.white)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: JangColors.noteBg, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    'Jàngalekat est une intelligence artificielle. Il peut se tromper : '
                    'vérifie avec ton professeur. '
                    'Il répond sur la leçon « ${widget.lesson.title} », en français simple. '
                    '${TutorService.perDay} questions par jour.',
                    style: t.bodyMedium,
                  ),
                ),
                const SizedBox(height: 14),
                for (final e in _items) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8, left: 40),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(e.simpler ? 'Explique plus simplement : ${e.question}' : e.question),
                    ),
                  ),
                  if (e.answer != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4, right: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: JangColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LessonText(e.answer!, accent: color),
                          const SizedBox(height: 6),
                          Text('Réponse de Jàngalekat (IA), à vérifier avec ton professeur.',
                              style: t.bodySmall),
                        ],
                      ),
                    ),
                  if (e.answer != null && e == _items.last)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _busy ? null : () => _ask(simplerOf: e.answer, question: e.question),
                        icon: const Icon(Icons.lightbulb_outline),
                        label: const Text('Explique plus simplement'),
                      ),
                    ),
                  if (e.error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: JangColors.errorBg, borderRadius: BorderRadius.circular(10)),
                      child: Text(e.error!, style: const TextStyle(color: JangColors.error)),
                    ),
                  const SizedBox(height: 8),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('Jàngalekat réfléchit…'),
                    ]),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_remaining != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Questions restantes aujourd\'hui : $_remaining',
                          style: t.bodySmall),
                    ),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 500,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                            labelText: 'Ta question sur la leçon', counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: color),
                      tooltip: 'Envoyer',
                      onPressed: _busy ? null : () => _ask(),
                      icon: const Icon(Icons.send, color: Colors.white),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
