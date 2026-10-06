import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme.dart';
import '../../widgets/characters.dart';
import '../../widgets/jang_ui.dart';

/// Le guide de bienvenue des missions (« Comment ça marche »).
class MissionGuide {
  MissionGuide._();

  static const _seenKey = 'guide_missions_vu';

  /// Montre le guide la toute première fois.
  static Future<void> showFirstTime(BuildContext context) async {
    var seen = false;
    try {
      seen = (await SharedPreferences.getInstance()).getBool(_seenKey) ?? false;
    } catch (_) {}
    if (seen || !context.mounted) return;
    await show(context);
  }

  /// Montre le guide (et le note comme vu).
  static Future<void> show(BuildContext context) async {
    await Navigator.push(
        context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _GuidePage()));
    try {
      await (await SharedPreferences.getInstance()).setBool(_seenKey, true);
    } catch (_) {}
  }
}

class _Slide {
  final List<String> chars;
  final String text;
  final IconData? icon;
  const _Slide(this.chars, this.text, {this.icon});
}

class _GuidePage extends StatefulWidget {
  const _GuidePage();

  @override
  State<_GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<_GuidePage> {
  static const _slides = [
    _Slide([Chars.lion], 'Gaïndé est un petit lion.\nIl veut apprendre l\'anglais.'),
    _Slide([Chars.modou, Chars.lion], 'Dans chaque mission, tu apprends une chose.\nPuis tu l\'apprends à Gaïndé.'),
    _Slide([Chars.lion], 'Gaïndé se trompe souvent.\nToi, tu l\'aides !'),
    _Slide([Chars.kocc], 'Tu bloques ? Kocc Barma te donne un indice.\nIl ne donne jamais la réponse.'),
    _Slide([Chars.awa], 'Tu peux répondre en parlant ou en écrivant.\nAppuie sur 🔊 pour écouter.',
        icon: Icons.volume_up_rounded),
  ];
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page >= _slides.length - 1) {
      Navigator.pop(context);
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page >= _slides.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comment ça marche'),
        actions: [
          if (!last) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Passer')),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final s = _slides[i];
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (final c in s.chars)
                        CharacterView(c,
                            size: s.chars.length > 1 ? 120 : 160,
                            moves: i == 2 ? Moves.sway : (c == Chars.kocc ? Moves.bob : Moves.dance)),
                    ]),
                    const SizedBox(height: 24),
                    Text(s.text, textAlign: TextAlign.center, style: titleStyle(23, weight: 800)),
                    if (s.icon != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: JangColors.noteBg, shape: BoxShape.circle),
                        child: Icon(s.icon, size: 36, color: JangColors.primaryDark),
                      ),
                    ],
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == _page ? 22 : 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _page ? JangColors.primary : JangColors.border,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: ChunkyButton(label: last ? 'COMMENCER' : 'SUIVANT', onPressed: _next),
          ),
        ]),
      ),
    );
  }
}

/// La barre des 6 étapes d'une mission : pastilles + « 2/6 · Je regarde ».
class StepBar extends StatelessWidget {
  final int current;
  final List<String> names;
  const StepBar({super.key, required this.current, required this.names});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        for (var i = 0; i < names.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(height: 3, color: i <= current ? JangColors.success : JangColors.border),
            ),
          Container(
            width: i == current ? 26 : 20,
            height: i == current ? 26 : 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < current ? JangColors.success : (i == current ? JangColors.primary : Colors.white),
              border: i > current ? Border.all(color: JangColors.border, width: 2) : null,
            ),
            child: Center(
              child: i < current
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: i == current ? Colors.white : JangColors.textSecondary)),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 4),
      Text('${current + 1}/${names.length} · ${names[current]}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: JangColors.primaryDark)),
    ]);
  }
}

/// Fait battre doucement un élément pour attirer l'œil.
class Pulse extends StatefulWidget {
  final Widget child;
  final bool active;
  const Pulse({super.key, required this.child, this.active = true});

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(Pulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.07).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// Petite bulle de guidage (première mission) avec une flèche et une croix.
class GuideTip extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  /// Vrai : la flèche pointe vers le bas (l'élément est en dessous).
  final bool pointDown;
  const GuideTip({super.key, required this.text, required this.onClose, this.pointDown = true});

  @override
  Widget build(BuildContext context) {
    final arrow = Icon(pointDown ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
        color: JangColors.warning, size: 26);
    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 2, 6),
      decoration: BoxDecoration(
        color: JangColors.warningBg,
        border: Border.all(color: JangColors.warning, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Text('👆', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        IconButton(
          tooltip: 'Fermer',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 20),
          onPressed: onClose,
        ),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: pointDown
            ? [bubble, Padding(padding: const EdgeInsets.only(left: 18), child: arrow)]
            : [Padding(padding: const EdgeInsets.only(left: 18), child: arrow), bubble],
      ),
    );
  }
}
