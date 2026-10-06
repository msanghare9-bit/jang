import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// Une question de la banque des matchs (contenus/quiz/DOMAINE_NIVEAU.json).
class BankQuestion {
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

  static const domains = ['vocabulaire', 'grammaire', 'expressions', 'comprehension', 'culture'];
  static const mixed = 'melange';
  static const levels = ['debutant', 'intermediaire', 'avance'];

  static String domainLabel(String d) => switch (d) {
        'vocabulaire' => 'Vocabulaire',
        'grammaire' => 'Grammaire',
        'expressions' => 'Expressions',
        'comprehension' => 'Compréhension',
        'culture' => 'Culture générale',
        mixed => 'Mélange',
        _ => d,
      };

  static String domainEmoji(String d) => switch (d) {
        'vocabulaire' => '📚',
        'grammaire' => '🧩',
        'expressions' => '💬',
        'comprehension' => '📖',
        'culture' => '🌍',
        _ => '🎲',
      };

  static String levelLabel(String l) => switch (l) {
        'debutant' => 'Débutant',
        'intermediaire' => 'Intermédiaire',
        'avance' => 'Avancé',
        _ => l,
      };

  final Map<String, List<BankQuestion>> _mem = {};

  Future<File> _file(String key) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/quiz_$key.json');
  }

  /// Les questions d'un domaine et d'un niveau (liste vide si rien n'est disponible).
  Future<List<BankQuestion>> load(String domain, String level) async {
    final key = '${domain}_$level';
    final mem = _mem[key];
    if (mem != null) return mem;
    String? text;
    File? f;
    try {
      f = await _file(key);
    } catch (_) {}
    // Version locale récente (moins d'un jour) : pas besoin d'internet.
    try {
      if (f != null && await f.exists() && DateTime.now().difference(await f.lastModified()).inHours < 24) {
        text = await f.readAsString();
      }
    } catch (_) {}
    if (text == null) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
        try {
          final req = await client.getUrl(Uri.parse('$_base/$key.json'));
          final res = await req.close().timeout(const Duration(seconds: 20));
          if (res.statusCode == 200) {
            text = await res.transform(utf8.decoder).join();
            jsonDecode(text);
            await f?.writeAsString(text);
          }
        } finally {
          client.close();
        }
      } catch (e) {
        debugPrint('Banque de questions en ligne indisponible : $e');
        text = null;
      }
    }
    // Sans internet : l'ancienne version du téléphone, même vieille.
    try {
      if (text == null && f != null && await f.exists()) text = await f.readAsString();
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

  /// Tire [count] questions au hasard (domaine « melange » : tous les domaines du niveau).
  Future<List<BankQuestion>> draw(String domain, String level, int count) async {
    final pools = domain == mixed
        ? await Future.wait([for (final d in domains) load(d, level)])
        : [await load(domain, level)];
    final all = [for (final p in pools) ...p];
    all.shuffle(Random());
    if (domain != mixed) return all.take(count).toList();
    // Mélange : on alterne les domaines pour qu'il y ait de tout.
    final byDomain = [for (final p in pools) (List.of(p)..shuffle(Random()))];
    final out = <BankQuestion>[];
    var i = 0;
    while (out.length < count && byDomain.any((l) => l.isNotEmpty)) {
      final l = byDomain[i % byDomain.length];
      if (l.isNotEmpty) out.add(l.removeLast());
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
