import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/content_repo.dart';
import 'services/engagement_service.dart';
import 'services/progress_repo.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Une erreur d'affichage montre un message lisible au lieu d'un écran vide.
  ErrorWidget.builder = (details) => Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Erreur d\'affichage : ${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.black, fontSize: 14)),
        ),
      );
  // L'application s'affiche tout de suite ; le démarrage se fait derrière l'écran d'accueil.
  runApp(const _Bootstrap());
}

/// Démarre Firebase puis affiche l'application. En cas de problème, affiche la cause.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
            .timeout(const Duration(seconds: 30));
        // Copie locale illimitée : tout le contenu téléchargé reste disponible hors connexion.
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      }
      await ContentRepo.instance.init().timeout(const Duration(seconds: 15));
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const JangApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: JangColors.primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Jàng',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800)),
                const SizedBox(height: 24),
                if (_error == null)
                  const Center(child: CircularProgressIndicator(color: Colors.white))
                else ...[
                  const Text('Le démarrage a échoué. Vérifie ta connexion internet, puis réessaie.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 12),
                  Text('Détail : $_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white, foregroundColor: JangColors.primary),
                    onPressed: _start,
                    child: const Text('Réessayer'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class JangApp extends StatelessWidget {
  const JangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jàng',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}

/// Affiche l'écran de connexion ou l'application selon l'état du compte.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _loadedFor;
  bool _loading = false;

  Future<void> _load(User user) async {
    if (_loadedFor == user.uid || _loading) return;
    _loading = true;
    await AuthService.instance.loadProfile();
    await ProgressRepo.instance.load(user.uid);
    await EngagementService.instance.init(user.uid);
    _loadedFor = user.uid;
    _loading = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authChanges,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const _Splash();
        final user = snap.data;
        if (user == null) {
          _loadedFor = null;
          ProgressRepo.instance.clear();
          return const LoginScreen();
        }
        if (_loadedFor != user.uid) {
          _load(user);
          return const _Splash();
        }
        return ValueListenableBuilder(
          valueListenable: AuthService.instance.profile,
          builder: (context, profile, _) {
            if (profile == null) return _ProfileMissing(onRetry: () {
              _loadedFor = null;
              setState(() {});
            });
            return const HomeScreen();
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JangColors.primary,
      body: Center(
        child: Text('Jàng', style: titleStyle(52, color: Colors.white, weight: 800)),
      ),
    );
  }
}

class _ProfileMissing extends StatelessWidget {
  final VoidCallback onRetry;
  const _ProfileMissing({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Profil introuvable', style: titleStyle(24)),
              const SizedBox(height: 12),
              const Text(
                  'Ton profil n\'a pas pu être chargé. Vérifie ta connexion internet puis réessaie.'),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: () => AuthService.instance.signOut(),
                  child: const Text('Se déconnecter')),
            ],
          ),
        ),
      ),
    );
  }
}
