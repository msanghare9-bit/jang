import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/mission_service.dart';
import '../../services/speech_service.dart';
import '../../services/story_service.dart';
import '../../theme.dart';
import '../../widgets/characters.dart';
import '../../widgets/class_section.dart';
import '../../widgets/jang_ui.dart';
import '../../widgets/say.dart';
import '../story_screen.dart';
import 'learn_mode.dart';
import 'mission_guide.dart';
import 'mission_screen.dart';
import 'unit_end_screen.dart';

/// Le parcours en missions d'une matière (collège) : Parcours, Je sais, Carnet.
class CourseScreen extends StatefulWidget {
  final Course course;
  final Subject subject;
  const CourseScreen({super.key, required this.course, required this.subject});

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // La toute première fois : le guide « Comment ça marche ».
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MissionGuide.showFirstTime(context);
    });
  }

  Future<void> _open(Mission m) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => MissionScreen(mission: m, subject: widget.subject)));
    if (mounted) setState(() {});
  }

  Future<void> _story() async {
    final st = await StoryService.instance.stateFor(widget.subject);
    if (!mounted) return;
    if (st == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pas encore d\'histoire pour cette matière.')));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StoryScreen(state: st)));
  }

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(widget.subject.color);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name),
        actions: [
          IconButton(
            tooltip: 'Comment ça marche',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => MissionGuide.show(context),
          ),
          IconButton(
            tooltip: 'Mon histoire',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: _story,
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: MissionService.instance.revision,
        builder: (context, _, __) => switch (_tab) {
          0 => _path(color),
          1 => _canDo(),
          _ => _notebook(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.route_outlined), label: 'Parcours'),
          NavigationDestination(icon: Icon(Icons.star_outline), label: 'Je sais'),
          NavigationDestination(icon: Icon(Icons.book_outlined), label: 'Mon carnet'),
        ],
      ),
    );
  }

  Widget _path(Color color) {
    final svc = MissionService.instance;
    final course = widget.course;
    final next = svc.next(course);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        LearnModeSwitch(current: LearnMode.practice, subject: widget.subject, course: course),
        ClassSection(subject: widget.subject, padding: const EdgeInsets.only(top: 14)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SAISON', style: TextStyle(color: JangColors.on(color), fontWeight: FontWeight.w800, fontSize: 12)),
                Text(course.season, style: titleStyle(22, color: JangColors.on(color), weight: 800)),
                Text('${svc.doneCount(course)} mission${svc.doneCount(course) > 1 ? 's' : ''} sur ${course.missions.length}',
                    style: TextStyle(color: JangColors.on(color), fontWeight: FontWeight.w700)),
              ]),
            ),
            const CharacterView(Chars.lion, size: 80, moves: Moves.dance),
          ]),
        ),
        for (var u = 0; u < course.units.length; u++) ...[
          const SizedBox(height: 16),
          Text('Unité ${u + 1} · ${course.units[u].title}', style: titleStyle(20, weight: 800)),
          const SizedBox(height: 6),
          for (var i = 0; i < course.units[u].missions.length; i++)
            _node(course.units[u].missions[i], i, next),
          _unitEnd(course.units[u]),
        ],
      ],
    );
  }

  Widget _node(Mission m, int i, Mission? next) {
    final done = MissionService.instance.isDone(m.id);
    final current = next?.id == m.id;
    final offset = [0.0, 40.0, 80.0, 40.0][i % 4];
    return Padding(
      padding: EdgeInsets.only(left: offset, bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(m),
        child: Row(children: [
          Container(
            width: current ? 70 : 60,
            height: current ? 70 : 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? JangColors.success : (current ? JangColors.primary : Colors.white),
              border: done || current ? null : Border.all(color: JangColors.border, width: 3),
              boxShadow: [
                BoxShadow(
                    color: done ? JangColors.successDark : (current ? JangColors.primaryDark : JangColors.border),
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 32)
                  : current
                      ? const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36)
                      : Text('${i + 1}', style: titleStyle(22, color: JangColors.textSecondary, weight: 800)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: current ? const EdgeInsets.all(8) : EdgeInsets.zero,
              decoration: current ? BoxDecoration(color: JangColors.noteBg, borderRadius: BorderRadius.circular(12)) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (current)
                  const Text('À TOI !',
                      style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: JangColors.primaryDark)),
                Text('Je sais ${m.canDo}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(m.title, style: const TextStyle(color: JangColors.textSecondary, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _unitEnd(CourseUnit u) {
    final all = u.missions.every((m) => MissionService.instance.isDone(m.id));
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => UnitEndScreen(unit: u, subject: widget.subject))),
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: all ? const Color(0xFFFFF8E6) : Colors.white,
          border: Border.all(color: all ? const Color(0xFFFFE2A0) : JangColors.border, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          const Icon(Icons.flag_outlined, color: Color(0xFFB07A00)),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Fin de l\'unité', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text('Je révise · Je m\'entraîne · Je crée', style: TextStyle(color: JangColors.textSecondary)),
            ]),
          ),
          const Icon(Icons.chevron_right),
        ]),
      ),
    );
  }

  Widget _canDo() {
    final svc = MissionService.instance;
    final all = widget.course.missions;
    final counts = [0, 0, 0, 0];
    for (final m in all) {
      counts[svc.result(m.id)?.canDo ?? 0]++;
    }
    Widget box(String label, int n, Color bg, Color fg) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text('$n', style: titleStyle(24, color: fg, weight: 800)),
              Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text('Mes « Je sais… »', style: titleStyle(24, weight: 800)),
        const Text('Pas de note. Je dis moi-même ce que je sais.'),
        const SizedBox(height: 10),
        Row(children: [
          box('Tout seul', counts[3], JangColors.successBg, JangColors.successDark),
          box('Avec de l\'aide', counts[2], JangColors.warningBg, const Color(0xFF9A6A00)),
          box('Pas encore', counts[1], JangColors.errorBg, JangColors.errorDark),
        ]),
        for (final u in widget.course.units) ...[
          const SizedBox(height: 14),
          Text(u.title.toUpperCase(),
              style: const TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w800, color: JangColors.textSecondary)),
          for (final m in u.missions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Je sais ${m.canDo}.', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                SegmentedButton<int>(
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1, label: Text('Pas encore', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: 2, label: Text('Avec aide', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: 3, label: Text('Tout seul', style: TextStyle(fontSize: 12))),
                  ],
                  selected: (svc.result(m.id)?.canDo ?? 0) == 0 ? {} : {svc.result(m.id)!.canDo},
                  onSelectionChanged: (v) {
                    if (v.isNotEmpty) svc.setCanDo(m, v.first);
                  },
                ),
              ]),
            ),
        ],
      ],
    );
  }

  Widget _notebook() {
    final svc = MissionService.instance;
    final done = [
      for (final u in widget.course.units)
        for (final m in u.missions)
          if (svc.isDone(m.id)) m,
    ];
    if (done.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Ton carnet se remplit à chaque mission terminée.', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text('Mon carnet', style: titleStyle(24, weight: 800)),
        const Text('Mes mots et mes phrases en anglais.'),
        const SizedBox(height: 10),
        for (final m in done.reversed)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.canDo.toUpperCase(),
                    style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: JangColors.textSecondary)),
                for (final e in m.expressions) Padding(padding: const EdgeInsets.only(top: 4), child: SayText(e)),
                if ((svc.result(m.id)?.phrase ?? '').isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: JangColors.warningBg, borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Expanded(child: Text('Ma phrase : ${svc.result(m.id)!.phrase}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      SayButton(svc.result(m.id)!.phrase, size: 28),
                    ]),
                  ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final w in m.notebook)
                    ActionChip(
                      avatar: const Icon(Icons.volume_up_rounded, size: 16, color: JangColors.primaryDark),
                      label: Text(w),
                      onPressed: () => Speech.instance.say(w),
                    ),
                ]),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        ChunkyButton(
          label: 'Réviser mon carnet',
          icon: Icons.style_outlined,
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => UnitEndScreen.cardsFor(context, widget.course, widget.subject))),
        ),
      ],
    );
  }
}
