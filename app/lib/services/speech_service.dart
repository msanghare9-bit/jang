import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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

/// Reconnaissance vocale : l'élève répond en parlant (anglais).
class SpeechInput {
  SpeechInput._();
  static final instance = SpeechInput._();

  final _stt = stt.SpeechToText();
  bool? _available;

  Future<bool> available() async {
    if (_available != null) return _available!;
    try {
      _available = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  bool get listening => _stt.isListening;

  /// Écoute l'élève. [onText] reçoit le texte au fur et à mesure ; [onDone] à la fin.
  Future<bool> listen({required void Function(String text) onText, required void Function(String text) onDone}) async {
    if (!await available()) return false;
    var last = '';
    try {
      final locales = await _stt.locales();
      final ids = locales.map((l) => l.localeId).toList();
      final locale = ids.contains('en_GB') ? 'en_GB' : (ids.contains('en_US') ? 'en_US' : null);
      await _stt.listen(
        localeId: locale,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
        onResult: (r) {
          last = r.recognizedWords;
          onText(last);
          if (r.finalResult) onDone(last);
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
