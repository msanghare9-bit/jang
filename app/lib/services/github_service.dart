import 'package:flutter/foundation.dart';

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

  static const String _download =
      'https://github.com/msanghare9-bit/jang/releases/latest/download';

  String get shareUrl => 'https://github.com/msanghare9-bit/jang';

  static String get apkUrl {
    return '$_download/jang.apk';
  }

  Future<List<ReleaseInfo>> getReleases() async {
    return [];
  }

  Future<ReleaseInfo?> getLatestRelease() async {
    return null;
  }
}
