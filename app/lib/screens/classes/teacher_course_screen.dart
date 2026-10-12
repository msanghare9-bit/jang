import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../services/lesson_pdf_service.dart';
import '../../services/tutor_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/jang_ui.dart';

/// Kocc helps a teacher draft a complete learner-centered class lesson.
///
/// En deux temps : le professeur choisit TOUJOURS le thème.
/// 1) Kocc discute avec le professeur (comme une conversation) pour proposer
///    une approche communicative, centrée sur l'élève et focalisée sur une
///    fonction langagière réelle. Le professeur peut répondre à Kocc pour
///    ajuster ; les conseils de Kocc eux-mêmes ne sont pas modifiables à la
///    main, seule la discussion les fait évoluer.
/// 2) Une fois cette approche validée, Kocc rédige DEUX documents :
///    - la leçon complète pour le professeur (avec le corrigé) : jamais
///      visible par les élèves et jamais ajoutable à une classe ; peut être
///      exportée en PDF ou partagée avec les autres professeurs (stockée à
///      part, jamais dans les contenus de classe) ;
///    - LA leçon pour l'élève : explication + activités intégrées, suivant
///      la même progression que la leçon du professeur, pensée pour que
///      l'élève puisse comprendre et faire les activités même sans le
///      professeur. C'est la SEULE chose qu'on peut ajouter à une classe,
///      et elle est automatiquement publique : visible et réutilisable par
///      tous les professeurs, à n'importe quel niveau.
class TeacherCourseScreen extends StatefulWidget {
  final ClassRoom classRoom;
  const TeacherCourseScreen({super.key, required this.classRoom});

  @override
  State<TeacherCourseScreen> createState() => _TeacherCourseScreenState();
}

/// Un message de la discussion avec Kocc sur l'approche pédagogique.
class _ChatTurn {
  final bool fromTeacher;
  final String text;
  _ChatTurn(this.fromTeacher, this.text);
}

class _TeacherCourseScreenState extends State<TeacherCourseScreen> {
  final _topic = TextEditingController();
  final _objectives = TextEditingController();
  final _reply = TextEditingController();
  final _draft = TextEditingController();
  final _studentLesson = TextEditingController();

  final List<_ChatTurn> _chat = [];
  final List<Map<String, String>> _history = [];

  bool _busyChat = false;
  bool _busy = false;
  bool _savingLesson = false;
  bool _exportingPdf = false;
  bool _exportingLessonPdf = false;
  bool _sharingLesson = false;

  @override
  void dispose() {
    _topic.dispose();
    _objectives.dispose();
    _reply.dispose();
    _draft.dispose();
    _studentLesson.dispose();
    super.dispose();
  }

  Lesson _blankLesson() => Lesson(
        id: 'draft_${widget.classRoom.id}',
        examId: widget.classRoom.examId,
        subjectId: '',
        chapterId: '',
        title: _topic.text.trim(),
        body: 'Préparation de cours pour ${widget.classRoom.name}, matière ${widget.classRoom.subjectName}.',
      );

  /// Démarre (ou redémarre) la discussion : Kocc propose une première fois
  /// une fonction langagière et des conseils pour rendre la séance
  /// communicative et centrée sur l’élève.
  Future<void> _startChat() async {
    if (_topic.text.trim().length < 3) {
      showMessage(context, 'Saisissez le thème du cours.');
      return;
    }
    setState(() {
      _busyChat = true;
      _chat.clear();
      _history.clear();
      _draft.clear();
      _studentLesson.clear();
    });
    final prompt = 'Le professeur veut faire un cours sur le thème qu’il a choisi : '
        '« ${_topic.text.trim()} », pour la classe ${widget.classRoom.name}, en ${widget.classRoom.subjectName}. '
        'Les objectifs sont : ${_objectives.text.trim().isEmpty ? 'proposez des objectifs adaptés' : _objectives.text.trim()}. '
        'Ne rédige PAS encore la leçon complète. Pour l’instant, propose seulement des conseils pédagogiques, '
        'que le professeur pourra discuter et ajuster avec vous avant de les valider : '
        '1) quelle fonction langagière réelle correspond le mieux à ce thème (ce que l’élève doit savoir FAIRE avec '
        'la langue dans une situation concrète, ex. se présenter, demander un prix au marché, décrire un lieu, '
        'donner son avis, raconter un événement) — jamais une règle de grammaire isolée apprise pour elle-même ; '
        '2) 3 à 5 conseils concrets, précis pour CE thème, pour rendre la séance communicative et centrée sur '
        'l’élève (l’élève parle, interagit et produit la langue la majorité du temps ; le professeur guide et '
        'facilite, il ne fait pas un cours magistral) ; '
        '3) une brève explication, en langage simple, de pourquoi cette approche aide mieux les élèves à progresser '
        'que partir directement d’une règle de grammaire. '
        'Réponds de façon concise et claire (pas de leçon complète, pas d’activités détaillées pour l’instant). '
        'Si le professeur te répond ensuite pour ajuster ces conseils, tiens compte de sa remarque.';
    final result = await TutorService.instance.ask(_blankLesson(), prompt, mode: 'teacher');
    if (!mounted) return;
    setState(() {
      _busyChat = false;
      if (result.answer != null) {
        _history
          ..add({'role': 'user', 'content': prompt})
          ..add({'role': 'assistant', 'content': result.answer!});
        _chat.add(_ChatTurn(false, result.answer!));
      }
    });
    if (result.error != null) showMessage(context, result.error!);
  }

  /// Le professeur répond à Kocc pour ajuster les conseils (ex. « change la
  /// fonction », « mets plus d’oral »…) : ça continue la même conversation.
  Future<void> _sendReply() async {
    final message = _reply.text.trim();
    if (message.length < 2) return;
    setState(() {
      _busyChat = true;
      _chat.add(_ChatTurn(true, message));
    });
    _reply.clear();
    final result = await TutorService.instance.ask(
      _blankLesson(),
      message,
      mode: 'teacher',
      history: List<Map<String, String>>.from(_history),
    );
    if (!mounted) return;
    setState(() {
      _busyChat = false;
      if (result.answer != null) {
        _history
          ..add({'role': 'user', 'content': message})
          ..add({'role': 'assistant', 'content': result.answer!});
        _chat.add(_ChatTurn(false, result.answer!));
      }
    });
    if (result.error != null) showMessage(context, result.error!);
  }

  /// Une fois les conseils validés par la discussion, Kocc rédige DEUX
  /// documents : la leçon complète pour le professeur (jamais vue par les
  /// élèves) et LA leçon de l'élève — un document autonome (explication +
  /// activités intégrées, même ordre que la leçon du professeur) qui lui
  /// permet de comprendre et de faire les activités même sans le professeur.
  Future<void> _generateLesson() async {
    final lastAdvice = _history.reversed.firstWhere(
      (h) => h['role'] == 'assistant',
      orElse: () => const {},
    )['content'];
    if (lastAdvice == null || lastAdvice.trim().isEmpty) {
      showMessage(context, 'Demandez d’abord les conseils de Kocc, puis validez-les.');
      return;
    }
    setState(() => _busy = true);
    const marker = '===LECON ELEVE===';
    final prompt = 'Le professeur a validé, après discussion avec vous, l’approche pédagogique suivante pour le '
        'cours sur « ${_topic.text.trim()} » (classe ${widget.classRoom.name}, ${widget.classRoom.subjectName}) : '
        '« $lastAdvice ». '
        'Rédige maintenant DEUX documents séparés, en respectant strictement cette approche validée (communicative, '
        'centrée sur l’apprenant, focalisée sur la fonction langagière retenue ; la grammaire et le vocabulaire ne '
        'sont introduits que comme des outils nécessaires pour réussir cette fonction). '
        'PREMIER document, la leçon complète pour le professeur : 60 minutes, réellement prête à être enseignée, '
        'pas un résumé ni un plan général. Ne t’adresse JAMAIS directement au professeur dans ce document (pas de '
        '« vous », pas de rappel de l’approche pédagogique, pas de discours introductif) : va directement au '
        'contenu. Elle doit comporter AU MOINS SIX activités numérotées exactement « Activité 1 », « Activité 2 », '
        'etc. Pour chacune : durée, objectif, matériel, contenus et exemples précis à enseigner, la consigne que le '
        'professeur peut dire mot pour mot, les étapes détaillées, ce que font le professeur et les élèves, les '
        'réponses attendues ou critères de réussite, et comment vérifier la réussite. Prévois une progression '
        'variée (mise en situation, découverte, pratique guidée, travail en binômes, production ou résolution de '
        'problème, partage et évaluation/transfert), répartie pour totaliser 60 minutes. Ancre les exemples et '
        'supports dans un contexte sénégalais concret et respectueux (école, quartier, marché, transport, famille, '
        'environnement ou vie locale selon le thème), sans clichés. Ajoute des objectifs mesurables, les '
        'prérequis, une évaluation formative, une adaptation pour les élèves qui ont besoin d’aide, un défi pour '
        'ceux qui avancent vite, et un devoir lié à leur vie quotidienne. Utilise les sections : Objectifs et '
        'prérequis; Contenu complet de la leçon; Déroulement détaillé des Activités 1 à 6 (ou davantage); Corrigé '
        'détaillé réservé à la préparation du professeur; Devoir. '
        'DEUXIÈME document, juste après : LA leçon destinée à l’ÉLÈVE lui-même — un document AUTONOME que l’élève '
        'doit pouvoir lire seul et utiliser pour comprendre ET FAIRE les activités, MÊME SANS LE PROFESSEUR présent. '
        'Suis EXACTEMENT la même logique et la même progression que les Activités 1 à 6 du premier document, dans le '
        'même ordre (mise en situation, découverte, règle ou notion expliquée simplement, puis pratique). Pour '
        'chaque étape : explique d’abord la notion avec des mots simples et des exemples concrets (reprends les '
        'exemples sénégalais du premier document), puis donne DIRECTEMENT, dans la suite du même document, '
        'l’activité ou l’exercice correspondant que l’élève doit faire à ce moment-là (une consigne claire qu’il '
        'peut suivre seul). Le document doit donc contenir à la fois l’explication ET les activités, dans l’ordre, '
        'de façon à ce que l’élève puisse progresser du début à la fin sans aide extérieure. Ne donne jamais les '
        'réponses ou le corrigé des exercices dans ce document, et ne t’adresse jamais au professeur (adresse-toi '
        'directement à l’élève, tutoie-le, encourage-le). N’inclus pas les instructions de mise en œuvre destinées '
        'au professeur (durée, matériel, consignes à dire mot pour mot) : seulement ce que l’élève doit lire et faire. '
        'Sépare les deux documents par EXACTEMENT cette ligne, seule sur sa ligne, sans rien avant ni après : '
        '$marker '
        'N’impose aucune limite de longueur : sois aussi détaillé que nécessaire pour que les deux documents soient '
        'complets et réellement utilisables, même si cela demande plusieurs centaines ou milliers de mots. '
        'Rédige en français simple, prêt à être lu en classe.';
    final result = await TutorService.instance.ask(_blankLesson(), prompt, mode: 'teacher');
    if (!mounted) return;
    var missing = false;
    setState(() {
      _busy = false;
      final answer = result.answer;
      if (answer != null) {
        final parts = answer.split(
          RegExp(r'={2,}\s*LE[CÇ]ON\s*[EÉ]L[EÈ]VE\s*={2,}', caseSensitive: false),
        );
        if (parts.length >= 2) {
          _draft.text = parts.first.trim();
          _studentLesson.text = parts.sublist(1).join('\n').trim();
        } else {
          _draft.text = answer.trim();
          _studentLesson.clear();
          missing = true;
        }
      }
    });
    if (result.error != null) showMessage(context, result.error!);
    if (result.answer != null && missing) {
      showMessage(context, 'Kocc n’a pas séparé la leçon-élève cette fois — relancez si besoin, ou recopiez-la vous-même depuis la leçon.');
    }
  }

  /// Ajoute LA leçon-élève à la classe — toujours publique : tous les
  /// professeurs, à n'importe quel niveau, peuvent la voir, l'exporter en
  /// PDF ou l'ajouter à leur propre classe. La leçon du PROFESSEUR (avec le
  /// corrigé) n'est jamais ajoutée à la classe : elle ne sort qu'en PDF.
  Future<void> _saveStudentLesson() async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    if (_studentLesson.text.trim().isEmpty) {
      showMessage(context, 'Il n’y a rien à ajouter pour l’instant.');
      return;
    }
    setState(() => _savingLesson = true);
    try {
      final title = _topic.text.trim();
      await ClassService.instance.saveItem(ClassItem(
        id: '',
        classId: widget.classRoom.id,
        ownerUid: p.uid,
        ownerName: p.name,
        examId: widget.classRoom.examId,
        subject: widget.classRoom.subject,
        type: ClassItem.lesson,
        title: title.isEmpty ? 'Cours préparé avec Kocc' : title,
        body: _studentLesson.text.trim(),
        // Toujours publique : visible et réutilisable par tous les profs.
        visibility: 'public',
        // Marque cette leçon comme créée avec Kocc, pour la rubrique
        // « Leçons créées avec Kocc » (visible par tous les professeurs).
        sourceOwnerName: koccSourceName,
      ));
      if (!mounted) return;
      showMessage(context, 'Ajoutée à ${widget.classRoom.name} — visible par tous les professeurs.');
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible d’ajouter ce contenu. Vérifiez votre connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _savingLesson = false);
    }
  }

  /// Partage la préparation complète (avec corrigé) avec les autres
  /// professeurs, dans la rubrique « Préparations de cours (profs) ». Ce
  /// document reste strictement réservé aux professeurs : il n'est jamais
  /// ajouté à une classe et n'est donc jamais visible par un élève.
  Future<void> _shareTeacherLesson() async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    if (_draft.text.trim().isEmpty) {
      showMessage(context, 'Il n’y a rien à partager pour l’instant.');
      return;
    }
    setState(() => _sharingLesson = true);
    try {
      final title = _topic.text.trim();
      await ClassService.instance.shareTeacherLesson(
        title: title.isEmpty ? 'Cours préparé avec Kocc' : title,
        subjectName: widget.classRoom.subjectName,
        body: _draft.text.trim(),
        authorUid: p.uid,
        authorName: p.name,
      );
      if (!mounted) return;
      showMessage(context, 'Partagée avec les autres professeurs (Développement professionnel).');
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible de partager cette préparation. Vérifiez votre connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _sharingLesson = false);
    }
  }

  Future<void> _exportDraftPdf(TextEditingController controller, {required bool isStudentLesson}) async {
    if (controller.text.trim().isEmpty) {
      showMessage(context, 'Il n’y a rien à exporter pour l’instant.');
      return;
    }
    setState(() {
      if (isStudentLesson) {
        _exportingLessonPdf = true;
      } else {
        _exportingPdf = true;
      }
    });
    try {
      final title = _topic.text.trim();
      final base = title.isEmpty ? 'Cours préparé avec Kocc' : title;
      final lesson = Lesson(
        id: 'draft_${widget.classRoom.id}',
        examId: widget.classRoom.examId,
        subjectId: '',
        chapterId: '',
        title: isStudentLesson ? base : '$base — Préparation prof',
        body: controller.text.trim(),
        createdByName: AuthService.instance.profile.value?.name ?? '',
      );
      await LessonPdfService.shareLesson(
        lesson,
        subjectName: widget.classRoom.subjectName,
        levelName: widget.classRoom.name,
      );
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible de préparer le PDF. Réessayez.');
    } finally {
      if (mounted) {
        setState(() {
          _exportingPdf = false;
          _exportingLessonPdf = false;
        });
      }
    }
  }

  Widget _chatBubble(_ChatTurn turn) {
    final mine = turn.fromTeacher;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 8, left: mine ? 40 : 0, right: mine ? 0 : 40),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? JangColors.snGreen.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: mine ? null : Border.all(color: JangColors.border),
        ),
        child: Text(turn.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAdvice = _chat.any((t) => !t.fromTeacher);
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer un cours avec Kocc')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            color: JangColors.successBg,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '${widget.classRoom.name} · ${widget.classRoom.subjectName}\n'
                'Vous choisissez toujours le thème. Discutez avec Kocc de l’approche (communicative, centrée sur '
                'l’élève, fonction langagière) ; une fois d’accord, Kocc rédige votre leçon complète et une leçon '
                'pour l’élève que celui-ci peut suivre seul, même sans vous.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _topic,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Thème du cours',
              hintText: 'Ex. Se présenter en anglais au collège',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _objectives,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Objectifs ou besoins particuliers (facultatif)',
              hintText: 'Ce que vos élèves devront savoir faire',
            ),
          ),
          const SizedBox(height: 14),
          ChunkyButton(
            label: _chat.isEmpty
                ? (_busyChat ? 'Kocc réfléchit…' : 'Demander les conseils de Kocc')
                : (_busyChat ? 'Kocc réfléchit…' : 'Recommencer la discussion'),
            icon: Icons.tips_and_updates_outlined,
            onPressed: _busyChat ? null : _startChat,
          ),
          if (_chat.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Discussion avec Kocc sur l’approche pédagogique', style: titleStyle(16, weight: 800)),
            const SizedBox(height: 8),
            for (final turn in _chat) _chatBubble(turn),
            if (_busyChat)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Kocc réfléchit…'),
                ]),
              ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _reply,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Répondre à Kocc (facultatif)',
                    hintText: 'Ex. Plutôt la fonction « demander son chemin »',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: JangColors.snGreen),
                tooltip: 'Envoyer',
                onPressed: _busyChat ? null : _sendReply,
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ]),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: (!hasAdvice || _busy) ? null : _generateLesson,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(_busy ? 'Kocc rédige le cours…' : 'Valider et rédiger le cours complet'),
            ),
          ],
          if (_draft.text.isNotEmpty || _studentLesson.text.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('1. Leçon du professeur (jamais visible par les élèves)',
                style: titleStyle(18, weight: 800)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: JangColors.noteBg, borderRadius: BorderRadius.circular(10)),
              child: const Text(
                'Ce document contient votre préparation (dont le corrigé) : il ne peut JAMAIS être ajouté à '
                'une classe, donc jamais vu par un élève. Vous pouvez l’exporter en PDF pour vous, ou le '
                'partager avec les autres professeurs (visible dans « Développement professionnel », jamais '
                'côté élève).',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _draft,
              minLines: 12,
              maxLines: 28,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'La leçon complète de Kocc apparaîtra ici.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _sharingLesson ? null : _shareTeacherLesson,
              icon: const Icon(Icons.groups_outlined),
              label: Text(_sharingLesson ? 'Partage…' : 'Partager avec les collègues professeurs'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _exportingPdf ? null : () => _exportDraftPdf(_draft, isStudentLesson: false),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_exportingPdf ? 'Préparation du PDF…' : 'Exporter la leçon en PDF'),
            ),
            const SizedBox(height: 22),
            Text('2. Leçon de l’élève (explication + activités, pour qu’il la fasse même sans vous)',
                style: titleStyle(18, weight: 800)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: JangColors.successBg, borderRadius: BorderRadius.circular(10)),
              child: const Text(
                'Ce document contient l’explication ET les activités, dans le même ordre que votre leçon : '
                'l’élève peut le lire et travailler seul. C’est le SEUL document qu’on peut ajouter à une '
                'classe. Une fois ajouté, il devient automatiquement public : visible, exportable en PDF et '
                'réutilisable par tous les professeurs, à n’importe quel niveau.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _studentLesson,
              minLines: 12,
              maxLines: 30,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'La leçon de l’élève (explication + activités) apparaîtra ici.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _savingLesson ? null : _saveStudentLesson,
              icon: const Icon(Icons.public),
              label: Text(_savingLesson ? 'Ajout…' : 'Ajouter à ${widget.classRoom.name} (public)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _exportingLessonPdf ? null : () => _exportDraftPdf(_studentLesson, isStudentLesson: true),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_exportingLessonPdf ? 'Préparation du PDF…' : 'Exporter la leçon-élève en PDF'),
            ),
          ],
        ],
      ),
    );
  }
}
