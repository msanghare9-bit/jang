import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _register = false;
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
  void dispose() {
    _name.dispose();
    _user.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_register && !_consent) {
      setState(() => _error = 'Coche la case : tes parents doivent être d\'accord.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await AuthService.instance.register(
          name: _name.text,
          username: _user.text,
          password: _pass.text,
          examId: '',
          parentConsent: _consent,
        );
      } else {
        await AuthService.instance.signIn(_user.text, _pass.text);
      }
    } on AuthError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Une erreur est survenue. Vérifie ta connexion et réessaie.');
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
                    Text('Jàng', style: titleStyle(46, color: JangColors.primary, weight: 800)),
                    const SizedBox(height: 6),
                    Text('Apprendre, leçon après leçon.',
                        style: t.bodyLarge!.copyWith(color: JangColors.textSecondary)),
                    const SizedBox(height: 32),
                    Text(_register ? 'Créer mon compte' : 'Se connecter', style: titleStyle(24)),
                    const SizedBox(height: 18),
                    if (_register) ...[
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
                    if (_register) ...[
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _consent,
                        onChanged: (v) => setState(() => _consent = v ?? false),
                        title: const Text(
                            'Mes parents sont d\'accord pour que j\'utilise Jàng, '
                            'y compris la discussion et Jàngalekat (une intelligence artificielle).'),
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
