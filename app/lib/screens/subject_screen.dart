
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../services/progress_repo.dart';
import '../services/speech_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/characters.dart';
import '../widgets/fun.dart';
import '../widgets/class_section.dart';
import '../widgets/jang_ui.dart';
import 'flashcards_screen.dart';
import 'lesson_screen.dart';
import 'story_screen.dart';
import 'mission/learn_mode.dart';
import '../services/mission_service.dart';

class SubjectScreen extends StatefulWidget {
  final Subject subject;

  /// Parcours en missions de la matière : affiche le choix « Je pratique / Je lis le cours ».
  final Course? course;
  const SubjectScreen({super.key, required this.subject, this.course});

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
      await repo.lessonsOfSubject(widget.subject.id,
          examId: AuthService.instance.profile.value?.examId),
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
                            const CharacterView(Chars.modou, size: 70, moves: Moves.sway),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  if (widget.course != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: LearnModeSwitch(current: LearnMode.read, subject: widget.subject, course: widget.course!),
                    ),
                  ClassSection(subject: widget.subject, padding: const EdgeInsets.fromLTRB(16, 14, 16, 0)),
                  if (data != null && lessons.isNotEmpty && widget.course == null)
                    StoryCard(subject: widget.subject, lessons: lessons),
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
                          for (var i = 0; i < lessons.length; i++) ...[
                            if (lessonSection(lessons[i].title).isNotEmpty &&
                                (i == 0 ||
                                    lessonSection(lessons[i].title) !=
                                        lessonSection(lessons[i - 1].title)))
                              _sectionHeader(lessonSection(lessons[i].title), color),
                            if (i == current)
                              CharacterSays(
                                'gainde',
                                i == 0
                                    ? 'On commence ici ! Suis-moi, je connais le chemin… enfin presque 🦁'
                                    : 'C\'est ici que tu t\'es arrêté. Allez, leçon ${i + 1} ! Comprendre nga bou bax !',
                              ),
                            _step(context, i, lessons[i], decks[lessons[i].id], color,
                                current: i == current, last: i == lessons.length - 1),
                          ],
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
    final Color nodeBg = done ? JangColors.ocre : (current ? JangColors.primary : const Color(0xFFE5E5E5));
    final Color nodeFg = done ? JangColors.text : (current ? Colors.white : const Color(0xFFAFAFAF));
    void open() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => LessonScreen(lesson: l, subject: widget.subject)),
        );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 56,
            child: Column(children: [
              const SizedBox(height: 8),
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nodeBg,
                  shape: BoxShape.circle,
                  border: current ? Border.all(color: JangColors.noteBg, width: 4) : null,
                  boxShadow: [
                    BoxShadow(color: JangColors.darker(nodeBg, 0.12), offset: const Offset(0, 4)),
                  ],
                ),
                child: done
                    ? const Icon(Icons.star_rounded, color: Colors.white, size: 28)
                    : Text('${index + 1}', style: titleStyle(19, color: nodeFg, weight: 800)),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 4,
                    margin: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(
                      color: done ? JangColors.ocre.withValues(alpha: 0.5) : JangColors.border,
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
                    border: Border.all(color: current ? JangColors.primary : JangColors.border, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: current ? JangColors.primaryDark : JangColors.border,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (splitLessonTitle(l.title).$1.isNotEmpty)
                            Text(splitLessonTitle(l.title).$1.toUpperCase(),
                                style: TextStyle(
                                    color: JangColors.darker(color, 0.05),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.7)),
                          Text(splitLessonTitle(l.title).$2, style: titleStyle(18, weight: 800)),
                          const SizedBox(height: 6),
                          Row(children: [
                            Icon(done ? Icons.check_circle_rounded : Icons.play_circle_outline_rounded,
                                size: 16, color: done ? JangColors.success : JangColors.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(child: Text(_details(l, deck, p), style: t.bodySmall)),
                          ]),
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
                                  FlashcardsScreen(
                                  deck: deck,
                                  title: l.title,
                                  color: color,
                                  speak: Speech.isEnglish(widget.subject.name))),
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

  /// Titre de rubrique (Vocabulaire, Fonctions, Grammaire…) entre les leçons.
  Widget _sectionHeader(String name, Color color) {
    final n = name.toLowerCase();
    final (emoji, label) = n.startsWith('vocab')
        ? ('📚', 'Vocabulaire')
        : n.startsWith('function')
            ? ('💬', 'Fonctions de la langue')
            : n.startsWith('gramm')
                ? ('✏️', 'Grammaire')
                : ('📌', name);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Text(label, style: titleStyle(20, color: JangColors.darker(color, 0.1), weight: 800)),
        ]),
      ),
    );
  }

  String _details(Lesson l, FlashcardDeck? deck, LessonProgress? p) {
    final parts = <String>[];
    if (p?.quizDone == true) {
      parts.add('Exercices ${p!.bestScore}/${p.total}');
    } else if (l.quiz.isNotEmpty) {
      parts.add('Exercices ${l.quiz.length}');
    }
    if (l.videos.isNotEmpty) parts.add('${l.videos.length} vidéo${l.videos.length > 1 ? 's' : ''}');
    if (deck != null) parts.add('révision ${deck.cards.length}');
    if (parts.isEmpty && l.body.trim().isNotEmpty) parts.add('leçon');
    return parts.isEmpty ? 'En préparation' : parts.join(' · ');
  }
}
