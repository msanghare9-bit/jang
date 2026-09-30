import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models.dart';
import '../services/progress_repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'quiz_screen.dart';

class LessonScreen extends StatefulWidget {
  final Lesson lesson;
  final Subject subject;
  const LessonScreen({super.key, required this.lesson, required this.subject});

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  YoutubePlayerController? _controller;
  int _playing = -1;

  @override
  void initState() {
    super.initState();
    ProgressRepo.instance.markSeen(widget.lesson);
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  /// Le lecteur n'est créé qu'au premier appui : rien n'est téléchargé avant.
  void _play(int index) {
    final id = widget.lesson.videos[index].youtubeId;
    setState(() {
      _playing = index;
      if (_controller == null) {
        _controller = YoutubePlayerController.fromVideoId(
          videoId: id,
          autoPlay: true,
          params: const YoutubePlayerParams(
            showFullscreenButton: true,
            strictRelatedVideos: true,
            showVideoAnnotations: false,
          ),
        );
      } else {
        _controller!.loadVideoById(videoId: id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return _page(context, null);
    return YoutubePlayerScaffold(
      controller: c,
      aspectRatio: 16 / 9,
      defaultOrientations: const [DeviceOrientation.portraitUp],
      builder: (context, player) => _page(context, player),
    );
  }

  Widget _page(BuildContext context, Widget? player) {
    final lesson = widget.lesson;
    final color = JangColors.fromHex(widget.subject.color);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name, style: titleStyle(19, color: Colors.white)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
        children: [
          Text(lesson.title, style: titleStyle(26)),
          if (lesson.videos.isNotEmpty) ...[
            SectionTitle('Vidéos', color: color),
            if (player != null)
              ClipRRect(borderRadius: BorderRadius.circular(10), child: player),
            if (player != null) const SizedBox(height: 10),
            for (var i = 0; i < lesson.videos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  color: i == _playing ? color.withValues(alpha: 0.08) : Colors.white,
                  child: ListTile(
                    minVerticalPadding: 12,
                    leading: CircleAvatar(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      child: Icon(i == _playing ? Icons.graphic_eq : Icons.play_arrow),
                    ),
                    title: Text(
                      lesson.videos[i].title.isEmpty ? 'Vidéo ${i + 1}' : lesson.videos[i].title,
                      style: t.titleSmall,
                    ),
                    subtitle: Text(i == _playing ? 'En lecture' : 'Appuie pour regarder',
                        style: t.bodySmall),
                    onTap: () => _play(i),
                  ),
                ),
              ),
            Text('Les vidéos demandent une connexion internet.', style: t.bodySmall),
          ],
          if (lesson.body.trim().isNotEmpty) ...[
            SectionTitle('Leçon', color: color),
            LessonText(lesson.body, accent: color),
          ],
          if (lesson.quiz.isNotEmpty) ...[
            SectionTitle('QCM', color: color),
            _QuizCard(lesson: lesson, subject: widget.subject, color: color),
          ],
          if (lesson.videos.isEmpty && lesson.body.trim().isEmpty && lesson.quiz.isEmpty)
            const EmptyState(
              icon: Icons.hourglass_empty,
              title: 'Leçon en préparation',
              message: 'Son contenu sera bientôt disponible.',
            ),
        ],
      ),
    );
  }
}

class _QuizCard extends StatelessWidget {
  final Lesson lesson;
  final Subject subject;
  final Color color;
  const _QuizCard({required this.lesson, required this.subject, required this.color});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ProgressRepo.instance.revision,
      builder: (context, _, __) {
        final p = ProgressRepo.instance.of(lesson.id);
        final n = lesson.quiz.length;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('$n question${n > 1 ? 's' : ''} pour vérifier ce que tu as compris.'),
                if (p?.quizDone == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Meilleure note : ${p!.bestScore}/${p.total} · dernière : ${p.lastScore}/${p.total}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => QuizScreen(lesson: lesson, subject: subject)),
                  ),
                  child: Text(p?.quizDone == true ? 'Refaire le QCM' : 'Commencer le QCM'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
