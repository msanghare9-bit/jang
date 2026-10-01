import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// Remet en forme un texte collé d'un seul bloc (retours à la ligne perdus).
/// - « 1. », « 2. »… en début de partie deviennent des titres de partie ;
/// - « • » devient une puce ;
/// - si le texte n'avait presque pas de retours à la ligne, une phrase par ligne.
String autoFormatLesson(String input) {
  var text = input.replaceAll('\r\n', '\n').replaceAll(' ', ' ');
  final collapsed = '\n'.allMatches(text).length < 3;

  // Puces « • » : une par ligne.
  text = text.replaceAllMapped(RegExp(r'\s*[•●▪]\s*'), (_) => '\n- ');

  // Parties numérotées 1., 2., 3.… (dans l'ordre, pour ne pas toucher aux nombres ordinaires).
  var expected = 1;
  final out = StringBuffer();
  var i = 0;
  final partRe = RegExp(r'(^|[\s.;:!?])(\d{1,2})[.)]\s+(?=\S)');
  while (true) {
    final m = partRe.allMatches(text, i).cast<RegExpMatch?>().firstWhere(
        (m) => m != null && int.parse(m.group(2)!) == expected,
        orElse: () => null);
    if (m == null) break;
    final numStart = m.start + m.group(1)!.length;
    out.write(text.substring(i, numStart));
    // Le titre va jusqu'à « : » proche, ou jusqu'au premier mot en majuscule qui suit.
    final rest = text.substring(m.end);
    final title = _splitTitle(rest);
    out.write('\n\n## $expected. ${title.$1}\n');
    i = m.end + title.$2;
    expected++;
  }
  out.write(text.substring(i));
  text = out.toString();

  if (collapsed) {
    // Une phrase par ligne dans les paragraphes (pas dans les titres ni les puces).
    text = text.split('\n').map((line) {
      if (line.startsWith('## ') || line.startsWith('- ')) return line;
      return line.replaceAllMapped(
          RegExp(r'([.?!])\s+(?=[A-ZÀ-ÝÉ«"])'), (m) => '${m.group(1)}\n');
    }).join('\n');
  }

  // Nettoyage : espaces en fin de ligne, lignes vides en trop.
  text = text
      .split('\n')
      .map((l) => l.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .replaceAll(RegExp(r'\n- \n'), '\n')
      .trim();
  return text;
}

/// Renvoie (titre, longueur consommée) au début de [rest].
(String, int) _splitTitle(String rest) {
  final colon = rest.indexOf(':');
  final lineEnd = rest.indexOf('\n');
  final limit = lineEnd < 0 ? rest.length : lineEnd;
  if (colon > 0 && colon < 50 && colon < limit) {
    return (rest.substring(0, colon).trim(), colon + 1);
  }
  final words = RegExp(r'\S+').allMatches(rest.substring(0, limit)).toList();
  for (var w = 1; w < words.length && w <= 8; w++) {
    final word = words[w].group(0)!;
    final first = word.characters.first;
    if (first.toUpperCase() == first && first.toLowerCase() != first) {
      return (rest.substring(0, words[w].start).trim(), words[w].start);
    }
  }
  // Pas de coupure évidente : le titre va jusqu'à la fin de la phrase si elle est courte.
  final end = RegExp(r'[.?!]').firstMatch(rest.substring(0, limit));
  if (end != null && end.end <= 70) {
    return (rest.substring(0, end.start).trim(), end.end);
  }
  return ('', 0);
}

/// Petite page d'aide « Comment mettre en forme ? ».
void showFormatHelp(BuildContext context) {
  const rows = [
    ['## Giving advice', 'un titre de partie numéroté'],
    ['- You should study.', 'une puce'],
    ['**SHOULD**', 'un mot en gras'],
    ['*Tu devrais étudier.*', 'une traduction (italique gris)'],
    ['À retenir : SHOULD + verbe', 'un encadré vert'],
    ['Exemple : He should study.', 'un encadré exemple'],
    ['Attention : pas de « to »', 'un encadré rouge'],
    ['Astuce : …', 'un encadré astuce'],
  ];
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (c) => Scaffold(
        appBar: AppBar(title: const Text('Comment mettre en forme ?')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text('Le plus simple', style: titleStyle(20)),
            const SizedBox(height: 6),
            const Text('1. Colle ta leçon dans l\'onglet « Leçon ».\n'
                '2. Touche « Mise en forme automatique ».\n'
                '3. Ajoute deux ou trois encadrés « À retenir » avec les boutons.\n'
                '4. Vérifie avec « Voir comme un élève », puis enregistre.'),
            const SizedBox(height: 18),
            Text('Les boutons', style: titleStyle(20)),
            const SizedBox(height: 6),
            const Text('Place le curseur au début d\'une ligne puis touche Partie, Puce, À retenir, '
                'Exemple, Attention ou Astuce. Pour Gras et Traduction, sélectionne d\'abord des mots.'),
            const SizedBox(height: 18),
            Text('Les codes (si tu préfères écrire)', style: titleStyle(20)),
            const SizedBox(height: 8),
            for (final r in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: JangColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r[0], style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('→ ${r[1]}', style: const TextStyle(color: JangColors.textSecondary)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text('Exemple de résultat', style: titleStyle(20)),
            const SizedBox(height: 8),
            const LessonText('## Giving advice\n'
                'À retenir : pour donner un conseil, on utilise **SHOULD + verbe**.\n'
                '- You should study. — *Tu devrais étudier.*\n'
                'Attention : pas de « to » après SHOULD.'),
          ],
        ),
      ),
    ),
  );
}
