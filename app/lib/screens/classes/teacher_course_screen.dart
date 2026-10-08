import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../services/tutor_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/jang_ui.dart';

/// Kocc helps a teacher draft a complete learner-centered class lesson.
class TeacherCourseScreen extends StatefulWidget {
  final ClassRoom classRoom;
  const TeacherCourseScreen({super.key, required this.classRoom});

  @override
  State<TeacherCourseScreen> createState() => _TeacherCourseScreenState();
}

class _TeacherCourseScreenState extends State<TeacherCourseScreen> {
  final _topic = TextEditingController();
  final _objectives = TextEditingController();
  final _draft = TextEditingController();
  bool _busy = false;
  bool _saving = false;

  @override
  void dispose() {
    _topic.dispose();
    _objectives.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_topic.text.trim().length < 3) {
      showMessage(context, 'Écris le thème du cours.');
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
    final prompt = 'Kocc Bàrma, aide-moi à préparer un cours complet sur « ${_topic.text.trim()} » '
        'pour la classe ${widget.classRoom.name}, en ${widget.classRoom.subjectName}. '
        'Les objectifs sont : ${_objectives.text.trim().isEmpty ? 'propose des objectifs adaptés' : _objectives.text.trim()}. '
        'Propose un cours communicatif et centré sur les apprenants, avec une durée indicative de 45 minutes. '
        'Donne le titre, les objectifs mesurables, le matériel, les étapes avec durées, '
        'les consignes du professeur, les tâches où les élèves parlent et travaillent ensemble, '
        'une vérification des acquis, une différenciation pour ceux qui ont besoin d’aide et un devoir. '
        'Rédige les consignes du professeur en français simple. Fais un document clair que je peux donner à ma classe.';
    final result = await TutorService.instance.ask(lesson, prompt);
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
        visibility: 'prive',
      ));
      if (!mounted) return;
      showMessage(context, 'Le cours a été ajouté à ${widget.classRoom.name}.');
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible d’ajouter le cours. Vérifie ta connexion et réessaie.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kocc prépare un cours')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            color: JangColors.successBg,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '${widget.classRoom.name} · ${widget.classRoom.subjectName}\n'
                'Kocc va proposer un cours communicatif et centré sur les apprenants. '
                'Relis et adapte le brouillon avant de l’ajouter.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _topic,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Thème du cours',
              hintText: 'Ex. Se présenter en anglais',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _objectives,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Objectifs ou besoins particuliers (facultatif)',
              hintText: 'Ce que les élèves devront savoir faire',
            ),
          ),
          const SizedBox(height: 14),
          ChunkyButton(
            label: _busy ? 'Kocc prépare le cours…' : 'Demander des conseils et un cours complet',
            icon: Icons.auto_awesome,
            onPressed: _busy ? null : _generate,
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
              hintText: 'Le cours de Kocc apparaîtra ici. Tu peux le modifier avant de l’ajouter.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.add_to_photos_outlined),
            label: Text(_saving ? 'Ajout…' : 'Ajouter directement à ${widget.classRoom.name}'),
          ),
        ],
      ),
    );
  }
}
