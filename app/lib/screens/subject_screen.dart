import 'package:flutter/material.dart';

import '../models.dart';
import '../services/content_repo.dart';
import '../services/progress_repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'flashcards_screen.dart';
import 'lesson_screen.dart';

class SubjectScreen extends StatefulWidget {
  final Subject subject;
  const SubjectScreen({super.key, required this.subject});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  late Future<(List<Chapter>, List<Lesson>, Map<String, FlashcardDeck>)> _future;

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

  Future<(List<Chapter>, List<Lesson>, Map<String, FlashcardDeck>)> _load() async {
    final repo = ContentRepo.instance;
    return (
      await repo.chapters(widget.subject.id),
      await repo.lessonsOfSubject(widget.subject.id),
      await repo.decksOfSubject(widget.subject.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(widget.subject.color);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name, style: titleStyle(21, color: Colors.white)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<(List<Chapter>, List<Lesson>, Map<String, FlashcardDeck>)>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (chapters, lessons, decks) = snap.data!;
          if (chapters.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.hourglass_empty,
                title: 'Pas encore de chapitre',
                message: 'Les chapitres de cette matière apparaîtront ici.',
              ),
            );
          }
          return ValueListenableBuilder(
            valueListenable: ProgressRepo.instance.revision,
            builder: (context, _, __) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                for (var i = 0; i < chapters.length; i++) ...[
                  SectionTitle('${i + 1}. ${chapters[i].title}', color: color),
                  ..._lessonTiles(context, chapters[i], lessons, color),
                  if (decks[chapters[i].id] != null && decks[chapters[i].id]!.cards.isNotEmpty)
                    _deckTile(context, chapters[i], decks[chapters[i].id]!, color),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _lessonTiles(
      BuildContext context, Chapter chapter, List<Lesson> all, Color color) {
    final lessons = all.where((l) => l.chapterId == chapter.id).toList();
    if (lessons.isEmpty) {
      return [
        Text('Leçons à venir.', style: Theme.of(context).textTheme.bodySmall),
      ];
    }
    return lessons.map((l) {
      final p = ProgressRepo.instance.of(l.id);
      Widget? trailing;
      if (p?.quizDone == true) {
        final ok = p!.bestScore! * 2 >= p.total;
        trailing = Pill('QCM ${p.bestScore}/${p.total}',
            color: ok ? JangColors.success : JangColors.error,
            background: ok ? JangColors.successBg : JangColors.errorBg);
      } else if (p?.seen == true) {
        trailing = const Pill('Lue', color: JangColors.textSecondary, background: JangColors.noteBg);
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ListTile(
            minVerticalPadding: 14,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            title: Text(l.title, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_details(l), style: Theme.of(context).textTheme.bodySmall),
            ),
            trailing: trailing,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => LessonScreen(lesson: l, subject: widget.subject)),
            ),
          ),
        ),
      );
    }).toList();
  }

  String _details(Lesson l) {
    final parts = <String>[];
    if (l.videos.isNotEmpty) parts.add('${l.videos.length} vidéo${l.videos.length > 1 ? 's' : ''}');
    if (l.body.trim().isNotEmpty) parts.add('leçon écrite');
    if (l.quiz.isNotEmpty) parts.add('QCM de ${l.quiz.length} question${l.quiz.length > 1 ? 's' : ''}');
    return parts.isEmpty ? 'En préparation' : parts.join(' · ');
  }

  Widget _deckTile(BuildContext context, Chapter chapter, FlashcardDeck deck, Color color) {
    final n = deck.cards.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: color.withValues(alpha: 0.06),
        child: ListTile(
          minVerticalPadding: 12,
          leading: Icon(Icons.style_outlined, color: color),
          title: Text('Flashcards du chapitre', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text('$n carte${n > 1 ? 's' : ''} pour mémoriser l\'essentiel',
              style: Theme.of(context).textTheme.bodySmall),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    FlashcardsScreen(deck: deck, title: chapter.title, color: color)),
          ),
        ),
      ),
    );
  }
}
