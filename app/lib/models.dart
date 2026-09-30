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
  QuizQuestion({
    required this.question,
    required this.options,
    required this.answer,
    this.explanation = '',
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
    );
  }

  Map<String, dynamic> toMap() =>
      {'question': question, 'options': options, 'answer': answer, 'explanation': explanation};

  QuizQuestion copy() => QuizQuestion(
      question: question, options: List.of(options), answer: answer, explanation: explanation);
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
  UserProfile({
    required this.uid,
    required this.name,
    required this.username,
    required this.role,
    required this.examId,
  });

  bool get isAdmin => role == 'admin';

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return UserProfile(
      uid: d.id,
      name: _str(m['name']),
      username: _str(m['username']),
      role: _str(m['role'], 'student'),
      examId: _str(m['examId']),
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
  LessonProgress({
    required this.lessonId,
    required this.subjectId,
    this.seen = false,
    this.lastScore,
    this.bestScore,
    this.total = 0,
    this.attempts = 0,
  });

  bool get quizDone => bestScore != null && total > 0;

  factory LessonProgress.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return LessonProgress(
      lessonId: d.id,
      subjectId: _str(m['subjectId']),
      seen: _bool(m['seen']),
      lastScore: m['lastScore'] is num ? (m['lastScore'] as num).toInt() : null,
      bestScore: m['bestScore'] is num ? (m['bestScore'] as num).toInt() : null,
      total: _int(m['total']),
      attempts: _int(m['attempts']),
    );
  }
}
