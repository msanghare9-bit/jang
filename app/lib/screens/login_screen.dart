import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/characters.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _register = false;
  bool _teacher = false;
  List<Exam> _exams = const [];
  final Set<String> _teacherExamIds = {};
  final _school = TextEditingController();
  final List<TextEditingController> _subjectFields = [TextEditingController()];
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  bool _consent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ContentRepo.instance.exams().then((exams) {
      if (mounted) setState(() => _exams = exams);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _pass.dispose();
    _pass2.dispose();
    _school.dispose();
    for (final field in _subjectFields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_register && _teacher && (_school.text.trim().isEmpty || _teacherExamIds.isEmpty || _subjectFields.every((field) => field.text.trim().isEmpty))) {
      setState(() => _error = 'Renseignez votre école, au moins un niveau et une matière.');
      return;
    }
    if (_register && !_teacher && !_consent) {
      setState(() => _error = 'Coche la case : tes parents doivent être d\'accord.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        final selectedExams = _exams.where((exam) => _teacherExamIds.contains(exam.id)).toList();
        final school = _school.text.trim();
        await AuthService.instance.register(
          name: _name.text,
          username: _user.text,
          password: _pass.text,
          examId: '',
          parentConsent: _consent,
          teacher: _teacher,
          school: school,
          teacherClasses: [for (final exam in selectedExams) '$school · ${exam.name}'],
          teacherSubjects: _subjectFields.map((field) => field.text.trim()).where((s) => s.isNotEmpty).toList(),
          teacherExamId: selectedExams.first.id,
          teacherExamIds: [for (final exam in selectedExams) exam.id],
        );
      } else {
        await AuthService.instance.signIn(_user.text, _pass.text);
      }
    } on AuthError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      debugPrint('Inscription/connexion : $e');
      final code = switch (e) {
        FirebaseAuthException authError => 'auth/${authError.code}',
        FirebaseException firebaseError => '${firebaseError.plugin}/${firebaseError.code}',
        _ => e.runtimeType.toString(),
      };
      setState(() => _error =
          'La demande n’a pas abouti (code : $code). Réessaie; si le problème persiste, communique ce code à Jàng.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      CharacterView(Chars.awa, size: 70, moves: Moves.bob),
                      CharacterView(Chars.lion, size: 96, moves: Moves.dance),
                      CharacterView(Chars.modou, size: 70, moves: Moves.sway, flip: true),
                    ]),
                    const SizedBox(height: 8),
                    Text('Jàng', style: titleStyle(46, color: JangColors.primary, weight: 800)),
                    const SizedBox(height: 6),
                    Text('Apprendre, leçon après leçon.',
                        style: t.bodyLarge!.copyWith(color: JangColors.textSecondary)),
                    const SizedBox(height: 32),
                    Text(_register ? 'Créer mon compte' : 'Se connecter', style: titleStyle(24)),
                    const SizedBox(height: 18),
                    if (_register) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Élève'), icon: Icon(Icons.menu_book_outlined)),
                          ButtonSegment(value: true, label: Text('Professeur'), icon: Icon(Icons.school_outlined)),
                        ],
                        selected: {_teacher},
                        onSelectionChanged: (v) => setState(() { _teacher = v.first; _error = null; }),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Prénom et nom'),
                        validator: (v) =>
                            (v == null || v.trim().length < 2) ? 'Écris ton prénom et ton nom.' : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _user,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.visiblePassword,
                      decoration: InputDecoration(
                        labelText: 'Identifiant',
                        helperText: _register ? 'Exemple : awa.diop — à retenir pour te reconnecter' : null,
                      ),
                      validator: (v) => AuthService.validateUsername(v ?? ''),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _pass,
                      obscureText: _hide,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        suffixIcon: IconButton(
                          tooltip: _hide ? 'Afficher' : 'Masquer',
                          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 6) ? '6 caractères minimum.' : null,
                    ),
                    if (_register) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _pass2,
                        obscureText: _hide,
                        decoration: const InputDecoration(labelText: 'Confirme le mot de passe'),
                        validator: (v) =>
                            v != _pass.text ? 'Les deux mots de passe sont différents.' : null,
                      ),
                    ],
                    if (_register && _teacher) ...[
                      const SizedBox(height: 14),
                      TextFormField(controller: _school, textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'École')),
                      const SizedBox(height: 12),
                      Text('Niveaux de classe', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const Text('Cochez tous les niveaux où vous enseignez. Une classe sera créée automatiquement pour chacun.'),
                      const SizedBox(height: 4),
                      if (_exams.isEmpty)
                        const LinearProgressIndicator()
                      else
                        ..._exams.map((exam) => CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _teacherExamIds.contains(exam.id),
                              title: Text(exam.name),
                              onChanged: (selected) => setState(() {
                                if (selected == true) {
                                  _teacherExamIds.add(exam.id);
                                } else {
                                  _teacherExamIds.remove(exam.id);
                                }
                              }),
                            )),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: Text('Matières enseignées', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                        IconButton(
                          tooltip: 'Ajouter une matière',
                          onPressed: () => setState(() => _subjectFields.add(TextEditingController())),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ]),
                      for (var i = 0; i < _subjectFields.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Expanded(child: TextFormField(
                              controller: _subjectFields[i],
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(labelText: 'Matière ${i + 1}', hintText: 'Anglais'),
                            )),
                            if (_subjectFields.length > 1)
                              IconButton(
                                tooltip: 'Supprimer cette matière',
                                onPressed: () => setState(() {
                                  _subjectFields.removeAt(i).dispose();
                                }),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                          ]),
                        ),
                      const SizedBox(height: 8),
                      const Text('Votre espace professeur et vos classes seront créés immédiatement, sans validation manuelle.'),
                    ],
                    if (_register && !_teacher) ...[
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _consent,
                        onChanged: (v) => setState(() => _consent = v ?? false),
                        title: const Text(
                            'Mes parents sont d\'accord pour que j\'utilise Jàng, '
                            'y compris la discussion et Kocc Barma (une intelligence artificielle).'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: JangColors.errorBg, borderRadius: BorderRadius.circular(8)),
                        child: Text(_error!, style: const TextStyle(color: JangColors.error)),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(_register ? 'Créer mon compte' : 'Se connecter'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _teacher = false;
                                _error = null;
                              }),
                      child: Text(_register
                          ? 'J\'ai déjà un compte : me connecter'
                          : 'Nouveau ? Créer un compte'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
