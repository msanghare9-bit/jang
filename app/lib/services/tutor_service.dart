import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import 'auth_service.dart';

/// Tuteur IA : envoie la question au relais Cloudflare, qui interroge le modèle.
class TutorService {
  TutorService._();
  static final instance = TutorService._();

  /// Adresse du relais Cloudflare (Worker).
  static const endpoint = 'https://jang-tuteur.msanghare9.workers.dev/ask';
  static const perDay = 20;

  Future<TutorAnswer> ask(Lesson lesson, String question, {String? previousAnswer}) async {
    final token = await AuthService.instance.idToken();
    if (token == null) return TutorAnswer.error('Connecte-toi d\'abord.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(Uri.parse(endpoint));
      req.headers.contentType = ContentType.json;
      req.headers.set('Authorization', 'Bearer $token');
      final body = jsonEncode({
        'lessonId': lesson.id,
        'lessonTitle': lesson.title,
        'lessonText': _text(lesson.body),
        'question': question,
        if (previousAnswer != null) 'previousAnswer': previousAnswer,
        'simpler': previousAnswer != null,
      });
      req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 60));
      final text = await res.transform(utf8.decoder).join();
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        return TutorAnswer.error((j['error'] ?? 'Le tuteur ne répond pas pour le moment.') as String,
            remaining: (j['remaining'] as num?)?.toInt());
      }
      final answer = (j['answer'] ?? '') as String;
      final remaining = (j['remaining'] as num?)?.toInt();
      _log(lesson, question, answer, previousAnswer != null);
      return TutorAnswer(answer: answer, remaining: remaining);
    } on SocketException {
      return TutorAnswer.error('Pas de connexion internet. Le tuteur a besoin d\'internet.');
    } on TimeoutException {
      return TutorAnswer.error('Le tuteur met trop de temps à répondre. Réessaie dans un moment.');
    } catch (e) {
      debugPrint('Tuteur : $e');
      return TutorAnswer.error('Le tuteur ne répond pas pour le moment. Réessaie plus tard.');
    } finally {
      client.close();
    }
  }

  /// Copie de l'échange, consultable par le responsable.
  void _log(Lesson lesson, String question, String answer, bool simpler) {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    unawaited(FirebaseFirestore.instance.collection('tutorLogs').add({
      'uid': p.uid,
      'name': p.name,
      'lessonId': lesson.id,
      'lessonTitle': lesson.title,
      'question': question.length > 1000 ? question.substring(0, 1000) : question,
      'answer': answer.length > 4000 ? answer.substring(0, 4000) : answer,
      'simpler': simpler,
      'createdAt': FieldValue.serverTimestamp(),
    }).then((_) {}, onError: (e) => debugPrint('$e')));
  }
}

class TutorAnswer {
  final String? answer;
  final String? error;
  final int? remaining;
  TutorAnswer({this.answer, this.remaining}) : error = null;
  TutorAnswer.error(this.error, {this.remaining}) : answer = null;
}

/// Texte de la leçon pour Jàngalekat : les photos deviennent « (Photo : légende) ».
String _text(String body) {
  final t = body.replaceAllMapped(RegExp(r'\[photo [A-Za-z0-9_-]+\]\s*(.*)'),
      (m) => (m.group(1) ?? '').trim().isEmpty ? '(Photo)' : '(Photo : ${m.group(1)!.trim()})');
  return t.length > 6000 ? t.substring(0, 6000) : t;
}
