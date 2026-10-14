import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mode économe en données : si activé, les images (photos des leçons et des
/// questions) ne se chargent pas automatiquement. L'élève appuie sur
/// « Afficher l'image » pour la télécharger quand il le souhaite.
class DataSaverService {
  DataSaverService._();
  static final instance = DataSaverService._();

  final enabled = ValueNotifier<bool>(false);
  Future<bool>? _loading;
  bool _ready = false;

  Future<bool> isEnabled() async {
    if (_ready) return enabled.value;
    _loading ??= _load();
    return _loading!;
  }

  Future<bool> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool('data_saver') ?? false;
    } catch (_) {}
    _ready = true;
    return enabled.value;
  }

  Future<void> set(bool value) async {
    enabled.value = value;
    _ready = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('data_saver', value);
    } catch (_) {}
  }
}
