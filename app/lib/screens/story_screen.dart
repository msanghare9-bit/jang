import 'package:flutter/material.dart';

import '../services/speech_service.dart';

import '../models.dart';
import '../services/story_service.dart';
import '../theme.dart';
import '../widgets/characters.dart';
import '../widgets/jang_ui.dart';

const _green = Color(0xFF1F9D55);
const _yellow = Color(0xFFF6B81C);

/// Carte « Mon histoire » en haut de la liste des leçons d'une matière.
class StoryCard extends StatefulWidget {
  final Subject subject;
  final List<Lesson> lessons;
  const StoryCard({super.key, required this.subject, required this.lessons});

  @override
  State<StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends State<StoryCard> {
  StoryState? _state;
  int _opened = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StoryCard old) {
    super.didUpdateWidget(old);
    _load();
  }

  Future<void> _load() async {
    StoryState? st;
    var opened = 0;
    try {
      st = await StoryService.instance.stateFor(widget.subject, lessons: widget.lessons);
      if (st != null) opened = await StoryService.instance.opened(st.season);
    } catch (e) {
      debugPrint('Histoire : $e');
    }
    if (mounted) {
      setState(() {
        _state = st;
        _opened = opened;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    if (!_loaded) return const SizedBox.shrink();
    if (st == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF6F2EA), borderRadius: BorderRadius.circular(20)),
          child: const Row(children: [
            CharacterView(Chars.lion, size: 60),
            SizedBox(width: 10),
            Expanded(
              child: Text('📖 Mon histoire : les aventures de Gaïndé arrivent bientôt pour cette matière !',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );
    }
    final n = st.season.episodes.length;
    final u = st.unlocked;
    final fresh = u > _opened;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: _green,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => StoryScreen(state: st)));
            _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const CharacterView(Chars.lion, size: 66),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text('📖 ${st.season.title}',
                          style: titleStyle(17, color: Colors.white, weight: 800)),
                    ),
                    if (fresh)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: _yellow, borderRadius: BorderRadius.circular(10)),
                        child: const Text('Nouveau', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text('$u épisode${u > 1 ? 's' : ''} sur $n',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: n == 0 ? 0 : u / n,
                      minHeight: 8,
                      color: _yellow,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      st.lessonsToNext == 0
                          ? 'Toute l\'histoire est ouverte !'
                          : 'Prochain épisode dans ${st.lessonsToNext} leçon${st.lessonsToNext > 1 ? 's' : ''} (exercices faits)',
                      style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Liste des épisodes d'une saison.
class StoryScreen extends StatefulWidget {
  final StoryState state;
  const StoryScreen({super.key, required this.state});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  int _opened = 0;

  @override
  void initState() {
    super.initState();
    StoryService.instance.opened(widget.state.season).then((v) {
      if (mounted) setState(() => _opened = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final s = st.season;
    final u = st.unlocked;
    return Scaffold(
      appBar: AppBar(title: Text('Mon histoire', style: titleStyle(20))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(children: [
            const CharacterView(Chars.lion, size: 80),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: titleStyle(22, weight: 800)),
                Text('$u épisode${u > 1 ? 's' : ''} ouvert${u > 1 ? 's' : ''} sur ${s.episodes.length}.\n'
                    'Un nouvel épisode toutes les 3 leçons terminées.',
                    style: const TextStyle(color: JangColors.textSecondary)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          for (var i = 0; i < s.episodes.length; i++) _tile(i, u),
        ],
      ),
    );
  }

  Widget _tile(int i, int unlocked) {
    final st = widget.state;
    final ep = st.season.episodes[i];
    final open = i < unlocked;
    final fresh = open && i >= _opened;
    final need = st.need(i);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: fresh ? const Color(0xFFFFF4D6) : const Color(0xFFF6F2EA),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: !open
              ? null
              : () async {
                  await StoryService.instance.markOpened(st.season, i);
                  if (!mounted) return;
                  setState(() => _opened = _opened > i + 1 ? _opened : i + 1);
                  await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => EpisodeScreen(season: st.season, index: i)));
                },
          child: Opacity(
            opacity: open ? 1 : 0.55,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: open ? (fresh ? _yellow : _green) : Colors.grey,
                  child: Text(open ? '${i + 1}' : '🔒',
                      style: TextStyle(
                          color: fresh ? Colors.black : Colors.white, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ep.title + (fresh ? '  ✨ Nouveau' : ''),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(open ? 'Touche pour lire' : 'S\'ouvre après $need leçons terminées',
                        style: const TextStyle(color: JangColors.textSecondary, fontSize: 12.5)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un épisode : une petite bande dessinée.
/// Couleurs (ciel, sol) d'un décor d'histoire : cour, classe, marché, nuit…
(Color, Color) storyColors(String name) => EpisodeScreen._bg(name);

/// Animation d'un personnage à partir de son nom (« danse », « saute »…).
Moves storyMoves(String name) => EpisodeScreen._moves(name);

class EpisodeScreen extends StatelessWidget {
  final StorySeason season;
  final int index;
  const EpisodeScreen({super.key, required this.season, required this.index});

  static (Color, Color) _bg(String name) => switch (name) {
        'classe' => (const Color(0xFFF3E9D2), const Color(0xFFB98B5E)),
        'mer' || 'plage' => (const Color(0xFFCFE8FF), const Color(0xFF5FB3E8)),
        'marche' => (const Color(0xFFFFE3B3), const Color(0xFFE8C48A)),
        'nuit' || 'bibliotheque' => (const Color(0xFF2E2A45), const Color(0xFF4A4466)),
        'maison' => (const Color(0xFFFCE7D6), const Color(0xFFC9A27E)),
        'terrain' => (const Color(0xFFCFE8FF), const Color(0xFF6BBF59)),
        _ => (const Color(0xFFCFE8FF), const Color(0xFFE8D6B0)),
      };

  static Moves _moves(String m) => switch (m) {
        'danse' => Moves.dance,
        'danse2' => Moves.danceAlt,
        'saute' => Moves.jump,
        'balance' => Moves.sway,
        'tangue' => Moves.rock,
        'immobile' => Moves.still,
        _ => Moves.bob,
      };

  @override
  Widget build(BuildContext context) {
    final ep = season.episodes[index];
    final last = index == season.episodes.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text('Épisode ${index + 1}', style: titleStyle(20))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        children: [
          Text(ep.title, style: titleStyle(22, weight: 800)),
          const SizedBox(height: 8),
          for (final p in ep.panels) _panel(p),
          if (ep.words.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFEFE8FF), borderRadius: BorderRadius.circular(14)),
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: 'Mots de l\'épisode : ', style: TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: ep.words.join(' · ')),
              ])),
            ),
          ChunkyButton(
            label: last ? 'FIN DE LA SAISON' : 'RETOUR AUX ÉPISODES',
            color: _green,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _panel(StoryPanel p) {
    final (sky, ground) = _bg(p.background);
    final dark = p.background == 'nuit' || p.background == 'bibliotheque';
    return Container(
      height: 200,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1D1B26), width: 3),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [sky, sky, ground, ground],
          stops: const [0, .62, .62, 1],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        return Stack(children: [
          if (dark) const Positioned(right: 14, top: 10, child: Text('🌙', style: TextStyle(fontSize: 22))),
          for (final a in p.actors)
            Positioned(
              left: (a.x * w).clamp(0.0, w - 20),
              bottom: 4,
              child: CharacterView.of(a.id, size: a.size, moves: _moves(a.moves), flip: a.flip),
            ),
          for (final b in p.bubbles)
            Positioned(
              left: (b.x * w).clamp(0.0, w * .5),
              top: (b.y * h).clamp(0.0, h - 50),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: w * .55),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1D1B26), width: 2),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (b.en.isNotEmpty)
                      GestureDetector(
                        onTap: () => Speech.instance.say(b.en),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                              child: Text(b.en, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
                          const SizedBox(width: 4),
                          const Icon(Icons.volume_up_rounded, size: 16, color: JangColors.primaryDark),
                        ]),
                      ),
                    if (b.fr.isNotEmpty)
                      Text(b.fr,
                          style: const TextStyle(color: JangColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
                  ]),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}
