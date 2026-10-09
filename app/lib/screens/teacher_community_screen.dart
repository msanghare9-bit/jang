import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../services/class_service.dart';
import '../services/content_repo.dart';
import '../theme.dart';
import '../widgets/common.dart';

class _TeacherPost {
  final String id;
  final String type;
  final String title;
  final String body;
  final String authorUid;
  final String authorName;
  final String targetSubject;
  final DateTime? createdAt;

  const _TeacherPost({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.authorUid,
    required this.authorName,
    required this.targetSubject,
    this.createdAt,
  });

  factory _TeacherPost.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final created = data['createdAt'];
    return _TeacherPost(
      id: doc.id,
      type: '${data['type'] ?? 'tip'}',
      title: '${data['title'] ?? ''}',
      body: '${data['body'] ?? ''}',
      authorUid: '${data['authorUid'] ?? ''}',
      authorName: '${data['authorName'] ?? 'Professeur'}',
      targetSubject: '${data['targetSubject'] ?? ''}',
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

/// Ressources de formation sélectionnées par l'administration et conseils partagés par les professeurs.
class TeacherCommunityScreen extends StatefulWidget {
  const TeacherCommunityScreen({super.key});

  @override
  State<TeacherCommunityScreen> createState() => _TeacherCommunityScreenState();
}

/// Conseils publiés par les professeurs, visibles sur l'accueil des élèves.
class TeacherTipsCard extends StatelessWidget {
  const TeacherTipsCard({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('teacherPosts')
            .where('type', isEqualTo: 'tip')
            .limit(3)
            .get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
          final tips = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final ad = a.data()['createdAt'];
              final bd = b.data()['createdAt'];
              final at = ad is Timestamp ? ad : Timestamp(0, 0);
              final bt = bd is Timestamp ? bd : Timestamp(0, 0);
              return bt.compareTo(at);
            });
          return Card(
            child: Column(children: [
              for (final tip in tips)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: JangColors.successBg,
                    child: Icon(Icons.lightbulb_outline, color: JangColors.snGreen),
                  ),
                  title: Text('${tip.data()['title'] ?? 'Conseil d’un professeur'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${tip.data()['body'] ?? ''}\nPar ${tip.data()['authorName'] ?? 'un professeur'}',
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                ),
            ]),
          );
        },
      );
}

class _TeacherCommunityScreenState extends State<TeacherCommunityScreen> {
  late Future<List<_TeacherPost>> _posts = _loadPosts();
  late Future<List<ClassItem>> _courses = ClassService.instance.sharedTeacherItems();
  bool _saving = false;

  Future<List<_TeacherPost>> _loadPosts() async {
    final profile = AuthService.instance.profile.value;
    if (profile == null) return const [];
    final collection = FirebaseFirestore.instance.collection('teacherPosts');
    final snapshots = <QuerySnapshot<Map<String, dynamic>>>[];
    if (profile.isAdmin) {
      snapshots.add(await collection.orderBy('createdAt', descending: true).limit(100).get());
    } else {
      snapshots.add(await collection.where('targetSubject', isEqualTo: '').orderBy('createdAt', descending: true).limit(100).get());
      for (final subject in profile.profSubjects.toSet()) {
        if (subject.isEmpty) continue;
        snapshots.add(await collection.where('targetSubject', isEqualTo: subject).orderBy('createdAt', descending: true).limit(100).get());
      }
    }
    final posts = <String, _TeacherPost>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        posts[doc.id] = _TeacherPost.fromDoc(doc);
      }
    }
    final result = posts.values.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return result;
  }

  Future<List<(String, String)>> _allSubjects() async {
    final repo = ContentRepo.instance;
    final result = <(String, String)>[];
    for (final exam in await repo.exams()) {
      for (final subject in await repo.subjects(exam.id)) {
        final key = subjectKey(subject.name);
        if (key.isNotEmpty && !result.any((s) => s.$1 == key)) result.add((key, subject.name));
      }
    }
    return result;
  }

  Future<void> _compose() async {
    final profile = AuthService.instance.profile.value;
    if (profile == null) return;
    final admin = profile.isAdmin;
    final subjects = admin ? await _allSubjects() : const <(String, String)>[];
    if (!mounted) return;
    final title = TextEditingController();
    final body = TextEditingController();
    var selectedSubject = '';
    final posted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(admin ? 'Ajouter une ressource professionnelle' : 'Partager un conseil'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, maxLength: 100, decoration: const InputDecoration(labelText: 'Titre')),
            const SizedBox(height: 8),
            TextField(controller: body, minLines: 3, maxLines: 7,
                decoration: const InputDecoration(labelText: 'Information ou conseil', alignLabelWithHint: true)),
            if (admin) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedSubject,
                decoration: const InputDecoration(labelText: 'Qui peut voir cette ressource ?'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Tous les professeurs')),
                  for (final subject in subjects) DropdownMenuItem(value: subject.$1, child: Text(subject.$2)),
                ],
                onChanged: (value) => setDialogState(() => selectedSubject = value ?? ''),
              ),
            ],
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Publier')),
          ],
        ),
      ),
    );
    if (posted != true || title.text.trim().isEmpty || body.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('teacherPosts').add({
        'type': admin ? 'resource' : 'tip',
        'title': title.text.trim(),
        'body': body.text.trim(),
        'authorUid': profile.uid,
        'authorName': profile.name,
        'targetSubject': admin ? selectedSubject : '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        showMessage(context, 'Publication visible dans l’espace professeur.');
        setState(() => _posts = _loadPosts());
      }
    } catch (_) {
      if (mounted) showMessage(context, 'Publication impossible. Vérifiez votre connexion puis réessayez.');
    } finally {
      title.dispose();
      body.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(_TeacherPost post) async {
    await FirebaseFirestore.instance.collection('teacherPosts').doc(post.id).delete();
    if (mounted) setState(() => _posts = _loadPosts());
  }

  void _showCourse(ClassItem item) {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(item.title),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${ClassItem.label(item.type)} · ${item.subject} · ${item.ownerName}'),
        const SizedBox(height: 12),
        if (item.body.isNotEmpty) Text(item.body),
        if (item.quiz.isNotEmpty) Text('${item.quiz.length} questions / activités'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final profile = AuthService.instance.profile.value!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Développement professionnel'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Ressources et conseils'),
            Tab(text: 'Cours partagés'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _saving ? null : _compose,
          icon: Icon(profile.isAdmin ? Icons.add : Icons.lightbulb_outline),
          label: Text(profile.isAdmin ? 'Publier une ressource' : 'Partager un conseil'),
        ),
        body: TabBarView(children: [
          FutureBuilder<List<_TeacherPost>>(
            future: _posts,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Text('Impossible de charger les ressources.'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final posts = snapshot.data!;
              if (posts.isEmpty) return const Center(child: Text('Aucune ressource pour le moment.'));
              return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 88), children: [
                for (final post in posts)
                  Card(child: ListTile(
                    leading: CircleAvatar(backgroundColor: JangColors.successBg,
                        child: Icon(post.type == 'resource' ? Icons.menu_book_outlined : Icons.lightbulb_outline, color: JangColors.snGreen)),
                    title: Text(post.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${post.body}\n${post.type == 'resource' ? 'Ressource Jàng' : 'Conseil de ${post.authorName}'}', maxLines: 5, overflow: TextOverflow.ellipsis),
                    isThreeLine: true,
                    onTap: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
                      title: Text(post.title), content: SingleChildScrollView(child: Text(post.body)),
                      actions: [
                        if (profile.isAdmin || post.authorUid == profile.uid)
                          TextButton(onPressed: () { Navigator.pop(context); _delete(post); }, child: const Text('Supprimer')),
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
                      ],
                    )),
                  )),
              ]);
            },
          ),
          FutureBuilder<List<ClassItem>>(
            future: _courses,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Text('Impossible de charger les cours partagés.'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final courses = snapshot.data!;
              if (courses.isEmpty) return const Center(child: Text('Aucun cours n’a encore été partagé par un professeur.'));
              return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 88), children: [
                for (final item in courses)
                  Card(child: ListTile(
                    leading: const CircleAvatar(backgroundColor: JangColors.successBg,
                        child: Icon(Icons.menu_book_outlined, color: JangColors.snGreen)),
                    title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${ClassItem.label(item.type)} · ${item.subject} · ${item.ownerName}'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _showCourse(item),
                  )),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
