import 'dart:async';

import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../services/lesson_pdf_service.dart';
import '../../services/tutor_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/jang_ui.dart';

/// Kocc helps a teacher draft a complete lesson, for the teacher only.
///
/// Le professeur choisit TOUJOURS le thème.
/// 1) Kocc propose une première fois une approche communicative, centrée sur
///    l'élève et focalisée sur une fonction langagière réelle. Le professeur
///    peut répondre à Kocc pour ajuster ; les conseils de Kocc eux-mêmes ne
///    sont pas modifiables à la main, seule la discussion les fait évoluer.
/// 2) DÈS que ces conseils (initiaux, ou ajustés par une réponse du
///    professeur) arrivent, Kocc rédige directement la leçon complète pour
///    le PROFESSEUR (avec le corrigé), prévue pour une séance de 120
///    minutes, sans que le professeur ait besoin de le redemander. Ce
///    document n'est jamais visible par les élèves et n'est jamais ajouté à
///    une classe ; il peut être exporté en PDF ou partagé avec les autres
///    professeurs (stocké à part, jamais dans les contenus de classe).
///    L'application ne génère plus de leçon séparée pour l'élève.
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

  final List<_ChatTurn> _chat = [];
  final List<Map<String, String>> _history = [];

  bool _busyChat = false;
  bool _busy = false;
  bool _exportingPdf = false;
  bool _sharingLesson = false;

  @override
  void dispose() {
    _topic.dispose();
    _objectives.dispose();
    _reply.dispose();
    _draft.dispose();
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

  /// Démarre la discussion : Kocc propose une première fois une fonction
  /// langagière et des conseils pour rendre la séance communicative et
  /// centrée sur l’élève, puis rédige directement le cours complet à partir
  /// de ces conseils — sans que le professeur ait besoin de cliquer sur un
  /// deuxième bouton pour le demander.
  ///
  /// Si une discussion existe déjà, on ne l’efface pas : changer le thème
  /// et cliquer à nouveau continue la même conversation (voir
  /// [_changeTopic]) au lieu de tout recommencer à zéro — utile si le
  /// premier sujet ne convenait pas au professeur.
  Future<void> _startChat() async {
    if (_topic.text.trim().length < 3) {
      showMessage(context, 'Saisissez le thème du cours.');
      return;
    }
    if (_chat.isNotEmpty) {
      await _changeTopic();
      return;
    }
    setState(() {
      _busyChat = true;
      _chat.clear();
      _history.clear();
      _draft.clear();
    });
    final prompt = 'Le professeur veut faire un cours sur le thème qu’il a choisi : '
        '« ${_topic.text.trim()} », pour la classe ${widget.classRoom.name}, en ${widget.classRoom.subjectName}. '
        'Les objectifs sont : ${_objectives.text.trim().isEmpty ? 'proposez des objectifs adaptés' : _objectives.text.trim()}. '
        'Ne rédige PAS encore la leçon complète. Pour l’instant, donne seulement, de façon courte et facile à lire '
        'rapidement (le professeur ne doit pas se fatiguer à les lire, mais doit comprendre pourquoi) : '
        '1) la fonction langagière réelle qui correspond le mieux à ce thème, en une ou deux phrases (ce que '
        'l’élève doit savoir FAIRE avec la langue dans une situation concrète, ex. se présenter, demander un prix '
        'au marché, décrire un lieu, donner son avis, raconter un événement — jamais une règle de grammaire isolée '
        'apprise pour elle-même) ; '
        '2) 3 à 4 conseils concrets, précis pour CE thème, pour rendre la séance communicative et centrée sur '
        'l’élève (l’élève parle, interagit et produit la langue la majorité du temps ; le professeur guide et '
        'facilite, il ne fait pas un cours magistral) — chacun en une ou deux phrases, avec au besoin un très '
        'court exemple concret. '
        'Pas de longue introduction ni de longue conclusion, mais une brève phrase finale expliquant simplement '
        'pourquoi cette approche aide mieux les élèves à progresser. Vise environ 120 à 150 mots au total : assez '
        'court pour se lire d’un coup d’œil, mais assez clair pour que le professeur comprenne le choix sans avoir '
        'à deviner. Si le professeur te répond ensuite pour ajuster ces conseils, réponds tout aussi brièvement.';
    final result = await TutorService.instance.ask(_blankLesson(), prompt, mode: 'teacher');
    if (!mounted) return;
    setState(() {
      _busyChat = false;
      if (result.answer != null) {
        _history
          ..add({'role': 'user', 'content': prompt})
          ..add({'role': 'assistant', 'content': result.answer!});
        _chat.add(_ChatTurn(false, _stripGreeting(result.answer!)));
      }
    });
    if (result.error != null) {
      showMessage(context, result.error!);
      return;
    }
    // Les conseils sont là : on rédige directement le cours complet, sans
    // attendre que le professeur le demande explicitement.
    await _generateLesson();
  }

  /// Change de thème SANS effacer la discussion précédente : continue la
  /// même conversation en informant Kocc du nouveau thème choisi (comme une
  /// réponse du professeur dans [_sendReply]), puis réécrit directement le
  /// cours complet. Permet d’essayer un autre sujet si le premier ne
  /// convenait pas, sans perdre les échanges déjà faits avec Kocc.
  Future<void> _changeTopic() async {
    final message = 'Je change le thème du cours pour : « ${_topic.text.trim()} ». '
        'Les objectifs sont : ${_objectives.text.trim().isEmpty ? 'proposez des objectifs adaptés' : _objectives.text.trim()}. '
        'Garde ce qui reste pertinent de notre échange précédent sur l’approche pédagogique, mais adapte la '
        'fonction langagière et les conseils à ce nouveau thème. Réponds aussi brièvement qu’avant.';
    setState(() {
      _busyChat = true;
      _chat.add(_ChatTurn(true, message));
    });
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
        _chat.add(_ChatTurn(false, _stripGreeting(result.answer!)));
      }
    });
    if (result.error != null) {
      showMessage(context, result.error!);
      return;
    }
    await _generateLesson();
  }

  /// Le professeur répond à Kocc pour ajuster les conseils (ex. « change la
  /// fonction », « mets plus d’oral »…) : ça continue la même conversation,
  /// puis le cours complet est réécrit directement à partir des conseils
  /// ajustés, sans que le professeur ait besoin de le redemander.
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
        _chat.add(_ChatTurn(false, _stripGreeting(result.answer!)));
      }
    });
    if (result.error != null) {
      showMessage(context, result.error!);
      return;
    }
    await _generateLesson();
  }

  /// Une fois les conseils validés par la discussion, Kocc rédige la leçon
  /// complète pour le professeur (jamais vue par les élèves, jamais ajoutée
  /// à une classe). Enlève une éventuelle formule d'introduction ou de
  /// salutation ("Cher collègue…", "Bonjour…") que Kocc aurait malgré tout
  /// ajoutée au début du document, en filet de sécurité en plus de la
  /// consigne donnée dans le prompt. Ne touche qu'au tout début du texte.
  static String _stripGreeting(String text) {
    final t = text.trim();
    if (t.isEmpty) return t;
    final greeting = RegExp(
      r'^(cher(e)?s?\s+(coll[eè]gue|professeur|enseignant)s?|bonjour|bonsoir|madame|monsieur|salut)[^\n]*',
      caseSensitive: false,
    );
    final match = greeting.matchAsPrefix(t);
    if (match == null) return t;
    final rest = t.substring(match.end);
    final blank = rest.indexOf('\n\n');
    if (blank == -1) return rest.trimLeft().isEmpty ? t : rest.trimLeft();
    return rest.substring(blank + 2).trimLeft();
  }

  Future<void> _generateLesson() async {
    final lastAdvice = _history.reversed.firstWhere(
      (h) => h['role'] == 'assistant',
      orElse: () => const {},
    )['content'];
    if (lastAdvice == null || lastAdvice.trim().isEmpty) {
      showMessage(context, 'Demandez d’abord les conseils de Kocc, puis validez-les.');
      return;
    }
    setState(() {
      _busy = true;
      _draft.clear();
    });
    final topic = _topic.text.trim();
    final approche = 'Approche pédagogique validée par le professeur après discussion avec vous (communicative, '
        'centrée sur l’apprenant, focalisée sur la fonction langagière retenue ; la grammaire et le vocabulaire ne '
        'sont introduits que comme des outils nécessaires pour réussir cette fonction) : « $lastAdvice ». '
        'Cette approche ne doit PAS rester seulement une instruction pour toi : elle doit apparaître, rédigée en '
        'clair, DANS le document lui-même, comme sa toute première section (voir la liste des sections '
        'ci-dessous). Ne la présente pas comme un résumé de notre discussion ni comme un rappel ("comme convenu", '
        '"suite à nos échanges") : rédige-la comme une partie normale du document, à la troisième personne, comme '
        'si tu l’écrivais pour la première fois.';
    final noAdresse = 'IMPORTANT : commence directement par le contenu pédagogique (par exemple par un titre ou '
        'par « Approche pédagogique »). N’écris JAMAIS de salutation ni de phrase d’introduction adressée à qui '
        'que ce soit (pas de « Cher collègue », pas de « Bonjour », pas de « vous », pas de rappel de notre '
        'discussion) : seulement le contenu lui-même, du premier mot au dernier.';
    final mef = 'Mise en forme à respecter STRICTEMENT, car ce texte est converti tel quel en PDF : fais précéder '
        'chaque grand titre de section (Objectifs et prérequis, Contenu complet de la leçon, Déroulement détaillé, '
        'Corrigé, Devoir, etc.) de « ## » et chaque « Activité N » de « ### ». N’utilise un tiret « - » en début '
        'de ligne QUE pour une vraie liste de plusieurs éléments similaires (une liste de vocabulaire, plusieurs '
        'exemples) ; pour les informations ponctuelles d’une activité (durée, objectif, matériel, consigne, '
        'critères…), écris une phrase normale avec le nom du champ en gras suivi de deux-points, par exemple '
        '« **Durée :** 7 minutes. », SANS tiret devant. N’utilise JAMAIS de notation mathématique ou LaTeX (pas de '
        '« \\rightarrow », pas de symboles de ce genre) : écris en français courant, ou utilise directement le '
        'symbole « → » si besoin d’indiquer une transformation.';

    final teacherPrompt = 'Rédige la leçon complète destinée au PROFESSEUR, pour le cours sur « $topic » (classe '
        '${widget.classRoom.name}, ${widget.classRoom.subjectName}). $approche '
        'C’est un document de préparation réellement prêt à être enseigné, pas un résumé ni un plan général, '
        'prévu pour une séance de 120 minutes : laisse aux élèves le temps d’assimiler la matière et de faire '
        'les activités sans être bousculés. $noAdresse $mef '
        'Elle doit comporter AU MOINS SIX activités numérotées exactement « Activité 1 », « Activité 2 », etc. '
        'Pour chacune : durée, objectif, matériel, contenus et exemples précis à enseigner, la consigne que le '
        'professeur peut dire mot pour mot, les étapes détaillées, ce que font le professeur et les élèves, les '
        'réponses attendues ou critères de réussite, et comment vérifier la réussite. Prévois une progression '
        'variée (mise en situation, découverte, pratique guidée, travail en binômes, production ou résolution de '
        'problème, partage et évaluation/transfert), répartie pour totaliser 120 minutes. Ancre les exemples et '
        'supports dans un contexte sénégalais concret et respectueux (école, quartier, marché, transport, famille, '
        'environnement ou vie locale selon le thème), sans clichés. Ajoute des objectifs mesurables, les '
        'prérequis, une évaluation formative, une adaptation pour les élèves qui ont besoin d’aide, un défi pour '
        'ceux qui avancent vite, et un devoir lié à leur vie quotidienne. Utilise les sections, dans cet ordre : '
        'Approche pédagogique (reprends ici, en clair et en une courte section, la fonction langagière et les '
        'conseils retenus décrits plus haut — pas une nouvelle liste différente, la même approche, juste rédigée '
        'comme partie du document) ; Objectifs et prérequis; Contenu complet de la leçon; Déroulement détaillé '
        'des Activités 1 à 6 (ou davantage); Corrigé détaillé réservé à la préparation du professeur; Devoir. '
        'La section « Contenu complet de la leçon » doit rester COURTE : seulement l’essentiel à retenir (la '
        'notion ou fonction langagière, le vocabulaire-clé, les structures ou règles principales), sous forme '
        'condensée, sans répéter les explications pas à pas, les exemples détaillés ni les consignes — tout '
        'cela a sa place uniquement dans le Déroulement détaillé des Activités, pas ici. '
        'N’impose aucune limite de longueur pour le reste du document : sois aussi détaillé que nécessaire pour '
        'qu’il soit complet et réellement utilisable. Rédige en français simple.';
    final teacherResult = await TutorService.instance.ask(_blankLesson(), teacherPrompt, mode: 'teacher');
    if (!mounted) return;
    if (teacherResult.error != null || teacherResult.answer == null || teacherResult.answer!.trim().isEmpty) {
      setState(() => _busy = false);
      showMessage(context, teacherResult.error ?? 'Kocc n’a pas pu rédiger la leçon. Réessayez.');
      return;
    }
    final teacherLesson = _stripGreeting(teacherResult.answer!);
    setState(() {
      _busy = false;
      _draft.text = teacherLesson;
    });
    // Le PDF de la leçon du professeur est préparé automatiquement, sans
    // attendre que le professeur clique sur le bouton d'export.
    unawaited(_exportDraftPdf());
    // La leçon est aussi partagée automatiquement avec tous les autres
    // professeurs (« Préparations de cours (profs) ») dès qu'elle est
    // rédigée, sans action à faire.
    unawaited(_shareTeacherLesson(silent: true));
  }

  /// Partage la préparation complète (avec corrigé) avec les autres
  /// professeurs, dans la rubrique « Préparations de cours (profs) ». Ce
  /// document reste strictement réservé aux professeurs : il n'est jamais
  /// ajouté à une classe et n'est donc jamais visible par un élève.
  ///
  /// [silent] : pas de message ni d'indicateur de chargement — utilisé
  /// pour le partage AUTOMATIQUE dès que Kocc rédige la leçon (voir
  /// [_generateLesson]), sans que le professeur ait à cliquer sur le
  /// bouton « Partager ». Le bouton reste disponible pour repartager après
  /// une modification manuelle du texte.
  Future<void> _shareTeacherLesson({bool silent = false}) async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    if (_draft.text.trim().isEmpty) {
      if (!silent) showMessage(context, 'Il n’y a rien à partager pour l’instant.');
      return;
    }
    if (!silent) setState(() => _sharingLesson = true);
    try {
      final title = _topic.text.trim();
      await ClassService.instance.shareTeacherLesson(
        title: title.isEmpty ? 'Cours préparé avec Kocc' : title,
        subjectName: widget.classRoom.subjectName,
        examId: widget.classRoom.examId,
        classId: widget.classRoom.id,
        body: _draft.text.trim(),
        authorUid: p.uid,
        authorName: p.name,
      );
      if (!mounted || silent) return;
      showMessage(context, 'Partagée avec les autres professeurs (Télécharger une fiche de cours).');
    } catch (_) {
      if (mounted && !silent) {
        showMessage(context, 'Impossible de partager cette préparation. Vérifiez votre connexion et réessayez.');
      }
    } finally {
      if (mounted && !silent) setState(() => _sharingLesson = false);
    }
  }

  Future<void> _exportDraftPdf() async {
    if (_draft.text.trim().isEmpty) {
      showMessage(context, 'Il n’y a rien à exporter pour l’instant.');
      return;
    }
    setState(() => _exportingPdf = true);
    try {
      final title = _topic.text.trim();
      final base = title.isEmpty ? 'Cours préparé avec Kocc' : title;
      final lesson = Lesson(
        id: 'draft_${widget.classRoom.id}',
        examId: widget.classRoom.examId,
        subjectId: '',
        chapterId: '',
        title: '$base — Préparation prof',
        body: _draft.text.trim(),
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
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  /// Construit les morceaux de texte d'une ligne (gras **…** rendu comme du
  /// vrai gras, le reste en texte normal) : évite d'afficher les astérisques
  /// bruts de Kocc dans la bulle de discussion.
  List<InlineSpan> _boldSpans(String line, TextStyle base) {
    final spans = <InlineSpan>[];
    final bold = base.copyWith(fontWeight: FontWeight.w800);
    var last = 0;
    for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start), style: base));
      spans.add(TextSpan(text: m.group(1), style: bold));
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last), style: base));
    return spans;
  }

  /// Affiche la réponse de Kocc proprement : un titre numéroté comme
  /// « **1) Fonction langagière cible** » devient un vrai sous-titre, une
  /// ligne « - … » devient une vraie puce, et le « ** » du gras disparaît
  /// au profit d'un vrai texte en gras — plutôt que les symboles bruts.
  Widget _adviceBody(String text) {
    final base = const TextStyle(fontSize: 14, height: 1.4, color: JangColors.text);
    final lines = text.split('\n');
    final widgets = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      final headingOnly = RegExp(r'^\*\*(.+)\*\*$').firstMatch(line.trim());
      final heading = RegExp(r'^#{1,3}\s*(.+)$').firstMatch(line.trim());
      if (headingOnly != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(headingOnly.group(1)!,
              style: base.copyWith(fontWeight: FontWeight.w800, color: JangColors.snGreen)),
        ));
      } else if (heading != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(heading.group(1)!,
              style: base.copyWith(fontWeight: FontWeight.w800, color: JangColors.snGreen)),
        ));
      } else if (RegExp(r'^[-*]\s+').hasMatch(line.trim())) {
        final content = line.trim().replaceFirst(RegExp(r'^[-*]\s+'), '');
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: base.copyWith(color: JangColors.snGreen, fontWeight: FontWeight.w800)),
            Expanded(child: RichText(text: TextSpan(children: _boldSpans(content, base)))),
          ]),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: RichText(text: TextSpan(children: _boldSpans(line, base))),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
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
        child: mine ? Text(turn.text) : _adviceBody(turn.text),
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
                'Vous choisissez toujours le thème. Kocc propose une approche (communicative, centrée sur '
                'l’élève, fonction langagière), puis rédige directement votre leçon complète de préparation — '
                'sans que vous ayez besoin de le redemander. Vous pouvez répondre à Kocc pour ajuster l’approche : '
                'le cours est alors réécrit automatiquement avec les nouveaux conseils.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _topic,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Thème du cours',
              hintText: 'Ex. Se présenter en anglais au collège',
              helperText: _chat.isEmpty
                  ? null
                  : 'Vous pouvez changer le thème ici : la discussion déjà faite avec Kocc sera gardée.',
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
                : (_busyChat ? 'Kocc réfléchit…' : 'Changer le thème (garde la discussion)'),
            icon: Icons.tips_and_updates_outlined,
            onPressed: (_busyChat || _busy) ? null : _startChat,
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
                onPressed: (_busyChat || _busy) ? null : _sendReply,
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ]),
            if (_busy) ...[
              const SizedBox(height: 14),
              const Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Kocc rédige le cours complet à partir de ces conseils…'),
              ]),
            ] else if (hasAdvice && _draft.text.isNotEmpty) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busyChat ? null : _generateLesson,
                icon: const Icon(Icons.refresh),
                label: const Text('Régénérer le cours à partir de ces conseils'),
              ),
            ],
          ],
          if (_draft.text.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('Leçon du professeur (jamais visible par les élèves)',
                style: titleStyle(18, weight: 800)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: JangColors.noteBg, borderRadius: BorderRadius.circular(10)),
              child: const Text(
                'Ce document contient votre préparation (dont le corrigé) : il ne peut JAMAIS être ajouté à '
                'une classe, donc jamais vu par un élève. Elle est partagée automatiquement avec les autres '
                'professeurs (visible dans « Télécharger une fiche de cours », jamais côté élève) dès qu’elle '
                'est rédigée, et gardée ici, dans cette classe, pour la retrouver facilement plus tard.',
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
            OutlinedButton.icon(
              onPressed: _sharingLesson ? null : () => _shareTeacherLesson(),
              icon: const Icon(Icons.groups_outlined),
              label: Text(_sharingLesson ? 'Partage…' : 'Repartager (après une modification)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _exportingPdf ? null : _exportDraftPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_exportingPdf ? 'Préparation du PDF…' : 'Télécharger la leçon en PDF'),
            ),
          ],
        ],
      ),
    );
  }
}
