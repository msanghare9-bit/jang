import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'auth_service.dart';

/// Une étape de croissance du mouton.
class SheepStage {
  final String name;
  final int from;
  final double scale;
  const SheepStage(this.name, this.from, this.scale);
}

/// Un camarade, pour comparer les moutons de la semaine.
class SheepRival {
  final String name;
  final int week;
  SheepRival(this.name, this.week);
}

/// Le mouton de l'élève : il grandit à chaque mission (ou leçon) terminée.
/// Il ne rétrécit jamais et ne meurt jamais.
class SheepService {
  SheepService._();
  static final instance = SheepService._();

  static const stages = [
    SheepStage('Agneau', 0, 0.55),
    SheepStage('Petit mouton', 5, 0.7),
    SheepStage('Jeune mouton', 12, 0.82),
    SheepStage('Beau mouton', 20, 0.92),
    SheepStage('Ladoum champion', 30, 1.0),
  ];

  /// Accessoires gagnés : un toutes les 6 missions.
  static const accessories = [
    'Collier bleu',
    'Ruban rouge',
    'Grelot doré',
    'Couverture brodée',
    'Bonnet de laine',
  ];

  final _db = FirebaseFirestore.instance;
  final ValueNotifier<int> revision = ValueNotifier(0);
  int total = 0;
  int week = 0;
  DateTime? lastFed;
  String? _uid;

  /// Numéro de semaine (lundi au dimanche), ex. « 2026-W41 ».
  static String weekKey([DateTime? d]) {
    final now = d ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final thursday = day.add(Duration(days: 4 - day.weekday));
    final firstDay = DateTime(thursday.year, 1, 1);
    final n = ((thursday.difference(firstDay).inDays) / 7).floor() + 1;
    return '${thursday.year}-W${n.toString().padLeft(2, '0')}';
  }

  SheepStage get stage => stages.lastWhere((s) => total >= s.from);
  SheepStage? get nextStage {
    for (final s in stages) {
      if (s.from > total) return s;
    }
    return null;
  }

  int get accessoriesWon => (total ~/ 6).clamp(0, accessories.length);

  /// Faim : pas de mission depuis 3 jours.
  bool get hungry => lastFed != null && DateTime.now().difference(lastFed!).inDays >= 3;

  Future<void> load(String uid) async {
    _uid = uid;
    final prefs = await SharedPreferences.getInstance();
    total = prefs.getInt('sheep_total_$uid') ?? 0;
    final wk = prefs.getString('sheep_week_key_$uid');
    week = wk == weekKey() ? (prefs.getInt('sheep_week_$uid') ?? 0) : 0;
    final fed = prefs.getInt('sheep_fed_$uid');
    lastFed = fed == null ? null : DateTime.fromMillisecondsSinceEpoch(fed);
    revision.value++;
    unawaited(_syncFromServer(uid));
  }

  Future<void> _syncFromServer(String uid) async {
    try {
      final d = await _db.collection('moutons').doc(uid).get().timeout(const Duration(seconds: 12));
      final m = d.data();
      if (m == null) return;
      final t = (m['total'] as num?)?.toInt() ?? 0;
      final w = m['weekKey'] == weekKey() ? ((m['week'] as num?)?.toInt() ?? 0) : 0;
      if (t > total || w > week) {
        total = t > total ? t : total;
        week = w > week ? w : week;
        await _saveLocal(uid);
        revision.value++;
      }
    } catch (_) {}
  }

  Future<void> _saveLocal(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sheep_total_$uid', total);
    await prefs.setInt('sheep_week_$uid', week);
    await prefs.setString('sheep_week_key_$uid', weekKey());
    if (lastFed != null) await prefs.setInt('sheep_fed_$uid', lastFed!.millisecondsSinceEpoch);
  }

  /// Une mission (ou une leçon) vient d'être terminée pour la première fois.
  Future<void> feed() async {
    final uid = _uid;
    final p = AuthService.instance.profile.value;
    if (uid == null || p == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('sheep_week_key_$uid') != weekKey()) week = 0;
    total++;
    week++;
    lastFed = DateTime.now();
    await _saveLocal(uid);
    revision.value++;
    unawaited(_db.collection('moutons').doc(uid).set({
      'name': p.hideName ? '' : p.firstName,
      'sheep': p.sheepName,
      'examId': p.examId,
      'total': total,
      'week': week,
      'weekKey': weekKey(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).catchError((e) => debugPrint('Mouton non enregistré : $e')));
  }

  Future<void> rename(String name) async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    AuthService.instance.profile.value = p.copyWith(sheepName: name);
    unawaited(_db.collection('users').doc(p.uid).update({'sheepName': name}).catchError((_) {}));
    unawaited(_db
        .collection('moutons')
        .doc(p.uid)
        .set({'sheep': name}, SetOptions(merge: true)).catchError((_) {}));
    revision.value++;
  }

  Future<void> setHideName(bool hide) async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    AuthService.instance.profile.value = p.copyWith(hideName: hide);
    unawaited(_db.collection('users').doc(p.uid).update({'hideName': hide}).catchError((_) {}));
    unawaited(_db
        .collection('moutons')
        .doc(p.uid)
        .set({'name': hide ? '' : p.firstName}, SetOptions(merge: true)).catchError((_) {}));
  }

  /// Camarades du même niveau cette semaine : (celui juste devant, celui juste derrière).
  Future<(SheepRival?, SheepRival?)> rivals() async {
    final p = AuthService.instance.profile.value;
    if (p == null || p.examId.isEmpty) return (null, null);
    try {
      final s = await _db
          .collection('moutons')
          .where('examId', isEqualTo: p.examId)
          .where('weekKey', isEqualTo: weekKey())
          .limit(80)
          .get()
          .timeout(const Duration(seconds: 12));
      SheepRival? ahead, behind;
      for (final d in s.docs) {
        if (d.id == p.uid) continue;
        final m = d.data();
        final w = (m['week'] as num?)?.toInt() ?? 0;
        final raw = (m['name'] as String?) ?? '';
        final name = raw.isEmpty ? 'un élève de ta classe' : raw;
        if (w > week && (ahead == null || w < ahead.week)) ahead = SheepRival(name, w);
        if (w < week && w > 0 && (behind == null || w > behind.week)) behind = SheepRival(name, w);
      }
      return (ahead, behind);
    } catch (e) {
      debugPrint('Comparaison impossible : $e');
      return (null, null);
    }
  }
}

/// Le profil a-t-il déjà un nom de mouton ?
bool hasSheepName(UserProfile? p) => (p?.sheepName ?? '').trim().isNotEmpty;
