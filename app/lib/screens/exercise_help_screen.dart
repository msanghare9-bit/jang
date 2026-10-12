import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/characters.dart';
import '../widgets/jang_ui.dart';
import 'tutor_screen.dart';

/// Accueil : l'élève colle ou écrit un exercice qu'on lui a donné (à l'école
/// ou à la maison, même sur papier), et demande de l'aide à Kocc Bàrma.
/// Réutilise exactement le même tuteur que pour un devoir de classe
/// (TutorScreen en mode « homeworkCoach ») : il guide avec des indices, des
/// explications ou du vocabulaire utile, mais ne donne jamais la réponse
/// finale à sa place.
class ExerciseHelpScreen extends StatefulWidget {
  const ExerciseHelpScreen({super.key});

  @override
  State<ExerciseHelpScreen> createState() => _ExerciseHelpScreenState();
}

class _ExerciseHelpScreenState extends State<ExerciseHelpScreen> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _go() {
    final text = _ctl.text.trim();
    if (text.length < 3) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Copie ou écris l’exercice avant de continuer.')));
      return;
    }
    final p = AuthService.instance.profile.value;
    final lesson = Lesson(
      id: 'aide_exercice_${DateTime.now().millisecondsSinceEpoch}',
      examId: p?.examId ?? '',
      subjectId: '',
      chapterId: '',
      title: 'Exercice',
      body: text,
    );
    final subject = Subject(id: '', examId: p?.examId ?? '', name: 'Exercice', color: '#6D28D9');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TutorScreen(
          lesson: lesson,
          subject: subject,
          homeworkCoach: true,
          // L'élève a déjà écrit son exercice : Kocc répond tout de suite,
          // sans lui demander de retaper une question.
          initialQuestion: 'Aide-moi à réfléchir à cet exercice, étape par étape, sans me donner directement la réponse.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aide exercice')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(child: CharacterView(Chars.kocc, size: 100, moves: Moves.sway)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: JangColors.noteBg, borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'Colle ou écris ici un exercice qu’on t’a donné. Kocc Bàrma va t’aider à réfléchir — avec '
              'des indices, des explications ou une liste de vocabulaire utile — mais il ne te donnera '
              'jamais directement la réponse.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctl,
            minLines: 5,
            maxLines: 12,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'L’exercice',
              hintText: 'Exemple : « Complète les phrases avec le bon temps du verbe… »',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ChunkyButton(
            label: 'Demander de l’aide à Kocc Bàrma',
            icon: Icons.lightbulb_outline,
            color: JangColors.snGreen,
            onPressed: _go,
          ),
        ],
      ),
    );
  }
}
