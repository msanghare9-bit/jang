import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/sheep_service.dart';
import '../theme.dart';
import '../widgets/characters.dart';
import '../widgets/jang_ui.dart';

/// Carte « Mon mouton » de l'accueil (remplace la plante).
class SheepCard extends StatelessWidget {
  const SheepCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SheepService.instance;
    return ValueListenableBuilder(
      valueListenable: s.revision,
      builder: (context, _, __) {
        final p = AuthService.instance.profile.value;
        final name = (p?.sheepName ?? '').trim();
        final next = s.nextStage;
        final title = name.isEmpty ? 'Ton mouton' : name;
        final sub = s.hungry
            ? 'Ton mouton a faim ! Une mission pour le nourrir ?'
            : next == null
                ? 'C\'est un Ladoum champion !'
                : 'Encore ${next.from - s.total} mission${next.from - s.total > 1 ? 's' : ''} pour qu\'il grandisse.';
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SheepScreen())),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFE2A0), width: 2),
            ),
            child: Row(children: [
              SheepView(size: 64, total: s.total),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: titleStyle(19, weight: 800)),
                  Text('${s.stage.name} · ${s.total} mission${s.total > 1 ? 's' : ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: Color(0xFFB07A00), fontSize: 13)),
                  Text(sub, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFB07A00)),
            ]),
          ),
        );
      },
    );
  }
}

/// Le mouton dessiné à la taille de son étape.
class SheepView extends StatelessWidget {
  final double size;
  final int total;
  final Moves moves;
  const SheepView({super.key, required this.size, required this.total, this.moves = Moves.bob});

  @override
  Widget build(BuildContext context) {
    final stage = SheepService.stages.lastWhere((s) => total >= s.from);
    return SizedBox(
      width: size,
      height: size,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: CharacterView(Chars.mouton, size: size * stage.scale, moves: moves),
      ),
    );
  }
}

class SheepScreen extends StatefulWidget {
  const SheepScreen({super.key});

  @override
  State<SheepScreen> createState() => _SheepScreenState();
}

class _SheepScreenState extends State<SheepScreen> {
  late final Future<(SheepRival?, SheepRival?)> _rivals = SheepService.instance.rivals();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!hasSheepName(AuthService.instance.profile.value)) _askName();
    });
  }

  Future<void> _askName() async {
    final c = TextEditingController(text: AuthService.instance.profile.value?.sheepName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Donne un nom à ton mouton', style: titleStyle(20)),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 20,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Ex. : Ndiambour, Gaal, Ladoum…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Plus tard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('C\'est son nom')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await SheepService.instance.rename(name);
  }

  @override
  Widget build(BuildContext context) {
    final s = SheepService.instance;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon mouton')),
      body: ValueListenableBuilder(
        valueListenable: s.revision,
        builder: (context, _, __) {
          final p = AuthService.instance.profile.value;
          final name = (p?.sheepName ?? '').trim();
          final next = s.nextStage;
          final from = s.stage.from;
          final pct = next == null ? 1.0 : (s.total - from) / (next.from - from);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E6),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFFFE2A0), width: 2),
                ),
                child: Column(children: [
                  GestureDetector(
                    onTap: _askName,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(name.isEmpty ? 'Ton mouton' : name, style: titleStyle(28, weight: 800)),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit, size: 18, color: Color(0xFFB07A00)),
                    ]),
                  ),
                  Text('${s.stage.name} · ${s.total} mission${s.total > 1 ? 's' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB07A00))),
                  SheepView(size: 190, total: s.total, moves: s.hungry ? Moves.sway : Moves.jump),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      minHeight: 12,
                      color: JangColors.ocre,
                      backgroundColor: const Color(0xFFFFE9B0),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      next == null
                          ? 'Ton mouton est un Ladoum champion. Bravo !'
                          : 'Encore ${next.from - s.total} mission${next.from - s.total > 1 ? 's' : ''} pour devenir « ${next.name} ».',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium),
                  if (s.hungry) ...[
                    const SizedBox(height: 6),
                    const Text('Ton mouton a faim ! Fais une mission pour le nourrir.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w800, color: JangColors.errorDark)),
                  ],
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                for (final st in SheepService.stages)
                  Expanded(
                    child: Opacity(
                      opacity: s.total >= st.from ? 1 : 0.35,
                      child: Column(children: [
                        SheepView(size: 54, total: st.from, moves: Moves.still),
                        Text(st.name.split(' ').first,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
              FutureBuilder<(SheepRival?, SheepRival?)>(
                future: _rivals,
                builder: (context, snap) {
                  final ahead = snap.data?.$1;
                  final behind = snap.data?.$2;
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (ahead != null)
                      _Note(
                        color: JangColors.noteBg,
                        text: 'Le mouton de ${ahead.name} a grandi plus vite cette semaine ! On le rattrape ?',
                      ),
                    if (behind != null)
                      _Note(
                        color: JangColors.successBg,
                        text: 'Bravo ! Ton mouton a dépassé celui de ${behind.name} cette semaine.',
                      ),
                  ]);
                },
              ),
              const SizedBox(height: 8),
              Text('Ses accessoires', style: titleStyle(18, weight: 800)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var i = 0; i < SheepService.accessories.length; i++)
                  Chip(
                    label: Text(i < s.accessoriesWon
                        ? SheepService.accessories[i]
                        : '${SheepService.accessories[i]} · ${(i + 1) * 6} missions'),
                    backgroundColor: i < s.accessoriesWon ? JangColors.noteBg : null,
                  ),
              ]),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: !(p?.hideName ?? false),
                onChanged: (v) async {
                  await SheepService.instance.setHideName(!v);
                  if (mounted) setState(() {});
                },
                title: const Text('Les autres élèves voient mon prénom'),
                subtitle: const Text('Sinon, ils voient « un élève de ta classe ».'),
              ),
              const SizedBox(height: 8),
              ChunkyButton(label: 'Une mission pour mon mouton', onPressed: () => Navigator.pop(context)),
            ],
          );
        },
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final Color color;
  final String text;
  const _Note({required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const CharacterView(Chars.mouton, size: 40, moves: Moves.still),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
      );
}

/// Utilisé par les écrans qui terminent une mission ou une leçon.
Future<void> feedSheep() => SheepService.instance.feed();
