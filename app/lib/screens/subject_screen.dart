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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name, style: titleStyle(21, color: Colors.white)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<(List<Lesson>, Map<String, FlashcardDeck>)>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (lessons, decks) = snap.data!;
          if (lessons.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.hourglass_empty,
                title: 'Pas encore de leçon',
                message: 'Les leçons de cette matière apparaîtront ici.',
              ),
            );
          }
          return ValueListenableBuilder(
            valueListenable: ProgressRepo.instance.revision,
            builder: (context, _, __) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                Text('${lessons.length} leçon${lessons.length > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                for (var i = 0; i < lessons.length; i++)
                  _lessonTile(context, i, lessons[i], decks[lessons[i].id], color),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _lessonTile(
      BuildContext context, int index, Lesson l, FlashcardDeck? deck, Color color) {
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
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => LessonScreen(lesson: l, subject: widget.subject)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p?.seen == true ? color : color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('${index + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: p?.seen == true ? Colors.white : color)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.title, style: t.titleMedium),
                      const SizedBox(height: 3),
                      Text(_details(l, deck), style: t.bodySmall),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
                if (deck != null)
                  IconButton(
                    tooltip: 'Révision',
                    color: color,
                    icon: const Icon(Icons.style_outlined),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => FlashcardsScreen(deck: deck, title: l.title, color: color)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _details(Lesson l, FlashcardDeck? deck) {
    final parts = <String>[];
    if (l.videos.isNotEmpty) parts.add('${l.videos.length} vidéo${l.videos.length > 1 ? 's' : ''}');
    if (l.body.trim().isNotEmpty) parts.add('leçon');
    if (l.quiz.isNotEmpty) parts.add('QCM ${l.quiz.length}');
    if (deck != null) parts.add('révision ${deck.cards.length}');
    return parts.isEmpty ? 'En préparation' : parts.join(' · ');
  }
}
