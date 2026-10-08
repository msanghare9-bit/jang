import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'auth_service.dart';
import 'content_repo.dart';
import 'pack_service.dart';
import 'mission_service.dart';
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

  /// Mission après laquelle l'épisode s'ouvre (parcours en missions), ou vide.
  final String after;
  StoryEpisode(this.title, this.panels, this.words, {this.after = ''});
}

/// Une saison = l'histoire d'une matière pour un niveau.
class StorySeason {
  final String subject;
  final String level;
  final String title;
  final List<StoryEpisode> episodes;
  StorySeason(this.subject, this.level, this.title, this.episodes);

  String get key => '${subject}_$level'.toLowerCase().replaceAll(' ', '');

  /// Leçons (ou missions) terminées nécessaires pour ouvrir l'épisode [i] (0 = premier) :
  /// un épisode toutes les [per] leçons (3) ou missions (2), le dernier à la fin du niveau.
  int required(int i, int totalLessons, {int per = 3}) {
    if (i == episodes.length - 1) return totalLessons;
    final r = per * (i + 1);
    return r > totalLessons ? totalLessons : r;
  }

  int unlocked(int done, int totalLessons, {int per = 3}) {
    if (totalLessons == 0) return 0;
    var n = 0;
    for (var i = 0; i < episodes.length; i++) {
      if (done >= required(i, totalLessons, per: per)) n = i + 1;
    }
    return n;
  }
}

/// Avancement de l'élève dans une saison.
class StoryState {
  final StorySeason season;
  final int done;
  final int total;

  /// Leçons (3) ou missions (2) par épisode.
  final int per;

  /// Missions à terminer pour ouvrir chaque épisode, quand l'épisode dit après quelle mission il vient.
  final List<int>? needs;
  StoryState(this.season, this.done, this.total, {this.per = 3, this.needs});

  /// Leçons (ou missions) terminées nécessaires pour ouvrir l'épisode [i].
  int need(int i) => needs != null && i < needs!.length ? needs![i] : season.required(i, total, per: per);

  int get unlocked {
    if (total == 0) return 0;
    var n = 0;
    for (var i = 0; i < season.episodes.length; i++) {
      if (done >= need(i)) n = i + 1;
    }
    return n;
  }

  /// Leçons qu'il reste à terminer pour ouvrir le prochain épisode (0 si tout est ouvert).
  int get lessonsToNext {
    final u = unlocked;
    if (u >= season.episodes.length) return 0;
    return need(u) - done;
  }
}

/// Les histoires de Gaïndé, Awa, Modou, Doudou et Kocc Barma.
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
      final res = await http.get(Uri.parse(_url)).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        text = res.body;
        _parse(text);
        await prefs.setString('stories_cache', text);
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
            _s(e['titre']), panels, [for (final w in (e['mots'] as List? ?? const [])) '$w'],
            after: _s(e['apres'])));
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
    // Niveau de l'élève ; sinon un des niveaux de la matière (matière partagée, compte enseignant…).
    final profileExam = AuthService.instance.profile.value?.examId ?? '';
    final candidates = <String>[
      if (profileExam.isNotEmpty) profileExam,
      ...subject.examIds.where((e) => e != profileExam),
    ];
    final name = _norm(subject.name);
    final all = await seasons();
    StorySeason? season;
    var examId = profileExam;
    for (final id in candidates) {
      final exam = await ContentRepo.instance.exam(id);
      final level = LessonPack.levelOf(exam?.name ?? '');
      if (level.isEmpty) continue;
      for (final s in all) {
        final want = _norm(s.subject);
        final okSubject = name.contains(want) || (want.startsWith('angl') && name.contains('english'));
        if (okSubject && LessonPack.levelOf(s.level) == level && s.episodes.isNotEmpty) {
          season = s;
          examId = id;
          break;
        }
      }
      if (season != null) break;
    }
    if (season == null) return null;
    // Parcours en missions (collège) : un épisode toutes les 2 missions.
    final course = await MissionService.instance.courseFor(subject, examId);
    if (course != null) {
      final ids = [for (final m in course.missions) m.id];
      final needs = <int>[];
      for (var i = 0; i < season.episodes.length; i++) {
        final at = ids.indexOf(season.episodes[i].after);
        var n = at >= 0 ? at + 1 : season.required(i, ids.length, per: 2);
        if (needs.isNotEmpty && n < needs.last) n = needs.last;
        needs.add(n);
      }
      return StoryState(season, MissionService.instance.doneCount(course), ids.length, per: 2, needs: needs);
    }
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
