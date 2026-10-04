import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';
import 'characters.dart';
import 'jang_ui.dart';

/// Barre de progression des exercices : la pirogue avance d'une vague à chaque bonne réponse,
/// jusqu'à la plage. À l'arrivée, des poissons sautent.
class PirogueTrack extends StatelessWidget {
  final int steps;
  final int position;
  const PirogueTrack({super.key, required this.steps, required this.position});

  @override
  Widget build(BuildContext context) {
    final arrived = steps > 0 && position >= steps;
    return SizedBox(
      height: 74,
      child: LayoutBuilder(builder: (context, box) {
        const boat = 74.0;
        final travel = max(0.0, box.maxWidth - boat - 34);
        final x = steps == 0 ? 0.0 : travel * position.clamp(0, steps) / steps;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 6,
            height: 20,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF5FB3E8),
                borderRadius: BorderRadius.circular(10),
                border: const Border(top: BorderSide(color: Color(0xFF8FD0F5), width: 4)),
              ),
            ),
          ),
          const Positioned(right: 0, bottom: 14, child: Text('🏝️', style: TextStyle(fontSize: 28))),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            left: x,
            bottom: 8,
            child: const CharacterView(Chars.pirogue, size: boat, height: 52, moves: Moves.rock),
          ),
          if (arrived)
            for (var i = 0; i < 5; i++)
              Positioned(
                left: travel - 10 + i * 14.0,
                bottom: 18,
                child: JumpingFish(delay: Duration(milliseconds: i * 180)),
              ),
        ]);
      }),
    );
  }
}

/// Un poisson qui saute hors de l'eau.
class JumpingFish extends StatefulWidget {
  final Duration delay;
  final double size;
  const JumpingFish({super.key, this.delay = Duration.zero, this.size = 30});

  @override
  State<JumpingFish> createState() => _JumpingFishState();
}

class _JumpingFishState extends State<JumpingFish> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1050));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.repeat();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final dy = -sin(t * pi) * 36;
        final dx = t * 30;
        final opacity = t < .1 ? t * 10 : (t > .9 ? (1 - t) * 10 : 1.0);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.rotate(angle: 0.6 - t * 1.4, child: child),
          ),
        );
      },
      child: SvgPicture.string(Chars.poisson, width: widget.size, height: widget.size * .6),
    );
  }
}

/// Confettis aux couleurs du drapeau.
class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  final _rnd = Random();
  late final List<List<double>> _bits =
      List.generate(36, (_) => [_rnd.nextDouble(), _rnd.nextDouble(), _rnd.nextDouble() * 6, _rnd.nextDouble()]);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_bits, _c.value), size: Size.infinite),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<List<double>> bits;
  final double t;
  _ConfettiPainter(this.bits, this.t);

  static const _colors = [Color(0xFF1F9D55), Color(0xFFF6B81C), Color(0xFFD93A2B)];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < bits.length; i++) {
      final b = bits[i];
      final p = (t + b[1]) % 1.0;
      final x = b[0] * size.width + sin((p + b[3]) * 6) * 12;
      final y = p * (size.height + 20) - 10;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p * b[2] * 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-4, -6, 8, 12), const Radius.circular(2)),
        Paint()..color = _colors[i % 3],
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Grande fête de fin d'exercices (bonne note) : Awa et Modou dansent, Doudou joue du tama,
/// les poissons sautent autour de la pirogue.
class Celebration extends StatelessWidget {
  final int score;
  final int total;
  final int xp;
  final String? episode;
  final VoidCallback onContinue;
  const Celebration({
    super.key,
    required this.score,
    required this.total,
    required this.xp,
    required this.onContinue,
    this.episode,
  });

  @override
  Widget build(BuildContext context) {
    final perfect = score >= total;
    return Container(
      color: const Color(0xFFFFF8E6),
      child: Stack(children: [
        const Positioned.fill(child: Confetti()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(children: [
              const Spacer(),
              Text(perfect ? 'Gathié ngalama !' : 'Diambar nga !',
                  textAlign: TextAlign.center, style: titleStyle(34, weight: 800)),
              const SizedBox(height: 4),
              Text('$score / $total', style: titleStyle(46, color: JangColors.success, weight: 800)),
              const SizedBox(height: 14),
              const Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                CharacterView(Chars.awa, size: 84, moves: Moves.dance),
                CharacterView(Chars.doudou, size: 104, moves: Moves.jump),
                CharacterView(Chars.modou, size: 84, moves: Moves.danceAlt),
              ]),
              SizedBox(
                height: 70,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  const CharacterView(Chars.pirogue, size: 110, height: 70, moves: Moves.jump),
                  for (var i = 0; i < min(score, 6); i++)
                    Positioned(
                      left: 10.0 + i * 38,
                      top: 10,
                      child: JumpingFish(delay: Duration(milliseconds: i * 170), size: 28),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              Text('Belle pêche : $score poisson${score > 1 ? 's' : ''} !   ⭐ +$xp XP',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              if (episode != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4D6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF6B81C), width: 2),
                  ),
                  child: Text('📖 Nouvel épisode débloqué : « $episode »',
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
              const Spacer(),
              ChunkyButton(label: 'CONTINUER', color: JangColors.success, onPressed: onContinue),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Un personnage qui parle (bulle à côté de lui).
class CharacterSays extends StatelessWidget {
  final String id;
  final String text;
  final Color color;
  final bool right;
  const CharacterSays(this.id, this.text, {super.key, this.color = const Color(0xFFFFF4D6), this.right = false});

  @override
  Widget build(BuildContext context) {
    final bubble = Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x22000000)),
        ),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      ),
    );
    final who = CharacterView.of(id, size: 76, moves: Moves.bob, flip: right);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: right ? [bubble, const SizedBox(width: 6), who] : [who, const SizedBox(width: 6), bubble],
      ),
    );
  }
}
