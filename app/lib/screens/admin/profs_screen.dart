import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../firebase_options.dart';
import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Les profs : l'admin en ajoute pour une ou plusieurs matières, dans un ou plusieurs niveaux.
class ProfsScreen extends StatefulWidget {
  const ProfsScreen({super.key});

  @override
  State<ProfsScreen> createState() => _ProfsScreenState();
}

class _ProfsScreenState extends State<ProfsScreen> {
  final _db = FirebaseFirestore.instance;
  late Future<List<UserProfile>> _future = _load();
  List<Exam> _exams = const [];
  Map<String, String> _subjects = const {};

  Future<List<UserProfile>> _load() async {
    final repo = ContentRepo.instance;
    final exams = await repo.exams();
    final subjects = <String, String>{};
    for (final e in exams) {
      for (final s in await repo.subjects(e.id)) {
        subjects.putIfAbsent(subjectKey(s.name), () => s.name);
      }
    }
    _exams = exams;
    _subjects = subjects;
    final s = await _db.collection('users').where('role', whereIn: ['admin', 'prof']).get();
    final list = s.docs.map(UserProfile.fromDoc).toList()
      ..sort((a, b) => a.isAdmin == b.isAdmin ? a.name.compareTo(b.name) : (a.isAdmin ? -1 : 1));
    return list;
  }

  String _describe(UserProfile p) {
    if (p.isAdmin) return 'Admin · tout';
    final subj = p.profSubjects.map((k) => _subjects[k] ?? k).join(', ');
    final lv = p.profExams.isEmpty
        ? 'tous les niveaux'
        : p.profExams.map((id) => _exams.where((e) => e.id == id).firstOrNull?.name ?? '?').join(', ');
    return 'Prof · ${subj.isEmpty ? 'aucune matière' : subj} · $lv${p.canEdit ? ' · peut modifier les contenus' : ''}';
  }

  Future<void> _edit({UserProfile? prof}) async {
    final r = await showDialog<_ProfChoice>(
      context: context,
      builder: (_) => _ProfDialog(prof: prof, exams: _exams, subjects: _subjects),
    );
    if (r == null || !mounted) return;
    try {
      var uid = prof?.uid;
      if (uid == null && r.create) {
        uid = await _createAccount(r.name, r.username, r.password);
      } else if (uid == null) {
        final u = AuthService.normalizeUsername(r.username);
        final s = await _db.collection('users').where('username', isEqualTo: u).limit(1).get();
        if (s.docs.isEmpty) {
          if (mounted) showMessage(context, 'Aucun compte avec l\'identifiant « $u ».');
          return;
        }
        uid = s.docs.first.id;
      }
      await _db.collection('users').doc(uid).set({
        'role': 'prof',
        'profSubjects': r.subjects,
        'profExams': r.exams,
        'canEdit': r.canEdit,
        if (r.name.isNotEmpty) 'name': r.name,
      }, SetOptions(merge: true));
      if (!mounted) return;
      showMessage(context, prof == null ? 'Prof ajouté.' : 'Prof modifié.');
      setState(() => _future = _load());
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        showMessage(context, e.code == 'email-already-in-use' ? 'Cet identifiant est déjà pris.' : 'Erreur : ${e.code}');
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    }
  }

  /// Crée le compte du prof sans déconnecter l'admin (deuxième connexion Firebase).
  Future<String> _createAccount(String name, String username, String password) async {
    final app = await Firebase.initializeApp(
        name: 'creation_${DateTime.now().millisecondsSinceEpoch}', options: DefaultFirebaseOptions.currentPlatform);
    try {
      final auth = FirebaseAuth.instanceFor(app: app);
      final u = AuthService.normalizeUsername(username);
      final cred = await auth.createUserWithEmailAndPassword(email: '$u@jang.app', password: password);
      final uid = cred.user!.uid;
      await _db.collection('users').doc(uid).set({
        'name': name,
        'username': u,
        'role': 'prof',
        'examId': '',
        'parentConsent': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await auth.signOut();
      return uid;
    } finally {
      await app.delete();
    }
  }

  Future<void> _remove(UserProfile p) async {
    if (!await confirm(context, 'Retirer ${p.name} ?',
        'Ce compte redevient un compte élève. Il ne verra plus l\'onglet « Gestion ».',
        ok: 'Retirer')) {
      return;
    }
    await _db.collection('users').doc(p.uid).update({'role': 'student'});
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Les profs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Ajouter un prof'),
      ),
      body: FutureBuilder<List<UserProfile>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: EmptyState(icon: Icons.cloud_off, title: 'Chargement impossible', message: '${snap.error}'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final me = AuthService.instance.profile.value!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              Text(
                  'Un prof voit ses élèves, leur écrit et fait des annonces dans ses matières. '
                  'Il ne peut pas supprimer d\'élève ni ajouter d\'autres profs.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              for (final p in snap.data!)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: p.isAdmin ? JangColors.text : JangColors.noteBg,
                      child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                          style: TextStyle(color: p.isAdmin ? Colors.white : JangColors.primaryDark)),
                    ),
                    title: Text(p.uid == me.uid ? '${p.name} (moi)' : p.name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${p.username} · ${_describe(p)}'),
                    trailing: p.isAdmin
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (v) => v == 'edit' ? _edit(prof: p) : _remove(p),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Modifier')),
                              PopupMenuItem(value: 'remove', child: Text('Retirer')),
                            ],
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfChoice {
  final bool create;
  final String name;
  final String username;
  final String password;
  final List<String> subjects;
  final List<String> exams;
  final bool canEdit;
  _ProfChoice(this.create, this.name, this.username, this.password, this.subjects, this.exams, this.canEdit);
}

class _ProfDialog extends StatefulWidget {
  final UserProfile? prof;
  final List<Exam> exams;
  final Map<String, String> subjects;
  const _ProfDialog({this.prof, required this.exams, required this.subjects});

  @override
  State<_ProfDialog> createState() => _ProfDialogState();
}

class _ProfDialogState extends State<_ProfDialog> {
  late bool _create = widget.prof == null;
  late final _name = TextEditingController(text: widget.prof?.name ?? '');
  late final _username = TextEditingController(text: widget.prof?.username ?? '');
  final _password = TextEditingController();
  late final Set<String> _subjects = {...?widget.prof?.profSubjects};
  late final Set<String> _exams = {...?widget.prof?.profExams};
  late bool _canEdit = widget.prof?.canEdit ?? false;

  bool get _valid {
    if (_subjects.isEmpty) return false;
    if (widget.prof != null) return true;
    if (AuthService.validateUsername(_username.text) != null) return false;
    if (_create && (_name.text.trim().isEmpty || _password.text.length < 6)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.prof != null;
    return AlertDialog(
      title: Text(editing ? 'Modifier ${widget.prof!.name}' : 'Ajouter un prof', style: titleStyle(20)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!editing) ...[
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Créer un compte'), selected: _create, onSelected: (_) => setState(() => _create = true)),
              ChoiceChip(label: const Text('Choisir un inscrit'), selected: !_create, onSelected: (_) => setState(() => _create = false)),
            ]),
            if (_create)
              TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nom (ex. : M. Diallo)')),
            TextField(
                controller: _username,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Identifiant')),
            if (_create)
              TextField(
                  controller: _password,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Mot de passe (6 caractères minimum)')),
            const SizedBox(height: 10),
          ],
          const Text('Matières', style: TextStyle(fontWeight: FontWeight.w800)),
          Wrap(spacing: 6, children: [
            for (final e in widget.subjects.entries)
              FilterChip(
                label: Text(e.value),
                selected: _subjects.contains(e.key),
                onSelected: (v) => setState(() => v ? _subjects.add(e.key) : _subjects.remove(e.key)),
              ),
          ]),
          const SizedBox(height: 8),
          const Text('Niveaux (aucun coché = tous)', style: TextStyle(fontWeight: FontWeight.w800)),
          Wrap(spacing: 6, children: [
            for (final e in widget.exams)
              FilterChip(
                label: Text(e.name),
                selected: _exams.contains(e.id),
                onSelected: (v) => setState(() => v ? _exams.add(e.id) : _exams.remove(e.id)),
              ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _canEdit,
            onChanged: (v) => setState(() => _canEdit = v),
            title: const Text('Peut modifier les contenus de ses matières'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(
                  context,
                  _ProfChoice(_create, _name.text.trim(), _username.text, _password.text, _subjects.toList(),
                      _exams.toList(), _canEdit))
              : null,
          child: Text(editing ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}
