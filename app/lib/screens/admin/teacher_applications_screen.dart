import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/class_service.dart';
import '../../services/content_repo.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class TeacherApplicationsScreen extends StatefulWidget {
  const TeacherApplicationsScreen({super.key});
  @override
  State<TeacherApplicationsScreen> createState() => _TeacherApplicationsScreenState();
}

class _TeacherApplicationsScreenState extends State<TeacherApplicationsScreen> {
  final _db = FirebaseFirestore.instance;
  final Set<String> _busy = {};

  Future<void> _approve(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data() ?? {};
    final uid = '${d['uid'] ?? doc.id}';
    final examId = '${d['examId'] ?? ''}';
    final school = '${d['school'] ?? ''}';
    final classes = (d['classNames'] is List ? d['classNames'] as List : const []).whereType<String>().toList();
    final subjects = (d['subjects'] is List ? d['subjects'] as List : const []).whereType<String>().toList();
    final name = '${d['name'] ?? 'Professeur'}';
    if (classes.isEmpty || subjects.isEmpty || examId.isEmpty) {
      showMessage(context, 'La demande ne contient pas de classes, matières ou niveau utilisable.');
      return;
    }
    setState(() => _busy.add(doc.id));
    try {
      final exams = await ContentRepo.instance.exams();
      if (!exams.any((e) => e.id == examId)) throw Exception('Le niveau choisi n’existe plus.');
      for (final className in classes) {
        for (final subject in subjects) {
          final room = await ClassService.instance.create(
            name: className,
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
        'profExams': [examId],
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

  Future<void> _reject(DocumentSnapshot<Map<String, dynamic>> doc) async {
    setState(() => _busy.add(doc.id));
    try {
      final batch = _db.batch();
      batch.update(_db.collection('users').doc(doc.id), {'role': 'student'});
      batch.update(doc.reference, {'status': 'rejected', 'reviewedAt': FieldValue.serverTimestamp()});
      await batch.commit();
      if (mounted) showMessage(context, 'Demande refusée.');
    } catch (_) {
      if (mounted) showMessage(context, 'Impossible de refuser cette demande.');
    } finally {
      if (mounted) setState(() => _busy.remove(doc.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Demandes de professeurs')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('teacherApplications').where('status', isEqualTo: 'pending').snapshots(),
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
                final classes = (d['classNames'] is List ? d['classNames'] as List : const []).join(', ');
                final subjects = (d['subjects'] is List ? d['subjects'] as List : const []).join(', ');
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${d['name'] ?? 'Professeur'}', style: titleStyle(19, weight: 800)),
                      const SizedBox(height: 4),
                      Text('École : ${d['school'] ?? '—'}'),
                      Text('Niveau : ${d['examName'] ?? d['examId'] ?? '—'}'),
                      Text('Classes : $classes'),
                      Text('Matières : $subjects'),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, children: [
                        OutlinedButton(onPressed: busy ? null : () => _reject(doc), child: const Text('Refuser')),
                        FilledButton(onPressed: busy ? null : () => _approve(doc),
                          child: Text(busy ? 'Traitement…' : 'Valider et créer les classes')),
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
