import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'auth_service.dart';
import 'content_repo.dart';
import 'pack_service.dart';
import 'progress_repo.dart';

/// Un personnage placé dans une case de bande dessinée.
class StoryActor {
  final String id;
  final double x;
  final double size;
  final String moves;
  final bool flip;
  StoryActor(this.id, this.x, this.size, this.moves, this.flip);
}

/// Une bulle de dialogue (anglais + traduction).
class StoryBubble {
  final String en;
  final String fr;
  final double x;
  final double y;
  StoryBubble(this.en, this.fr, this.x, this.y);
}

class StoryPanel {
  final String background;
  final List<StoryActor> actors;
  final List<StoryBubble> bubbles;
  StoryPanel(this.background, this.actors, this.bubbles);
}

class StoryEpisode {
  final String title;
  final List<StoryPanel> panels;
  final List<String> words;
  StoryEpisode(this.title, this.panels, this.words);
}

/// Une saison = l'histoire d'une matière pour un niveau.
class StorySeason {
  final String subject;
  final String level;
  final String title;
  final List<StoryEpisode> episodes;
  StorySeason(this.subject, this.level, this.title, this.episodes);

  String get key => '${subject}_$level'.toLowerCase().replaceAll(' ', '');

  /// Leçons terminées nécessaires pour ouvrir l'épisode [i] (0 = premier) :
  /// un épisode toutes les 3 leçons, le dernier à la fin du niveau.
  int required(int i, int totalLessons) {
    if (i == episodes.length - 1) return totalLessons;
    final r = 3 * (i + 1);
    return r > totalLessons ? totalLessons : r;
  }

  int unlocked(int done, int totalLessons) {
    if (totalLessons == 0) return 0;
    var n = 0;
    for (var i = 0; i < episodes.length; i++) {
      if (done >= required(i, totalLessons)) n = i + 1;
    }
    return n;
  }
}

/// Avancement de l'élève dans une saison.
class StoryState {
  final StorySeason season;
  final int done;
  final int total;
  StoryState(this.season, this.done, this.total);
  int get unlocked => season.unlocked(done, total);

  /// Leçons qu'il reste à terminer pour ouvrir le prochain épisode (0 si tout est ouvert).
  int get lessonsToNext {
    final u = unlocked;
    if (u >= season.episodes.length) return 0;
    return season.required(u, total) - done;
  }
}

/// Les histoires de Gaïndé, Awa, Modou, Doudou et Jàngalekat.
/// Le fichier est dans l'application et peut être mis à jour depuis GitHub.
class StoryService {
  StoryService._();
  static final instance = StoryService._();

  static const _url = 'https://raw.githubusercontent.com/msanghare9-bit/jang/main/contenus/histoires.json';
  List<StorySeason>? _seasons;
  Future<List<StorySeason>>? _loading;

  Future<List<StorySeason>> seasons() => _loading ??= _load();

  Future<List<StorySeason>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    String? text;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final req = await client.getUrl(Uri.parse(_url));
        final res = await req.close().timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          text = await res.transform(utf8.decoder).join();
          _parse(text);
          await prefs.setString('stories_cache', text);
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Histoires en ligne indisponibles : $e');
      text = null;
    }
    text ??= prefs.getString('stories_cache');
    try {
      if (text != null) return _seasons = _parse(text);
    } catch (_) {}
    try {
      return _seasons = _parse(await rootBundle.loadString('assets/histoires.json'));
    } catch (e) {
      debugPrint('Histoires indisponibles : $e');
      return _seasons = const [];
    }
  }

  static double _d(dynamic v, double def) => v is num ? v.toDouble() : def;
  static String _s(dynamic v) => v is String ? v : '';

  List<StorySeason> _parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final out = <StorySeason>[];
    for (final s in (j['saisons'] as List? ?? const []).whereType<Map>()) {
      final eps = <StoryEpisode>[];
      for (final e in (s['episodes'] as List? ?? const []).whereType<Map>()) {
        final panels = <StoryPanel>[];
        for (final c in (e['cases'] as List? ?? const []).whereType<Map>()) {
          panels.add(StoryPanel(
            _s(c['fond']),
            [
              for (final a in (c['persos'] as List? ?? const []).whereType<Map>())
                StoryActor(_s(a['id']), _d(a['x'], 0.1), _d(a['taille'], 90), _s(a['anim']), a['retourne'] == true),
            ],
            [
              for (final b in (c['bulles'] as List? ?? const []).whereType<Map>())
                StoryBubble(_s(b['en']), _s(b['fr']), _d(b['x'], 0.05), _d(b['y'], 0.05)),
            ],
          ));
        }
        eps.add(StoryEpisode(
            _s(e['titre']), panels, [for (final w in (e['mots'] as List? ?? const [])) '$w']));
      }
      out.add(StorySeason(_s(s['matiere']), _s(s['niveau']), _s(s['titre']), eps));
    }
    return out;
  }

  static String _norm(String t) => t
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâ]'), 'a')
      .replaceAll(RegExp(r'\s+'), '');

  /// Saison de cette matière pour le niveau de l'élève.
  Future<StoryState?> stateFor(Subject subject, {List<Lesson>? lessons}) async {
    final examId = AuthService.instance.profile.value?.examId ?? '';
    final exam = examId.isEmpty ? null : await ContentRepo.instance.exam(examId);
    final level = LessonPack.levelOf(exam?.name ?? '');
    if (level.isEmpty) return null;
    final name = _norm(subject.name);
    StorySeason? season;
    for (final s in await seasons()) {
      final want = _norm(s.subject);
      final okSubject = name.contains(want) || (want.startsWith('angl') && name.contains('english'));
      if (okSubject && LessonPack.levelOf(s.level) == level && s.episodes.isNotEmpty) {
        season = s;
        break;
      }
    }
    if (season == null) return null;
    final list = lessons ??
        await ContentRepo.instance.lessonsOfSubject(subject.id, examId: examId.isEmpty ? null : examId);
    final withQuiz = list.where((l) => l.quiz.isNotEmpty).toList();
    final done = withQuiz.where((l) => ProgressRepo.instance.of(l.id)?.quizDone == true).length;
    return StoryState(season, done, withQuiz.length);
  }

  /// Épisodes déjà ouverts par l'élève (pour la pastille « Nouveau »).
  Future<int> opened(StorySeason s) async =>
      (await SharedPreferences.getInstance()).getInt('story_opened_${s.key}') ?? 0;

  Future<void> markOpened(StorySeason s, int episodeIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getInt('story_opened_${s.key}') ?? 0;
    if (episodeIndex + 1 > old) await prefs.setInt('story_opened_${s.key}', episodeIndex + 1);
  }

  /// Après des exercices : titre du nouvel épisode débloqué, ou null.
  Future<String?> newlyUnlocked(Subject subject) async {
    try {
      final st = await stateFor(subject);
      if (st == null) return null;
      final prefs = await SharedPreferences.getInstance();
      final k = 'story_announced_${st.season.key}';
      final before = prefs.getInt(k) ?? 0;
      final now = st.unlocked;
      if (now <= before) return null;
      await prefs.setInt(k, now);
      return st.season.episodes[now - 1].title;
    } catch (e) {
      debugPrint('$e');
      return null;
    }
  }
}
