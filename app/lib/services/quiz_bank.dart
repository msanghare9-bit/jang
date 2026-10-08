import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Une question de la banque des matchs (contenus/quiz/DOMAINE_NIVEAU.json).
class BankQuestion {
  final String id;
  final String question;
  final List<String> options;
  final int answer;
  final String explanation;

  /// Texte à lire (compréhension), vide sinon.
  final String text;

  /// Domaine et niveau d'où vient la question (pour les signalements).
  final String domain;
  final String level;
  BankQuestion({
    this.id = '',
    required this.question,
    required this.options,
    required this.answer,
    this.explanation = '',
    this.text = '',
    this.domain = '',
    this.level = '',
  });

  factory BankQuestion.fromMap(Map m, {String domain = '', String level = ''}) {
    final o = (m['o'] is List ? m['o'] as List : const []).map((e) => '$e').toList();
    while (o.length < 4) {
      o.add('');
    }
    return BankQuestion(
      id: '${m['id'] ?? ''}',
      question: '${m['q'] ?? ''}',
      options: o.take(4).toList(),
      answer: (m['r'] is num ? (m['r'] as num).toInt() : 0).clamp(0, 3).toInt(),
      explanation: '${m['e'] ?? ''}',
      text: '${m['t'] ?? ''}',
      domain: '${m['d'] ?? domain}',
      level: '${m['n'] ?? level}',
    );
  }

  Map<String, dynamic> toMap() => {
        if (id.isNotEmpty) 'id': id,
        'q': question,
        'o': options,
        'r': answer,
        'e': explanation,
        if (text.isNotEmpty) 't': text,
        if (domain.isNotEmpty) 'd': domain,
        if (level.isNotEmpty) 'n': level,
      };

  /// Pour réutiliser l'écran de quiz (mode seul) et les QCM des profs.
  QuizQuestion toQuiz() => QuizQuestion(
        question: text.isEmpty ? question : '$text\n\n$question',
        options: options,
        answer: answer,
        explanation: explanation,
      );

  factory BankQuestion.fromQuiz(QuizQuestion q) =>
      BankQuestion(question: q.question, options: q.options, answer: q.answer, explanation: q.explanation);
}

/// La banque de questions : téléchargée depuis GitHub par domaine et niveau, gardée sur le téléphone.
class QuizBank {
  QuizBank._();
  static final instance = QuizBank._();

  static const _base = 'https://raw.githubusercontent.com/msanghare9-bit/jang/main/contenus/quiz';

  static const domains = ['vocabulaire', 'grammaire', 'expressions', 'comprehension', 'culture', 'synonymes', 'antonymes', 'francais_anglais'];
  static const mixed = 'melange';
  static const levels = ['debutant', 'intermediaire', 'avance'];

  static String domainLabel(String d) => switch (d) {
        'vocabulaire' => 'Vocabulaire',
        'grammaire' => 'Grammaire',
        'expressions' => 'Expressions',
        'comprehension' => 'Compréhension',
        'culture' => 'Culture générale',
        'synonymes' => 'Synonymes',
        'antonymes' => 'Antonymes',
        'francais_anglais' => 'Français → anglais',
        mixed => 'Mélange',
        _ => d,
      };

  static String domainEmoji(String d) => switch (d) {
        'vocabulaire' => '📚',
        'grammaire' => '🧩',
        'expressions' => '💬',
        'comprehension' => '📖',
        'culture' => '🌍',
        'synonymes' => '🔁',
        'antonymes' => '↔️',
        'francais_anglais' => '🇫🇷',
        _ => '🎲',
      };

  static String levelLabel(String l) => switch (l) {
        'debutant' => 'Débutant',
        'intermediaire' => 'Intermédiaire',
        'avance' => 'Avancé',
        _ => l,
      };

  final Map<String, List<BankQuestion>> _mem = {};

  /// Les questions d'un domaine et d'un niveau (liste vide si rien n'est disponible).
  Future<List<BankQuestion>> load(String domain, String level) async {
    final key = '${domain}_$level';
    final mem = _mem[key];
    if (mem != null) return mem;
    String? text;
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'quiz_cache_$key';
    final cachedAtKey = 'quiz_cache_at_$key';
    // Version locale récente (moins d'un jour) : pas besoin d'internet.
    try {
      final cachedAt = prefs.getInt(cachedAtKey) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - cachedAt < const Duration(hours: 24).inMilliseconds) {
        text = prefs.getString(cacheKey);
      }
    } catch (_) {}
    if (text == null) {
      try {
        final res = await http.get(Uri.parse('$_base/$key.json')).timeout(const Duration(seconds: 20));
        if (res.statusCode == 200) {
          text = res.body;
          jsonDecode(text);
          await prefs.setString(cacheKey, text);
          await prefs.setInt(cachedAtKey, DateTime.now().millisecondsSinceEpoch);
        }
      } catch (e) {
        debugPrint('Banque de questions en ligne indisponible : $e');
        text = null;
      }
    }
    // Sans internet : l'ancienne version du téléphone, même vieille.
    try {
      if (text == null) text = prefs.getString(cacheKey);
    } catch (_) {}
    if (text == null) return const [];
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      final list = [
        for (final q in (j['questions'] as List? ?? const []))
          if (q is Map) BankQuestion.fromMap(q, domain: domain, level: level),
      ];
      return _mem[key] = list;
    } catch (e) {
      debugPrint('Banque de questions illisible : $e');
      return const [];
    }
  }

  /// Tire [count] questions au hasard dans le domaine demandé ou dans tous les domaines.
  Future<List<BankQuestion>> draw(String domain, String level, int count) =>
      drawDomains(domain == mixed ? domains : [domain], level, count);

  /// Tire des questions en alternant les domaines choisis, pour garder une partie équilibrée.
  Future<List<BankQuestion>> drawDomains(List<String> selectedDomains, String level, int count) async {
    final selected = domains.where(selectedDomains.toSet().contains).toList();
    if (selected.isEmpty || count <= 0) return const [];
    final pools = await Future.wait([for (final d in selected) load(d, level)]);
    final byDomain = [for (final p in pools) (List.of(p)..shuffle(Random()))];
    final out = <BankQuestion>[];
    var i = 0;
    while (out.length < count && byDomain.any((items) => items.isNotEmpty)) {
      final pool = byDomain[i % byDomain.length];
      if (pool.isNotEmpty) out.add(pool.removeLast());
      i++;
    }
    return out..shuffle(Random());
  }

  /// Un élève ou un prof signale une question fausse ou mal écrite.
  Future<void> report(BankQuestion q, UserProfile p, {String note = ''}) =>
      FirebaseFirestore.instance.collection('signalements').add({
        'question': q.toMap(),
        'domaine': q.domain,
        'niveau': q.level,
        'note': note.trim(),
        'uid': p.uid,
        'name': p.publicName,
        'at': FieldValue.serverTimestamp(),
      });
}
