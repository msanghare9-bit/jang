import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/content_repo.dart';

/// Liste les leçons officielles nouvellement attribuées à un auteur.
class LessonCreatorsScreen extends StatelessWidget {
  const LessonCreatorsScreen({super.key});

  Future<Map<String, String>> _labels() async {
    final labels = <String, String>{};
    for (final exam in await ContentRepo.instance.exams()) {
      labels[exam.id] = exam.name;
      for (final subject in await ContentRepo.instance.subjects(exam.id)) {
        labels[subject.id] = subject.name;
      }
    }
    return labels;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Leçons créées')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('lessons')
              .where('createdByUid', isNotEqualTo: '').orderBy('createdByUid').limit(300).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return const Center(child: Text('Impossible de charger les leçons.'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            if (docs.isEmpty) return const Center(child: Text('Aucune leçon avec un auteur enregistré.'));
            return FutureBuilder<Map<String, String>>(
              future: _labels(),
              builder: (context, labelSnap) {
                final labels = labelSnap.data ?? const <String, String>{};
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final title = (data['title'] as String?)?.trim();
                    final creator = (data['createdByName'] as String?)?.trim();
                    final exam = labels[data['examId']] ?? (data['examId'] as String? ?? 'Niveau inconnu');
                    final subject = labels[data['subjectId']] ?? (data['subjectId'] as String? ?? 'Matière inconnue');
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.menu_book_outlined)),
                        title: Text(title?.isNotEmpty == true ? title! : 'Leçon sans titre'),
                        subtitle: Text('${creator?.isNotEmpty == true ? creator : 'Auteur inconnu'} · $exam · $subject'),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      );
}
