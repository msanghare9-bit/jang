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

  /// Toutes les classes qui voient cette matière (la classe principale comprise).
  final List<String> examIds;
  final String name;
  final String color;
  final int order;
  final bool deleted;
  Subject({
    required this.id,
    required this.examId,
    List<String>? examIds,
    required this.name,
    required this.color,
    this.order = 0,
    this.deleted = false,
  }) : examIds = {if (examId.isNotEmpty) examId, ...?examIds}.toList();

  factory Subject.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Subject(
      id: d.id,
      examId: _str(m['examId']),
      examIds: (m['examIds'] is List ? m['examIds'] as List : const []).whereType<String>().toList(),
      name: _str(m['name']),
      color: _str(m['color'], '#0F5C4A'),
      order: _int(m['order']),
      deleted: _bool(m['deleted']),
    );
  }

  Map<String, dynamic> toMap() => {
        'examId': examId,
        'examIds': examIds,
        'name': name,
        'color': color,
        'order': order,
        'deleted': deleted,
      };
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
  String bankId;

  /// Photo de la question (identifiant dans media/), vide s'il n'y en a pas.
  String image;
  QuizQuestion({
    required this.question,
    required this.options,
    required this.answer,
    this.explanation = '',
    this.image = '',
    this.bankId = '',
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
      bankId: _str(m['bankId']),
    );
  }

  Map<String, dynamic> toMap() => {
        'question': question,
        'options': options,
        'answer': answer,
        'explanation': explanation,
        if (image.isNotEmpty) 'image': image,
        if (bankId.isNotEmpty) 'bankId': bankId,
      };

  QuizQuestion copy() => QuizQuestion(
      question: question,
      options: List.of(options),
      answer: answer,
      explanation: explanation,
      image: image,
      bankId: bankId);
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
  final String createdByUid;
  final String createdByName;

  /// Classes (niveaux) où la leçon est retirée, quand la matière est partagée.
  final List<String> hiddenIn;
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
    this.createdByUid = '',
    this.createdByName = '',
    this.hiddenIn = const [],
    this.deleted = false,
  });

  /// Vrai si la leçon est visible dans cette classe ('' = toutes).
  bool visibleIn(String? examId) => examId == null || examId.isEmpty || !hiddenIn.contains(examId);

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
      createdByUid: _str(m['createdByUid']),
      createdByName: _str(m['createdByName']),
      hiddenIn: (m['hiddenIn'] is List ? m['hiddenIn'] as List : const []).whereType<String>().toList(),
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
        'createdByUid': createdByUid,
        'createdByName': createdByName,
        'hiddenIn': hiddenIn,
        'deleted': deleted,
      };
}

class UserProfile {
  final String uid;
  final String name;
  final String username;
  final String role; // student | prof | admin
  final String examId;
  final bool parentConsent;
  final bool blocked;
  final List<String> badges;

  /// Prof : matières (noms simplifiés, ex. « anglais ») et niveaux (identifiants) qu'il suit.
  final List<String> profSubjects;
  final List<String> profExams;

  /// Prof : peut modifier les contenus de ses matières.
  final bool canEdit;

  /// Compte désactivé par l'admin : l'élève ne peut plus entrer.
  final bool disabled;

  /// Le prénom n'est pas montré aux autres élèves (comparaison des moutons).
  final bool hideName;
  final String sheepName;
  final String school;
  UserProfile({
    required this.uid,
    required this.name,
    required this.username,
    required this.role,
    required this.examId,
    this.parentConsent = false,
    this.blocked = false,
    this.badges = const [],
    this.profSubjects = const [],
    this.profExams = const [],
    this.canEdit = false,
    this.disabled = false,
    this.hideName = false,
    this.sheepName = '',
    this.school = '',
  });

  bool get isAdmin => role == 'admin';
  bool get isProf => role == 'prof';

  /// Admin ou prof : accès à l'onglet « Gestion ».
  bool get isStaff => isAdmin || isProf;

  /// Peut modifier les contenus de cette matière (nom de la matière).
  bool canEditSubject(String subjectName) =>
      isAdmin || (isProf && canEdit && profSubjects.contains(subjectKey(subjectName)));

  /// Suit cette matière dans ce niveau (vide = tous les niveaux de ses matières).
  bool follows(String subjectName, String examId) =>
      isAdmin ||
      (isProf &&
          profSubjects.contains(subjectKey(subjectName)) &&
          (profExams.isEmpty || profExams.contains(examId)));

  /// Nom affiché publiquement : prénom + initiale du nom (« Awa D. »).
  String get publicName => publicNameOf(name);

  String get firstName {
    final n = name.trim();
    return n.isEmpty ? '' : n.split(RegExp(r'\s+')).first;
  }

  static String publicNameOf(String full) {
    final parts = full.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Élève';
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last[0].toUpperCase()}.';
  }

  UserProfile copyWith({String? examId, bool? parentConsent, bool? hideName, String? sheepName}) =>
      UserProfile(
        uid: uid,
        name: name,
        username: username,
        role: role,
        examId: examId ?? this.examId,
        parentConsent: parentConsent ?? this.parentConsent,
        blocked: blocked,
        badges: badges,
        profSubjects: profSubjects,
        profExams: profExams,
        canEdit: canEdit,
        disabled: disabled,
        hideName: hideName ?? this.hideName,
        sheepName: sheepName ?? this.sheepName,
        school: school,
      );

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    List<String> list(dynamic v) => (v is List ? v : const []).whereType<String>().toList();
    var role = _str(m['role'], 'student');
    if (role == 'teacher') role = 'prof';
    return UserProfile(
      uid: d.id,
      name: _str(m['name']),
      username: _str(m['username']),
      role: role,
      examId: _str(m['examId']),
      parentConsent: _bool(m['parentConsent']),
      blocked: _bool(m['blocked']),
      badges: list(m['badges']),
      profSubjects: list(m['profSubjects']),
      profExams: list(m['profExams']),
      canEdit: _bool(m['canEdit']),
      disabled: _bool(m['disabled']),
      hideName: _bool(m['hideName']),
      sheepName: _str(m['sheepName']),
      school: _str(m['school']),
    );
  }
}

/// Clé simple d'une matière, pour comparer des noms écrits différemment
/// (« Anglais », « anglais 6e », « English » → « anglais »).
String subjectKey(String name) {
  var n = name.toLowerCase().trim();
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final ch in n.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  n = b.toString();
  if (n.contains('angl') || n.contains('english')) return 'anglais';
  if (n.contains('franc')) return 'francais';
  if (n.contains('math')) return 'maths';
  if (n.contains('svt') || n.contains('vie et de la terre')) return 'svt';
  return n.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
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

/// Découpe un titre « Vocabulary 7 – Health » en (« Vocabulary 7 », « Health »).
/// Sans tiret : ('', titre).
(String, String) splitLessonTitle(String title) {
  final t = title.trim();
  final m = RegExp(r'^(.{2,40}?)\s+[–—-]\s+(.+)$').firstMatch(t);
  return m == null ? ('', t) : (m.group(1)!.trim(), m.group(2)!.trim());
}

/// Rubrique d'une leçon numérotée (« Vocabulary 7 » → « Vocabulary »), sinon ''.
String lessonSection(String title) {
  final k = splitLessonTitle(title).$1;
  final m = RegExp(r'^(.+?)\s+\d+$').firstMatch(k);
  return m?.group(1) ?? '';
}

/// Une classe : un groupe d'élèves d'un niveau, dans une matière, avec son prof (classes/{id}).
class ClassRoom {
  final String id;
  final String name;
  final String examId;

  /// Matière : nom simplifié (subjectKey) et nom affiché.
  final String subject;
  final String subjectName;
  final String profUid;
  final String profName;
  final String school;

  /// Code à donner aux élèves pour entrer dans la classe.
  final String code;
  final List<String> students;
  final bool deleted;
  ClassRoom({
    required this.id,
    required this.name,
    required this.examId,
    required this.subject,
    required this.subjectName,
    required this.profUid,
    required this.profName,
    this.school = '',
    required this.code,
    this.students = const [],
    this.deleted = false,
  });

  factory ClassRoom.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return ClassRoom(
      id: d.id,
      name: _str(m['name']),
      examId: _str(m['examId']),
      subject: _str(m['subject']),
      subjectName: _str(m['subjectName']),
      profUid: _str(m['profUid']),
      profName: _str(m['profName']),
      school: _str(m['school']),
      code: _str(m['code']),
      students: (m['students'] is List ? m['students'] as List : const []).whereType<String>().toList(),
      deleted: _bool(m['deleted']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'examId': examId,
        'subject': subject,
        'subjectName': subjectName,
        'profUid': profUid,
        'profName': profName,
        'school': school,
        'code': code,
        'students': students,
        'deleted': deleted,
      };
}

/// Une phrase à trous : « avant ___ après », avec toutes les bonnes réponses.
class GapItem {
  String before;
  String after;
  List<String> answers;
  GapItem({this.before = '', this.after = '', List<String>? answers}) : answers = answers ?? [];

  factory GapItem.fromMap(Map m) => GapItem(
        before: _str(m['before']),
        after: _str(m['after']),
        answers: (m['answers'] is List ? m['answers'] as List : const []).whereType<String>().toList(),
      );
  Map<String, dynamic> toMap() => {'before': before, 'after': after, 'answers': answers};
}

/// Un contenu créé par un prof pour sa classe (classItems/{id}).
class ClassItem {
  static const lesson = 'lecon';
  static const mcq = 'qcm';
  static const gaps = 'trous';
  static const homework = 'devoir';
  static const mission = 'mission';
  static const types = [lesson, mcq, gaps, homework, mission];

  static String label(String type) => switch (type) {
        lesson => 'Leçon',
        mcq => 'QCM',
        gaps => 'Texte à trous',
        homework => 'Devoir',
        mission => 'Mission avec Gaïndé',
        _ => type,
      };

  final String id;
  final String classId;
  final String ownerUid;
  final String ownerName;
  final String examId;
  final String subject;
  final String type;
  final String title;
  final String sourceLessonId;
  final String sourceOwnerName;
  final List<Video> videos;

  /// Leçon : le texte (même format que les leçons) ; devoir : la consigne.
  final String body;
  final List<QuizQuestion> quiz;
  final List<GapItem> gapItems;

  /// Mission avec Gaïndé : même format que contenus/missions.json.
  final Map<String, dynamic> missionData;

  /// « prive » : seulement les élèves de la classe ; « public » : tous les élèves du niveau.
  final String visibility;
  final bool deleted;
  final DateTime? createdAt;
  final DateTime? dueAt;
  ClassItem({
    required this.id,
    required this.classId,
    required this.ownerUid,
    required this.ownerName,
    required this.examId,
    required this.subject,
    required this.type,
    required this.title,
    this.sourceLessonId = '',
    this.sourceOwnerName = '',
    this.videos = const [],
    this.body = '',
    this.quiz = const [],
    this.gapItems = const [],
    this.missionData = const {},
    this.visibility = 'prive',
    this.deleted = false,
    this.createdAt,
    this.dueAt,
  });

  bool get isPublic => visibility == 'public';

  /// Identifiant utilisé pour la progression de l'élève (progress/ ou missions/).
  String get progressId => 'classe_$id';

  factory ClassItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final ts = m['createdAt'];
    final due = m['dueAt'];
    return ClassItem(
      id: d.id,
      classId: _str(m['classId']),
      ownerUid: _str(m['ownerUid']),
      ownerName: _str(m['ownerName']),
      examId: _str(m['examId']),
      subject: _str(m['subject']),
      type: _str(m['type'], lesson),
      title: _str(m['title']),
      sourceLessonId: _str(m['sourceLessonId']),
      sourceOwnerName: _str(m['sourceOwnerName']),
      videos: (m['videos'] is List ? m['videos'] as List : const []).whereType<Map>().map(Video.fromMap).toList(),
      body: _str(m['body']),
      quiz: (m['quiz'] is List ? m['quiz'] as List : const []).whereType<Map>().map(QuizQuestion.fromMap).toList(),
      gapItems: (m['gaps'] is List ? m['gaps'] as List : const []).whereType<Map>().map(GapItem.fromMap).toList(),
      missionData: m['mission'] is Map ? Map<String, dynamic>.from(m['mission'] as Map) : const {},
      visibility: _str(m['visibility'], 'prive'),
      deleted: _bool(m['deleted']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
      dueAt: due is Timestamp ? due.toDate() : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'classId': classId,
        'ownerUid': ownerUid,
        'ownerName': ownerName,
        'examId': examId,
        'subject': subject,
        'type': type,
        'title': title,
        'sourceLessonId': sourceLessonId,
        'sourceOwnerName': sourceOwnerName,
        'videos': videos.map((v) => v.toMap()).toList(),
        'body': body,
        'quiz': quiz.map((q) => q.toMap()).toList(),
        'gaps': gapItems.map((g) => g.toMap()).toList(),
        'mission': missionData,
        'visibility': visibility,
        'deleted': deleted,
        'dueAt': dueAt == null ? null : Timestamp.fromDate(dueAt!),
      };

  /// Leçon fabriquée pour réutiliser les écrans de leçon et de quiz (et la progression).
  Lesson asLesson(Subject s) => Lesson(
        id: progressId,
        examId: examId,
        subjectId: s.id,
        chapterId: '',
        title: title,
        videos: videos,
        body: body,
        quiz: quiz,
        createdByUid: ownerUid,
        createdByName: ownerName,
      );
}

/// Le devoir rendu par un élève (classItems/{id}/rendus/{uid}).
class Submission {
  final String uid;
  final String name;
  final String text;
  final DateTime? at;

  /// Note donnée par le prof (texte libre, ex. « 15/20 »), vide si pas encore corrigé.
  final String grade;
  final String comment;
  Submission({required this.uid, required this.name, required this.text, this.at, this.grade = '', this.comment = ''});

  bool get graded => grade.isNotEmpty || comment.isNotEmpty;

  factory Submission.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final ts = m['at'];
    return Submission(
      uid: d.id,
      name: _str(m['name']),
      text: _str(m['text']),
      at: ts is Timestamp ? ts.toDate() : null,
      grade: _str(m['grade']),
      comment: _str(m['comment']),
    );
  }
}
