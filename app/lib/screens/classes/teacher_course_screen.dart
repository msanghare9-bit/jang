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
/// En deux temps : le professeur choisit TOUJOURS le thème. Kocc propose
/// d'abord seulement des conseils pédagogiques (comment rendre la séance
/// communicative, centrée sur l'élève, et focalisée sur une fonction
/// langagière réelle). Le professeur relit, modifie si besoin, puis valide
/// ces conseils. C'est seulement après cette validation que Kocc rédige la
/// leçon complète en respectant l'approche validée.
class TeacherCourseScreen extends StatefulWidget {
  final ClassRoom classRoom;
  const TeacherCourseScreen({super.key, required this.classRoom});

  @override
  State<TeacherCourseScreen> createState() => _TeacherCourseScreenState();
}

class _TeacherCourseScreenState extends State<TeacherCourseScreen> {
  final _topic = TextEditingController();
  final _objectives = TextEditingController();
  final _advice = TextEditingController();
  final _draft = TextEditingController();
  bool _busyAdvice = false;
  bool _busy = false;
  bool _saving = false;
  bool _exportingPdf = false;
  bool _shareWithColleagues = false;

  @override
  void dispose() {
    _topic.dispose();
    _objectives.dispose();
    _advice.dispose();
    _draft.dispose();
    super.dispose();
  }

  /// Étape 1 : Kocc propose seulement des conseils pédagogiques pour ce
  /// thème précis (pas encore la leçon complète).
  Future<void> _generateAdvice() async {
    if (_topic.text.trim().length < 3) {
      showMessage(context, 'Saisissez le thème du cours.');
      return;
    }
    setState(() {
      _busyAdvice = true;
      _draft.clear();
    });
    final lesson = Lesson(
      id: 'draft_${widget.classRoom.id}',
      examId: widget.classRoom.examId,
      subjectId: '',
      chapterId: '',
      title: _topic.text.trim(),
      body: 'Préparation de cours pour ${widget.classRoom.name}, matière ${widget.classRoom.subjectName}.',
    );
    final prompt = 'Kocc Bàrma, le professeur veut faire un cours sur le thème qu’il a choisi : '
        '« ${_topic.text.trim()} », pour la classe ${widget.classRoom.name}, en ${widget.classRoom.subjectName}. '
        'Les objectifs sont : ${_objectives.text.trim().isEmpty ? 'proposez des objectifs adaptés' : _objectives.text.trim()}. '
        'Ne rédige PAS encore la leçon complète. Pour l’instant, propose seulement des conseils pédagogiques, '
        'pour que le professeur puisse les lire, les modifier si besoin, puis les valider : '
        '1) quelle fonction langagière réelle correspond le mieux à ce thème (ce que l’élève doit savoir FAIRE avec '
        'la langue dans une situation concrète, ex. se présenter, demander un prix au marché, décrire un lieu, '
        'donner son avis, raconter un événement) — jamais une règle de grammaire isolée apprise pour elle-même ; '
        '2) 3 à 5 conseils concrets, précis pour CE thème, pour rendre la séance communicative et centrée sur '
        'l’élève (l’élève parle, interagit et produit la langue la majorité du temps ; le professeur guide et '
        'facilite, il ne fait pas un cours magistral) ; '
        '3) une brève explication, en langage simple, de pourquoi cette approche aide mieux les élèves à progresser '
        'que partir directement d’une règle de grammaire. '
        'Réponds de façon concise et claire (pas de leçon complète, pas d’activités détaillées pour l’instant), '
        'vouvoie le professeur.';
    final result = await TutorService.instance.ask(lesson, prompt, mode: 'teacher');
    if (!mounted) return;
    setState(() {
      _busyAdvice = false;
      if (result.answer != null) _advice.text = result.answer!;
    });
    if (result.error != null) showMessage(context, result.error!);
  }

  /// Étape 2 : une fois les conseils validés (et éventuellement modifiés)
  /// par le professeur, Kocc rédige la leçon complète en les respectant.
  Future<void> _generateLesson() async {
    if (_advice.text.trim().length < 3) {
      showMessage(context, 'Demandez d’abord les conseils de Kocc, puis validez-les.');
      return;
    }
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    setState(() => _busy = true);
    final lesson = Lesson(
      id: 'draft_${widget.classRoom.id}',
      examId: widget.classRoom.examId,
      subjectId: '',
      chapterId: '',
      title: _topic.text.trim(),
      body: 'Préparation de cours pour ${widget.classRoom.name}, matière ${widget.classRoom.subjectName}.',
    );
    final prompt = 'Kocc Bàrma, le professeur a validé l’approche pédagogique suivante pour le cours sur '
        '« ${_topic.text.trim()} » (classe ${widget.classRoom.name}, ${widget.classRoom.subjectName}) : '
        '« ${_advice.text.trim()} ». '
        'Rédige maintenant la leçon complète en respectant STRICTEMENT cette approche validée : reste '
        'communicative, centrée sur l’apprenant, et focalisée sur la fonction langagière retenue — la grammaire '
        'et le vocabulaire ne sont introduits que comme des outils nécessaires pour réussir cette fonction. '
        'Rédige une leçon complète de 60 minutes, réellement prête à être enseignée, pas un résumé ni un plan '
        'général. La leçon doit comporter AU MOINS SIX activités d’apprentissage distinctes, numérotées exactement '
        '« Activité 1 », « Activité 2 », etc. Pour chacune, indique la durée, l’objectif, le matériel, '
        'les contenus et exemples précis à enseigner, la consigne que le professeur peut dire mot pour mot, '
        'les étapes détaillées, ce que font le professeur et les élèves, les réponses attendues ou critères de réussite, '
        'et comment vérifier leur réussite. Ne vous contentez pas d’énumérer une activité ou d’en donner les grandes lignes. '
        'Prévois une progression variée : mise en situation, découverte, pratique guidée, travail en binômes, '
        'production ou résolution de problème, partage et évaluation/transfert. Répartissez les durées pour totaliser 60 minutes. '
        'Ancrez les exemples et supports dans un contexte sénégalais concret et respectueux : école, quartier, marché, '
        'transport, famille, environnement ou vie locale, selon le thème et la matière; évite les clichés. '
        'Les élèves doivent parler, réfléchir et travailler ensemble; le professeur facilite et guide. '
        'Ajoutez des objectifs mesurables, les prérequis, une évaluation formative, une adaptation pour les élèves '
        'qui ont besoin d’aide, un défi pour ceux qui avancent vite et un devoir lié à leur vie quotidienne. '
        'Rédigez aussi les supports et contenus complets à utiliser en classe (textes, exemples, données, dialogues ou tableau, '
        'selon la matière), puis une série d’exercices avec leurs consignes, et un corrigé complet séparé qui explique '
        'les réponses. Les exercices et corrigés doivent correspondre aux objectifs et aux activités de la leçon. '
        'Commencez par rappeler en 2-3 phrases l’approche pédagogique validée par le professeur (section '
        '« Approche pédagogique retenue »), puis rédigez la leçon. '
        'Utilisez obligatoirement des sections clairement titrées : Approche pédagogique retenue; '
        'Objectifs et prérequis; Contenu complet de la leçon; Déroulement détaillé des Activités 1 à 6 (ou davantage); '
        'Exercices à donner aux élèves; Corrigé détaillé réservé à la préparation du professeur; Devoir. '
        'Rédigez en français simple, avec des consignes prêtes à lire à la classe, dans un document que je peux '
        'relire, modifier et partager. '
        'Adressez-vous toujours au professeur en le vouvoyant. Vous pouvez parfois lui donner un conseil très simple en anglais, suivi de sa traduction française.';
    final result = await TutorService.instance.ask(lesson, prompt, mode: 'teacher');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.answer != null) _draft.text = result.answer!;
    });
    if (result.error != null) showMessage(context, result.error!);
  }

  Future<void> _save() async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    if (_draft.text.trim().isEmpty) {
      showMessage(context, 'Génère ou écris le contenu du cours avant de l’ajouter.');
      return;
    }
    setState(() => _saving = true);
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
        body: _draft.text.trim(),
        visibility: _shareWithColleagues ? 'public' : 'prive',
      ));
      if (!mounted) return;
      showMessage(context, 'Le cours a été ajouté à ${widget.classRoom.name}.');
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible d’ajouter le cours. Vérifiez votre connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Exporte le brouillon en PDF, avec la même mise en page Jàng (logo,
  /// bandeau vert, présentation de l’app…) que pour une leçon.
  Future<void> _exportPdf() async {
    if (_draft.text.trim().isEmpty) {
      showMessage(context, 'Génère ou écris le contenu du cours avant de l’exporter.');
      return;
    }
    setState(() => _exportingPdf = true);
    try {
      final title = _topic.text.trim();
      final lesson = Lesson(
        id: 'draft_${widget.classRoom.id}',
        examId: widget.classRoom.examId,
        subjectId: '',
        chapterId: '',
        title: title.isEmpty ? 'Cours préparé avec Kocc' : title,
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

  @override
  Widget build(BuildContext context) {
    final hasAdvice = _advice.text.trim().isNotEmpty;
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
                'Vous choisissez toujours le thème. Kocc vous conseille d’abord sur comment rendre la séance '
                'communicative et centrée sur une fonction langagière réelle (plutôt qu’une règle de grammaire '
                'isolée). Une fois ces conseils validés, Kocc rédige la leçon complète en les respectant.',
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
            label: _busyAdvice ? 'Kocc réfléchit…' : 'Étape 1 · Demander les conseils de Kocc',
            icon: Icons.tips_and_updates_outlined,
            onPressed: _busyAdvice ? null : _generateAdvice,
          ),
          const SizedBox(height: 18),
          Text('Conseils de Kocc (à relire, modifier si besoin, puis valider)',
              style: titleStyle(16, weight: 800)),
          const SizedBox(height: 8),
          TextField(
            controller: _advice,
            minLines: 6,
            maxLines: 16,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'La fonction langagière proposée et les conseils pour rendre la séance communicative '
                  'apparaîtront ici. Modifiez-les si besoin avant de valider.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (!hasAdvice || _busy) ? null : _generateLesson,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(_busy ? 'Kocc rédige le cours…' : 'Étape 2 · Valider et rédiger le cours complet'),
          ),
          const SizedBox(height: 18),
          Text('Brouillon du cours', style: titleStyle(19, weight: 800)),
          const SizedBox(height: 8),
          TextField(
            controller: _draft,
            minLines: 12,
            maxLines: 28,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'La leçon complète de Kocc apparaîtra ici, avec le contenu, les activités détaillées, les exercices et leur corrigé. Vous pourrez la modifier avant de l’ajouter.',
              alignLabelWithHint: true,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _shareWithColleagues,
            onChanged: (value) => setState(() => _shareWithColleagues = value),
            title: const Text('Partager ce cours avec les autres professeurs'),
            subtitle: const Text('Les professeurs pourront le retrouver dans « Cours partagés ». Les élèves du niveau pourront aussi le voir.'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.add_to_photos_outlined),
            label: Text(_saving ? 'Ajout…' : 'Ajouter directement à ${widget.classRoom.name}'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _exportingPdf ? null : _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_exportingPdf ? 'Préparation du PDF…' : 'Exporter le cours en PDF'),
          ),
        ],
      ),
    );
  }
}
