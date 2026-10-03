import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'auth_service.dart';
import 'content_repo.dart';
import 'progress_repo.dart';
import 'stats_service.dart';

/// Un badge à gagner.
class BadgeDef {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  const BadgeDef(this.id, this.title, this.description, this.icon);
}

const badgeDefs = <BadgeDef>[
  BadgeDef('premier_pas', 'Premier pas', 'Ouvrir ta première leçon', Icons.directions_walk),
  BadgeDef('lecteur', 'Lecteur assidu', 'Ouvrir 10 leçons', Icons.menu_book),
  BadgeDef('premier_qcm', 'Premiers exercices', 'Terminer tes premiers exercices', Icons.quiz_outlined),
  BadgeDef('sans_faute', 'Sans faute', 'Avoir 100 % à des exercices', Icons.verified_outlined),
  BadgeDef('perfection', 'Perfection', 'Avoir 100 % à 5 séries d\'exercices', Icons.workspace_premium_outlined),
  BadgeDef('chapitre', 'Dix séries', 'Terminer 10 séries d\'exercices', Icons.flag_outlined),
  BadgeDef('matiere', 'Matière bouclée', 'Faire tous les exercices d\'une matière', Icons.emoji_events_outlined),
  BadgeDef('serie3', 'Régulier', 'Réviser 3 jours de suite', Icons.local_fire_department_outlined),
  BadgeDef('serie7', 'Infatigable', 'Réviser 7 jours de suite', Icons.whatshot_outlined),
  BadgeDef('correcteur', 'Correcteur', 'Corriger 10 erreurs en révision', Icons.build_circle_outlined),
  BadgeDef('objectif', 'Objectif atteint', 'Atteindre ton objectif de la semaine', Icons.track_changes),
  BadgeDef('memoire', 'Bonne mémoire', 'Réviser 50 cartes', Icons.style_outlined),
  BadgeDef('curieux', 'Curieux', 'Poser ta première question', Icons.forum_outlined),
];

/// Motivation : jours de révision, série, objectif de la semaine, badges.
/// Les données sont gardées sur le téléphone ; les badges gagnés sont aussi copiés sur le compte.
class EngagementService {
  EngagementService._();
  static final instance = EngagementService._();

  final ValueNotifier<int> revision = ValueNotifier(0);

  /// Dernier badge gagné, pour afficher une félicitation.
  final ValueNotifier<BadgeDef?> newBadge = ValueNotifier(null);

  SharedPreferences? _prefs;
  String _uid = '';

  String _k(String name) => '${name}_$_uid';

  Future<void> init(String uid) async {
    _prefs = await SharedPreferences.getInstance();
    _uid = uid;
    // Récupère les badges déjà enregistrés sur le compte (après une réinstallation).
    final fromAccount = AuthService.instance.profile.value?.badges ?? const [];
    final local = earnedIds;
    final merged = {...local, ...fromAccount}.toList();
    await _prefs!.setStringList(_k('badges'), merged);
    revision.value++;
    unawaited(evaluate());
  }

  Set<String> get earnedIds => (_prefs?.getStringList(_k('badges')) ?? const []).toSet();

  // ---------------- Jours de révision et série ----------------

  List<String> get _days => _prefs?.getStringList(_k('study_days')) ?? const [];

  /// Enregistre une activité ([type] = 'lesson' ou 'quiz'), une seule fois par jour et par leçon.
  Future<void> logStudy(String type, String lessonId) async {
    final p = _prefs;
    if (p == null) return;
    final today = StatsService.dayKey();
    final days = {..._days, today}.toList()..sort();
    await p.setStringList(_k('study_days'), days.length > 90 ? days.sublist(days.length - 90) : days);
    final entry = '$today|$type|$lessonId';
    final old = p.getStringList(_k('events')) ?? const <String>[];
    if (old.contains(entry)) return;
    final events = [...old, entry];
    await p.setStringList(_k('events'), events.length > 400 ? events.sublist(events.length - 400) : events);
    revision.value++;
    unawaited(evaluate());
  }

  /// Jours où l'élève a appris (clés « AAAA-MM-JJ »).
  Set<String> get daySet => _days.toSet();

  int get streak {
    final set = _days.toSet();
    var d = DateTime.now();
    if (!set.contains(StatsService.dayKey(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (set.contains(StatsService.dayKey(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  // ---------------- Objectif de la semaine ----------------

  /// Type : 'lesson' (leçons ouvertes) ou 'quiz' (QCM faits). 0 = pas d'objectif.
  String get goalType => _prefs?.getString(_k('goal_type')) ?? 'lesson';
  int get goalTarget => _prefs?.getInt(_k('goal_target')) ?? 0;

  Future<void> setGoal(String type, int target) async {
    await _prefs?.setString(_k('goal_type'), type);
    await _prefs?.setInt(_k('goal_target'), target);
    revision.value++;
    unawaited(evaluate());
  }

  static DateTime get weekStart {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  int weekCount(String type) {
    final start = StatsService.dayKey(weekStart);
    return (_prefs?.getStringList(_k('events')) ?? const <String>[]).where((e) {
      final parts = e.split('|');
      return parts.length >= 2 && parts[1] == type && parts[0].compareTo(start) >= 0;
    }).length;
  }

  // ---------------- Compteurs divers ----------------

  int counter(String name) => _prefs?.getInt(_k('count_$name')) ?? 0;

  Future<void> addTo(String name, [int n = 1]) async {
    await _prefs?.setInt(_k('count_$name'), counter(name) + n);
    revision.value++;
    unawaited(evaluate());
  }

  // ---------------- Badges ----------------

  bool _evaluating = false;

  Future<void> evaluate() async {
    final p = _prefs;
    if (p == null || _uid.isEmpty || _evaluating) return;
    _evaluating = true;
    try {
      final progress = ProgressRepo.instance.all.values.toList();
      final seen = progress.where((x) => x.seen).length;
      final quizzes = progress.where((x) => x.quizDone).toList();
      final perfect = quizzes.where((x) => x.bestScore == x.total).length;

      final earned = <String>{};
      if (seen >= 1) earned.add('premier_pas');
      if (seen >= 10) earned.add('lecteur');
      if (quizzes.isNotEmpty) earned.add('premier_qcm');
      if (quizzes.length >= 10) earned.add('chapitre');
      if (perfect >= 1) earned.add('sans_faute');
      if (perfect >= 5) earned.add('perfection');
      final s = streak;
      if (s >= 3) earned.add('serie3');
      if (s >= 7) earned.add('serie7');
      if (counter('mistakes_fixed') >= 10) earned.add('correcteur');
      if (counter('flashcards') >= 50) earned.add('memoire');
      if (counter('questions') >= 1) earned.add('curieux');
      if (goalTarget > 0 && weekCount(goalType) >= goalTarget) earned.add('objectif');

      // Matières terminées (toutes les leçons avec QCM faites).
      final examId = AuthService.instance.profile.value?.examId ?? '';
      if (examId.isNotEmpty && quizzes.isNotEmpty) {
        final lessons = (await ContentRepo.instance.lessonsOfExam(examId))
            .where((l) => l.quiz.isNotEmpty)
            .toList();
        bool done(Lesson l) => ProgressRepo.instance.of(l.id)?.quizDone == true;
        final bySubject = <String, List<Lesson>>{};
        for (final l in lessons) {
          bySubject.putIfAbsent(l.subjectId, () => []).add(l);
        }
        if (bySubject.values.any((ls) => ls.length >= 3 && ls.every(done))) earned.add('matiere');
      }

      final before = earnedIds;
      final fresh = earned.difference(before);
      if (fresh.isNotEmpty) {
        await p.setStringList(_k('badges'), {...before, ...earned}.toList());
        final def = badgeDefs.firstWhere((b) => b.id == fresh.first);
        newBadge.value = def;
        revision.value++;
        unawaited(FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .set({'badges': FieldValue.arrayUnion(fresh.toList())}, SetOptions(merge: true))
            .catchError((e) => debugPrint('$e')));
      }
    } finally {
      _evaluating = false;
    }
  }
}
