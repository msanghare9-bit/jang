import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../version.dart';

/// Informations publiques du dépôt GitHub (versions publiées, téléchargements).
class GithubService {
  GithubService._();
  static final instance = GithubService._();

  static const repo = 'msanghare9-bit/jang';
  static const apkUrl = 'https://github.com/$repo/releases/latest/download/jang.apk';

  Future<dynamic> _get(String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$repo$path'));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'jang-app');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw HttpException('GitHub ${res.statusCode}');
      return jsonDecode(body);
    } finally {
      client.close();
    }
  }

  /// Numéro de construction extrait d'une étiquette « v1.0.0-12 ».
  static int buildOf(String tag) {
    final m = RegExp(r'-(\d+)$').firstMatch(tag);
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  /// Renvoie la version la plus récente si elle est plus récente que celle installée.
  /// Vérifie au plus une fois toutes les 12 heures, sauf si [force].
  Future<ReleaseInfo?> newerVersion({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('update_check_at') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - last < const Duration(hours: 12).inMilliseconds) {
      final saved = prefs.getInt('update_latest_build') ?? 0;
      final name = prefs.getString('update_latest_name') ?? '';
      return saved > appBuild ? ReleaseInfo(name: name, build: saved, downloads: 0) : null;
    }
    try {
      final j = await _get('/releases/latest') as Map<String, dynamic>;
      final build = buildOf((j['tag_name'] ?? '') as String);
      final name = (j['name'] ?? '') as String;
      await prefs.setInt('update_check_at', now);
      await prefs.setInt('update_latest_build', build);
      await prefs.setString('update_latest_name', name);
      return build > appBuild ? ReleaseInfo(name: name, build: build, downloads: 0) : null;
    } catch (_) {
      return null;
    }
  }

  /// Toutes les versions publiées avec leur nombre de téléchargements.
  Future<List<ReleaseInfo>> releases() async {
    final list = await _get('/releases?per_page=100') as List;
    return list.whereType<Map>().map((r) {
      final assets = (r['assets'] as List?) ?? const [];
      final downloads = assets.whereType<Map>().fold<int>(
          0, (a, x) => a + ((x['download_count'] as num?)?.toInt() ?? 0));
      return ReleaseInfo(
        name: (r['name'] ?? r['tag_name'] ?? '') as String,
        build: buildOf((r['tag_name'] ?? '') as String),
        downloads: downloads,
        publishedAt: DateTime.tryParse((r['published_at'] ?? '') as String),
      );
    }).toList();
  }
}

class ReleaseInfo {
  final String name;
  final int build;
  final int downloads;
  final DateTime? publishedAt;
  ReleaseInfo({required this.name, required this.build, required this.downloads, this.publishedAt});
}
