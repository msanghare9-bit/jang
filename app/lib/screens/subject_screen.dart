import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/content_repo.dart';
import '../services/progress_repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/jang_ui.dart';
import 'flashcards_screen.dart';
import 'lesson_screen.dart';

class SubjectScreen extends StatefulWidget {
  final Subject subject;
  const SubjectScreen({super.key, required this.subject});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  late Future<(List<Lesson>, Map<String, FlashcardDeck>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    ContentRepo.instance.revision.addListener(_reload);
  }

  @override
  void dispose() {
    ContentRepo.instance.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<(List<Lesson>, Map<String, FlashcardDeck>)> _load() async {
    final repo = ContentRepo.instance;
    return (
      await repo.lessonsOfSubject(widget.subject.id),
      await repo.decksOfSubject(widget.subject.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(widget.subject.color);
    final fg = JangColors.on(color);
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: FutureBuilder<(List<Lesson>, Map<String, FlashcardDeck>)>(
        future: _future,
        builder: (context, snap) {
          final data = snap.data;
          return ValueListenableBuilder(
            valueListenable: ProgressRepo.instance.revision,
            builder: (context, _, __) {
              final lessons = data?.$1 ?? const <Lesson>[];
              final decks = data?.$2 ?? const <String, FlashcardDeck>{};
              final seen = lessons.where((l) => ProgressRepo.instance.of(l.id)?.seen == true).length;
              final current = lessons.indexWhere((l) => ProgressRepo.instance.of(l.id)?.seen != true);
              return ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  WaxHeader(
                    color: color,
                    padding: EdgeInsets.fromLTRB(8, top + 4, 20, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.arrow_back_rounded, color: fg),
                          ),
                          const Spacer(),
                          if (lessons.isNotEmpty) Chip2('$seen / ${lessons.length} vues'),
                        ]),
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 4),
                          child: Row(children: [
                            Text(subjectEmoji(widget.subject.name), style: const TextStyle(fontSize: 30)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(widget.subject.name,
                                  style: titleStyle(32, color: fg, weight: 800)),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  if (data == null)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (lessons.isEmpty)
                    const EmptyState(
                      icon: Icons.hourglass_empty,
                      title: 'Pas encore de leçon',
                      message: 'Les leçons de cette matière apparaîtront ici.',
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                      child: Column(
                        children: [
                          for (var i = 0; i < lessons.length; i++)
                            _step(context, i, lessons[i], decks[lessons[i].id], color,
                                current: i == current, last: i == lessons.length - 1),
                        ],
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _step(BuildContext context, int index, Lesson l, FlashcardDeck? deck, Color color,
      {required bool current, required bool last}) {
    final p = ProgressRepo.instance.of(l.id);
    final done = p?.seen == true;
    final t = Theme.of(context).textTheme;
    final Color nodeBg = done ? JangColors.success : (current ? JangColors.ocre : Colors.white);
    final Color nodeFg = done ? Colors.white : (current ? JangColors.text : JangColors.textSecondary);
    void open() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => LessonScreen(lesson: l, subject: widget.subject)),
        );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Column(children: [
              const SizedBox(height: 8),
              Transform.rotate(
                angle: pi / 4,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: nodeBg,
                    borderRadius: BorderRadius.circular(11),
                    border: done || current ? null : Border.all(color: JangColors.border, width: 2),
                    boxShadow: done || current
                        ? [BoxShadow(color: JangColors.darker(nodeBg, 0.15), offset: const Offset(3, 3))]
                        : null,
                  ),
                  child: Transform.rotate(
                    angle: -pi / 4,
                    child: done
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                        : Text('${index + 1}', style: titleStyle(19, color: nodeFg, weight: 800)),
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 4,
                    margin: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(
                      color: done ? JangColors.success.withValues(alpha: 0.4) : JangColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: open,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: current ? JangColors.ocre : JangColors.border, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: current ? JangColors.ocre : JangColors.border,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.title, style: titleStyle(18, weight: 800)),
                          const SizedBox(height: 2),
                          Text(_details(l, deck, p), style: t.bodySmall),
                          if (current) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ChunkyButton(label: 'Commencer', onPressed: open),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (deck != null)
                      IconButton(
                        tooltip: 'Révision',
                        color: color,
                        icon: const Icon(Icons.style_rounded),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  FlashcardsScreen(deck: deck, title: l.title, color: color)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _details(Lesson l, FlashcardDeck? deck, LessonProgress? p) {
    final parts = <String>[];
    if (p?.quizDone == true) {
      parts.add('QCM ${p!.bestScore}/${p.total}');
    } else if (l.quiz.isNotEmpty) {
      parts.add('QCM ${l.quiz.length}');
    }
    if (l.videos.isNotEmpty) parts.add('${l.videos.length} vidéo${l.videos.length > 1 ? 's' : ''}');
    if (deck != null) parts.add('révision ${deck.cards.length}');
    if (parts.isEmpty && l.body.trim().isNotEmpty) parts.add('leçon');
    return parts.isEmpty ? 'En préparation' : parts.join(' · ');
  }
}
