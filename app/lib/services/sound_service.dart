import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Petits sons de l'application, fabriqués par le code (aucun fichier à télécharger) :
/// le tama de Doudou pour une bonne note, un bruit d'eau quand la pirogue avance.
class SoundService {
  SoundService._();
  static final instance = SoundService._();

  static const _rate = 22050;
  final _players = <AudioPlayer>[];
  int _next = 0;
  Uint8List? _tama;
  Uint8List? _splash;

  AudioPlayer get _player {
    if (_players.length < 3) {
      final p = AudioPlayer();
      p.setReleaseMode(ReleaseMode.stop);
      _players.add(p);
      return p;
    }
    _next = (_next + 1) % _players.length;
    return _players[_next];
  }

  Future<void> _play(Uint8List bytes, {double volume = 1}) async {
    try {
      final p = _player;
      await p.stop();
      await p.setVolume(volume);
      await p.play(BytesSource(bytes));
    } catch (e) {
      debugPrint('Son indisponible : $e');
    }
  }

  /// Roulement de tama (bonne note).
  Future<void> tama() => _play(_tama ??= _makeTama());

  /// Bruit d'eau (la pirogue avance).
  Future<void> splash() => _play(_splash ??= _makeSplash(), volume: 0.6);

  // ---------------- Fabrication des sons ----------------

  static Uint8List _makeTama() {
    // [début (s), fréquence de départ, sommet, fin, durée, volume] : le tama « parle » en glissant.
    const hits = [
      [0.00, 180.0, 260.0, 170.0, 0.32, 0.8],
      [0.18, 150.0, 150.0, 120.0, 0.20, 0.5],
      [0.32, 200.0, 300.0, 190.0, 0.35, 0.8],
      [0.55, 160.0, 160.0, 130.0, 0.18, 0.5],
      [0.68, 210.0, 320.0, 150.0, 0.60, 0.9],
    ];
    final total = (1.35 * _rate).round();
    final buf = Float64List(total);
    final rnd = Random(7);
    for (final h in hits) {
      final start = (h[0] * _rate).round();
      final dur = h[4];
      final n = (dur * _rate).round();
      var phase = 0.0;
      for (var i = 0; i < n && start + i < total; i++) {
        final t = i / _rate;
        final x = t / dur;
        final f = x < .35
            ? h[1] * pow(h[2] / h[1], x / .35)
            : h[2] * pow(h[3] / h[2], (x - .35) / .65);
        phase += 2 * pi * f / _rate;
        final env = (t < .005 ? t / .005 : 1.0) * pow(0.001, x);
        var v = sin(phase) * env * h[5];
        if (t < .04) v += (rnd.nextDouble() * 2 - 1) * (1 - t / .04) * h[5] * .3;
        buf[start + i] += v;
      }
    }
    return _wav(buf, gain: 0.6);
  }

  static Uint8List _makeSplash() {
    final n = (0.35 * _rate).round();
    final buf = Float64List(n);
    final rnd = Random(3);
    var low = 0.0;
    for (var i = 0; i < n; i++) {
      final x = i / n;
      final noise = rnd.nextDouble() * 2 - 1;
      final k = 0.35 - 0.3 * x; // filtre de plus en plus sourd
      low += k * (noise - low);
      buf[i] = low * pow(1 - x, 2);
    }
    return _wav(buf, gain: 1.6);
  }

  static Uint8List _wav(Float64List s, {double gain = 1}) {
    final data = ByteData(44 + s.length * 2);
    void str(int o, String t) {
      for (var i = 0; i < t.length; i++) {
        data.setUint8(o + i, t.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + s.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, _rate, Endian.little);
    data.setUint32(28, _rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, s.length * 2, Endian.little);
    for (var i = 0; i < s.length; i++) {
      final v = (s[i] * gain).clamp(-1.0, 1.0);
      data.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
