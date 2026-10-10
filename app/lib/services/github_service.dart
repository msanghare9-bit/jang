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

class UpdateCheckException implements Exception {
  final String message;
  const UpdateCheckException(this.message);

  @override
  String toString() => message;
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
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const UpdateCheckException(
          'GitHub limite temporairement les vérifications. Réessayez dans quelques minutes.',
        );
      }
      if (response.statusCode == 404) {
        throw const UpdateCheckException(
          'Aucune version publiée n’a été trouvée sur GitHub.',
        );
      }
      throw UpdateCheckException(
        'GitHub n’a pas pu vérifier la mise à jour (code ${response.statusCode}).',
      );
    }
    return jsonDecode(response.body);
  }

  static int _buildOf(String tag) {
    final match = RegExp(r'-(\d+)$').firstMatch(tag);
    return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
  }

  /// GitHub's unauthenticated REST API is quickly rate-limited for app users.
  /// The public latest-release URL redirects to its tag without using that API.
  Future<String> _latestTag() async {
    final client = http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('https://github.com/$_repo/releases/latest'),
      )
        ..followRedirects = false
        ..headers.addAll(const {
          'Accept': 'text/html',
          'User-Agent': 'jang-app',
        });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final location = response.headers['location'];
      if (response.statusCode < 300 || response.statusCode >= 400 || location == null) {
        throw const UpdateCheckException(
          'GitHub n’a pas retourné la version publiée.',
        );
      }

      final path = Uri.parse(location).pathSegments;
      if (path.length < 5 ||
          path[0] != 'msanghare9-bit' ||
          path[1] != 'jang' ||
          path[2] != 'releases' ||
          path[3] != 'tag') {
        throw const UpdateCheckException(
          'Le lien de la dernière version GitHub est invalide.',
        );
      }
      return path[4];
    } finally {
      client.close();
    }
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
      final tag = await _latestTag();
      final latestBuild = _buildOf(tag);

      if (latestBuild == 0) {
        throw const UpdateCheckException(
          'Le numéro de la dernière version GitHub est invalide.',
        );
      }

      await prefs.setInt('update_check_at', now);
      await prefs.setInt('update_latest_build', latestBuild);
      await prefs.setString(
        'update_latest_name',
        'Jàng $appVersion ($latestBuild)',
      );

      if (latestBuild <= appBuild) return null;
      return ReleaseInfo(
        name: 'Jàng $appVersion ($latestBuild)',
        downloads: 0,
        publishedAt: '',
      );
    } on UpdateCheckException {
      rethrow;
    } catch (_) {
      throw UpdateCheckException(
        'Impossible de vérifier les mises à jour auprès de GitHub. '
        'Vérifiez la connexion Internet puis réessayez.',
      );
    }
  }
}
