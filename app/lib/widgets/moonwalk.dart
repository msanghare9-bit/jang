import 'dart:math';

import 'package:flutter/material.dart';

import 'characters.dart';

/// Arrivée de Gaïndé sur l'accueil : il entre en moonwalk par le bas de l'écran,
/// s'arrête, se retourne et salue l'élève. Une seule fois par ouverture de l'application.
class GaindeMoonwalk extends StatefulWidget {
  final String name;
  const GaindeMoonwalk({super.key, required this.name});

  static bool _shown = false;

  @override
  State<GaindeMoonwalk> createState() => _GaindeMoonwalkState();
}

class _GaindeMoonwalkState extends State<GaindeMoonwalk> with TickerProviderStateMixin {
  // 0 → 0.45 : moonwalk ; 0.45 → 0.55 : demi-tour ; 0.55 → 0.92 : salut ; puis il s'en va.
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 9000));
  late final AnimationController _step =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..repeat();
  bool _visible = !GaindeMoonwalk._shown;

  static const _hellos = [
    'Na nga def, {n} ! Tu as vu mon moonwalk ? 🕺 Allez, on apprend !',
    'Salut {n} ! Le roi de la danse est là… et le roi de l\'anglais aussi !',
    '{n} ! MIAOU… euh, ROAR ! Prêt pour une nouvelle leçon ?',
    'Bienvenue {n} ! Comprendre nga bou bax ! On commence ?',
  ];
  late final String _hello = _hellos[Random().nextInt(_hellos.length)]
      .replaceAll('{n}', widget.name.isEmpty ? 'champion' : widget.name);

  @override
  void initState() {
    super.initState();
    if (_visible) {
      GaindeMoonwalk._shown = true;
      _c.forward().whenComplete(() {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _step.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    _c.stop();
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 230,
      child: GestureDetector(
        onTap: _close,
        behavior: HitTestBehavior.translucent,
        child: LayoutBuilder(builder: (context, box) {
          const size = 120.0;
          final w = box.maxWidth;
          return AnimatedBuilder(
            animation: Listenable.merge([_c, _step]),
            builder: (context, _) {
              final t = _c.value;
              final s = _step.value;
              // Position : entre par la droite à reculons, s'arrête vers le milieu, puis repart.
              double x;
              if (t < .45) {
                x = w + 10 - (w + 10 - (w - size) / 2) * Curves.linear.transform(t / .45);
              } else if (t < .92) {
                x = (w - size) / 2;
              } else {
                x = (w - size) / 2 - ((t - .92) / .08) * (w / 2 + size);
              }
              final walking = t < .45;
              final greeting = t >= .55 && t < .92;
              // Pas glissés du moonwalk : petit rebond et bascule en rythme.
              final bob = walking ? -(sin(s * pi * 2).abs()) * 6 : (greeting ? -sin(s * pi * 2) * 3 : 0.0);
              final tilt = walking ? sin(s * pi * 2) * .08 : 0.0;
              final turning = t >= .45 && t < .55;
              // Il regarde vers la droite (dos au chemin) pendant le moonwalk, puis se retourne.
              final scaleX = turning ? cos(((t - .45) / .1) * pi) : (walking ? -1.0 : 1.0);
              final fade = t > .92 ? (1 - (t - .92) / .08).clamp(0.0, 1.0) : (t < .03 ? t / .03 : 1.0);
              return Opacity(
                opacity: fade,
                child: Stack(clipBehavior: Clip.none, children: [
                  if (greeting)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: size + 12,
                      child: _Bubble(_hello),
                    ),
                  if (walking)
                    for (var i = 0; i < 3; i++)
                      Positioned(
                        left: x + size * .6 + i * 18,
                        bottom: 18 + ((s + i / 3) % 1) * 50,
                        child: Opacity(
                          opacity: 1 - ((s + i / 3) % 1),
                          child: Text(i.isEven ? '🎵' : '✨', style: const TextStyle(fontSize: 18)),
                        ),
                      ),
                  Positioned(
                    left: x,
                    bottom: 6 - bob,
                    child: Transform.rotate(
                      angle: tilt,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.diagonal3Values(scaleX.abs() < .05 ? .05 : scaleX, 1, 1),
                        child: const CharacterView(Chars.lion, size: size, moves: Moves.still),
                      ),
                    ),
                  ),
                ]),
              );
            },
          );
        }),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  const _Bubble(this.text);

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: const Color(0xFFFFF4D6),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF3B2A12))),
      ),
    );
  }
}
