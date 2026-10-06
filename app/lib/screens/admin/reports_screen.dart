import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/quiz_bank.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Les questions des matchs signalées par les élèves et les profs (admin).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _col = FirebaseFirestore.instance.collection('signalements');
  late Future<QuerySnapshot<Map<String, dynamic>>> _future = _load();

  Future<QuerySnapshot<Map<String, dynamic>>> _load() => _col.orderBy('at', descending: true).limit(200).get();

  Future<void> _done(String id) async {
    await _col.doc(id).delete();
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Questions signalées')),
      body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: TextButton(onPressed: () => setState(() => _future = _load()), child: const Text('Réessayer')),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const EmptyState(
              icon: Icons.flag_outlined,
              title: 'Aucun signalement',
              message: 'Quand un élève ou un prof signale une question de match, elle arrive ici.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Text(
                'Pour corriger une question, change-la dans pedagogie/quiz/ (sur GitHub), puis marque le signalement comme traité.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final d in docs) _card(d),
            ],
          );
        },
      ),
    );
  }

  Widget _card(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final q = BankQuestion.fromMap(m['question'] is Map ? m['question'] as Map : const {});
    final note = '${m['note'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${QuizBank.domainLabel('${m['domaine'] ?? ''}')} · ${QuizBank.levelLabel('${m['niveau'] ?? ''}')} · ${m['name'] ?? ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          if (q.text.isNotEmpty) Text(q.text, style: const TextStyle(fontStyle: FontStyle.italic)),
          Text(q.question, style: const TextStyle(fontWeight: FontWeight.w800)),
          for (var i = 0; i < q.options.length; i++)
            Text('${i == q.answer ? '✅' : '•'} ${q.options[i]}',
                style: TextStyle(fontWeight: i == q.answer ? FontWeight.w800 : FontWeight.w400)),
          if (q.explanation.isNotEmpty) Text(q.explanation, style: Theme.of(context).textTheme.bodySmall),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: JangColors.errorBg, borderRadius: BorderRadius.circular(10)),
              child: Text('« $note »'),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _done(d.id),
              icon: const Icon(Icons.check),
              label: const Text('Traité'),
            ),
          ),
        ]),
      ),
    );
  }
}
