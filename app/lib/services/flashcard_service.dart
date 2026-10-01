import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'auth_service.dart';
import 'engagement_service.dart';
import 'stats_service.dart';

/// Répétition espacée (boîtes de Leitner), gardée sur le téléphone.
/// Boîte 1 : à revoir aujourd'hui ; boîte 5 : bien connue (revue dans 14 jours).
class FlashcardService {
  FlashcardService._();
  static final instance = FlashcardService._();

  static const _intervals = [0, 0, 1, 3, 7, 14]; // index = boîte

  String get _key => 'flash_${AuthService.instance.profile.value?.uid ?? ''}';

  static String cardKey(String chapterId, Flashcard c) =>
      '$chapterId:${StatsService.questionKey(c.front)}';

  Future<Map<String, List<dynamic>>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v as List<dynamic>));
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, List<dynamic>> m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(m));
  }

  /// Cartes à réviser maintenant (nouvelles ou arrivées à échéance), au plus [max].
  Future<List<Flashcard>> dueCards(FlashcardDeck deck, {int max = 20}) async {
    final state = await _load();
    final today = StatsService.dayKey();
    final due = deck.cards.where((c) {
      final s = state[cardKey(deck.chapterId, c)];
      return s == null || (s[1] as String).compareTo(today) <= 0;
    }).toList()
      ..shuffle();
    return due.take(max).toList();
  }

  Future<(int known, int total)> mastery(FlashcardDeck deck) async {
    final state = await _load();
    final known = deck.cards
        .where((c) => ((state[cardKey(deck.chapterId, c)]?[0] as num?)?.toInt() ?? 0) >= 4)
        .length;
    return (known, deck.cards.length);
  }

  /// Vrai si l'élève a déjà révisé au moins une carte du paquet.
  Future<bool> started(FlashcardDeck deck) async {
    final state = await _load();
    return deck.cards.any((c) => state.containsKey(cardKey(deck.chapterId, c)));
  }

  Future<void> answer(FlashcardDeck deck, Flashcard c, bool knew) async {
    final state = await _load();
    final k = cardKey(deck.chapterId, c);
    final box = (state[k]?[0] as num?)?.toInt() ?? 0;
    final int next = knew ? (box < 1 ? 2 : (box + 1).clamp(1, 5).toInt()) : 1;
    final due = StatsService.dayKey(DateTime.now().add(Duration(days: _intervals[next])));
    state[k] = [next, due];
    await _save(state);
    await EngagementService.instance.addTo('flashcards');
  }
}
