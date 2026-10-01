import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models.dart';
import '../services/content_repo.dart';
import '../services/flashcard_service.dart';
import '../services/progress_repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/discussion.dart';
import 'flashcards_screen.dart';
import 'quiz_screen.dart';
import 'tutor_screen.dart';

class LessonScreen extends StatefulWidget {
  final Lesson lesson;
  final Subject subject;

  /// Aperçu du responsable : rien n'est enregistré dans la progression.
  final bool preview;
  const LessonScreen(
      {super.key, required this.lesson, required this.subject, this.preview = false});

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  static const _scales = [1.0, 1.15, 1.3];

  YoutubePlayerController? _controller;
  int _playing = -1;
  double _scale = 1;
  int _position = 0; // 1-based, 0 = inconnu
  int _count = 0;
  FlashcardDeck? _deck;
  bool _revStarted = false;
  bool _videoSeen = false;

  String get _videoKey => 'video_seen_${widget.lesson.id}';

  @override
  void initState() {
    super.initState();
    if (!widget.preview) ProgressRepo.instance.markSeen(widget.lesson);
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = prefs.getDouble('lesson_scale') ?? 1;
    final videoSeen = prefs.getBool(_videoKey) ?? false;
    final repo = ContentRepo.instance;
    var pos = 0, count = 0;
    if (!widget.preview) {
      final all = await repo.lessonsOfSubject(widget.subject.id);
      count = all.length;
      pos = all.indexWhere((l) => l.id == widget.lesson.id) + 1;
    }
    final deck = await repo.deck(widget.lesson.id);
    final started = deck == null ? false : await FlashcardService.instance.started(deck);
    if (!mounted) return;
    setState(() {
      _scale = scale;
      _videoSeen = videoSeen;
      _position = pos;
      _count = count;
      _deck = (deck != null && deck.cards.isNotEmpty) ? deck : null;
      _revStarted = started;
    });
  }

  Future<void> _toggleScale() async {
    final i = _scales.indexOf(_scale);
    final next = _scales[(i + 1) % _scales.length];
    setState(() => _scale = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('lesson_scale', next);
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
      _videoSeen = true;
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
    if (!widget.preview) {
      SharedPreferences.getInstance().then((p) => p.setBool(_videoKey, true));
    }
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

  int get _readMinutes {
    final words = RegExp(r'\S+').allMatches(widget.lesson.body).length;
    return (words / 130).ceil().clamp(1, 99).toInt();
  }

  Widget _page(BuildContext context, Widget? player) {
    final lesson = widget.lesson;
    final color = JangColors.fromHex(widget.subject.color);
    final t = Theme.of(context).textTheme;
    final hasBody = lesson.body.trim().isNotEmpty;
    final empty = lesson.videos.isEmpty && !hasBody && lesson.quiz.isEmpty;

    final meta = <String>[
      if (hasBody) 'Lecture : $_readMinutes min',
      if (lesson.videos.isNotEmpty)
        '${lesson.videos.length} vidéo${lesson.videos.length > 1 ? 's' : ''}',
      if (lesson.quiz.isNotEmpty) 'QCM de ${lesson.quiz.length} question${lesson.quiz.length > 1 ? 's' : ''}',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.preview ? 'Aperçu élève' : widget.subject.name,
            style: titleStyle(19, color: Colors.white)),
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _toggleScale,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: 'A', style: TextStyle(fontSize: 13)),
                const TextSpan(text: ' '),
                TextSpan(
                    text: 'A',
                    style: TextStyle(
                        fontSize: 18, fontWeight: _scale > 1 ? FontWeight.w800 : FontWeight.w600)),
              ])),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          // ---------- Bandeau ----------
          Container(
            color: color,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_position > 0)
                  Text('Leçon $_position sur $_count',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
                const SizedBox(height: 4),
                Text(lesson.title.isEmpty ? 'Sans titre' : lesson.title,
                    style: titleStyle(27, color: Colors.white, weight: 800)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(meta.join(' · '),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
                ],
              ],
            ),
          ),
          if (!empty) _steps(color),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (lesson.videos.isNotEmpty) ...[
                  SectionTitle('Vidéo${lesson.videos.length > 1 ? 's' : ''}', color: color),
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
                            lesson.videos[i].title.isEmpty
                                ? 'Vidéo ${i + 1}'
                                : lesson.videos[i].title,
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
                if (hasBody) ...[
                  if (lesson.videos.isNotEmpty) SectionTitle('La leçon', color: color),
                  if (lesson.videos.isEmpty) const SizedBox(height: 12),
                  LessonText(lesson.body, accent: color, scale: _scale),
                ],
                if (empty)
                  const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: EmptyState(
                      icon: Icons.hourglass_empty,
                      title: 'Leçon en préparation',
                      message: 'Son contenu sera bientôt disponible.',
                    ),
                  ),
                const SizedBox(height: 22),
                if (lesson.quiz.isNotEmpty) _QuizButton(lesson: lesson, subject: widget.subject, color: color, preview: widget.preview),
                if (_deck != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    icon: const Icon(Icons.style_outlined),
                    label: Text(
                        'Révision : ${_deck!.cards.length} carte${_deck!.cards.length > 1 ? 's' : ''}'),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => FlashcardsScreen(
                                deck: _deck!, title: lesson.title, color: color)),
                      );
                      _load();
                    },
                  ),
                ],
                const SizedBox(height: 18),
                Card(
                  child: ListTile(
                    minVerticalPadding: 12,
                    leading: CircleAvatar(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.school_outlined),
                    ),
                    title: Text('Demander au Prof', style: t.titleSmall),
                    subtitle: Text('Il t\'explique la leçon en français simple.',
                        style: t.bodySmall),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.preview
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      TutorScreen(lesson: lesson, subject: widget.subject)),
                            ),
                  ),
                ),
                if (!widget.preview) ...[
                  SectionTitle('Ton avis sur la leçon', color: color),
                  _VoteRow(lesson: lesson, color: color),
                  const SizedBox(height: 8),
                  SectionTitle('Questions des élèves', color: color),
                  DiscussionSection(lesson: lesson, color: color),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _steps(Color color) {
    final lesson = widget.lesson;
    final p = ProgressRepo.instance.of(lesson.id);
    final steps = <(String, bool)>[
      if (lesson.videos.isNotEmpty) ('Vidéo', _videoSeen),
      if (lesson.body.trim().isNotEmpty) ('Leçon', p?.seen == true || widget.preview),
      if (lesson.quiz.isNotEmpty) ('QCM', p?.quizDone == true),
      if (_deck != null) ('Révision', _revStarted),
    ];
    if (steps.length < 2) return const SizedBox.shrink();
    final current = steps.indexWhere((s) => !s.$2);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: JangColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: steps[i].$2 ? JangColors.primary : Colors.white,
                      border: Border.all(
                        width: 2,
                        color: steps[i].$2
                            ? JangColors.primary
                            : (i == current ? color : JangColors.border),
                      ),
                    ),
                    child: steps[i].$2
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text('${i + 1}',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: i == current ? color : JangColors.textSecondary)),
                  ),
                  const SizedBox(height: 4),
                  Text(steps[i].$1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == current ? FontWeight.w700 : FontWeight.w400,
                        color: i == current ? JangColors.text : JangColors.textSecondary,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QuizButton extends StatelessWidget {
  final Lesson lesson;
  final Subject subject;
  final Color color;
  final bool preview;
  const _QuizButton(
      {required this.lesson, required this.subject, required this.color, required this.preview});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ProgressRepo.instance.revision,
      builder: (context, _, __) {
        final p = ProgressRepo.instance.of(lesson.id);
        final n = lesson.quiz.length;
        final done = p?.quizDone == true && !preview;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              icon: const Icon(Icons.quiz_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => QuizScreen(lesson: lesson, subject: subject)),
              ),
              label: Text(done
                  ? 'Refaire le QCM'
                  : 'Faire le QCM ($n question${n > 1 ? 's' : ''})'),
            ),
            if (done) ...[
              const SizedBox(height: 6),
              Text(
                'Meilleure note : ${p!.bestScore}/${p.total} · dernière : ${p.lastScore}/${p.total}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _VoteRow extends StatelessWidget {
  final Lesson lesson;
  final Color color;
  const _VoteRow({required this.lesson, required this.color});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ProgressRepo.instance.revision,
      builder: (context, _, __) {
        final v = ProgressRepo.instance.of(lesson.id)?.vote ?? 0;
        Widget button(int value, IconData on, IconData off, String label) {
          final active = v == value;
          return Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: active ? Colors.white : color,
                backgroundColor: active ? color : null,
                side: BorderSide(color: color),
              ),
              onPressed: () => ProgressRepo.instance.vote(lesson, active ? 0 : value),
              icon: Icon(active ? on : off),
              label: Text(label),
            ),
          );
        }

        return Row(children: [
          button(1, Icons.thumb_up, Icons.thumb_up_outlined, 'J\'aime'),
          const SizedBox(width: 10),
          button(-1, Icons.thumb_down, Icons.thumb_down_outlined, 'Je n\'aime pas'),
        ]);
      },
    );
  }
}
