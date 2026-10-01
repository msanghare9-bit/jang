import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/flashcard_service.dart';
import '../theme.dart';
import '../widgets/cheer.dart';
import '../widgets/common.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text('Flashcards', style: titleStyle(20, color: Colors.white)),
        backgroundColor: widget.color,
        foregroundColor: Colors.white,
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
                    action: OutlinedButton(
                        onPressed: () => _start(all: true),
                        child: const Text('Revoir toutes les cartes')),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${widget.title} · ${q.length} carte${q.length > 1 ? 's' : ''} à voir',
                          style: t.bodySmall),
                      const SizedBox(height: 14),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _flipped = !_flipped),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: _flipped ? 1 : 0),
                            duration: const Duration(milliseconds: 300),
                            builder: (context, v, _) {
                              final showBack = v > 0.5;
                              return Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.001)
                                  ..rotateY(pi * v),
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()..rotateY(showBack ? pi : 0),
                                  child: Container(
                                    padding: const EdgeInsets.all(22),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: showBack ? widget.color.withValues(alpha: 0.08) : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: widget.color, width: 2),
                                    ),
                                    child: SingleChildScrollView(
                                      child: Column(children: [
                                        Text(showBack ? 'Réponse' : 'Question',
                                            style: t.bodySmall),
                                        const SizedBox(height: 12),
                                        Text(
                                          showBack ? q.first.back : q.first.front,
                                          textAlign: TextAlign.center,
                                          style: titleStyle(22, weight: showBack ? 600 : 700),
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
                      const SizedBox(height: 14),
                      if (!_flipped)
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: widget.color),
                          onPressed: () => setState(() => _flipped = true),
                          child: const Text('Voir la réponse'),
                        )
                      else
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _answer(false),
                              child: const Text('À revoir'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: JangColors.success),
                              onPressed: () => _answer(true),
                              child: const Text('Je savais'),
                            ),
                          ),
                        ]),
                    ],
                  ),
                ),
    );
  }
}
