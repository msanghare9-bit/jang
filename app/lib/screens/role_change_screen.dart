import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/content_repo.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Permet à un élève de demander à devenir professeur, ou à un professeur
/// de demander à redevenir élève. La demande est enregistrée dans
/// `roleRequests` : rien ne change tant qu'un administrateur ne l'a pas
/// validée (voir admin/teacher_applications_screen.dart).
class RoleChangeScreen extends StatefulWidget {
  const RoleChangeScreen({super.key});

  @override
  State<RoleChangeScreen> createState() => _RoleChangeScreenState();
}

class _RoleChangeScreenState extends State<RoleChangeScreen> {
  final _db = FirebaseFirestore.instance;
  late Future<List<Exam>> _exams = ContentRepo.instance.exams();
  late Future<DocumentSnapshot<Map<String, dynamic>>?> _pending = _loadPending();

  // Élève → professeur.
  final _school = TextEditingController();
  final Set<String> _examIds = {};
  final List<TextEditingController> _subjectFields = [TextEditingController()];

  // Professeur → élève.
  String? _studentExamId;

  bool _busy = false;

  Future<DocumentSnapshot<Map<String, dynamic>>?> _loadPending() async {
    final p = AuthService.instance.profile.value;
    if (p == null) return null;
    final s = await _db
        .collection('roleRequests')
        .where('uid', isEqualTo: p.uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    return s.docs.isEmpty ? null : s.docs.first;
  }

  @override
  void dispose() {
    _school.dispose();
    for (final f in _subjectFields) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _cancelPending(DocumentSnapshot<Map<String, dynamic>> doc) async {
    setState(() => _busy = true);
    try {
      await doc.reference.update({'status': 'cancelled', 'reviewedAt': FieldValue.serverTimestamp()});
      if (mounted) setState(() => _pending = _loadPending());
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible d’annuler la demande. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitToProf(UserProfile p, List<Exam> exams) async {
    final school = _school.text.trim();
    final subjects = _subjectFields.map((f) => f.text.trim()).where((s) => s.isNotEmpty).toList();
    if (school.isEmpty || _examIds.isEmpty || subjects.isEmpty) {
      showMessage(context, 'Renseignez votre école, au moins un niveau et une matière.');
      return;
    }
    final selected = exams.where((e) => _examIds.contains(e.id)).toList();
    setState(() => _busy = true);
    try {
      await _db.collection('roleRequests').add({
        'uid': p.uid,
        'name': p.name,
        'currentRole': p.role,
        'direction': 'toProf',
        'status': 'pending',
        'school': school,
        'examIds': [for (final e in selected) e.id],
        'examNames': [for (final e in selected) e.name],
        'subjects': subjects,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      showMessage(context, 'Demande envoyée. Elle sera étudiée par un administrateur.');
      setState(() => _pending = _loadPending());
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible d’envoyer la demande. Vérifiez votre connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitToStudent(UserProfile p, List<Exam> exams) async {
    if (_studentExamId == null) {
      showMessage(context, 'Choisissez votre niveau.');
      return;
    }
    final exam = exams.firstWhere((e) => e.id == _studentExamId);
    setState(() => _busy = true);
    try {
      await _db.collection('roleRequests').add({
        'uid': p.uid,
        'name': p.name,
        'currentRole': p.role,
        'direction': 'toStudent',
        'status': 'pending',
        'examId': exam.id,
        'examName': exam.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      showMessage(context, 'Demande envoyée. Elle sera étudiée par un administrateur.');
      setState(() => _pending = _loadPending());
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible d’envoyer la demande. Vérifiez votre connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthService.instance.profile.value;
    if (p == null) return const SizedBox.shrink();
    final toProf = !p.isProf;
    return Scaffold(
      appBar: AppBar(title: Text(toProf ? 'Devenir professeur' : 'Redevenir élève')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
        future: _pending,
        builder: (context, pendingSnap) {
          if (!pendingSnap.hasData && pendingSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final pendingDoc = pendingSnap.data;
          if (pendingDoc != null) {
            final d = pendingDoc.data() ?? {};
            final dir = '${d['direction'] ?? ''}';
            return ListView(padding: const EdgeInsets.all(18), children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: JangColors.noteBg, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  dir == 'toProf'
                      ? 'Votre demande pour devenir professeur est en attente de validation par un administrateur.'
                      : 'Votre demande pour redevenir élève est en attente de validation par un administrateur.',
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _busy ? null : () => _cancelPending(pendingDoc),
                child: Text(_busy ? 'Annulation…' : 'Annuler ma demande'),
              ),
            ]);
          }
          return FutureBuilder<List<Exam>>(
            future: _exams,
            builder: (context, examSnap) {
              final exams = examSnap.data ?? const <Exam>[];
              return ListView(
                padding: const EdgeInsets.all(18),
                children: toProf ? _buildToProf(p, exams) : _buildToStudent(p, exams),
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _buildToProf(UserProfile p, List<Exam> exams) => [
        const Text(
          'Remplissez ces informations pour demander un compte professeur. '
          'Votre demande sera étudiée avant toute validation — votre compte élève continue de fonctionner normalement en attendant.',
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _school,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'École'),
        ),
        const SizedBox(height: 14),
        const Text('Niveaux de classe', style: TextStyle(fontWeight: FontWeight.w800)),
        const Text('Cochez tous les niveaux où vous enseignez.'),
        if (exams.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator())
        else
          ...exams.map((exam) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _examIds.contains(exam.id),
                title: Text(exam.name),
                onChanged: (selected) => setState(() {
                  if (selected == true) {
                    _examIds.add(exam.id);
                  } else {
                    _examIds.remove(exam.id);
                  }
                }),
              )),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(child: Text('Matières enseignées', style: TextStyle(fontWeight: FontWeight.w800))),
          IconButton(
            tooltip: 'Ajouter une matière',
            onPressed: () => setState(() => _subjectFields.add(TextEditingController())),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ]),
        for (var i = 0; i < _subjectFields.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _subjectFields[i],
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: 'Matière ${i + 1}', hintText: 'Anglais'),
                ),
              ),
              if (_subjectFields.length > 1)
                IconButton(
                  tooltip: 'Supprimer cette matière',
                  onPressed: () => setState(() => _subjectFields.removeAt(i).dispose()),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
            ]),
          ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : () => _submitToProf(p, exams),
          child: Text(_busy ? 'Envoi…' : 'Envoyer la demande'),
        ),
      ];

  List<Widget> _buildToStudent(UserProfile p, List<Exam> exams) => [
        const Text(
          'Si vous redevenez élève, votre compte professeur et vos classes existantes resteront tels quels '
          '(vous ne pourrez simplement plus les gérer tant que vous n’êtes pas de nouveau professeur).',
        ),
        const SizedBox(height: 16),
        const Text('Votre niveau', style: TextStyle(fontWeight: FontWeight.w800)),
        if (exams.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator())
        else
          DropdownButtonFormField<String>(
            value: _studentExamId,
            decoration: const InputDecoration(labelText: 'Niveau'),
            items: [for (final e in exams) DropdownMenuItem(value: e.id, child: Text(e.name))],
            onChanged: (v) => setState(() => _studentExamId = v),
          ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _busy ? null : () => _submitToStudent(p, exams),
          child: Text(_busy ? 'Envoi…' : 'Envoyer la demande'),
        ),
      ];
}
