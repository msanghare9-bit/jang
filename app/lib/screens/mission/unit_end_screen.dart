import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/mission_service.dart';
import '../../theme.dart';
import '../../widgets/jang_ui.dart';
import '../../widgets/say.dart';
import '../flashcards_screen.dart';
import '../quiz_screen.dart';

/// Fin d'unité : fiche de révision, cartes, exercices (la pirogue) et production.
class UnitEndScreen extends StatelessWidget {
  final CourseUnit unit;
  final Subject subject;
  const UnitEndScreen({super.key, required this.unit, required this.subject});

  /// Cartes de révision de tout le carnet (missions terminées du parcours).
  static Widget cardsFor(BuildContext context, Course course, Subject subject) {
    final svc = MissionService.instance;
    final cards = <Flashcard>[
      for (final u in course.units)
        for (final m in u.missions)
          if (svc.isDone(m.id))
            for (final e in m.expressions) Flashcard(front: e, back: 'Je sais ${m.canDo}'),
    ];
    return FlashcardsScreen(
      deck: FlashcardDeck(chapterId: 'carnet_${subjectKey(course.subject)}_${course.level}', subjectId: subject.id, examId: subject.examId, cards: cards),
      title: 'Mon carnet',
      color: JangColors.fromHex(subject.color),
      speak: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(subject.color);
    return Scaffold(
      appBar: AppBar(title: const Text('Fin de l\'unité')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E6),
              border: Border.all(color: const Color(0xFFFFE2A0), width: 2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('FICHE DE RÉVISION',
                  style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: Color(0xFFB07A00))),
              Text(unit.title, style: titleStyle(26, weight: 800)),
              Text('Toute l\'unité sur une page.', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          if (unit.sheet.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Ce que je sais dire', style: titleStyle(19, color: JangColors.primaryDark, weight: 800)),
            for (final (fn, en) in unit.sheet)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 120, child: Text(fn, style: const TextStyle(fontWeight: FontWeight.w800))),
                  Expanded(child: SayText(en, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), size: 26)),
                ]),
              ),
          ],
          if (unit.words.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Mes mots', style: titleStyle(19, color: JangColors.primaryDark, weight: 800)),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text('ANGLAIS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                Expanded(child: Text('FRANÇAIS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                Expanded(child: Text('WOLOF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
              ]),
            ),
            for (final (en, fr, wo) in unit.words)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: SayText(en, style: const TextStyle(fontWeight: FontWeight.w800), size: 24)),
                  Expanded(child: Text(fr)),
                  Expanded(child: Text(wo)),
                ]),
              ),
          ],
          if (unit.traps.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: JangColors.errorBg, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Attention !', style: TextStyle(fontWeight: FontWeight.w800, color: JangColors.errorDark)),
                for (final t in unit.traps) Text('• $t', style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
          const SizedBox(height: 18),
          ChunkyButton(
            label: 'Mes cartes de révision',
            icon: Icons.style_outlined,
            color: JangColors.primary,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FlashcardsScreen(deck: unit.deck(subject), title: unit.title, color: color, speak: true),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (unit.exercises.isNotEmpty)
            ChunkyButton(
              label: 'Les exercices (la pirogue)',
              icon: Icons.sailing_outlined,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => QuizScreen(lesson: unit.exerciseLesson(subject), subject: subject)),
              ),
            ),
          if (unit.production.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: JangColors.noteBg, borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('JE CRÉE', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: JangColors.primaryDark)),
                Text(unit.production, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('Fais-la à l\'oral, à l\'écrit ou les deux, puis montre-la à ton prof.'),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
