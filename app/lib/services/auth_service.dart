import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import 'class_service.dart';
import 'stats_service.dart';

/// Les élèves se connectent avec un identifiant (sans e-mail).
/// En interne, l'identifiant devient une adresse fictive « identifiant@jang.app ».
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const _domain = 'jang.app';
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  /// Profil de l'utilisateur connecté (null tant qu'il n'est pas chargé).
  final ValueNotifier<UserProfile?> profile = ValueNotifier(null);

  Stream<User?> get authChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  static String normalizeUsername(String raw) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyy';
    var s = raw.trim().toLowerCase();
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    s = b.toString().replaceAll(RegExp(r'\s+'), '.');
    return s;
  }

  static String? validateUsername(String raw) {
    final u = normalizeUsername(raw);
    if (u.length < 3) return 'Au moins 3 caractères.';
    if (u.length > 30) return 'Au plus 30 caractères.';
    if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(u)) {
      return 'Utilise seulement des lettres, des chiffres, le point ou le tiret.';
    }
    return null;
  }

  String _emailFor(String username) => '${normalizeUsername(username)}@$_domain';

  Future<void> signIn(String username, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: _emailFor(username), password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthError(_message(e));
    }
  }

  Future<void> register({
    required String name,
    required String username,
    required String password,
    required String examId,
    bool parentConsent = false,
    bool teacher = false,
    String school = '',
    List<String> teacherClasses = const [],
    List<String> teacherSubjects = const [],
    String teacherExamId = '',
    List<String> teacherExamIds = const [],
  }) async {
    UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
          email: _emailFor(username), password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthError(_message(e));
    }
    final uid = cred.user!.uid;
    final normalized = normalizeUsername(username);
    final batch = _db.batch();
    final normalizedSubjects = teacherSubjects.map((s) => subjectKey(s)).where((s) => s.isNotEmpty).toSet().toList();
    final normalizedClasses = teacherClasses.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
    final normalizedExamIds = teacherExamIds.isNotEmpty ? teacherExamIds.toSet().toList() : [teacherExamId];
    batch.set(_db.collection('users').doc(uid), {
      'name': name.trim(),
      'username': normalized,
      'role': teacher ? 'prof' : 'student',
      'examId': teacher ? normalizedExamIds.first : examId,
      'parentConsent': parentConsent,
      'createdAt': FieldValue.serverTimestamp(),
      if (teacher) 'school': school.trim(),
      if (teacher) 'profSubjects': normalizedSubjects,
      if (teacher) 'profExams': normalizedExamIds,
      if (teacher) 'canEdit': false,
    });
    batch.set(_db.collection('usernames').doc(normalized), {
      'uid': uid,
      'name': UserProfile.publicNameOf(name),
      'username': normalized,
    });
    await batch.commit();
    if (teacher) {
      for (var i = 0; i < normalizedClasses.length && i < normalizedExamIds.length; i++) {
        final className = normalizedClasses[i];
        final classExamId = normalizedExamIds[i];
        for (final subject in teacherSubjects.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet()) {
          await ClassService.instance.create(
            name: className,
            examId: classExamId,
            subjectName: subject,
            profUid: uid,
            profName: name.trim(),
            school: school.trim(),
          );
        }
      }
    }
    StatsService.instance.recordNewUser();
    await loadProfile();
  }

  /// Charge le profil : d'abord depuis le téléphone, puis depuis internet si possible.
  Future<UserProfile?> loadProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      profile.value = null;
      return null;
    }
    final ref = _db.collection('users').doc(user.uid);
    DocumentSnapshot<Map<String, dynamic>>? snap;
    try {
      snap = await ref.get(const GetOptions(source: Source.cache));
      if (snap.exists) profile.value = UserProfile.fromDoc(snap);
    } catch (_) {}
    try {
      final fresh = await ref.get(const GetOptions(source: Source.server)).timeout(
            const Duration(seconds: 12),
          );
      if (fresh.exists) {
        profile.value = UserProfile.fromDoc(fresh);
      }
    } catch (_) {
      // Hors connexion : on garde la version du téléphone.
    }
    final loaded = profile.value;
    if (loaded != null) await _ensureUsernameIndex(loaded);
    return loaded;
  }

  Future<void> _ensureUsernameIndex(UserProfile p) async {
    if (p.username.isEmpty) return;
    final ref = _db.collection('usernames').doc(normalizeUsername(p.username));
    try {
      final current = await ref.get();
      if (!current.exists) {
        await ref.set({'uid': p.uid, 'name': p.publicName, 'username': normalizeUsername(p.username)});
      }
    } catch (e) {
      debugPrint('Index Xarit : $e');
    }
  }

  Future<void> updateExam(String examId) async {
    final p = profile.value;
    if (p == null) return;
    _db.collection('users').doc(p.uid).update({'examId': examId});
    profile.value = p.copyWith(examId: examId);
  }

  /// Accord des parents (requis pour le tuteur IA et la discussion).
  Future<void> setParentConsent() async {
    final p = profile.value;
    if (p == null) return;
    _db.collection('users').doc(p.uid).update({'parentConsent': true});
    profile.value = p.copyWith(parentConsent: true);
  }

  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  Future<void> signOut() async {
    profile.value = null;
    await _auth.signOut();
  }

  String _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Cet identifiant est déjà pris. Choisis-en un autre.';
      case 'invalid-email':
        return 'Identifiant invalide.';
      case 'weak-password':
        return 'Mot de passe trop court (6 caractères minimum).';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Identifiant ou mot de passe incorrect.';
      case 'network-request-failed':
        return 'Pas de connexion internet. Réessaie quand tu seras connecté.';
      case 'too-many-requests':
        return 'Trop d\'essais. Attends quelques minutes puis réessaie.';
      case 'user-disabled':
        return 'Ce compte a été désactivé.';
      default:
        return 'Erreur (${e.code}). Réessaie.';
    }
  }
}

class AuthError implements Exception {
  final String message;
  AuthError(this.message);
  @override
  String toString() => message;
}
