import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/media_service.dart';
import '../theme.dart';

/// Message affiché quand une liste est vide.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: JangColors.textSecondary),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: titleStyle(19)),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: JangColors.textSecondary)),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  const SectionTitle(this.text, {super.key, this.color = JangColors.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text, style: titleStyle(19, color: color)),
      );
}

class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  const ProgressBar({super.key, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: 8,
          color: color,
          backgroundColor: color.withValues(alpha: 0.14),
        ),
      );
}

/// Petite étiquette arrondie.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  const Pill(this.text, {super.key, required this.color, required this.background});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      );
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Confirmer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: titleStyle(20)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

/// Affiche le texte d'une leçon avec une mise en forme simple :
///   # Titre        ## Sous-titre
///   - élément de liste
///   > encadré « À retenir »
///   **gras**, *italique*, et les liens https://... deviennent cliquables.
class LessonText extends StatelessWidget {
  final String text;
  final Color accent;

  /// Taille du texte (1 = normal). Le bouton « A A » de la leçon la change.
  final double scale;
  const LessonText(this.text, {super.key, this.accent = JangColors.primary, this.scale = 1});

  static final _photoRe = RegExp(r'^\[photo ([A-Za-z0-9_-]+)\]\s*(.*)$');
  static final _boxRe = RegExp(r'^(À retenir|A retenir|Exemple|Attention|Astuce)\s*:\s*(.*)$',
      caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme.bodyLarge!;
    final base = theme.copyWith(fontSize: 17 * scale, height: 1.6);
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final children = <Widget>[];
    final quote = <String>[];
    var partNumber = 0;

    void flushQuote() {
      if (quote.isEmpty) return;
      children.add(_box(context, 'À retenir', quote.join('\n'), base));
      quote.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.startsWith('>')) {
        quote.add(line.substring(1).trimLeft());
        continue;
      }
      flushQuote();
      final photo = _photoRe.firstMatch(line.trim());
      if (photo != null) {
        children.add(_photo(context, photo.group(1)!, photo.group(2)!.trim()));
        continue;
      }
      final box = _boxRe.firstMatch(line.trim());
      if (line.trim().isEmpty) {
        children.add(SizedBox(height: 8 * scale));
      } else if (box != null) {
        children.add(_box(context, box.group(1)!, box.group(2)!, base));
      } else if (line.startsWith('## ') || line.startsWith('# ')) {
        var title = line.replaceFirst(RegExp(r'^#+\s+'), '');
        final numMatch = RegExp(r'^(\d+)[.)]\s*').firstMatch(title);
        String label;
        if (numMatch != null) {
          label = numMatch.group(1)!;
          title = title.substring(numMatch.end);
        } else {
          partNumber++;
          label = '$partNumber';
        }
        children.add(Padding(
          padding: EdgeInsets.only(top: 22 * scale, bottom: 6 * scale),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(right: 10, top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration:
                    BoxDecoration(color: accent, borderRadius: BorderRadius.circular(8)),
                child: Text(label,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15 * scale)),
              ),
              Expanded(child: Text(title, style: titleStyle(20 * scale, color: accent))),
            ],
          ),
        ));
      } else if (RegExp(r'^\s*[-*•]\s+').hasMatch(line)) {
        final content = line.replaceFirst(RegExp(r'^\s*[-*•]\s+'), '');
        children.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 11 * scale, right: 12),
                child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              ),
              Expanded(child: _rich(context, content, base)),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _rich(context, line, base),
        ));
      }
    }
    flushQuote();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _box(BuildContext context, String kind, String content, TextStyle base) {
    final k = kind.toLowerCase();
    late final Color fg;
    late final Color bg;
    late final IconData icon;
    late final String label;
    var dashed = false;
    if (k.contains('retenir')) {
      fg = JangColors.success;
      bg = JangColors.noteBg;
      icon = Icons.star;
      label = 'À RETENIR';
    } else if (k == 'attention') {
      fg = JangColors.error;
      bg = JangColors.errorBg;
      icon = Icons.warning_amber;
      label = 'ATTENTION';
    } else if (k == 'astuce') {
      fg = JangColors.warning;
      bg = JangColors.warningBg;
      icon = Icons.lightbulb_outline;
      label = 'ASTUCE';
    } else {
      fg = JangColors.textSecondary;
      bg = Colors.white;
      icon = Icons.chat_bubble_outline;
      label = 'EXEMPLE';
      dashed = true;
    }
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: 8 * scale),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: dashed
            ? Border.all(color: JangColors.border, width: 1.5)
            : Border(left: BorderSide(color: fg, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16 * scale, color: fg),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w700, fontSize: 13 * scale, letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 4),
          for (final l in content.split('\n')) _rich(context, l, base),
        ],
      ),
    );
  }

  Widget _photo(BuildContext context, String id, String caption) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: 10 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JangColors.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => Dialog(
                insetPadding: const EdgeInsets.all(12),
                child: InteractiveViewer(child: MediaImage(id, fit: BoxFit.contain)),
              ),
            ),
            child: MediaImage(id, height: 220 * scale, fit: BoxFit.cover, radius: 16),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(children: [
                const Icon(Icons.photo_camera_outlined, size: 18, color: JangColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(caption,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15 * scale,
                          color: JangColors.text)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _rich(BuildContext context, String s, TextStyle base) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'(\*\*[^*]+\*\*)|(\*[^*]+\*)|(https?://\S+)');
    var i = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > i) spans.add(TextSpan(text: s.substring(i, m.start)));
      final t = m.group(0)!;
      if (t.startsWith('**')) {
        spans.add(TextSpan(
            text: t.substring(2, t.length - 2), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (t.startsWith('*')) {
        // L'italique sert aux traductions : en gris pour les distinguer.
        spans.add(TextSpan(
            text: t.substring(1, t.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic, color: JangColors.textSecondary)));
      } else {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => openLink(t),
            child: Text(t,
                style: base.copyWith(
                    color: JangColors.primary, decoration: TextDecoration.underline)),
          ),
        ));
      }
      i = m.end;
    }
    if (i < s.length) spans.add(TextSpan(text: s.substring(i)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

Future<void> openLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Extrait l'identifiant d'une vidéo YouTube à partir d'un lien ou de l'identifiant seul.
String? youtubeIdFrom(String input) {
  final s = input.trim();
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(s)) return s;
  final patterns = [
    RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})'),
    RegExp(r'[?&]v=([A-Za-z0-9_-]{11})'),
    RegExp(r'/embed/([A-Za-z0-9_-]{11})'),
    RegExp(r'/shorts/([A-Za-z0-9_-]{11})'),
    RegExp(r'/live/([A-Za-z0-9_-]{11})'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(s);
    if (m != null) return m.group(1);
  }
  return null;
}
