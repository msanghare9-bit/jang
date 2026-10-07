import 'package:flutter/foundation.dart';
import 'dart:ffi' if (dart.library.html) 'dart:html' show Abi; // Import conditionnel ou neutralisé

class GithubService {
  static const String _download = 'https://github.com/msanghare9-bit/jang/releases/latest/download';

  static String get apkUrl {
    if (kIsWeb) {
      return '$_download/jang.apk';
    }
    try {
      final abi = Abi.current();
      if (abi.toString().contains('arm64')) return '$_download/jang-64.apk';
      if (abi.toString().contains('arm')) return '$_download/jang-32.apk';
    } catch (_) {}
    return '$_download/jang.apk';
  }
}
