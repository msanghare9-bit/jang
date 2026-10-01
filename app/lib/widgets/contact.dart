import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// « Nous contacter » : adresse e-mail et numéro de téléphone,
/// enregistrés dans config/contact et modifiables par le responsable.
class ContactCard extends StatefulWidget {
  final bool canEdit;
  const ContactCard({super.key, this.canEdit = false});

  @override
  State<ContactCard> createState() => _ContactCardState();
}

class _ContactCardState extends State<ContactCard> {
  static final _doc = FirebaseFirestore.instance.collection('config').doc('contact');
  String _email = '';
  String _phone = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    DocumentSnapshot<Map<String, dynamic>>? d;
    try {
      d = await _doc.get().timeout(const Duration(seconds: 8));
    } catch (_) {
      try {
        d = await _doc.get(const GetOptions(source: Source.cache));
      } catch (_) {}
    }
    final m = d?.data() ?? const {};
    if (!mounted) return;
    setState(() {
      _email = (m['email'] as String?)?.trim() ?? '';
      _phone = (m['phone'] as String?)?.trim() ?? '';
      _loaded = true;
    });
  }

  Future<void> _edit() async {
    final email = TextEditingController(text: _email);
    final phone = TextEditingController(text: _phone);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Nous contacter', style: titleStyle(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Adresse e-mail'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Numéro de téléphone', hintText: '+221 77 000 00 00'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    final e = email.text.trim();
    final p = phone.text.trim();
    email.dispose();
    phone.dispose();
    if (ok != true) return;
    setState(() {
      _email = e;
      _phone = p;
    });
    try {
      await _doc.set({'email': e, 'phone': p, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
      if (mounted) showMessage(context, 'Coordonnées enregistrées.');
    } catch (_) {
      if (mounted) showMessage(context, 'Enregistrement impossible. Vérifie ta connexion.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final empty = _email.isEmpty && _phone.isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Une question, une idée, un problème ?', style: t.titleSmall)),
              if (widget.canEdit)
                IconButton(
                  tooltip: 'Modifier',
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined),
                ),
            ]),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (empty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                    widget.canEdit
                        ? 'Ajoute ton e-mail et ton numéro avec le bouton ✎.'
                        : 'Les coordonnées seront bientôt disponibles.',
                    style: t.bodySmall),
              )
            else ...[
              if (_email.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline, color: JangColors.primary),
                  title: Text(_email),
                  subtitle: const Text('Écrire un e-mail'),
                  onTap: () => openLink('mailto:$_email?subject=J%C3%A0ng'),
                ),
              if (_phone.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone_outlined, color: JangColors.primary),
                  title: Text(_phone),
                  subtitle: const Text('Appeler'),
                  onTap: () => openLink('tel:${_phone.replaceAll(' ', '')}'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
