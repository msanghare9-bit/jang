import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/flashcard_service.dart';
import '../theme.dart';
import '../widgets/cheer.dart';
import '../widgets/common.dart';
import '../widgets/jang_ui.dart';
import '../services/media_service.dart';

/// Révision d'un paquet de flashcards.
class FlashcardsScreen extends StatefulWidget {
  final FlashcardDeck deck;
  final String title;
  final Color color;
  const FlashcardsScreen({super.key, required this.deck, required this.title, required this.color});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  List<Flashcard>? _queue;
  int _done = 0;
  int _cards = 0;
  int _knew = 0;
  bool _flipped = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start({bool all = false}) async {
    final cards = all
        ? (List.of(widget.deck.cards)..shuffle())
        : await FlashcardService.instance.dueCards(widget.deck);
    setState(() {
      _queue = cards;
      _cards = cards.length;
      _done = 0;
      _knew = 0;
      _flipped = false;
    });
  }

  Future<void> _answer(bool knew) async {
    final q = _queue!;
    final c = q.first;
    await FlashcardService.instance.answer(widget.deck, c, knew);
    setState(() {
      q.removeAt(0);
      _done++;
      if (knew) {
        _knew++;
      } else {
        q.add(c); // la carte revient à la fin de la séance
      }
      _flipped = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = _queue;
    final total = _done + (q?.length ?? 0);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Fermer',
          icon: const Icon(Icons.close_rounded, color: JangColors.textSecondary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : _done / total,
                minHeight: 14,
                color: JangColors.success,
                backgroundColor: JangColors.border,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('Révision', style: titleStyle(17, color: widget.color, weight: 800)),
          const SizedBox(width: 16),
        ]),
      ),
      body: q == null
          ? const Center(child: CircularProgressIndicator())
          : q.isEmpty
              ? Center(
                  child: EmptyState(
                    icon: Icons.check_circle_outline,
                    title: _done == 0 ? 'Rien à réviser aujourd\'hui' : 'Séance terminée, bravo !',
                    message: _done == 0
                        ? 'Tu connais bien ces cartes. Elles reviendront plus tard.'
                        : Cheer.flashcardsEnd(_knew, _cards),
                    action: ChunkyButton(
                        label: 'Revoir toutes les cartes',
                        color: JangColors.primary,
                        onPressed: () => _start(all: true)),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${widget.title} · ${q.length} carte${q.length > 1 ? 's' : ''} à voir',
                          style: t.bodySmall),
                      const SizedBox(height: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _flipped = !_flipped),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: _flipped ? 1 : 0),
                            duration: const Duration(milliseconds: 300),
                            builder: (context, v, _) {
                              final showBack = v > 0.5;
                              final card = q.first;
                              return Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.001)
                                  ..rotateY(pi * v),
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()..rotateY(showBack ? pi : 0),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 6, bottom: 6),
                                    padding: const EdgeInsets.all(16),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: showBack ? JangColors.successBg : Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                          color: showBack ? JangColors.success : JangColors.border,
                                          width: 2),
                                      boxShadow: const [
                                        BoxShadow(color: JangColors.ocre, offset: Offset(6, 6)),
                                      ],
                                    ),
                                    child: SingleChildScrollView(
                                      child: Column(children: [
                                        Text(showBack ? 'RÉPONSE' : 'QUESTION',
                                            style: titleStyle(14,
                                                color: JangColors.textSecondary, weight: 800)),
                                        const SizedBox(height: 10),
                                        if (!showBack && card.image.isNotEmpty) ...[
                                          MediaImage(card.image, height: 200, fit: BoxFit.contain),
                                          const SizedBox(height: 12),
                                        ],
                                        Text(
                                          showBack ? card.back : card.question,
                                          textAlign: TextAlign.center,
                                          style: titleStyle(24, weight: 800),
                                        ),
                                      ]),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_flipped)
                        ChunkyButton(
                          label: 'Voir la réponse',
                          color: JangColors.primary,
                          onPressed: () => setState(() => _flipped = true),
                        )
                      else
                        Row(children: [
                          Expanded(
                            child: ChunkyButton(
                              label: 'À revoir',
                              color: JangColors.accent,
                              onPressed: () => _answer(false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ChunkyButton(
                              label: 'Je savais',
                              color: JangColors.success,
                              onPressed: () => _answer(true),
                            ),
                          ),
                        ]),
                    ],
                  ),
                ),
    );
  }
}
