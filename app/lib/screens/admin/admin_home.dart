import 'dart:async';

import 'package:flutter/material.dart';

import '../classes/classes_admin_screen.dart';
import '../classes/my_classes_screen.dart';
import 'official_missions_screen.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../services/pack_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'admin_widgets.dart';
import 'lesson_editor.dart';
import 'moderation_screen.dart';
import 'stats_screen.dart';
import 'announce_screen.dart';
import 'home_config_screen.dart';
import 'profs_screen.dart';
import 'students_screen.dart';
import '../../services/auth_service.dart';

/// Onglet « Gestion » du responsable : niveaux > matières > leçons.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> with RepoListener<AdminHome> {
  List<Exam>? _exams;

  @override
  Future<void> load() async {
    var e = await ContentRepo.instance.exams();
    final me = AuthService.instance.profile.value;
    // Un prof ne voit que ses niveaux.
    if (me != null && me.isProf && me.profExams.isNotEmpty) {
      e = e.where((x) => me.profExams.contains(x.id)).toList();
    }
    if (mounted) setState(() => _exams = e);
  }

  Widget _go(String label, IconData icon, Widget screen, {bool filled = false}) {
    void onPressed() => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: filled
          ? FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label))
          : OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label)),
    );
  }

  Future<void> _addExam() async {
    final name = await askText(context, 'Nouveau niveau', 'Nom (ex. : 3e, Terminale, Anglais débutant)');
    if (name == null) return;
    final repo = ContentRepo.instance;
    final id = repo.newId('exams');
    repo.save('exams', id, Exam(id: id, name: name, order: _exams?.length ?? 0).toMap());
  }

  @override
  Widget build(BuildContext context) {
    final exams = _exams;
    final me = AuthService.instance.profile.value!;
    final admin = me.isAdmin;
    final canEdit = admin || me.canEdit;
    return SafeArea(
      child: exams == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                Text(admin ? 'Gestion' : 'Espace prof', style: titleStyle(26)),
                const SizedBox(height: 6),
                Text(
                    admin
                        ? 'Ce que tu enregistres ici est publié pour les élèves. Sans connexion, '
                            'l\'envoi se fait automatiquement dès le retour d\'internet.'
                        : 'Tu suis tes élèves, tu leur écris et tu fais des annonces dans tes matières.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                _go(admin ? 'Élèves' : 'Mes élèves', Icons.groups_outlined, const StudentsScreen(), filled: true),
                admin
                    ? _go('Profs et classes', Icons.school_outlined, const ClassesAdminScreen())
                    : _go('Mes classes', Icons.school_outlined, const MyClassesScreen()),
                _go('Annonces', Icons.campaign_outlined, const AnnouncementsScreen()),
                if (admin) _go('Missions avec Gaïndé', Icons.edit_note_outlined, const OfficialMissionsScreen()),
                if (admin) _go('Accueil de l\'app', Icons.home_outlined, const HomeConfigScreen()),
                if (admin) _go('Les profs', Icons.badge_outlined, const ProfsScreen()),
                if (admin) _go('Statistiques d\'utilisation', Icons.bar_chart, const StatsScreen()),
                _go('Questions des élèves', Icons.forum_outlined, const ModerationScreen()),
                if (admin) _go('Questions posées à Kocc Barma', Icons.psychology_alt_outlined, const TutorLogsScreen()),
                if (canEdit) const SectionTitle('Niveaux'),
                if (canEdit && exams.isEmpty && admin)
                  EmptyState(
                    icon: Icons.school_outlined,
                    title: 'Aucun niveau',
                    message: 'Commence par créer un niveau avec quatre matières (français, maths, anglais, SVT).',
                    action: FilledButton(
                      onPressed: () async {
                        final n = await askText(context, 'Premier niveau', 'Nom (ex. : 3e)');
                        if (n != null) ContentRepo.instance.seedFirstLevel(n);
                      },
                      child: const Text('Créer un niveau'),
                    ),
                  ),
                if (canEdit)
                for (var i = 0; i < exams.length; i++)
                  AdminRow(
                    title: exams[i].name,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => AdminExamScreen(exam: exams[i]))),
                    onUp: admin && i > 0 ? () => swapIn(context, 'exams', exams, i, i - 1) : null,
                    onDown: admin && i < exams.length - 1
                        ? () => swapIn(context, 'exams', exams, i, i + 1)
                        : null,
                    onEdit: !admin ? null : () async {
                      final n = await askText(context, 'Renommer le niveau', 'Nom',
                          initial: exams[i].name);
                      if (n != null) ContentRepo.instance.save('exams', exams[i].id, {'name': n});
                    },
                    onDelete: !admin ? null : () async {
                      if (await confirm(context, 'Supprimer ${exams[i].name} ?',
                          'Le niveau et tout son contenu ne seront plus visibles par les élèves.',
                          ok: 'Supprimer')) {
                        ContentRepo.instance.remove('exams', exams[i].id);
                      }
                    },
                  ),
                const SizedBox(height: 8),
                if (admin)
                OutlinedButton.icon(
                    onPressed: _addExam, icon: const Icon(Icons.add), label: const Text('Ajouter un niveau')),
              ],
            ),
    );
  }
}

class AdminExamScreen extends StatefulWidget {
  final Exam exam;
  const AdminExamScreen({super.key, required this.exam});

  @override
  State<AdminExamScreen> createState() => _AdminExamScreenState();
}

class _AdminExamScreenState extends State<AdminExamScreen> with RepoListener<AdminExamScreen> {
  List<Subject>? _subjects;
  bool get _admin => AuthService.instance.profile.value?.isAdmin ?? false;

  @override
  Future<void> load() async {
    var s = await ContentRepo.instance.subjects(widget.exam.id);
    final me = AuthService.instance.profile.value;
    if (me != null && !me.isAdmin) s = s.where((x) => me.canEditSubject(x.name)).toList();
    if (mounted) setState(() => _subjects = s);
  }

  Future<void> _edit([Subject? s]) async {
    final exams = await ContentRepo.instance.exams();
    if (!mounted) return;
    final result = await showDialog<(String, String, List<String>)>(
      context: context,
      builder: (_) => SubjectDialog(subject: s, exams: exams, examId: widget.exam.id),
    );
    if (result == null) return;
    final repo = ContentRepo.instance;
    final id = s?.id ?? repo.newId('subjects');
    repo.save('subjects', id, {
      'examId': s?.examId ?? widget.exam.id,
      'examIds': result.$3,
      'name': result.$1,
      'color': result.$2,
      if (s == null) 'order': _subjects?.length ?? 0,
      if (s == null) 'deleted': false,
    });
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _subjects;
    return Scaffold(
      appBar: AppBar(title: Text(widget.exam.name)),
      body: subjects == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                const SectionTitle('Matières'),
                if (subjects.isEmpty)
                  Text('Aucune matière pour ce niveau.', style: Theme.of(context).textTheme.bodySmall),
                for (var i = 0; i < subjects.length; i++)
                  AdminRow(
                    title: subjects[i].name,
                    color: JangColors.fromHex(subjects[i].color),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AdminSubjectScreen(subject: subjects[i], exam: widget.exam))),
                    onUp: i > 0 ? () => swapIn(context, 'subjects', subjects, i, i - 1) : null,
                    onDown: i < subjects.length - 1
                        ? () => swapIn(context, 'subjects', subjects, i, i + 1)
                        : null,
                    onEdit: _admin ? () => _edit(subjects[i]) : null,
                    onDelete: !_admin ? null : () async {
                      if (await confirm(context, 'Supprimer ${subjects[i].name} ?',
                          'La matière et ses leçons ne seront plus visibles par les élèves.',
                          ok: 'Supprimer')) {
                        ContentRepo.instance.remove('subjects', subjects[i].id);
                      }
                    },
                  ),
                const SizedBox(height: 8),
                if (_admin)
                OutlinedButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une matière')),
              ],
            ),
    );
  }
}

/// Échange l'ordre de deux éléments d'une liste triée (niveaux, matières, chapitres, leçons).
void swapIn(BuildContext context, String collection, List<dynamic> items, int a, int b) {
  final ia = items[a];
  final ib = items[b];
  // Si deux éléments ont le même ordre, on utilise leur position dans la liste.
  final oa = ia.order == ib.order ? a : ia.order as int;
  final ob = ia.order == ib.order ? b : ib.order as int;
  ContentRepo.instance.swapOrder(collection, ia.id as String, oa, ib.id as String, ob);
}

class AdminSubjectScreen extends StatefulWidget {
  final Subject subject;
  final Exam? exam;
  const AdminSubjectScreen({super.key, required this.subject, this.exam});

  @override
  State<AdminSubjectScreen> createState() => _AdminSubjectScreenState();
}

class _AdminSubjectScreenState extends State<AdminSubjectScreen>
    with RepoListener<AdminSubjectScreen> {
  List<Lesson>? _lessons;
  Map<String, FlashcardDeck> _decks = const {};
  bool _migrated = false;
  List<LessonPack> _packs = const [];
  bool _packsLoaded = false;
  String _packStatus = 'loading'; // loading | error | ok

  Future<void> _loadPacks() async {
    _packsLoaded = true;
    if (mounted) setState(() => _packStatus = 'loading');
    final all = await PackService.instance.fetch();
    final names = widget.exam != null
        ? [widget.exam!.name]
        : <String>[
            for (final id in widget.subject.examIds) (await ContentRepo.instance.exam(id))?.name ?? '',
          ];
    final fit = (all ?? const <LessonPack>[]).where((p) => p.fits(widget.subject, names)).toList();
    if (mounted) {
      setState(() {
        _packs = fit;
        _packStatus = all == null ? 'error' : 'ok';
      });
    }
  }

  List<LessonPack> get _newPacks {
    final have = {for (final l in _lessons ?? const <Lesson>[]) l.id};
    return _packs
        .where((p) => !have.contains(p.lessonId) && !have.contains(p.lessonIdFor(widget.subject)))
        .toList();
  }

  int get _nextOrder {
    final lessons = _lessons ?? const <Lesson>[];
    return lessons.isEmpty ? 0 : lessons.map((l) => l.order).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// Classe affichée (null : matière vue sans classe précise).
  String? get _examId => widget.exam?.id;

  /// La matière est-elle partagée entre plusieurs classes ?
  bool get _shared => _examId != null && widget.subject.examIds.length > 1;

  /// Pour une leçon créée ici : cachée dans les autres classes de la matière.
  List<String> get _hiddenForNew =>
      _shared ? widget.subject.examIds.where((e) => e != _examId).toList() : const [];

  void _addPacks(List<LessonPack> packs) {
    PackService.instance.add(widget.subject, packs, _nextOrder, hiddenIn: _hiddenForNew);
    showMessage(context,
        packs.length == 1 ? 'Leçon ajoutée.' : '${packs.length} leçons ajoutées.');
  }

  Widget _packsCard(Color color) {
    if (_packStatus == 'loading') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text('Recherche des leçons prêtes…', style: Theme.of(context).textTheme.bodySmall),
      );
    }
    if (_packStatus == 'error') {
      return Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: ListTile(
          leading: const Icon(Icons.wifi_off_rounded),
          title: const Text('Leçons prêtes : pas de connexion'),
          trailing: TextButton(onPressed: _loadPacks, child: const Text('Réessayer')),
        ),
      );
    }
    final packs = _newPacks;
    if (packs.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('✨ Leçons prêtes à ajouter (${packs.length})', style: titleStyle(17, weight: 800)),
            const SizedBox(height: 4),
            Text('Texte, exercices et fiches de révision déjà faits. Tu pourras tout modifier ensuite.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final p in packs)
              Row(children: [
                Expanded(
                    child: Text(p.title,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                TextButton(onPressed: () => _addPacks([p]), child: const Text('Ajouter')),
              ]),
            if (packs.length > 1) ...[
              const SizedBox(height: 6),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: () => _addPacks(packs),
                icon: const Icon(Icons.download_done_rounded),
                label: const Text('Tout ajouter'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Future<void> load() async {
    final repo = ContentRepo.instance;
    if (!_migrated) {
      _migrated = true;
      // Les anciennes leçons rangées par chapitres deviennent une simple liste.
      if (await repo.migrateSubject(widget.subject)) return; // load() sera rappelé
    }
    if (!_packsLoaded) unawaited(_loadPacks());
    final l = await repo.lessonsOfSubject(widget.subject.id);
    final d = await repo.decksOfSubject(widget.subject.id);
    if (mounted) {
      setState(() {
        _lessons = l;
        _decks = d;
      });
    }
  }

  void _openLesson(Lesson? lesson) {
    final next = _nextOrder;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LessonEditor(
            subject: widget.subject, lesson: lesson, nextOrder: next, hiddenIn: _hiddenForNew),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _lessons;
    final color = JangColors.fromHex(widget.subject.color);
    final lessons = all?.where((l) => l.visibleIn(_examId)).toList();
    final hidden = all?.where((l) => !l.visibleIn(_examId)).toList() ?? const <Lesson>[];
    final title = widget.exam == null ? widget.subject.name : '${widget.subject.name} · ${widget.exam!.name}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: titleStyle(20, color: Colors.white)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: lessons == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _packsCard(color),
                Text('${lessons.length} leçon${lessons.length > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                if (lessons.isEmpty)
                  const EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: 'Aucune leçon',
                      message: 'Ajoute une première leçon avec le bouton ci-dessous.'),
                for (var i = 0; i < lessons.length; i++) _row(lessons, i, color),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _openLesson(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une leçon'),
                ),
                const SizedBox(height: 10),
                Text(
                    'Le menu ⋮ de chaque leçon : Modifier, Copier vers un autre niveau, Monter, '
                    'Descendre, Retirer ou Supprimer.',
                    style: Theme.of(context).textTheme.bodySmall),
                if (hidden.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Retirées de ce niveau (${hidden.length})',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Elles restent visibles dans les autres niveaux.'),
                    children: [
                      for (final l in hidden)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l.title),
                          trailing: TextButton(
                            onPressed: () => ContentRepo.instance.save('lessons', l.id, {
                              'hiddenIn': l.hiddenIn.where((e) => e != _examId).toList(),
                            }),
                            child: const Text('Remettre'),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  /// Copie la leçon (texte, exercices, révision) dans une autre matière / un autre niveau.
  Future<void> _copy(Lesson l, FlashcardDeck? deck) async {
    final repo = ContentRepo.instance;
    final targets = <(Exam, Subject)>[];
    for (final e in await repo.exams()) {
      for (final s in await repo.subjects(e.id)) {
        if (e.id == _examId && s.id == widget.subject.id) continue;
        targets.add((e, s));
      }
    }
    if (!mounted) return;
    final t = await showModalBottomSheet<(Exam, Subject)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('Copier « ${l.title} » vers…', style: titleStyle(18)),
            ),
            for (final x in targets)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: JangColors.fromHex(x.$2.color),
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.copy_rounded, size: 18),
                ),
                title: Text(x.$1.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(x.$2.name),
                onTap: () => Navigator.pop(ctx, x),
              ),
          ]),
        ),
      ),
    );
    if (t == null) return;
    final (exam, subject) = t;
    if (subject.id == widget.subject.id) {
      // Même matière partagée : la leçon redevient visible dans ce niveau.
      repo.save('lessons', l.id, {'hiddenIn': l.hiddenIn.where((e) => e != exam.id).toList()});
    } else {
      final others = await repo.lessonsOfSubject(subject.id);
      final order = others.isEmpty ? 0 : others.map((x) => x.order).reduce((a, b) => a > b ? a : b) + 1;
      final id = repo.newId('lessons');
      repo.save('lessons', id, {
        ...l.toMap(),
        'examId': subject.examId,
        'subjectId': subject.id,
        'chapterId': '',
        'order': order,
        'hiddenIn': subject.examIds.where((e) => e != exam.id).toList(),
        'deleted': false,
        'status': 'published',
      });
      if (deck != null) {
        repo.save('flashcards', id, {
          'chapterId': id,
          'lessonId': id,
          'subjectId': subject.id,
          'examId': subject.examId,
          'cards': deck.cards.map((c) => c.toMap()).toList(),
          'deleted': false,
        });
      }
    }
    if (mounted) showMessage(context, 'Leçon copiée dans ${exam.name} · ${subject.name}.');
  }

  Widget _row(List<Lesson> lessons, int i, Color color) {
    final l = lessons[i];
    final deck = _decks[l.id];
    final tags = <(String, bool)>[
      l.videos.isEmpty
          ? ('Pas de vidéo', false)
          : ('${l.videos.length} vidéo${l.videos.length > 1 ? 's' : ''}', true),
      l.body.trim().isEmpty ? ('Pas de texte', false) : ('Leçon', true),
      deck == null ? ('Pas de révision', false) : ('Révision ${deck.cards.length}', true),
      l.quiz.isEmpty ? ('Pas d\'exercices', false) : ('Exercices ${l.quiz.length}', true),
    ];
    final parts = splitLessonTitle(l.title);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JangColors.border),
        boxShadow: const [BoxShadow(color: JangColors.border, offset: Offset(0, 3))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openLesson(l),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Text('${i + 1}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (parts.$1.isNotEmpty)
                      Text(parts.$1.toUpperCase(),
                          style: TextStyle(
                              color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                    Text(parts.$2.isEmpty ? 'Sans titre' : parts.$2,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final t in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: t.$2 ? JangColors.noteBg : const Color(0xFFEEF1EE),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(t.$1,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: t.$2 ? JangColors.primary : JangColors.textSecondary)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Options de la leçon',
                onSelected: (v) async {
                  if (v == 'edit') _openLesson(l);
                  if (v == 'copy') await _copy(l, deck);
                  if (v == 'up' && i > 0) swapIn(context, 'lessons', lessons, i, i - 1);
                  if (v == 'down' && i < lessons.length - 1) {
                    swapIn(context, 'lessons', lessons, i, i + 1);
                  }
                  if (v == 'hide' &&
                      await confirm(context, 'Retirer « ${l.title} » de ${widget.exam?.name} ?',
                          'Elle reste visible dans les autres niveaux.',
                          ok: 'Retirer')) {
                    ContentRepo.instance
                        .save('lessons', l.id, {'hiddenIn': {...l.hiddenIn, _examId!}.toList()});
                  }
                  if (v == 'delete' &&
                      await confirm(
                          context,
                          'Supprimer « ${l.title} » ${_shared ? 'dans tous les niveaux' : ''} ?',
                          'Les élèves ne verront plus cette leçon.',
                          ok: 'Supprimer')) {
                    ContentRepo.instance.remove('lessons', l.id);
                    if (deck != null) ContentRepo.instance.remove('flashcards', l.id);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                  const PopupMenuItem(value: 'copy', child: Text('Copier vers un autre niveau')),
                  if (i > 0) const PopupMenuItem(value: 'up', child: Text('Monter')),
                  if (i < lessons.length - 1)
                    const PopupMenuItem(value: 'down', child: Text('Descendre')),
                  if (_shared)
                    PopupMenuItem(
                        value: 'hide', child: Text('Retirer de ${widget.exam!.name} seulement')),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text(_shared ? 'Supprimer dans tous les niveaux' : 'Supprimer')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
