import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models.dart';
import '../../services/mission_service.dart';
import '../../services/sheep_service.dart';
import '../../services/speech_service.dart';
import '../../services/story_service.dart';
import '../../theme.dart';
import '../../widgets/characters.dart';
import '../../widgets/jang_ui.dart';
import '../../widgets/say.dart';
import '../story_screen.dart';
import '../subject_screen.dart';

const _violet = Color(0xFF8B5CF6);
const _violetBg = Color(0xFFF1EBFF);

/// Texte simplifié pour comparer les réponses (minuscules, sans accents ni ponctuation).
String normAnswer(String s) {
  var t = s.toLowerCase().replaceAll(RegExp('[’`\']'), '');
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final ch in t.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  t = b.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Vrai si chaque groupe de mots-clés est présent (« im|i am » : l'un ou l'autre).
bool hasKeys(String answer, List<String> keys) {
  final a = ' ${normAnswer(answer)} ';
  for (final group in keys) {
    final ok = group.split('|').any((k) => k.trim().isNotEmpty && a.contains(' ${normAnswer(k)} '));
    if (!ok) return false;
  }
  return true;
}

/// Une mission : 6 temps (mes mots, je regarde, je comprends, j'aide Gaïndé, je parle, je garde).
class MissionScreen extends StatefulWidget {
  final Mission mission;
  final Subject subject;
  const MissionScreen({super.key, required this.mission, required this.subject});

  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> {
  static const _steps = ['Mes mots', 'Je regarde', 'Je comprends', 'J\'aide Gaïndé', 'Je parle', 'Je garde'];
  int _phase = 0;
  String _phrase = '';

  Mission get m => widget.mission;

  @override
  void initState() {
    super.initState();
    // Une mission sans mots commence à la scène.
    if (m.words.isEmpty) _phase = 1;
  }

  void _next() {
    setState(() {
      _phase++;
      if (_phase == 2 && m.questions.isEmpty) _phase++;
      if (_phase == 3 && m.steps.isEmpty) _phase++;
      if (_phase == 4 && m.turns.isEmpty) _phase++;
    });
  }

  Future<void> _finish(int canDo) async {
    final first = MissionService.instance.finish(m, phrase: _phrase);
    if (canDo > 0) MissionService.instance.setCanDo(m, canDo);
    if (first) await SheepService.instance.feed();
    final ep = first ? await StoryService.instance.newlyUnlocked(widget.subject) : null;
    if (!mounted) return;
    if (ep != null) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Nouvelle histoire !', style: titleStyle(22)),
          content: Text('L\'épisode « $ep » est ouvert. Va le lire dans « Mon histoire ».'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Super !'))],
        ),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    SpeechInput.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Row(children: [
              IconButton(
                  tooltip: 'Quitter la mission',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Row(children: [
                  for (var i = 0; i < 6; i++)
                    Expanded(
                      child: Container(
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i < _phase ? JangColors.success : (i == _phase ? JangColors.primary : JangColors.border),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ]),
              ),
              IconButton(
                tooltip: 'Boîte à outils',
                icon: const Icon(Icons.menu_book_outlined, color: JangColors.primaryDark),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => SubjectScreen(subject: widget.subject))),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Temps $_phase · ${_steps[_phase]}'.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w800, color: JangColors.primaryDark)),
            ),
          ),
          Expanded(
            child: switch (_phase) {
              0 => _WordsPhase(mission: m, onDone: _next),
              1 => _ObservePhase(mission: m, onDone: _next),
              2 => _UnderstandPhase(mission: m, onDone: _next),
              3 => _TeachPhase(mission: m, onDone: _next),
              4 => _SpeakPhase(
                  mission: m,
                  onDone: (phrase) {
                    _phrase = phrase;
                    _next();
                  }),
              _ => _KeepPhase(mission: m, phrase: _phrase, onFinish: _finish),
            },
          ),
        ]),
      ),
    );
  }
}

// ---------- Éléments communs ----------

/// Bulle d'aide de Kocc Barma.
class KoccSays extends StatelessWidget {
  final String label;
  final Widget child;
  const KoccSays({super.key, this.label = 'Kocc Barma', required this.child});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: _violetBg, border: Border.all(color: _violet, width: 2), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CharacterView(Chars.kocc, size: 46, moves: Moves.still),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: _violet)),
              const SizedBox(height: 2),
              child,
            ]),
          ),
        ]),
      );
}

/// Bulle d'un personnage (anglais + haut-parleur + traduction à la demande).
class _Bubble extends StatefulWidget {
  final String who;
  final String en;
  final String fr;
  final String plain;
  const _Bubble({required this.who, this.en = '', this.fr = '', this.plain = ''});

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  bool _fr = false;

  static const names = {
    'gainde': 'Gaïndé',
    'awa': 'Awa',
    'modou': 'Modou',
    'doudou': 'Doudou',
    'kocc': 'Kocc Barma',
    'bouc': 'Le bouc',
  };

  @override
  Widget build(BuildContext context) {
    final gainde = widget.who == 'gainde';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: gainde ? JangColors.warningBg : Colors.white,
        border: Border.all(color: gainde ? JangColors.ocre : JangColors.border, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CharacterView.of(widget.who, size: 36, moves: Moves.still),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((names[widget.who] ?? widget.who).toUpperCase(),
                style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: JangColors.textSecondary)),
            if (widget.plain.isNotEmpty) Text(widget.plain, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (widget.en.isNotEmpty) Text(widget.en, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            if (widget.fr.isNotEmpty && _fr)
              Text(widget.fr, style: const TextStyle(fontStyle: FontStyle.italic, color: JangColors.textSecondary)),
            if (widget.fr.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _fr = !_fr),
                child: Text(_fr ? 'Cacher' : 'Voir en français',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: JangColors.primaryDark)),
              ),
          ]),
        ),
        if (widget.en.isNotEmpty) SayButton(widget.en),
      ]),
    );
  }
}

/// Décor de la mission avec ses personnages et ses objets.
class _SceneBox extends StatelessWidget {
  final String background;
  final List<String> actors;
  final List<String> objects;
  final double height;
  const _SceneBox({required this.background, this.actors = const [], this.objects = const [], this.height = 170});

  @override
  Widget build(BuildContext context) {
    final (sky, ground) = storyColors(background);
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JangColors.border, width: 2),
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sky, sky, ground, ground],
            stops: const [0, .62, .62, 1]),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (objects.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: 10,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              children: [for (final o in objects) Text(o, style: const TextStyle(fontSize: 38))],
            ),
          ),
        Positioned(
          left: 6,
          right: 6,
          bottom: 2,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [for (final a in actors) CharacterView.of(a, size: 86, moves: Moves.bob)],
          ),
        ),
      ]),
    );
  }
}

Widget _bottom(Widget child) => Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: child);

// ---------- Temps 0 : mes mots ----------

class _WordsPhase extends StatefulWidget {
  final Mission mission;
  final VoidCallback onDone;
  const _WordsPhase({required this.mission, required this.onDone});

  @override
  State<_WordsPhase> createState() => _WordsPhaseState();
}

class _WordsPhaseState extends State<_WordsPhase> {
  final Set<int> _good = {};
  final Set<int> _bad = {};
  MissionWord? _last;

  int get _total => widget.mission.words.where((w) => w.ok).length;

  void _tap(int i) {
    final w = widget.mission.words[i];
    Speech.instance.say(w.word);
    setState(() {
      _last = w;
      (w.ok ? _good : _bad).add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final last = _last;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), children: [
          Text(m.wordsIntro.isEmpty ? 'Quels mots vont avec l\'image ?' : m.wordsIntro, style: titleStyle(22, weight: 800)),
          const SizedBox(height: 8),
          _SceneBox(background: m.scene, actors: m.sceneActors.take(2).toList(), objects: m.objects),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < m.words.length; i++)
              ActionChip(
                onPressed: () => _tap(i),
                avatar: const Icon(Icons.volume_up_rounded, size: 18, color: JangColors.primaryDark),
                label: Text(m.words[i].word, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                backgroundColor: _good.contains(i)
                    ? JangColors.successBg
                    : _bad.contains(i)
                        ? JangColors.errorBg
                        : Colors.white,
                side: BorderSide(
                    color: _good.contains(i)
                        ? JangColors.success
                        : _bad.contains(i)
                            ? JangColors.error
                            : JangColors.border,
                    width: 2),
              ),
          ]),
          if (last != null)
            KoccSays(
              child: Text(
                  last.why.isNotEmpty ? last.why : (last.ok ? 'Oui ! Bravo.' : 'Pas tout à fait. Regarde encore !'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
      Text('Trouvés : ${_good.length} sur $_total. Touche un mot pour l\'écouter.',
          style: const TextStyle(fontWeight: FontWeight.w800, color: JangColors.textSecondary)),
      _bottom(ChunkyButton(label: 'CONTINUER', onPressed: _good.length >= _total ? widget.onDone : null)),
    ]);
  }
}

// ---------- Temps 1 : je regarde ----------

class _ObservePhase extends StatefulWidget {
  final Mission mission;
  final VoidCallback onDone;
  const _ObservePhase({required this.mission, required this.onDone});

  @override
  State<_ObservePhase> createState() => _ObservePhaseState();
}

class _ObservePhaseState extends State<_ObservePhase> {
  int _shown = 0;

  void _more() {
    final lines = widget.mission.lines;
    if (_shown < lines.length) {
      Speech.instance.say(lines[_shown].en);
      setState(() => _shown++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final done = _shown >= m.lines.length;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), children: [
          Text(m.story.isEmpty ? m.title : m.story, style: titleStyle(20, weight: 800)),
          const SizedBox(height: 8),
          _SceneBox(background: m.scene, actors: m.sceneActors, height: 150),
          const SizedBox(height: 10),
          for (var i = 0; i < _shown; i++) _Bubble(who: m.lines[i].who, en: m.lines[i].en, fr: m.lines[i].fr),
          if (done && m.gaindeReaction.isNotEmpty) _Bubble(who: 'gainde', plain: m.gaindeReaction),
        ]),
      ),
      if (done)
        const Text('Tu peux écouter encore.', style: TextStyle(fontWeight: FontWeight.w800, color: JangColors.textSecondary)),
      _bottom(ChunkyButton(label: done ? 'CONTINUER' : (_shown == 0 ? 'ÉCOUTER' : 'LA SUITE'), onPressed: done ? widget.onDone : _more)),
    ]);
  }
}

// ---------- Temps 2 : je comprends ----------

class _UnderstandPhase extends StatefulWidget {
  final Mission mission;
  final VoidCallback onDone;
  const _UnderstandPhase({required this.mission, required this.onDone});

  @override
  State<_UnderstandPhase> createState() => _UnderstandPhaseState();
}

class _UnderstandPhaseState extends State<_UnderstandPhase> {
  int _q = 0;
  final Set<int> _wrong = {};
  bool _ok = false;

  void _answer(int i) {
    final q = widget.mission.questions[_q];
    if (i == q.answer) {
      setState(() => _ok = true);
    } else {
      setState(() => _wrong.add(i));
      if (q.replay >= 0 && q.replay < widget.mission.lines.length) {
        Speech.instance.say(widget.mission.lines[q.replay].en);
      }
    }
  }

  void _next() {
    if (_q + 1 >= widget.mission.questions.length) {
      widget.onDone();
    } else {
      setState(() {
        _q++;
        _wrong.clear();
        _ok = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final q = m.questions[_q];
    final replay = q.replay >= 0 && q.replay < m.lines.length ? m.lines[q.replay] : null;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), children: [
          Text('Question ${_q + 1} sur ${m.questions.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
          KoccSays(child: Text(q.question, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                  alignment: Alignment.centerLeft,
                  backgroundColor: _ok && i == q.answer
                      ? JangColors.successBg
                      : _wrong.contains(i)
                          ? JangColors.errorBg
                          : null,
                ),
                onPressed: _ok || _wrong.contains(i) ? null : () => _answer(i),
                child: Text(q.options[i], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: JangColors.text)),
              ),
            ),
          if (_wrong.isNotEmpty && !_ok && replay != null)
            KoccSays(
              label: 'Kocc Barma · Écoute encore',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Pas tout à fait. Écoute encore :', style: TextStyle(fontWeight: FontWeight.w700)),
                SayText(replay.en),
              ]),
            ),
          if (_ok)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: JangColors.successBg, borderRadius: BorderRadius.circular(12)),
              child: const Text('Oui ! Bien écouté.', style: TextStyle(fontWeight: FontWeight.w800, color: JangColors.successDark)),
            ),
        ]),
      ),
      _bottom(ChunkyButton(label: 'CONTINUER', onPressed: _ok ? _next : null)),
    ]);
  }
}

// ---------- Temps 3 : j'aide Gaïndé ----------

class _TeachPhase extends StatefulWidget {
  final Mission mission;
  final VoidCallback onDone;
  const _TeachPhase({required this.mission, required this.onDone});

  @override
  State<_TeachPhase> createState() => _TeachPhaseState();
}

class _TeachPhaseState extends State<_TeachPhase> {
  static const _tiers = ['Une question', 'Écoute encore', 'Un modèle', 'Le sens'];
  static const _gaindeWrong = [
    'Grrr… j\'ai l\'air bête, là !',
    'Hmm, Awa me regarde bizarrement…',
    'Oups ! Tu es sûr ?',
    'Aide-moi encore, s\'il te plaît !',
  ];
  int _i = 0;
  int _help = 0;
  bool _firstTry = true;
  int _streak = 0;
  bool _ok = false;
  bool _skipped = false;
  String _gaindeSays = '';
  final List<int> _order = [];
  final _text = TextEditingController();

  MissionStep get s => widget.mission.steps[_i];

  void _fail() {
    setState(() {
      _firstTry = false;
      _gaindeSays = _gaindeWrong[_help.clamp(0, 3)];
      _help = (_help + 1).clamp(0, 4);
    });
    final h = _hint;
    if (h != null && h.replay >= 0 && h.replay < widget.mission.lines.length) {
      Speech.instance.say(widget.mission.lines[h.replay].en);
    }
  }

  MissionHint? get _hint => _help == 0 || s.hints.isEmpty ? null : s.hints[(_help - 1).clamp(0, s.hints.length - 1)];

  void _success() {
    final said = switch (s.type) {
      'libre' => _text.text.trim(),
      _ => s.said.isNotEmpty ? s.said : (s.type == 'choix' ? s.options[s.answer] : s.target),
    };
    Speech.instance.say(said);
    setState(() {
      _ok = true;
      _gaindeSays = said;
      _streak = _firstTry ? _streak + 1 : 0;
    });
  }

  void _check() {
    switch (s.type) {
      case 'choix':
        break;
      case 'ordre':
        final got = normAnswer(_order.map((i) => s.tiles[i]).join(' '));
        if (got == normAnswer(s.target)) {
          _success();
        } else {
          _fail();
          setState(_order.clear);
        }
      case 'trou':
        final v = normAnswer(_text.text);
        if (s.accept.map(normAnswer).contains(v)) {
          _success();
        } else {
          _fail();
        }
      default:
        if (hasKeys(_text.text, s.keys)) {
          _success();
        } else {
          _fail();
        }
    }
  }

  void _next() {
    var n = _i + 1;
    // Deux réussites du premier coup : on saute une marche (jamais la dernière).
    var skipped = false;
    if (_streak >= 2 && n < widget.mission.steps.length - 1) {
      n++;
      _streak = 0;
      skipped = true;
    }
    if (n >= widget.mission.steps.length) {
      widget.onDone();
      return;
    }
    setState(() {
      _i = n;
      _help = 0;
      _firstTry = true;
      _ok = false;
      _skipped = skipped;
      _gaindeSays = '';
      _order.clear();
      _text.clear();
    });
  }

  Widget _input() {
    switch (s.type) {
      case 'choix':
        return Column(children: [
          for (var i = 0; i < s.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(14),
                        alignment: Alignment.centerLeft,
                        backgroundColor: _ok && i == s.answer ? JangColors.successBg : null),
                    onPressed: _ok ? null : () => i == s.answer ? _success() : _fail(),
                    child: Text(s.options[i],
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: JangColors.text)),
                  ),
                ),
                const SizedBox(width: 6),
                SayButton(s.options[i], size: 40),
              ]),
            ),
        ]);
      case 'ordre':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.only(bottom: 6),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: JangColors.border, width: 2))),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (var p = 0; p < _order.length; p++)
                ActionChip(
                  label: Text(s.tiles[_order[p]], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  backgroundColor: JangColors.noteBg,
                  onPressed: _ok ? null : () => setState(() => _order.removeAt(p)),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var t = 0; t < s.tiles.length; t++)
              if (!_order.contains(t))
                ActionChip(
                  label: Text(s.tiles[t], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  onPressed: _ok ? null : () => setState(() => _order.add(t)),
                ),
          ]),
          const SizedBox(height: 10),
          if (!_ok)
            FilledButton(onPressed: _order.length == s.tiles.length ? _check : null, child: const Text('Vérifier')),
        ]);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (s.type == 'trou')
            Text('${s.before} ___ ${s.after}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          TextField(
            controller: _text,
            enabled: !_ok,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _check(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
                hintText: s.type == 'trou' ? 'Le mot qui manque' : 'Écris en anglais', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          if (!_ok) FilledButton(onPressed: _check, child: const Text('Vérifier')),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = ['Choisir', 'Remettre dans l\'ordre', 'Compléter', 'Tout seul'];
    final kind = {'choix': 0, 'ordre': 1, 'trou': 2}[s.type] ?? 3;
    final hint = _hint;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), children: [
          Text('Marche ${_i + 1} sur ${widget.mission.steps.length} · ${names[kind]}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: JangColors.textSecondary)),
          if (_skipped)
            const KoccSays(child: Text('Tu vas vite ! On saute une marche.', style: TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            CharacterView(Chars.lion, size: 92, moves: _ok ? Moves.jump : (_help > 0 ? Moves.sway : Moves.bob)),
            const SizedBox(width: 6),
            Expanded(child: _Bubble(who: 'gainde', plain: _gaindeSays.isEmpty ? s.gainde : '', en: _ok ? _gaindeSays : '')),
          ]),
          if (!_ok && _gaindeSays.isNotEmpty) _Bubble(who: 'gainde', plain: _gaindeSays),
          const SizedBox(height: 8),
          _input(),
          if (hint != null && !_ok)
            KoccSays(
              label: 'Kocc Barma · ${_tiers[(_help - 1).clamp(0, 3)]}',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hint.text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (hint.replay >= 0 && hint.replay < widget.mission.lines.length)
                  Padding(padding: const EdgeInsets.only(top: 4), child: SayText(widget.mission.lines[hint.replay].en)),
                const SizedBox(height: 4),
                const Text('À toi ! Aide Gaïndé.', style: TextStyle(color: JangColors.textSecondary)),
              ]),
            ),
          if (_ok)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: JangColors.successBg, borderRadius: BorderRadius.circular(12)),
              child: Text(_firstTry ? 'Du premier coup ! Gaïndé a compris grâce à toi.' : 'Bravo, tu y es arrivé ! Gaïndé a compris.',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: JangColors.successDark)),
            ),
        ]),
      ),
      if (!_ok)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => setState(() {
                _firstTry = false;
                _help = (_help + 1).clamp(0, 4);
              }),
              child: const Text('Je ne sais pas encore'),
            ),
          ),
        ),
      _bottom(ChunkyButton(label: 'CONTINUER', onPressed: _ok ? _next : null)),
    ]);
  }
}

// ---------- Temps 4 : je parle ----------

class _SpeakPhase extends StatefulWidget {
  final Mission mission;
  final ValueChanged<String> onDone;
  const _SpeakPhase({required this.mission, required this.onDone});

  @override
  State<_SpeakPhase> createState() => _SpeakPhaseState();
}

class _SpeakPhaseState extends State<_SpeakPhase> {
  int _t = 0;
  String _mode = 'deux'; // parler | ecrire | deux
  String _heard = '';
  bool _listening = false;
  bool _spokenOk = false;
  int _micTries = 0;
  bool _ok = false;
  String _note = '';
  String _phrase = '';
  final _text = TextEditingController();

  MissionTurn get t => widget.mission.turns[_t];

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final m = p.getString('answer_mode');
      if (m != null && mounted) setState(() => _mode = m);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => Speech.instance.say(t.en));
  }

  Future<void> _setMode(String m) async {
    setState(() => _mode = m);
    (await SharedPreferences.getInstance()).setString('answer_mode', m);
  }

  Future<void> _listen() async {
    setState(() {
      _listening = true;
      _heard = '';
    });
    final started = await SpeechInput.instance.listen(
      onText: (s) => setState(() => _heard = s),
      onDone: (s) {
        setState(() {
          _listening = false;
          _heard = s;
          _micTries++;
        });
        _checkSpoken();
      },
    );
    if (!started && mounted) {
      setState(() {
        _listening = false;
        _micTries = 2;
        _note = 'Le micro ne marche pas sur ce téléphone. Pas grave : écris ta phrase.';
        if (_mode == 'parler') _mode = 'ecrire';
      });
    }
  }

  void _checkSpoken() {
    if (hasKeys(_heard, t.keys)) {
      setState(() {
        _spokenOk = true;
        _note = '';
      });
      if (_mode == 'parler') _accept(_heard);
    } else {
      setState(() => _note = _micTries >= 2
          ? 'Gaïndé n\'a pas bien entendu. Tu peux écrire ta phrase, ou appuyer sur « Je l\'ai dit ».'
          : 'Pardon, Gaïndé a de grosses oreilles mais il n\'a pas bien entendu ! Réessaie. Modèle : ${t.model}');
    }
  }

  void _checkWritten() {
    final v = _text.text.trim();
    if (v.isEmpty) return;
    if (hasKeys(v, t.keys)) {
      if (_mode == 'deux' && !_spokenOk && _micTries < 2) {
        setState(() => _note = 'Bien écrit ! Maintenant, dis-le aussi au micro.');
        return;
      }
      _accept(v);
    } else if (v.split(' ').length == 1) {
      setState(() => _note = 'Presque ! Fais une phrase complète. Modèle : ${t.model}');
    } else {
      setState(() => _note = 'Commence comme le modèle : ${t.model}');
    }
  }

  void _accept(String phrase) {
    Speech.instance.say(t.answer.replaceAll('{dit}', phrase));
    setState(() {
      _ok = true;
      _phrase = phrase;
      _note = '';
    });
  }

  void _next() {
    if (_t + 1 >= widget.mission.turns.length) {
      widget.onDone(_phrase);
      return;
    }
    setState(() {
      _t++;
      _ok = false;
      _spokenOk = false;
      _micTries = 0;
      _heard = '';
      _note = '';
      _text.clear();
    });
    Speech.instance.say(t.en);
  }

  @override
  Widget build(BuildContext context) {
    final speak = _mode != 'ecrire';
    final write = _mode != 'parler';
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            CharacterView.of(t.who, size: 88, moves: _ok ? Moves.dance : Moves.bob),
            const SizedBox(width: 6),
            Expanded(child: _Bubble(who: t.who, en: t.en, fr: t.fr)),
          ]),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'parler', icon: Icon(Icons.mic_none), label: Text('Je parle')),
              ButtonSegment(value: 'ecrire', icon: Icon(Icons.keyboard_outlined), label: Text('J\'écris')),
              ButtonSegment(value: 'deux', icon: Icon(Icons.add), label: Text('Les deux')),
            ],
            selected: {_mode},
            onSelectionChanged: _ok ? null : (v) => _setMode(v.first),
          ),
          const SizedBox(height: 10),
          if (speak && !_ok)
            Row(children: [
              FloatingActionButton(
                heroTag: 'micro',
                backgroundColor: _listening ? JangColors.error : JangColors.primary,
                onPressed: _listening ? SpeechInput.instance.stop : _listen,
                child: Icon(_listening ? Icons.stop : Icons.mic, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    _listening
                        ? 'Je t\'écoute…'
                        : _heard.isEmpty
                            ? 'Appuie et parle en anglais.'
                            : 'Gaïndé a entendu : « $_heard »',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          if (speak && !_ok && _micTries >= 2)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => _accept(t.model.replaceAll('…', '').trim()), child: const Text('Je l\'ai dit')),
            ),
          if (write && !_ok) ...[
            const SizedBox(height: 8),
            Text(_mode == 'deux' ? 'Et maintenant, écris ta phrase :' : 'Écris ta phrase :',
                style: const TextStyle(fontWeight: FontWeight.w800, color: JangColors.textSecondary)),
            const SizedBox(height: 4),
            TextField(
              controller: _text,
              onSubmitted: (_) => _checkWritten(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              decoration: InputDecoration(hintText: t.model, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            FilledButton(onPressed: _checkWritten, child: const Text('Envoyer')),
          ],
          if (_note.isNotEmpty)
            KoccSays(child: Text(_note, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          if (_ok)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: JangColors.successBg, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SayText(t.answer.replaceAll('{dit}', _phrase),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: JangColors.successDark)),
                if (_mode == 'deux' && _spokenOk)
                  const Text('Tu as parlé et écrit. Bravo : bonus !',
                      style: TextStyle(fontWeight: FontWeight.w700, color: JangColors.successDark)),
              ]),
            ),
        ]),
      ),
      _bottom(ChunkyButton(label: 'CONTINUER', onPressed: _ok ? _next : null)),
    ]);
  }
}

// ---------- Temps 5 : je garde ----------

class _KeepPhase extends StatefulWidget {
  final Mission mission;
  final String phrase;
  final Future<void> Function(int canDo) onFinish;
  const _KeepPhase({required this.mission, required this.phrase, required this.onFinish});

  @override
  State<_KeepPhase> createState() => _KeepPhaseState();
}

class _KeepPhaseState extends State<_KeepPhase> {
  int _canDo = 0;
  int? _hard;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final hard = [for (final h in m.hard) h.split('|')];
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), children: [
          Text('Mission réussie !', style: titleStyle(26, weight: 800)),
          const SizedBox(height: 8),
          if (widget.phrase.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: JangColors.noteBg,
                  border: Border.all(color: JangColors.primary, width: 2),
                  borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                const CharacterView(Chars.lion, size: 64, moves: Moves.dance),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('MA PHRASE',
                        style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: JangColors.primaryDark)),
                    SayText(widget.phrase, style: titleStyle(21, weight: 800)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 14),
          Text('Je sais ${m.canDo}…', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: 1, label: Text('Pas encore')),
              ButtonSegment(value: 2, label: Text('Avec de l\'aide')),
              ButtonSegment(value: 3, label: Text('Tout seul')),
            ],
            selected: _canDo == 0 ? {} : {_canDo},
            onSelectionChanged: (v) => setState(() => _canDo = v.isEmpty ? 0 : v.first),
          ),
          if (hard.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('C\'était difficile ?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < hard.length; i++)
                ChoiceChip(label: Text(hard[i].first), selected: _hard == i, onSelected: (_) => setState(() => _hard = i)),
            ]),
            if (_hard != null && hard[_hard!].length > 1)
              KoccSays(child: Text(hard[_hard!][1], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          ],
          if (m.notebook.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Dans mon carnet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final w in m.notebook)
                ActionChip(
                  avatar: const Icon(Icons.volume_up_rounded, size: 18, color: JangColors.primaryDark),
                  label: Text(w, style: const TextStyle(fontWeight: FontWeight.w800)),
                  backgroundColor: JangColors.warningBg,
                  onPressed: () => Speech.instance.say(w),
                ),
            ]),
          ],
        ]),
      ),
      _bottom(ChunkyButton(
        label: _busy ? '…' : 'TERMINER LA MISSION',
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                await widget.onFinish(_canDo);
              },
      )),
    ]);
  }
}
