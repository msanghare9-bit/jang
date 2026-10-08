import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import 'content_repo.dart';

/// Leçon toute prête (texte, QCM et fiches), publiée dans le dépôt GitHub.
class LessonPack {
  final String id;
  final String subject;
  final String level;
  final String title;
  final String body;
  final List<QuizQuestion> quiz;
  final List<Flashcard> cards;
  LessonPack({
    required this.id,
    required this.subject,
    required this.level,
    required this.title,
    required this.body,
    required this.quiz,
    required this.cards,
  });

  /// Ancien identifiant (partagé entre toutes les classes).
  String get lessonId => 'pack_$id';

  /// Identifiant propre à une matière : chaque classe a sa copie.
  String lessonIdFor(Subject s) => 'pack_${id}_${s.id}';

  factory LessonPack.fromMap(Map m) {
    String s(Object? v) => v is String ? v : '';
    final qcm = m['qcm'] is List ? m['qcm'] as List : const [];
    final fiches = m['fiches'] is List ? m['fiches'] as List : const [];
    return LessonPack(
      id: s(m['id']),
      subject: s(m['matiere']),
      level: s(m['niveau']),
      title: s(m['titre']),
      body: s(m['texte']),
      quiz: [
        for (final q in qcm.whereType<Map>())
          QuizQuestion(
            question: s(q['question']),
            options: [
              for (var i = 0; i < 4; i++)
                (q['options'] is List && (q['options'] as List).length > i)
                    ? s((q['options'] as List)[i])
                    : '',
            ],
            answer: (q['reponse'] is int ? q['reponse'] as int : 0).clamp(0, 3).toInt(),
            explanation: s(q['explication']),
          ),
      ],
      cards: [
        for (final c in fiches.whereType<Map>())
          Flashcard(front: s(c['recto']), back: s(c['verso'])),
      ],
    );
  }

  static String _norm(String t) => t
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâ]'), 'a')
      .replaceAll(RegExp(r'\s+'), '');

  /// Niveau lu dans un nom (« 6e », « 6ème », « Sixième »…) : '6', ou '' si aucun.
  static String levelOf(String name) {
    final n = _norm(name);
    const words = {
      'sixieme': '6', 'cinquieme': '5', 'quatrieme': '4', 'troisieme': '3',
      'seconde': '2', 'premiere': '1', 'terminale': 't',
    };
    for (final e in words.entries) {
      if (n.contains(e.key)) return e.value;
    }
    final m = RegExp(r'(\d)(e|eme|°)').firstMatch(n);
    return m?.group(1) ?? '';
  }

  /// Vrai si ce paquet est destiné à cette matière de ce niveau.
  bool fits(Subject s, List<String> examNames) {
    final name = _norm(s.name);
    final want0 = _norm(subject);
    final okSubject = want0.isEmpty ||
        name.contains(want0) ||
        (want0.startsWith('angl') && (name.contains('angl') || name.contains('english')));
    final want = levelOf(level);
    final haves = examNames.map(levelOf).where((l) => l.isNotEmpty).toSet();
    final okLevel = want.isEmpty || haves.isEmpty || haves.contains(want);
    return okSubject && okLevel;
  }
}

class PackService {
  PackService._();
  static final instance = PackService._();

  static const _url =
      'https://raw.githubusercontent.com/msanghare9-bit/jang/main/contenus/lecons.json';

  Future<List<LessonPack>?> fetch() async {
    try {
      final uri = Uri.parse('$_url?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}');
      final res = await http.get(uri).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final text = res.body;
      final data = jsonDecode(text);
      final list = data is Map && data['lecons'] is List ? data['lecons'] as List : const [];
      return list
          .whereType<Map>()
          .map(LessonPack.fromMap)
          .where((p) => p.id.isNotEmpty && p.title.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Leçons prêtes indisponibles : $e');
      return null;
    }
  }

  /// Ajoute les leçons dans la matière, à la suite des leçons existantes.
  /// [hiddenIn] : classes de la matière partagée où ces leçons restent cachées.
  void add(Subject subject, List<LessonPack> packs, int firstOrder, {List<String> hiddenIn = const []}) {
    final db = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    final batch = db.batch();
    var order = firstOrder;
    for (final p in packs) {
      final lid = p.lessonIdFor(subject);
      batch.set(db.collection('lessons').doc(lid), {
        'examId': subject.examId,
        'subjectId': subject.id,
        'chapterId': '',
        'title': p.title,
        'order': order++,
        'videos': <Map<String, dynamic>>[],
        'body': p.body,
        'quiz': p.quiz.map((q) => q.toMap()).toList(),
        'hiddenIn': hiddenIn,
        'deleted': false,
        'updatedAt': now,
      });
      if (p.cards.isNotEmpty) {
        batch.set(db.collection('flashcards').doc(lid), {
          'chapterId': lid,
          'lessonId': lid,
          'subjectId': subject.id,
          'examId': subject.examId,
          'cards': p.cards.map((c) => c.toMap()).toList(),
          'deleted': false,
          'updatedAt': now,
        });
      }
    }
    unawaited(batch.commit().catchError((e) => debugPrint('Écriture refusée : $e')));
    ContentRepo.instance.notifyChanged();
  }
}
