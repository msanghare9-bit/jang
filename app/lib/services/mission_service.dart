import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'content_repo.dart';
import 'pack_service.dart';

String _s(dynamic v) => v is String ? v : '';
int _i(dynamic v, [int d = 0]) => v is num ? v.toInt() : d;
List<String> _ls(dynamic v) => (v is List ? v : const []).map((e) => '$e').toList();
List<Map> _lm(dynamic v) => (v is List ? v : const []).whereType<Map>().toList();

/// Temps 0 : un mot proposé avec la photo (juste ou intrus) et son explication.
class MissionWord {
  final String word;
  final bool ok;
  final String why;
  MissionWord(this.word, this.ok, this.why);
}

/// Une réplique de la scène observée.
class MissionLine {
  final String who;
  final String en;
  final String fr;
  MissionLine(this.who, this.en, this.fr);
}

/// Temps 2 : une question de compréhension.
class MissionQuestion {
  final String question;
  final List<String> options;
  final int answer;
  final int replay;
  MissionQuestion(this.question, this.options, this.answer, this.replay);
}

/// Une aide de Kocc Barma (palier). [replay] ≥ 0 : rejouer cette réplique.
class MissionHint {
  final String text;
  final int replay;
  MissionHint(this.text, this.replay);
}

/// Temps 3 : une marche pour aider Gaïndé (choix, ordre, trou, libre).
class MissionStep {
  final String type;
  final String gainde;
  final List<String> options;
  final int answer;
  final List<String> tiles;
  final String target;
  final String before;
  final String after;
  final List<String> accept;
  final List<String> keys;
  final String said;
  final List<MissionHint> hints;
  MissionStep({
    required this.type,
    required this.gainde,
    this.options = const [],
    this.answer = 0,
    this.tiles = const [],
    this.target = '',
    this.before = '',
    this.after = '',
    this.accept = const [],
    this.keys = const [],
    this.said = '',
    this.hints = const [],
  });
}

/// Temps 4 : un tour de parole « pour de vrai ».
class MissionTurn {
  final String who;
  final String en;
  final String fr;
  final List<String> keys;
  final String model;
  final String answer;
  MissionTurn(this.who, this.en, this.fr, this.keys, this.model, this.answer);
}

class Mission {
  final String id;
  final String title;
  final String story;
  final String canDo;
  final List<String> expressions;
  final String wordsIntro;
  final String scene;
  final List<String> objects;
  final List<String> sceneActors;
  final List<MissionWord> words;
  final List<MissionLine> lines;
  final String gaindeReaction;
  final List<MissionQuestion> questions;
  final List<MissionStep> steps;
  final List<MissionTurn> turns;
  final List<String> notebook;
  final List<String> hard;

  /// Les données d'origine (format de contenus/missions.json), pour l'éditeur.
  final Map<String, dynamic> raw;
  Mission({
    required this.id,
    required this.title,
    required this.story,
    required this.canDo,
    required this.expressions,
    required this.wordsIntro,
    required this.scene,
    required this.objects,
    required this.sceneActors,
    required this.words,
    required this.lines,
    required this.gaindeReaction,
    required this.questions,
    required this.steps,
    required this.turns,
    required this.notebook,
    required this.hard,
    this.raw = const {},
  });

  factory Mission.fromMap(Map m) {
    final mots = m['mots'] is Map ? m['mots'] as Map : const {};
    final scene = m['scene'] is Map ? m['scene'] as Map : const {};
    List<MissionHint> hints(dynamic v) => [
          for (final h in (v is List ? v : const []))
            if (h is Map) MissionHint(_s(h['texte']), _i(h['rejouer'], -1)) else MissionHint('$h', -1),
        ];
    return Mission(
      id: _s(m['id']),
      title: _s(m['titre']),
      story: _s(m['histoire']),
      canDo: _s(m['jesais']),
      expressions: _ls(m['expressions']),
      wordsIntro: _s(mots['consigne']),
      scene: _s(mots['fond']).isEmpty ? _s(scene['fond']) : _s(mots['fond']),
      objects: _ls(mots['objets']),
      sceneActors: _ls(scene['persos']),
      words: [for (final w in _lm(mots['liste'])) MissionWord(_s(w['mot']), w['ok'] == true, _s(w['pourquoi']))],
      lines: [for (final l in _lm(scene['repliques'])) MissionLine(_s(l['qui']), _s(l['en']), _s(l['fr']))],
      gaindeReaction: _s(scene['gainde']),
      questions: [
        for (final q in _lm(m['questions']))
          MissionQuestion(_s(q['question']), _ls(q['options']), _i(q['reponse']), _i(q['rejouer'], -1)),
      ],
      steps: [
        for (final st in _lm(m['marches']))
          MissionStep(
            type: _s(st['type']),
            gainde: _s(st['gainde']),
            options: _ls(st['options']),
            answer: _i(st['reponse']),
            tiles: _ls(st['tuiles']),
            target: _s(st['cible']),
            before: _s(st['avant']),
            after: _s(st['apres']),
            accept: _ls(st['accepte']),
            keys: _ls(st['cles']),
            said: _s(st['dit']),
            hints: hints(st['aides']),
          ),
      ],
      turns: [
        for (final t in _lm(m['pourdevrai']))
          MissionTurn(_s(t['qui']), _s(t['en']), _s(t['fr']), _ls(t['cles']), _s(t['modele']), _s(t['reponse'])),
      ],
      notebook: _ls(m['carnet']),
      hard: _ls(m['difficile']),
      raw: Map<String, dynamic>.from(m),
    );
  }
}

/// Une unité : ses missions, sa fiche de révision, ses exercices, sa production.
class CourseUnit {
  final String id;
  final String title;
  final String production;
  final List<Mission> missions;
  final List<(String, String)> sheet;
  final List<(String, String, String)> words;
  final List<String> traps;
  final List<QuizQuestion> exercises;
  CourseUnit(this.id, this.title, this.production, this.missions, this.sheet, this.words, this.traps, this.exercises);

  factory CourseUnit.fromMap(Map m) {
    final r = m['revision'] is Map ? m['revision'] as Map : const {};
    return CourseUnit(
      _s(m['id']),
      _s(m['titre']),
      _s(m['production']),
      [for (final x in _lm(m['missions'])) Mission.fromMap(x)],
      [for (final l in _lm(r['lignes'])) (_s(l['fonction']), _s(l['en']))],
      [for (final w in _lm(r['mots'])) (_s(w['en']), _s(w['fr']), _s(w['wo']))],
      _ls(r['pieges']),
      [
        for (final q in _lm(m['exercices']))
          QuizQuestion(
            question: _s(q['question']),
            options: [for (var i = 0; i < 4; i++) i < _ls(q['options']).length ? _ls(q['options'])[i] : ''],
            answer: _i(q['reponse']).clamp(0, 3).toInt(),
            explanation: _s(q['explication']),
          ),
      ],
    );
  }

  /// Leçon fabriquée pour réutiliser l'écran d'exercices (la pirogue).
  Lesson exerciseLesson(Subject subject) => Lesson(
        id: 'unite_$id',
        examId: subject.examId,
        subjectId: subject.id,
        chapterId: '',
        title: 'Exercices · $title',
        quiz: exercises,
      );

  /// Cartes de révision : les mots et phrases de l'unité.
  FlashcardDeck deck(Subject subject) => FlashcardDeck(
        chapterId: 'unite_$id',
        subjectId: subject.id,
        examId: subject.examId,
        cards: [
          for (final (fn, en) in sheet) Flashcard(front: en, back: fn),
          for (final (en, fr, wo) in words) Flashcard(front: en, back: wo.isEmpty ? fr : '$fr · $wo'),
        ],
      );
}

/// Le parcours d'une matière pour un niveau.
class Course {
  final String subject;
  final String level;
  final String season;
  final List<CourseUnit> units;
  Course(this.subject, this.level, this.season, this.units);

  List<Mission> get missions => [for (final u in units) ...u.missions];
}

/// Ce que l'élève a fait dans une mission.
class MissionResult {
  final bool done;
  final int canDo; // 0 : pas dit, 1 : pas encore, 2 : avec de l'aide, 3 : tout seul
  final String phrase;
  MissionResult(this.done, this.canDo, this.phrase);
}

/// Les parcours en missions (collège). Le fichier est dans l'app et mis à jour depuis GitHub,
/// comme les histoires : on peut ajouter des missions sans nouvelle version.
class MissionService {
  MissionService._();
  static final instance = MissionService._();

  static const _url = 'https://raw.githubusercontent.com/msanghare9-bit/jang/main/contenus/missions.json';
  Future<List<Course>>? _loading;
  final Map<String, MissionResult> _results = {};
  final ValueNotifier<int> revision = ValueNotifier(0);
  String? _uid;

  Future<List<Course>> courses() => _loading ??= _load();

  Future<List<Course>> _load() async {
    await _loadEdits();
    final prefs = await SharedPreferences.getInstance();
    String? text;
    try {
      final uri = Uri.parse('$_url?t=${DateTime.now().millisecondsSinceEpoch ~/ 600000}');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        text = res.body;
        _parse(text);
        await prefs.setString('missions_cache', text);
      } else {
        text = null;
      }
    } catch (e) {
      debugPrint('Missions en ligne indisponibles : $e');
      text = null;
    }
    text ??= prefs.getString('missions_cache');
    try {
      if (text != null) return _parse(text);
    } catch (_) {}
    try {
      return _parse(await rootBundle.loadString('assets/missions.json'));
    } catch (e) {
      debugPrint('Missions indisponibles : $e');
      return const [];
    }
  }

  /// Missions modifiées par l'admin dans l'app (missionEdits/{id}) : elles remplacent celles du fichier.
  Map<String, Map> _edits = const {};

  Future<void> _loadEdits() async {
    try {
      final s = await FirebaseFirestore.instance
          .collection('missionEdits')
          .get()
          .timeout(const Duration(seconds: 15));
      _edits = {
        for (final d in s.docs)
          if (d.data()['mission'] is Map) d.id: d.data()['mission'] as Map,
      };
    } catch (e) {
      debugPrint('Missions modifiées indisponibles : $e');
    }
  }

  List<Course> _parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    Map unit(Map u) => {
          ...u,
          'missions': [for (final m in _lm(u['missions'])) _edits[_s(m['id'])] ?? m],
        };
    return [
      for (final c in _lm(j['parcours']))
        Course(_s(c['matiere']), _s(c['niveau']), _s(c['saison']),
            [for (final u in _lm(c['unites'])) CourseUnit.fromMap(unit(u))]),
    ];
  }

  /// L'admin enregistre une mission modifiée. Elle arrive chez les élèves au prochain chargement.
  Future<void> saveEdit(Map<String, dynamic> mission, String byUid) async {
    final id = _s(mission['id']);
    await FirebaseFirestore.instance.collection('missionEdits').doc(id).set({
      'mission': mission,
      'by': byUid,
      'at': FieldValue.serverTimestamp(),
    });
    _edits = {..._edits, id: mission};
    reload();
  }

  /// Remet la mission du fichier d'origine.
  Future<void> resetEdit(String missionId) async {
    await FirebaseFirestore.instance.collection('missionEdits').doc(missionId).delete();
    _edits = {..._edits}..remove(missionId);
    reload();
  }

  bool isEdited(String missionId) => _edits.containsKey(missionId);

  /// Recharge les parcours (après une modification).
  void reload() {
    _loading = null;
    revision.value++;
  }

  /// Parcours de cette matière pour ce niveau (null : la matière garde ses leçons).
  Future<Course?> courseFor(Subject subject, String examId) async {
    final exam = await ContentRepo.instance.exam(examId);
    final level = LessonPack.levelOf(exam?.name ?? '');
    if (level.isEmpty) return null;
    final key = subjectKey(subject.name);
    for (final c in await courses()) {
      if (subjectKey(c.subject) == key && LessonPack.levelOf(c.level) == level && c.missions.isNotEmpty) return c;
    }
    return null;
  }

  // ---------- Progression ----------

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('missions');

  Future<void> load(String uid) async {
    _uid = uid;
    _results.clear();
    try {
      final s = await _col(uid).get(const GetOptions(source: Source.cache));
      for (final d in s.docs) {
        _results[d.id] = _fromMap(d.data());
      }
    } catch (_) {}
    revision.value++;
    unawaited(() async {
      try {
        final s = await _col(uid).get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
        for (final d in s.docs) {
          _results[d.id] = _fromMap(d.data());
        }
        revision.value++;
      } catch (_) {}
    }());
  }

  MissionResult _fromMap(Map<String, dynamic> m) =>
      MissionResult(m['done'] == true, _i(m['jesais']), _s(m['phrase']));

  MissionResult? result(String missionId) => _results[missionId];
  bool isDone(String missionId) => _results[missionId]?.done ?? false;
  int doneCount(Course c) => c.missions.where((m) => isDone(m.id)).length;

  /// Enregistre la fin d'une mission. Renvoie vrai si c'est la première fois.
  bool finish(Mission m, {required String phrase}) {
    final first = !isDone(m.id);
    final old = _results[m.id];
    _results[m.id] = MissionResult(true, old?.canDo ?? 0, phrase.isEmpty ? (old?.phrase ?? '') : phrase);
    revision.value++;
    final uid = _uid;
    if (uid != null) {
      if (first) {
        unawaited(FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'missionsDone': FieldValue.increment(1)}, SetOptions(merge: true))
            .catchError((e) => debugPrint('$e')));
      }
      unawaited(_col(uid).doc(m.id).set({
        'done': true,
        if (phrase.isNotEmpty) 'phrase': phrase,
        'at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) => debugPrint('$e')));
    }
    return first;
  }

  /// L'élève dit lui-même où il en est (1 : pas encore, 2 : avec de l'aide, 3 : tout seul).
  void setCanDo(Mission m, int level) {
    final old = _results[m.id];
    _results[m.id] = MissionResult(old?.done ?? false, level, old?.phrase ?? '');
    revision.value++;
    final uid = _uid;
    if (uid != null) {
      unawaited(_col(uid).doc(m.id).set({'jesais': level}, SetOptions(merge: true)).catchError((e) => debugPrint('$e')));
    }
  }

  /// La mission à faire ensuite (la première pas terminée), ou null si tout est fait.
  Mission? next(Course c) {
    for (final m in c.missions) {
      if (!isDone(m.id)) return m;
    }
    return null;
  }
}
