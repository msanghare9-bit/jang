import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Les personnages de Jàng, dessinés en SVG (aucune image à télécharger).
class Chars {
  Chars._();

  /// Gaïndé, le lionceau.
  static const lion = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 130 130">
<ellipse cx="65" cy="124" rx="32" ry="5" fill="#000" fill-opacity=".1"/>
<path d="M98 98 Q122 92 118 70" stroke="#d58a2a" stroke-width="6" fill="none" stroke-linecap="round"/><circle cx="118" cy="68" r="6" fill="#8a4b14"/>
<ellipse cx="65" cy="100" rx="30" ry="22" fill="#f1a83c"/>
<circle cx="65" cy="55" r="38" fill="#8a4b14"/><circle cx="65" cy="58" r="29" fill="#f1a83c"/>
<circle cx="44" cy="34" r="8" fill="#f1a83c"/><circle cx="86" cy="34" r="8" fill="#f1a83c"/>
<circle cx="55" cy="55" r="5" fill="#1d1b26"/><circle cx="75" cy="55" r="5" fill="#1d1b26"/><circle cx="56.5" cy="53.5" r="1.6" fill="#fff"/><circle cx="76.5" cy="53.5" r="1.6" fill="#fff"/>
<ellipse cx="65" cy="70" rx="12" ry="9" fill="#fde3b5"/><path d="M61 66 L69 66 L65 70Z" fill="#5a2f0c"/>
<path d="M59 74 Q65 79 71 74" stroke="#5a2f0c" stroke-width="2.2" fill="none" stroke-linecap="round"/>
<path d="M38 86 Q65 100 92 86 L88 96 Q65 106 42 96Z" fill="#d93a2b"/>
<circle cx="50" cy="94" r="2.5" fill="#f6b81c"/><circle cx="65" cy="98" r="2.5" fill="#f6b81c"/><circle cx="80" cy="94" r="2.5" fill="#f6b81c"/>
</svg>''';

  /// Awa, élève de Kébémer.
  static const awa = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 130 130">
<ellipse cx="65" cy="125" rx="30" ry="5" fill="#000" fill-opacity=".1"/>
<path d="M40 125 L46 84 Q65 76 84 84 L90 125Z" fill="#1f9d55"/>
<path d="M48 100 L54 90 L60 100Z M66 100 L72 90 L78 100Z M52 116 L58 106 L64 116Z M70 116 L76 106 L82 116Z" fill="#f6b81c"/>
<path d="M44 88 Q28 76 30 60" stroke="#7a4a2c" stroke-width="7" stroke-linecap="round" fill="none"/>
<path d="M86 88 Q98 100 94 112" stroke="#7a4a2c" stroke-width="7" stroke-linecap="round" fill="none"/>
<rect x="58" y="70" width="14" height="12" fill="#7a4a2c"/>
<circle cx="65" cy="54" r="22" fill="#7a4a2c"/>
<path d="M40 46 Q42 14 66 14 Q92 14 92 44 Q80 30 66 32 Q50 32 40 46Z" fill="#f6b81c"/>
<circle cx="52" cy="26" r="3.5" fill="#d93a2b"/><circle cx="66" cy="20" r="3.5" fill="#d93a2b"/><circle cx="80" cy="26" r="3.5" fill="#d93a2b"/>
<path d="M82 18 Q100 8 98 28 Q92 22 86 26Z" fill="#d93a2b"/>
<circle cx="57" cy="54" r="3.2" fill="#1d1b26"/><circle cx="73" cy="54" r="3.2" fill="#1d1b26"/>
<path d="M58 64 Q65 70 72 64" stroke="#fff" stroke-width="2.5" fill="none" stroke-linecap="round"/>
<circle cx="44" cy="58" r="2.5" fill="#f6b81c"/><circle cx="86" cy="58" r="2.5" fill="#f6b81c"/>
</svg>''';

  /// Modou, son camarade.
  static const modou = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 130 130">
<ellipse cx="65" cy="125" rx="30" ry="5" fill="#000" fill-opacity=".1"/>
<path d="M38 125 L44 82 Q65 74 86 82 L92 125Z" fill="#2f7de1"/>
<rect x="78" y="84" width="20" height="28" rx="5" fill="#d93a2b"/>
<rect x="58" y="68" width="14" height="12" fill="#5c3720"/>
<circle cx="65" cy="52" r="22" fill="#5c3720"/>
<path d="M43 46 Q45 26 65 26 Q85 26 87 46 Q76 36 65 37 Q54 36 43 46Z" fill="#1d1b26"/>
<circle cx="57" cy="52" r="3.2" fill="#1d1b26"/><circle cx="73" cy="52" r="3.2" fill="#1d1b26"/>
<path d="M57 62 Q65 69 73 62" stroke="#fff" stroke-width="2.5" fill="none" stroke-linecap="round"/>
<path d="M44 88 Q30 70 36 56" stroke="#5c3720" stroke-width="7" stroke-linecap="round" fill="none"/><circle cx="36" cy="54" r="5" fill="#f6b81c"/>
</svg>''';

  /// Doudou, le griot au tama.
  static const doudou = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 130 130">
<ellipse cx="65" cy="125" rx="34" ry="5" fill="#000" fill-opacity=".1"/>
<path d="M26 125 L38 78 Q65 66 92 78 L104 125Z" fill="#f4f0e6"/>
<path d="M40 92 Q65 104 90 92" stroke="#c9a227" stroke-width="3" fill="none"/>
<circle cx="65" cy="50" r="21" fill="#4a2c19"/>
<path d="M46 40 L46 30 Q65 22 84 30 L84 40Z" fill="#d93a2b"/>
<path d="M52 44 Q57 41 61 44 M69 44 Q73 41 78 44" stroke="#1d1b26" stroke-width="2.5" fill="none" stroke-linecap="round"/>
<path d="M50 58 Q65 80 80 58 Q65 66 50 58Z" fill="#e8e3d8"/>
<path d="M58 61 Q65 66 72 61" stroke="#1d1b26" stroke-width="2.2" fill="none" stroke-linecap="round"/>
<g transform="rotate(-12 34 98)">
<path d="M20 84 L48 84 L38 98 L48 112 L20 112 L30 98Z" fill="#a8672a"/>
<ellipse cx="34" cy="84" rx="14" ry="4" fill="#e9d3a8"/><ellipse cx="34" cy="112" rx="14" ry="4" fill="#e9d3a8"/>
<path d="M22 86 L32 110 M46 86 L36 110 M28 85 L40 111 M40 85 L28 111" stroke="#5a3311" stroke-width="1"/>
</g>
<path d="M96 74 Q82 70 74 80" stroke="#6b3b14" stroke-width="4" fill="none" stroke-linecap="round"/>
<path d="M98 78 Q102 70 94 68" stroke="#4a2c19" stroke-width="7" stroke-linecap="round" fill="none"/>
</svg>''';

  /// Jàngalekat, la jeune panthère noire.
  static const panthere = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 130 130">
<ellipse cx="65" cy="124" rx="30" ry="5" fill="#000" fill-opacity=".12"/>
<path d="M92 108 Q120 104 116 80 Q114 72 108 76" stroke="#26232e" stroke-width="7" fill="none" stroke-linecap="round"/>
<ellipse cx="66" cy="102" rx="28" ry="18" fill="#26232e"/>
<ellipse cx="50" cy="118" rx="9" ry="6" fill="#26232e"/><ellipse cx="82" cy="118" rx="9" ry="6" fill="#26232e"/>
<path d="M38 34 L34 14 L52 26Z" fill="#26232e"/><path d="M88 34 L92 14 L74 26Z" fill="#26232e"/>
<path d="M40 30 L38 20 L48 27Z" fill="#8b5cf6"/><path d="M86 30 L88 20 L78 27Z" fill="#8b5cf6"/>
<ellipse cx="63" cy="54" rx="30" ry="27" fill="#26232e"/>
<ellipse cx="63" cy="70" rx="15" ry="10" fill="#3a3644"/>
<circle cx="51" cy="50" r="10" fill="#f6d33c"/><circle cx="75" cy="50" r="10" fill="#f6d33c"/>
<circle cx="53" cy="51" r="4.5" fill="#1d1b26"/><circle cx="77" cy="51" r="4.5" fill="#1d1b26"/>
<circle cx="54.5" cy="49" r="1.5" fill="#fff"/><circle cx="78.5" cy="49" r="1.5" fill="#fff"/>
<path d="M59 64 L67 64 L63 69Z" fill="#e48aa0"/>
<path d="M56 72 Q63 78 70 72" stroke="#f2ede4" stroke-width="2.2" fill="none" stroke-linecap="round"/>
<path d="M38 66 L24 62 M38 70 L24 72 M88 66 L102 62 M88 70 L102 72" stroke="#8a8697" stroke-width="1.5"/>
<g transform="rotate(-10 35 88)"><rect x="24" y="80" width="22" height="16" rx="2" fill="#fff" stroke="#bbbbbb"/>
<path d="M28 85 L42 85 M28 89 L40 89 M28 93 L38 93" stroke="#2f7de1" stroke-width="1.2"/></g>
<ellipse cx="38" cy="96" rx="7" ry="5" fill="#26232e"/>
</svg>''';

  /// La pirogue Jàmm.
  static const pirogue = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 130 90">
<path d="M60 16 L60 58" stroke="#6b4129" stroke-width="3"/>
<path d="M62 18 L70 21 L70 31 L62 34Z" fill="#1f9d55"/><path d="M70 21 L77 23.5 L77 28.5 L70 31Z" fill="#f6b81c"/><path d="M77 23.5 L84 26 L77 28.5Z" fill="#d93a2b"/>
<circle cx="44" cy="44" r="6" fill="#5c3720"/><path d="M38 58 L40 50 Q44 47 48 50 L50 58Z" fill="#2f7de1"/>
<path d="M48 52 L58 42" stroke="#5c3720" stroke-width="3" stroke-linecap="round"/>
<path d="M4 52 Q10 50 20 58 L110 58 Q120 50 126 50 Q120 74 100 76 L30 76 Q10 74 4 52Z" fill="#d93a2b"/>
<path d="M10 60 Q20 64 30 64 L100 64 Q112 64 120 58 L118 64 Q110 70 100 70 L30 70 Q16 70 10 64Z" fill="#f6b81c"/>
<path d="M22 70 L108 70 Q104 76 98 76 L32 76 Q26 76 22 70Z" fill="#1f9d55"/>
<circle cx="18" cy="60" r="3.5" fill="#fff"/><circle cx="18" cy="60" r="1.6" fill="#1d1b26"/>
<path d="M40 66 L46 62 L52 66 L58 62 L64 66 L70 62 L76 66 L82 62 L88 66" stroke="#2f7de1" stroke-width="2" fill="none"/>
</svg>''';

  /// Un poisson.
  static const poisson = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 24">
<path d="M4 12 Q14 0 28 6 L38 0 L36 12 L38 24 L28 18 Q14 24 4 12Z" fill="#9fb8c8"/>
<path d="M10 12 Q18 6 26 9" stroke="#fff" stroke-width="1.5" fill="none" stroke-opacity=".7"/>
<circle cx="10" cy="10" r="1.8" fill="#1d1b26"/>
</svg>''';

  static const _byId = {
    'gainde': lion,
    'lion': lion,
    'awa': awa,
    'modou': modou,
    'doudou': doudou,
    'griot': doudou,
    'jangalekat': panthere,
    'panthere': panthere,
    'pirogue': pirogue,
    'poisson': poisson,
  };

  static String? byId(String id) => _byId[id.toLowerCase()];
}

/// Façon de bouger d'un personnage.
enum Moves { still, bob, sway, dance, danceAlt, rock, jump }

/// Un personnage animé.
class CharacterView extends StatefulWidget {
  final String svg;
  final double size;
  final double? height;
  final Moves moves;
  final bool flip;
  const CharacterView(this.svg,
      {super.key, this.size = 100, this.height, this.moves = Moves.bob, this.flip = false});

  /// Personnage à partir de son identifiant (« awa », « modou »…).
  static Widget of(String id, {double size = 100, Moves moves = Moves.bob, bool flip = false}) {
    final svg = Chars.byId(id);
    if (svg == null) return SizedBox(width: size, height: size);
    return CharacterView(svg, size: size, moves: moves, flip: flip);
  }

  @override
  State<CharacterView> createState() => _CharacterViewState();
}

class _CharacterViewState extends State<CharacterView> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  Duration get _period => switch (widget.moves) {
        Moves.dance || Moves.danceAlt => const Duration(milliseconds: 520),
        Moves.jump => const Duration(milliseconds: 420),
        Moves.rock => const Duration(milliseconds: 1000),
        _ => const Duration(milliseconds: 1300),
      };

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _period);
    if (widget.moves != Moves.still) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picture = SvgPicture.string(widget.svg,
        width: widget.size, height: widget.height ?? widget.size, fit: BoxFit.contain);
    return AnimatedBuilder(
      animation: _c,
      child: picture,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        var dy = 0.0, angle = 0.0, sx = widget.flip ? -1.0 : 1.0, sy = 1.0;
        switch (widget.moves) {
          case Moves.still:
            break;
          case Moves.bob:
            dy = -6 * t;
          case Moves.sway:
            angle = (t - .5) * 0.14;
          case Moves.dance:
            dy = -16 * t;
            angle = (t - .5) * 0.42;
            if (_c.value > .5) sx = -sx;
          case Moves.danceAlt:
            dy = -14 * (1 - t);
            angle = (.5 - t) * 0.48;
            sy = 1 - 0.07 * t;
          case Moves.rock:
            angle = (t - .5) * 0.14;
            dy = -3 * sin(t * pi);
          case Moves.jump:
            dy = -10 * t;
            angle = -0.05 * t;
        }
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: angle,
            alignment: Alignment.bottomCenter,
            child: Transform.scale(scaleX: sx, scaleY: sy, alignment: Alignment.bottomCenter, child: child),
          ),
        );
      },
    );
  }
}
