import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/classes/my_classes_screen.dart';
import '../screens/match/match_screens.dart';
import '../screens/mission/learn_mode.dart';
import '../services/auth_service.dart';
import '../services/class_service.dart';
import '../services/content_repo.dart';
import '../theme.dart';
import 'characters.dart';
import 'class_section.dart';

/// Accueil : « Ma classe » (élève) ou « Mes classes » (prof).
class MyClassCard extends StatelessWidget {
  const MyClassCard({super.key});

  Future<void> _open(BuildContext context, ClassRoom c) async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    try {
      final subjects = await ContentRepo.instance.subjects(p.examId);
      final s = subjects.where((s) => subjectKey(s.name) == c.subject).firstOrNull;
      if (s != null && context.mounted) await LearnMode.open(context, s);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthService.instance.profile.value;
    if (p == null) return const SizedBox.shrink();
    if (p.isStaff) {
      return _card(
        context,
        title: 'Mes classes',
        subtitle: 'Tes élèves, leurs résultats, tes contenus.',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyClassesScreen())),
      );
    }
    return ValueListenableBuilder<List<ClassRoom>>(
      valueListenable: ClassService.instance.mine,
      builder: (context, classes, _) {
        if (classes.isEmpty) {
          return _card(
            context,
            title: 'Ma classe',
            subtitle: 'Tu as un code de ton prof ? Entre dans ta classe.',
            onTap: () => showJoinClassDialog(context),
            icon: Icons.vpn_key_outlined,
          );
        }
        return Column(children: [
          for (final c in classes)
            _card(
              context,
              title: 'Ma classe : ${c.name}',
              subtitle: '${c.subjectName}${c.profName.isEmpty ? '' : ' · ${c.profName}'}',
              onTap: () => _open(context, c),
            ),
        ]);
      },
    );
  }

  Widget _card(BuildContext context,
      {required String title, required String subtitle, required VoidCallback onTap, IconData icon = Icons.chevron_right_rounded}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: JangColors.snGreen, width: 2),
            ),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: JangColors.snGreen, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.school, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: titleStyle(18, weight: 800)),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              Icon(icon),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Accueil : les matchs entre amis (façon Kahoot).
class MatchCard extends StatelessWidget {
  const MatchCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF46178F),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MatchHomeScreen())),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(children: [
              const CharacterView(Chars.lion, size: 54, moves: Moves.jump),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Match ⚡', style: titleStyle(19, color: Colors.white, weight: 800)),
                  const Text('Joue contre tes amis avec un code.', style: TextStyle(color: Colors.white)),
                ]),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => joinMatchDialog(context),
                child: const Text('Rejoindre'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
