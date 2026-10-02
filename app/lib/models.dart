import 'package:cloud_firestore/cloud_firestore.dart';

int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : d;
String _str(dynamic v, [String d = '']) => v is String ? v : d;
bool _bool(dynamic v) => v == true;

class Exam {
  final String id;
  final String name;
  final int order;
  final bool deleted;
  Exam({required this.id, required this.name, this.order = 0, this.deleted = false});

  factory Exam.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Exam(id: d.id, name: _str(m['name']), order: _int(m['order']), deleted: _bool(m['deleted']));
  }

  Map<String, dynamic> toMap() => {'name': name, 'order': order, 'deleted': deleted};
}

class Subject {
  final String id;
  final String examId;
  final String name;
  final String color;
  final int order;
  final bool deleted;
  Subject({
    required this.id,
    required this.examId,
    required this.name,
    required this.color,
    this.order = 0,
    this.deleted = false,
  });

  factory Subject.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Subject(
      id: d.id,
      examId: _str(m['examId']),
      name: _str(m['name']),
      color: _str(m['color'], '#0F5C4A'),
      order: _int(m['order']),
      deleted: _bool(m['deleted']),
    );
  }

  Map<String, dynamic> toMap() =>
      {'examId': examId, 'name': name, 'color': color, 'order': order, 'deleted': deleted};
}

class Chapter {
  final String id;
  final String examId;
  final String subjectId;
  final String title;
  final int order;
  final bool deleted;
  Chapter({
    required this.id,
    required this.examId,
    required this.subjectId,
    required this.title,
    this.order = 0,
    this.deleted = false,
  });

  factory Chapter.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Chapter(
      id: d.id,
      examId: _str(m['examId']),
      subjectId: _str(m['subjectId']),
      title: _str(m['title']),
      order: _int(m['order']),
      deleted: _bool(m['deleted']),
    );
  }

  Map<String, dynamic> toMap() => {
        'examId': examId,
        'subjectId': subjectId,
        'title': title,
        'order': order,
        'deleted': deleted,
      };
}

class Video {
  final String youtubeId;
  final String title;
  Video({required this.youtubeId, required this.title});

  factory Video.fromMap(Map m) => Video(youtubeId: _str(m['youtubeId']), title: _str(m['title']));
  Map<String, dynamic> toMap() => {'youtubeId': youtubeId, 'title': title};
}

class QuizQuestion {
  String question;
  List<String> options;
  int answer;
  String explanation;

  /// Photo de la question (identifiant dans media/), vide s'il n'y en a pas.
  String image;
  QuizQuestion({
    required this.question,
    required this.options,
    required this.answer,
    this.explanation = '',
    this.image = '',
  });

  factory QuizQuestion.empty() =>
      QuizQuestion(question: '', options: ['', '', '', ''], answer: 0, explanation: '');

  factory QuizQuestion.fromMap(Map m) {
    final opts = (m['options'] is List ? (m['options'] as List) : const [])
        .map((e) => e is String ? e : '')
        .toList();
    while (opts.length < 4) {
      opts.add('');
    }
    return QuizQuestion(
      question: _str(m['question']),
      options: opts.take(4).toList(),
      answer: _int(m['answer']).clamp(0, 3).toInt(),
      explanation: _str(m['explanation']),
      image: _str(m['image']),
    );
  }

  Map<String, dynamic> toMap() => {
        'question': question,
        'options': options,
        'answer': answer,
        'explanation': explanation,
        if (image.isNotEmpty) 'image': image,
      };

  QuizQuestion copy() => QuizQuestion(
      question: question,
      options: List.of(options),
      answer: answer,
      explanation: explanation,
      image: image);
}

class Lesson {
  final String id;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String title;
  final int order;
  final List<Video> videos;
  final String body;
  final List<QuizQuestion> quiz;
  final bool deleted;
  Lesson({
    required this.id,
    required this.examId,
    required this.subjectId,
    required this.chapterId,
    required this.title,
    this.order = 0,
    this.videos = const [],
    this.body = '',
    this.quiz = const [],
    this.deleted = false,
  });

  factory Lesson.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final vids = m['videos'] is List ? m['videos'] as List : const [];
    final qz = m['quiz'] is List ? m['quiz'] as List : const [];
    return Lesson(
      id: d.id,
      examId: _str(m['examId']),
      subjectId: _str(m['subjectId']),
      chapterId: _str(m['chapterId']),
      title: _str(m['title']),
      order: _int(m['order']),
      videos: vids.whereType<Map>().map(Video.fromMap).toList(),
      body: _str(m['body']),
      quiz: qz.whereType<Map>().map(QuizQuestion.fromMap).toList(),
      deleted: _bool(m['deleted']),
    );
  }

  Map<String, dynamic> toMap() => {
        'examId': examId,
        'subjectId': subjectId,
        'chapterId': chapterId,
        'title': title,
        'order': order,
        'videos': videos.map((v) => v.toMap()).toList(),
        'body': body,
        'quiz': quiz.map((q) => q.toMap()).toList(),
        'deleted': deleted,
      };
}

class UserProfile {
  final String uid;
  final String name;
  final String username;
  final String role; // student | teacher | admin
  final String examId;
  final bool parentConsent;
  final bool blocked;
  final List<String> badges;
  UserProfile({
    required this.uid,
    required this.name,
    required this.username,
    required this.role,
    required this.examId,
    this.parentConsent = false,
    this.blocked = false,
    this.badges = const [],
  });

  bool get isAdmin => role == 'admin';

  /// Nom affiché publiquement : prénom + initiale du nom (« Awa D. »).
  String get publicName => publicNameOf(name);

  static String publicNameOf(String full) {
    final parts = full.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Élève';
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last[0].toUpperCase()}.';
  }

  UserProfile copyWith({String? examId, bool? parentConsent}) => UserProfile(
        uid: uid,
        name: name,
        username: username,
        role: role,
        examId: examId ?? this.examId,
        parentConsent: parentConsent ?? this.parentConsent,
        blocked: blocked,
        badges: badges,
      );

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return UserProfile(
      uid: d.id,
      name: _str(m['name']),
      username: _str(m['username']),
      role: _str(m['role'], 'student'),
      examId: _str(m['examId']),
      parentConsent: _bool(m['parentConsent']),
      blocked: _bool(m['blocked']),
      badges: (m['badges'] is List ? m['badges'] as List : const []).whereType<String>().toList(),
    );
  }
}

class LessonProgress {
  final String lessonId;
  final String subjectId;
  final bool seen;
  final int? lastScore;
  final int? bestScore;
  final int total;
  final int attempts;

  /// Questions ratées à revoir : clé de la question -> nombre de réussites d'affilée depuis l'erreur.
  final Map<String, int> mistakes;

  /// Avis de l'élève sur la leçon : 1 (j'aime), -1 (je n'aime pas), 0 (aucun).
  final int vote;
  LessonProgress({
    required this.lessonId,
    required this.subjectId,
    this.seen = false,
    this.lastScore,
    this.bestScore,
    this.total = 0,
    this.attempts = 0,
    this.mistakes = const {},
    this.vote = 0,
  });

  bool get quizDone => bestScore != null && total > 0;

  LessonProgress copyWith({
    bool? seen,
    int? lastScore,
    int? bestScore,
    int? total,
    int? attempts,
    Map<String, int>? mistakes,
    int? vote,
  }) =>
      LessonProgress(
        lessonId: lessonId,
        subjectId: subjectId,
        seen: seen ?? this.seen,
        lastScore: lastScore ?? this.lastScore,
        bestScore: bestScore ?? this.bestScore,
        total: total ?? this.total,
        attempts: attempts ?? this.attempts,
        mistakes: mistakes ?? this.mistakes,
        vote: vote ?? this.vote,
      );

  factory LessonProgress.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final mk = m['mistakes'] is Map ? m['mistakes'] as Map : const {};
    return LessonProgress(
      lessonId: d.id,
      subjectId: _str(m['subjectId']),
      seen: _bool(m['seen']),
      lastScore: m['lastScore'] is num ? (m['lastScore'] as num).toInt() : null,
      bestScore: m['bestScore'] is num ? (m['bestScore'] as num).toInt() : null,
      total: _int(m['total']),
      attempts: _int(m['attempts']),
      mistakes: {for (final e in mk.entries) '${e.key}': _int(e.value)},
      vote: _int(m['vote']),
    );
  }
}

/// Une carte de révision (recto / verso).
class Flashcard {
  final String front;
  final String back;

  /// Photo du recto (identifiant dans media/), vide s'il n'y en a pas.
  final String image;
  Flashcard({required this.front, required this.back, this.image = ''});
  factory Flashcard.fromMap(Map m) =>
      Flashcard(front: _str(m['front']), back: _str(m['back']), image: _str(m['image']));
  Map<String, dynamic> toMap() =>
      {'front': front, 'back': back, if (image.isNotEmpty) 'image': image};

  /// Question affichée (par défaut pour une carte qui n'a qu'une photo).
  String get question => front.trim().isEmpty && image.isNotEmpty ? 'Qu\'est-ce que c\'est ?' : front;
}

/// Paquet de cartes d'un chapitre (flashcards/{chapterId}).
class FlashcardDeck {
  final String chapterId;
  final String subjectId;
  final String examId;
  final List<Flashcard> cards;
  final bool deleted;
  FlashcardDeck({
    required this.chapterId,
    required this.subjectId,
    required this.examId,
    required this.cards,
    this.deleted = false,
  });
  factory FlashcardDeck.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final c = m['cards'] is List ? m['cards'] as List : const [];
    return FlashcardDeck(
      chapterId: d.id,
      subjectId: _str(m['subjectId']),
      examId: _str(m['examId']),
      cards: c.whereType<Map>().map(Flashcard.fromMap).toList(),
      deleted: _bool(m['deleted']),
    );
  }
}

/// Message de la discussion d'une leçon (question, commentaire ou réponse).
class Comment {
  final String id;
  final String lessonId;
  final String uid;
  final String name;
  final String text;
  final String parentId;
  final bool isStaff;
  final int reports;
  final bool answered;
  final DateTime? createdAt;
  Comment({
    required this.id,
    required this.lessonId,
    required this.uid,
    required this.name,
    required this.text,
    required this.parentId,
    required this.isStaff,
    required this.reports,
    required this.answered,
    this.createdAt,
  });
  factory Comment.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final ts = m['createdAt'];
    return Comment(
      id: d.id,
      lessonId: _str(m['lessonId']),
      uid: _str(m['uid']),
      name: _str(m['name']),
      text: _str(m['text']),
      parentId: _str(m['parentId']),
      isStaff: _bool(m['isStaff']),
      reports: _int(m['reports']),
      answered: _bool(m['answered']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}
