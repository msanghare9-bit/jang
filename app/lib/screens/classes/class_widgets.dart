import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/class_service.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Icône d'un type de contenu de classe.
IconData classItemIcon(String type) => switch (type) {
      ClassItem.lesson => Icons.menu_book_outlined,
      ClassItem.mcq => Icons.quiz_outlined,
      ClassItem.gaps => Icons.edit_note,
      ClassItem.homework => Icons.assignment_outlined,
      ClassItem.mission => Icons.pets,
      _ => Icons.description_outlined,
    };

/// Phrase simple qui explique un type de contenu.
String classItemHelp(String type) => switch (type) {
      ClassItem.lesson => 'Un texte à lire, avec un petit quiz à la fin si tu veux.',
      ClassItem.mcq => 'Des questions avec 4 réponses. L\'élève choisit la bonne.',
      ClassItem.gaps => 'Des phrases avec un mot qui manque. L\'élève l\'écrit.',
      ClassItem.homework => 'Une consigne. L\'élève écrit sa réponse et tu la corriges.',
      ClassItem.mission => 'Une petite histoire où l\'élève pratique avec Gaïndé.',
      _ => '',
    };

/// Pastille « Privé » ou « Public ».
class VisibilityPill extends StatelessWidget {
  final ClassItem item;
  const VisibilityPill(this.item, {super.key});

  @override
  Widget build(BuildContext context) => item.isPublic
      ? const Pill('Public', color: JangColors.successDark, background: JangColors.successBg)
      : const Pill('Privé', color: JangColors.primaryDark, background: JangColors.noteBg);
}

/// « Venu aujourd'hui », « Pas venu depuis 3 jours », « Jamais venu ».
String presenceLabel(StudentSummary s) {
  final d = s.daysAway;
  if (d == null) return 'Jamais venu';
  if (d <= 0) return 'Venu aujourd\'hui';
  if (d == 1) return 'Venu hier';
  return 'Pas venu depuis $d jours';
}

String plural(int n, String word, [String? many]) => '$n ${n > 1 ? (many ?? '${word}s') : word}';

/// Noms des niveaux (identifiant → nom), pour l'affichage.
Future<Map<String, String>> examNames() async {
  try {
    return {for (final e in await ContentRepo.instance.exams()) e.id: e.name};
  } catch (_) {
    return const {};
  }
}

/// Message d'erreur simple quand le chargement échoue.
Widget loadError(VoidCallback retry) => Center(
      child: EmptyState(
        icon: Icons.cloud_off,
        title: 'Chargement impossible',
        message: 'Vérifie ta connexion internet.',
        action: FilledButton(onPressed: retry, child: const Text('Réessayer')),
      ),
    );
