import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';

/// Vérifie l'accord des parents avant la discussion ou le tuteur IA.
Future<bool> ensureParentConsent(BuildContext context) async {
  final p = AuthService.instance.profile.value;
  if (p == null) return false;
  if (p.parentConsent || p.isStaff) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Accord des parents', style: titleStyle(20)),
      content: const Text(
          'Pour écrire dans la discussion ou poser une question à Kocc Barma, tes parents doivent être d\'accord. '
          'Tes messages sont visibles par les autres élèves et par le responsable. '
          'Ne donne jamais ton numéro de téléphone ni ton adresse.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(c, true), child: const Text('Mes parents sont d\'accord')),
      ],
    ),
  );
  if (ok == true) {
    await AuthService.instance.setParentConsent();
    return true;
  }
  return false;
}
