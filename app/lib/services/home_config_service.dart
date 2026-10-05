import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Une petite phrase d'un personnage sur l'accueil.
class HomeTip {
  final String id;
  final String text;
  HomeTip(this.id, this.text);
  Map<String, dynamic> toMap() => {'id': id, 'text': text};
}

/// Bannière du moment (avec dates).
class HomeBanner {
  final String text;
  final DateTime? from;
  final DateTime? to;
  HomeBanner(this.text, this.from, this.to);

  bool get active {
    if (text.trim().isEmpty) return false;
    final now = DateTime.now();
    if (from != null && now.isBefore(from!)) return false;
    if (to != null && now.isAfter(to!.add(const Duration(days: 1)))) return false;
    return true;
  }
}

/// Ce que l'admin a choisi pour l'accueil (pour tous les élèves, ou pour un niveau).
class HomeConfig {
  final List<String> welcome;
  final List<HomeTip> tips;
  final HomeBanner? banner;
  final Map<String, bool> blocks;
  HomeConfig({this.welcome = const [], this.tips = const [], this.banner, this.blocks = const {}});

  static const blockNames = {
    'mouton': 'Mon mouton',
    'revisions': 'Révisions du jour',
    'objectif': 'Objectif de la semaine',
    'banniere': 'Bannière',
  };

  bool show(String block) => blocks[block] ?? true;

  factory HomeConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return HomeConfig();
    DateTime? date(dynamic v) => v is Timestamp ? v.toDate() : null;
    final b = m['banner'];
    return HomeConfig(
      welcome: (m['welcome'] is List ? m['welcome'] as List : const [])
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList(),
      tips: [
        for (final t in (m['tips'] is List ? m['tips'] as List : const []).whereType<Map>())
          if ('${t['text'] ?? ''}'.trim().isNotEmpty) HomeTip('${t['id'] ?? 'gainde'}', '${t['text']}'),
      ],
      banner: b is Map ? HomeBanner('${b['text'] ?? ''}', date(b['from']), date(b['to'])) : null,
      blocks: {
        if (m['blocks'] is Map)
          for (final e in (m['blocks'] as Map).entries)
            if (e.value is bool) '${e.key}': e.value as bool,
      },
    );
  }

  Map<String, dynamic> toMap() => {
        'welcome': welcome,
        'tips': tips.map((t) => t.toMap()).toList(),
        'banner': {
          'text': banner?.text ?? '',
          'from': banner?.from == null ? null : Timestamp.fromDate(banner!.from!),
          'to': banner?.to == null ? null : Timestamp.fromDate(banner!.to!),
        },
        'blocks': blocks,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Le niveau remplace ce qui est réglé pour tous, élément par élément.
  HomeConfig over(HomeConfig base) => HomeConfig(
        welcome: welcome.isNotEmpty ? welcome : base.welcome,
        tips: tips.isNotEmpty ? tips : base.tips,
        banner: (banner?.text.trim().isNotEmpty ?? false) ? banner : base.banner,
        blocks: {...base.blocks, ...blocks},
      );
}

/// Accueil modifiable depuis l'admin, sans nouvelle version de l'app.
/// Documents : config/accueil (tous les élèves) et config/accueil_{niveau}.
class HomeConfigService {
  HomeConfigService._();
  static final instance = HomeConfigService._();

  final _db = FirebaseFirestore.instance;
  static final _rand = Random();

  static String docId(String examId) => examId.isEmpty ? 'accueil' : 'accueil_$examId';

  Future<HomeConfig> raw(String examId) async {
    final ref = _db.collection('config').doc(docId(examId));
    try {
      final d = await ref.get().timeout(const Duration(seconds: 8));
      return HomeConfig.fromMap(d.data());
    } catch (_) {
      try {
        final d = await ref.get(const GetOptions(source: Source.cache));
        return HomeConfig.fromMap(d.data());
      } catch (_) {
        return HomeConfig();
      }
    }
  }

  /// Réglage final pour un élève de ce niveau.
  Future<HomeConfig> forExam(String examId) async {
    final base = await raw('');
    if (examId.isEmpty) return base;
    return (await raw(examId)).over(base);
  }

  Future<void> save(String examId, HomeConfig c) async {
    try {
      await _db.collection('config').doc(docId(examId)).set(c.toMap());
    } catch (e) {
      debugPrint('Accueil non enregistré : $e');
      rethrow;
    }
  }

  /// Remplace {prénom} et {jours} dans un message.
  static String fill(String text, String firstName, int streak) => text
      .replaceAll('{prénom}', firstName)
      .replaceAll('{prenom}', firstName)
      .replaceAll('{jours}', '$streak');

  static T pick<T>(List<T> list) => list[_rand.nextInt(list.length)];
}
