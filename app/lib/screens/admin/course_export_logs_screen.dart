import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';

/// Historique réservé à l'administration : quel professeur a exporté quel cours.
class CourseExportLogsScreen extends StatelessWidget {
  const CourseExportLogsScreen({super.key});

  String _date(dynamic value) {
    final date = value is Timestamp ? value.toDate() : null;
    if (date == null) return 'Date inconnue';
    final d = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} à ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Exports des cours')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('courseExports').orderBy('createdAt', descending: true).limit(200).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Impossible de lire le journal. Vérifie la connexion et les règles Firestore.'),
              ));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Center(child: Text('Aucun cours n’a encore été exporté.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final data = docs[index].data();
                final exporter = (data['exporterName'] as String?)?.trim();
                final title = (data['lessonTitle'] as String?)?.trim();
                final className = (data['className'] as String?)?.trim();
                final school = (data['school'] as String?)?.trim();
                final subject = (data['subject'] as String?)?.trim();
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: JangColors.noteBg,
                      child: Icon(Icons.file_download_done_outlined, color: JangColors.primaryDark),
                    ),
                    title: Text(title?.isNotEmpty == true ? title! : 'Leçon sans titre',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${exporter?.isNotEmpty == true ? exporter : 'Professeur inconnu'} · '
                      '${className?.isNotEmpty == true ? className : 'Classe inconnue'}'
                      '${school?.isNotEmpty == true ? ' · $school' : ''}\n'
                      '${subject?.isNotEmpty == true ? subject : 'Matière inconnue'} · ${_date(data['createdAt'])}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            );
          },
        ),
      );
}
