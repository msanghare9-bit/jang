import 'package:flutter/material.dart';

import '../theme.dart';

/// Gros bouton en relief (il s'enfonce quand on appuie).
class ChunkyButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color? textColor;
  final IconData? icon;
  final bool outlined;
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = JangColors.accent,
    this.textColor,
    this.icon,
    this.outlined = false,
  });

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final base = enabled ? widget.color : const Color(0xFFE5E5E5);
    final bg = widget.outlined ? Colors.white : base;
    final shadow = widget.outlined ? JangColors.border : JangColors.darker(base, 0.15);
    final fg = widget.textColor ??
        (widget.outlined ? (enabled ? widget.color : JangColors.textSecondary) : JangColors.on(base));
    const depth = 5.0;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.onPressed,
      child: Padding(
        padding: EdgeInsets.only(top: _down ? depth - 1 : 0, bottom: _down ? 1 : depth),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: widget.outlined ? Border.all(color: JangColors.border, width: 2) : null,
            boxShadow: [
              BoxShadow(color: shadow, offset: Offset(0, _down ? 1 : depth), blurRadius: 0),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: fg, size: 22),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(widget.label,
                    textAlign: TextAlign.center, style: titleStyle(18, color: fg, weight: 800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bandeau du haut, de couleur unie, avec des coins arrondis en bas.
class WaxHeader extends StatelessWidget {
  final Color color;
  final Widget child;
  final EdgeInsets padding;
  const WaxHeader({
    super.key,
    required this.color,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 22),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: JangColors.on(color)), child: child),
    );
  }
}

/// Petite pastille blanche (niveau, série…).
class Chip2 extends StatelessWidget {
  final String text;
  const Chip2(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: const TextStyle(
                color: JangColors.text, fontWeight: FontWeight.w800, fontSize: 14)),
      );
}

/// Emoji d'une matière, d'après son nom.
String subjectEmoji(String name) {
  final n = name.toLowerCase();
  bool has(List<String> w) => w.any(n.contains);
  if (has(['fran'])) return '📖';
  if (has(['math', 'calcul'])) return '🔢';
  if (has(['angl', 'english'])) return '🇬🇧';
  if (has(['svt', 'vie', 'bio', 'agri'])) return '🌱';
  if (has(['phys', 'chim', 'pc'])) return '⚗️';
  if (has(['hist', 'géo', 'geo'])) return '🌍';
  if (has(['arab'])) return '🕌';
  if (has(['espa'])) return '🇪🇸';
  if (has(['info', 'ordi'])) return '💻';
  if (has(['civi', 'citoy'])) return '🤝';
  if (has(['wolof'])) return '🇸🇳';
  return '📚';
}
