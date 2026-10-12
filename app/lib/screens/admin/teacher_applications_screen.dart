import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/class_service.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Demandes de changement de rôle (élève → professeur, ou professeur →
/// élève), envoyées depuis le profil de chaque utilisateur. Rien ne change
/// sur le compte tant qu'un administrateur n'a pas validé ici.
class TeacherApplicationsScreen extends StatefulWidget {
  const TeacherApplicationsScreen({super.key});
  @override
  State<TeacherApplicationsScreen> createState() => _TeacherApplicationsScreenState();
}

class _TeacherApplicationsScreenState extends State<TeacherApplicationsScreen> {
  final _db = FirebaseFirestore.instance;
  final Set<String> _busy = {};

  Future<void> _approveToProf(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data() ?? {};
    final uid = '${d['uid'] ?? ''}';
    final school = '${d['school'] ?? ''}';
    final examIds = (d['examIds'] is List ? d['examIds'] as List : const []).whereType<String>().toList();
    final subjects = (d['subjects'] is List ? d['subjects'] as List : const []).whereType<String>().toList();
    final name = '${d['name'] ?? 'Professeur'}';
    if (uid.isEmpty || examIds.isEmpty || subjects.isEmpty) {
      showMessage(context, 'La demande ne contient pas de niveau ou de matière utilisable.');
      return;
    }
    setState(() => _busy.add(doc.id));
    try {
      final exams = await ContentRepo.instance.exams();
      final validExamIds = examIds.where((id) => exams.any((e) => e.id == id)).toList();
      if (validExamIds.isEmpty) throw Exception('Les niveaux choisis n’existent plus.');
      for (final examId in validExamIds) {
        final examName = exams.firstWhere((e) => e.id == examId).name;
        for (final subject in subjects) {
          final room = await ClassService.instance.create(
            name: '$school · $examName',
            examId: examId,
            subjectName: subject,
            profUid: uid,
            profName: name,
          );
          await _db.collection('classes').doc(room.id).update({'school': school});
        }
      }
      final batch = _db.batch();
      batch.update(_db.collection('users').doc(uid), {
        'role': 'prof',
        'school': school,
        'profSubjects': subjects.map(subjectKey).toList(),
        'profExams': validExamIds,
        'canEdit': false,
      });
      batch.update(doc.reference, {'status': 'approved', 'reviewedAt': FieldValue.serverTimestamp()});
      await batch.commit();
      if (mounted) showMessage(context, 'Compte professeur validé et classes créées.');
    } catch (e) {
      if (mounted) showMessage(context, 'La validation a échoué : $e');
    } finally {
      if (mounted) setState(() => _busy.remove(doc.id));
    }
  }

  Future<void> _approveToStudent(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data() ?? {};
    final uid = '${d['uid'] ?? ''}';
    final examId = '${d['examId'] ?? ''}';
    if (uid.isEmpty || examId.isEmpty) {
      showMessage(context, 'La demande ne contient pas de niveau utilisable.');
      return;
    }
    setState(() => _busy.add(doc.id));
    try {
      // Le compte redevient élève. Les classes qu'il possédait en tant que
      // professeur ne sont jamais supprimées : elles restent telles quelles,
      // simplement non gérables tant qu'il n'est pas de nouveau professeur.
      final batch = _db.batch();
      batch.update(_db.collection('users').doc(uid), {'role': 'student', 'examId': examId});
      batch.update(doc.reference, {'status': 'approved', 'reviewedAt': FieldValue.serverTimestamp()});
      await batch.commit();
      if (mounted) showMessage(context, 'Compte élève validé.');
    } catch (e) {
      if (mounted) showMessage(context, 'La validation a échoué : $e');
    } finally {
      if (mounted) setState(() => _busy.remove(doc.id));
    }
  }

  Future<void> _reject(DocumentSnapshot<Map<String, dynamic>> doc) async {
    setState(() => _busy.add(doc.id));
    try {
      await doc.reference.update({'status': 'rejected', 'reviewedAt': FieldValue.serverTimestamp()});
      if (mounted) showMessage(context, 'Demande refusée.');
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible de refuser cette demande.');
    } finally {
      if (mounted) setState(() => _busy.remove(doc.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Demandes de changement de rôle')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('roleRequests').where('status', isEqualTo: 'pending').snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return const Center(child: Text('Impossible de charger les demandes.'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            if (docs.isEmpty) return const Center(child: Text('Aucune demande en attente.'));
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final doc = docs[i];
                final d = doc.data();
                final busy = _busy.contains(doc.id);
                final toProf = '${d['direction'] ?? ''}' == 'toProf';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(toProf ? Icons.cast_for_education_outlined : Icons.school_outlined,
                            color: JangColors.snGreen),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(toProf ? 'Devenir professeur' : 'Redevenir élève',
                              style: titleStyle(14, weight: 700)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text('${d['name'] ?? 'Utilisateur'}', style: titleStyle(19, weight: 800)),
                      const SizedBox(height: 4),
                      if (toProf) ...[
                        Text('École : ${d['school'] ?? '—'}'),
                        Text('Niveaux : ${(d['examNames'] is List ? (d['examNames'] as List).join(', ') : '—')}'),
                        Text('Matières : ${(d['subjects'] is List ? (d['subjects'] as List).join(', ') : '—')}'),
                      ] else
                        Text('Niveau : ${d['examName'] ?? d['examId'] ?? '—'}'),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, children: [
                        OutlinedButton(onPressed: busy ? null : () => _reject(doc), child: const Text('Refuser')),
                        FilledButton(
                          onPressed: busy ? null : () => toProf ? _approveToProf(doc) : _approveToStudent(doc),
                          child: Text(busy ? 'Traitement…' : 'Valider'),
                        ),
                      ]),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      );
}
