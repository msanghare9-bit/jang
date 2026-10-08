import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../version.dart';

class ReleaseInfo {
  final String name;
  final int downloads;
  final String publishedAt;

  ReleaseInfo({
    required this.name,
    required this.downloads,
    required this.publishedAt,
  });
}

class GithubService {
  static final GithubService instance = GithubService._internal();

  GithubService._internal();

  static const String _repo = 'msanghare9-bit/jang';
  static const String _download =
      'https://github.com/$_repo/releases/latest/download';

  static String get shareUrl => 'https://github.com/$_repo';

  static String get apkUrl => '$_download/jang.apk';

  Future<dynamic> _get(String path) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$_repo$path'),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'jang-app',
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('GitHub ${response.statusCode}');
    }
    return jsonDecode(response.body);
  }

  static int _buildOf(String tag) {
    final match = RegExp(r'-(\d+)$').firstMatch(tag);
    return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
  }

  Future<ReleaseInfo?> _releaseFrom(dynamic value) async {
    if (value is! Map) return null;
    final assets = value['assets'] is List ? value['assets'] as List : const [];
    final downloads = assets.whereType<Map>().fold<int>(
      0,
      (total, asset) =>
          total + ((asset['download_count'] as num?)?.toInt() ?? 0),
    );
    return ReleaseInfo(
      name: (value['name'] ?? value['tag_name'] ?? '') as String,
      downloads: downloads,
      publishedAt: (value['published_at'] ?? '') as String,
    );
  }

  Future<List<ReleaseInfo>> releases() async {
    try {
      final result = await _get('/releases?per_page=100');
      if (result is! List) return [];
      final releases = <ReleaseInfo>[];
      for (final value in result) {
        final release = await _releaseFrom(value);
        if (release != null) releases.add(release);
      }
      return releases;
    } catch (_) {
      return [];
    }
  }

  Future<List<ReleaseInfo>> getReleases() => releases();

  Future<ReleaseInfo?> getLatestRelease() async {
    try {
      return await _releaseFrom(await _get('/releases/latest'));
    } catch (_) {
      return null;
    }
  }

  Future<ReleaseInfo?> newerVersion({
    String? currentVersion,
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastCheck = prefs.getInt('update_check_at') ?? 0;

    if (!force &&
        now - lastCheck < const Duration(hours: 12).inMilliseconds) {
      final savedBuild = prefs.getInt('update_latest_build') ?? 0;
      if (savedBuild <= appBuild) return null;
      return ReleaseInfo(
        name: prefs.getString('update_latest_name') ?? 'Nouvelle version',
        downloads: 0,
        publishedAt: '',
      );
    }

    try {
      final release = await _get('/releases/latest') as Map<String, dynamic>;
      final tag = (release['tag_name'] ?? '') as String;
      final latestBuild = _buildOf(tag);

      await prefs.setInt('update_check_at', now);
      await prefs.setInt('update_latest_build', latestBuild);
      await prefs.setString(
        'update_latest_name',
        (release['name'] ?? tag) as String,
      );

      if (latestBuild <= appBuild) return null;
      return _releaseFrom(release);
    } catch (_) {
      return null;
    }
  }
}
