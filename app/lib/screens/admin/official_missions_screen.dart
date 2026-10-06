import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/content_repo.dart';
import '../../services/mission_service.dart';
import '../../services/pack_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'mission_editor.dart';

/// L'admin modifie les missions officielles « avec Gaïndé » (niveau → unités → missions).
class OfficialMissionsScreen extends StatefulWidget {
  const OfficialMissionsScreen({super.key});

  @override
  State<OfficialMissionsScreen> createState() => _OfficialMissionsScreenState();
}

class _OfficialMissionsScreenState extends State<OfficialMissionsScreen> {
  late Future<List<Course>> _courses;
  final Map<String, Subject> _subjects = {};

  @override
  void initState() {
    super.initState();
    _courses = MissionService.instance.courses();
    MissionService.instance.revision.addListener(_reload);
  }

  @override
  void dispose() {
    MissionService.instance.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _courses = MissionService.instance.courses());
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// La matière d'anglais de ce niveau, pour essayer la mission.
  Future<Subject> _subjectFor(Course c) async {
    final cacheKey = '${c.subject}|${c.level}';
    final known = _subjects[cacheKey];
    if (known != null) return known;
    final level = LessonPack.levelOf(c.level);
    try {
      if (level.isNotEmpty) {
        for (final e in await ContentRepo.instance.exams()) {
          if (LessonPack.levelOf(e.name) != level) continue;
          for (final s in await ContentRepo.instance.subjects(e.id)) {
            if (subjectKey(s.name) == subjectKey(c.subject)) return _subjects[cacheKey] = s;
          }
        }
      }
    } catch (e) {
      debugPrint('Matière introuvable : $e');
    }
    return Subject(id: '', examId: '', name: 'Anglais', color: '#0F5C4A');
  }

  Future<void> _open(Course c, Mission m) async {
    final subject = await _subjectFor(c);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MissionEditorScreen(
          initial: m.raw,
          title: 'Modifier la mission',
          subject: subject,
          onSave: (mission) async {
            final uid = AuthService.instance.profile.value?.uid;
            if (uid == null) throw StateError('Pas connecté');
            await MissionService.instance.saveEdit(mission, uid);
          },
        ),
      ),
    );
  }

  Future<void> _reset(Mission m) async {
    final ok = await confirm(
      context,
      'Remettre la mission d\'origine ?',
      'Tes changements sur « ${m.title} » seront effacés. Les élèves retrouveront la mission d\'origine.',
      ok: 'Remettre',
    );
    if (!ok) return;
    try {
      await MissionService.instance.resetEdit(m.id);
      if (mounted) showMessage(context, 'La mission d\'origine est remise.');
    } catch (e) {
      if (mounted) showMessage(context, 'Impossible pour le moment. Vérifie ta connexion.');
    }
  }

  Widget _missionTile(Course c, Mission m, int n) {
    final edited = MissionService.instance.isEdited(m.id);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: JangColors.noteBg,
        child: Text('$n', style: titleStyle(14, color: JangColors.primaryDark)),
      ),
      title: Text(m.title.isEmpty ? 'Sans titre' : m.title),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.canDo.isNotEmpty) Text('Je sais ${m.canDo}', maxLines: 2, overflow: TextOverflow.ellipsis),
        if (edited)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Pill('modifiée', color: JangColors.warning, background: JangColors.warningBg),
          ),
      ]),
      trailing: edited
          ? PopupMenuButton<String>(
              tooltip: 'Options',
              onSelected: (v) {
                if (v == 'edit') _open(c, m);
                if (v == 'reset') _reset(m);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Modifier')),
                PopupMenuItem(value: 'reset', child: Text('Remettre la mission d\'origine')),
              ],
            )
          : const Icon(Icons.edit_outlined),
      onTap: () => _open(c, m),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Missions avec Gaïndé')),
      body: FutureBuilder<List<Course>>(
        future: _courses,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final courses = snap.data ?? const <Course>[];
          if (courses.isEmpty) {
            return const EmptyState(
              icon: Icons.cloud_off,
              title: 'Aucune mission',
              message: 'Les missions n\'ont pas pu être chargées. Vérifie ta connexion.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
            children: [
              for (final c in courses) ...[
                SectionTitle('${_cap(c.subject)} · ${c.level}'),
                if (c.season.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(c.season, style: Theme.of(context).textTheme.bodySmall),
                  ),
                for (final u in c.units)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        key: PageStorageKey('unite/${u.id}'),
                        title: Text(u.title, style: titleStyle(17)),
                        subtitle: Text(
                          [
                            '${u.missions.length} mission${u.missions.length > 1 ? 's' : ''}',
                            if (u.missions.any((m) => MissionService.instance.isEdited(m.id))) 'des missions modifiées',
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        children: [
                          for (var i = 0; i < u.missions.length; i++) _missionTile(c, u.missions[i], i + 1),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
