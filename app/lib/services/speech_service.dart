import 'package:flutter_tts/flutter_tts.dart';

/// Lecture à voix haute (prononciation de l'anglais), avec la voix du téléphone.
class Speech {
  Speech._();
  static final instance = Speech._();

  final _tts = FlutterTts();
  bool _ready = false;

  /// Vrai pour une matière d'anglais.
  static bool isEnglish(String subjectName) {
    final n = subjectName.toLowerCase();
    return n.contains('angl') || n.contains('english');
  }

  Future<void> _init() async {
    if (_ready) return;
    var ok = await _tts.isLanguageAvailable('en-GB');
    await _tts.setLanguage(ok == true ? 'en-GB' : 'en-US');
    await _tts.setSpeechRate(0.42); // un peu plus lent que la normale
    await _tts.setPitch(1.0);
    _ready = true;
  }

  /// Lit [text] en anglais.
  Future<void> say(String text) async {
    final t = text.replaceAll(RegExp(r'[*_#>]'), '').trim();
    if (t.isEmpty) return;
    try {
      await _init();
      await _tts.stop();
      await _tts.speak(t);
    } catch (_) {}
  }
}
