import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'inbox_service.dart';
import 'push_service.dart';

/// Actions de l'admin sur les comptes élèves : désactiver, supprimer.
class StudentAdminService {
  StudentAdminService._();
  static final instance = StudentAdminService._();

  final _db = FirebaseFirestore.instance;

  Future<void> setDisabled(String uid, bool disabled) =>
      _db.collection('users').doc(uid).update({'disabled': disabled});

  /// Efface les données de l'élève (progression, messages, mouton, profil),
  /// puis demande au serveur de supprimer son compte de connexion.
  /// Renvoie vrai si le compte de connexion a aussi été supprimé.
  Future<bool> delete(String uid) async {
    final user = _db.collection('users').doc(uid);
    for (final sub in ['progress', 'messages', 'missions']) {
      while (true) {
        final s = await user.collection(sub).limit(200).get();
        if (s.docs.isEmpty) break;
        final b = _db.batch();
        for (final d in s.docs) {
          b.delete(d.reference);
        }
        await b.commit();
      }
    }
    await _db.collection('moutons').doc(uid).delete().catchError((_) {});
    // Le compte reste désactivé tant que le compte de connexion existe.
    await user.set({'disabled': true, 'deleted': true, 'name': '', 'role': 'student'});
    final authDeleted = await PushService.instance.send({'uid': uid}, path: '/delete-user');
    if (authDeleted) await user.delete();
    try {
      await _db.collection('journal').add({'action': 'suppression', 'at': FieldValue.serverTimestamp()});
    } catch (_) {}
    return authDeleted;
  }
}

/// Messages tout prêts (modifiables avant l'envoi).
const messageTemplates = [
  'Bravo pour ton travail ! Continue comme ça.',
  'Je vois qu\'une mission est difficile. Tu veux de l\'aide ?',
  'On ne t\'a pas vu depuis quelques jours. Gaïndé t\'attend !',
  'Pense à faire les exercices de l\'unité.',
];

/// Fenêtre « Écrire un message » à un ou plusieurs élèves. Renvoie le nombre d'envois.
Future<int?> composeMessage(BuildContext context, List<String> uids, String label) async {
  final c = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Message à $label', style: titleStyle(20)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Messages tout prêts :', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final t in messageTemplates)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                  onPressed: () => setState(() => c.text = t),
                  child: Text(t),
                ),
              ),
            TextField(
              controller: c,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                  hintText: 'Écris un message court, en français simple.', border: OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Envoyer')),
        ],
      ),
    ),
  );
  if (text == null || text.isEmpty) return null;
  return InboxService.instance.send(uids, text);
}

/// Confirmation de suppression : il faut taper le prénom. Renvoie 'disable', 'delete' ou null.
Future<String?> confirmRemoval(BuildContext context, String name) async {
  final first = name.trim().split(RegExp(r'\s+')).first;
  final c = TextEditingController();
  var choice = 'disable';
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Supprimer $name ?', style: titleStyle(20)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'disable',
              groupValue: choice,
              onChanged: (v) => setState(() => choice = v!),
              title: const Text('Désactiver'),
              subtitle: const Text('Il ne peut plus se connecter. Ses résultats sont gardés. Tu peux le réactiver.'),
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'delete',
              groupValue: choice,
              onChanged: (v) => setState(() => choice = v!),
              title: const Text('Supprimer pour toujours', style: TextStyle(color: JangColors.errorDark)),
              subtitle: const Text('Compte, résultats et messages effacés. Impossible d\'annuler.'),
            ),
            const SizedBox(height: 8),
            Text('Pour confirmer, tape le prénom : $first'),
            TextField(controller: c, onChanged: (_) => setState(() {})),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: JangColors.error),
            onPressed: c.text.trim().toLowerCase() == first.toLowerCase() ? () => Navigator.pop(ctx, choice) : null,
            child: Text(choice == 'delete' ? 'Supprimer' : 'Désactiver'),
          ),
        ],
      ),
    ),
  );
}
