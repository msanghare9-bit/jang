import 'package:flutter/material.dart';

import '../services/speech_service.dart';
import '../theme.dart';

/// Icône haut-parleur : fait entendre la prononciation d'un mot ou d'une phrase en anglais.
class SayButton extends StatelessWidget {
  final String text;
  final double size;
  const SayButton(this.text, {super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Écouter',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Speech.instance.say(text),
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: JangColors.noteBg, shape: BoxShape.circle),
          child: Icon(Icons.volume_up_rounded, size: size * 0.55, color: JangColors.primaryDark),
        ),
      ),
    );
  }
}

/// Un texte anglais suivi de son haut-parleur.
class SayText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final double size;
  const SayText(this.text, {super.key, this.style, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(text, style: style ?? const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
      const SizedBox(width: 6),
      SayButton(text, size: size),
    ]);
  }
}
