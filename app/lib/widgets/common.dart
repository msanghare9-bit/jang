import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  const LessonText(this.text, {super.key, this.accent = JangColors.primary});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge!;
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final children = <Widget>[];
    final quote = <String>[];

    void flushQuote() {
      if (quote.isEmpty) return;
      children.add(Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          border: Border(left: BorderSide(color: accent, width: 4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: quote.map((l) => _rich(context, l, base)).toList(),
        ),
      ));
      quote.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.startsWith('>')) {
        quote.add(line.substring(1).trimLeft());
        continue;
      }
      flushQuote();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 10));
      } else if (line.startsWith('## ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(line.substring(3), style: titleStyle(18, color: accent)),
        ));
      } else if (line.startsWith('# ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(line.substring(2), style: titleStyle(22)),
        ));
      } else if (RegExp(r'^\s*[-*•]\s+').hasMatch(line)) {
        final content = line.replaceFirst(RegExp(r'^\s*[-*•]\s+'), '');
        children.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, right: 10),
                child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              ),
              Expanded(child: _rich(context, content, base)),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _rich(context, line, base),
        ));
      }
    }
    flushQuote();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
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
        spans.add(TextSpan(
            text: t.substring(1, t.length - 1), style: const TextStyle(fontStyle: FontStyle.italic)));
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
