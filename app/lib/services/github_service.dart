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

  static String get shareUrl => 'https://github.com/msanghare9-bit/jang';

  static String get apkUrl {
    return '$_download/jang.apk';
  }

  Future<List<ReleaseInfo>> releases() async {
    return [];
  }

  Future<List<ReleaseInfo>> getReleases() async {
    return [];
  }

  Future<ReleaseInfo?> getLatestRelease() async {
    return null;
  }

  Future<ReleaseInfo?> newerVersion([
    String? currentVersion,
    bool force = false,
  ]) async {
    return null;
  }

  // Permet de capturer les appels avec arguments nommés comme newerVersion(force: true)
  noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #newerVersion) {
      return Future<ReleaseInfo?>.value(null);
    }
    return super.noSuchMethod(invocation);
  }
}
