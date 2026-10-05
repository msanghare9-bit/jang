import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../services/home_config_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/fun.dart';

/// L'admin modifie l'accueil de l'app : messages, bulles, bannière, blocs.
class HomeConfigScreen extends StatefulWidget {
  const HomeConfigScreen({super.key});

  @override
  State<HomeConfigScreen> createState() => _HomeConfigScreenState();
}

class _HomeConfigScreenState extends State<HomeConfigScreen> {
  static const characters = {
    'gainde': 'Gaïndé',
    'kocc': 'Kocc Barma',
    'awa': 'Awa',
    'modou': 'Modou',
    'doudou': 'Doudou',
  };

  List<Exam> _exams = const [];
  String _examId = '';
  HomeConfig? _config;
  final List<TextEditingController> _welcome = [];
  final List<(String, TextEditingController)> _tips = [];
  final _banner = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  final Map<String, bool> _blocks = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ContentRepo.instance.exams().then((e) {
      if (mounted) setState(() => _exams = e);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _config = null);
    final c = await HomeConfigService.instance.raw(_examId);
    if (!mounted) return;
    setState(() {
      _config = c;
      _welcome
        ..clear()
        ..addAll(c.welcome.map((w) => TextEditingController(text: w)));
      _tips
        ..clear()
        ..addAll(c.tips.map((t) => (t.id, TextEditingController(text: t.text))));
      _banner.text = c.banner?.text ?? '';
      _from = c.banner?.from;
      _to = c.banner?.to;
      _blocks
        ..clear()
        ..addAll({for (final k in HomeConfig.blockNames.keys) k: c.show(k)});
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final c = HomeConfig(
      welcome: _welcome.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList(),
      tips: [for (final (id, c) in _tips) if (c.text.trim().isNotEmpty) HomeTip(id, c.text.trim())],
      banner: HomeBanner(_banner.text.trim(), _from, _to),
      blocks: Map.of(_blocks),
    );
    try {
      await HomeConfigService.instance.save(_examId, c);
      if (mounted) showMessage(context, 'Accueil publié.');
    } catch (e) {
      if (mounted) showMessage(context, 'Échec : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<DateTime?> _date(DateTime? initial) => showDatePicker(
        context: context,
        firstDate: DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDate: initial ?? DateTime.now(),
      );

  String _d(DateTime? d) => d == null ? '—' : '${d.day}/${d.month}/${d.year}';

  void _preview() {
    final welcome = _welcome.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    final tip = _tips.where((t) => t.$2.text.trim().isNotEmpty).toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aperçu', style: titleStyle(20)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: JangColors.primary, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Na nga def, Fatou ?', style: titleStyle(22, color: Colors.white, weight: 800)),
                Text(
                    welcome.isEmpty
                        ? '(message de l\'app)'
                        : HomeConfigService.fill(welcome.first, 'Fatou', 5),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 8),
            if (_banner.text.trim().isNotEmpty && (_blocks['banniere'] ?? true))
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: JangColors.warningBg, borderRadius: BorderRadius.circular(12)),
                child: Text(_banner.text, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            if (tip.isNotEmpty) CharacterSays(tip.first.$1, HomeConfigService.fill(tip.first.$2.text, 'Fatou', 5)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil de l\'app'),
        actions: [TextButton(onPressed: _config == null ? null : _preview, child: const Text('Aperçu'))],
      ),
      body: _config == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const SectionTitle('Pour qui ?'),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  ChoiceChip(
                    label: const Text('Tous les élèves'),
                    selected: _examId.isEmpty,
                    onSelected: (_) {
                      _examId = '';
                      _load();
                    },
                  ),
                  for (final e in _exams)
                    ChoiceChip(
                      label: Text(e.name),
                      selected: _examId == e.id,
                      onSelected: (_) {
                        _examId = e.id;
                        _load();
                      },
                    ),
                ]),
                const SizedBox(height: 4),
                Text(
                    _examId.isEmpty
                        ? 'Ce que tu règles ici vaut pour tous les niveaux.'
                        : 'Ce que tu remplis ici remplace, pour ce niveau, ce qui est réglé pour tous.',
                    style: t.bodySmall),
                const SectionTitle('Messages de bienvenue'),
                Text('L\'app en choisit un au hasard. Tu peux écrire {prénom} et {jours}.', style: t.bodySmall),
                for (var i = 0; i < _welcome.length; i++)
                  Row(children: [
                    Expanded(child: TextField(controller: _welcome[i], maxLength: 120)),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _welcome.removeAt(i))),
                  ]),
                TextButton.icon(
                  onPressed: () => setState(() => _welcome.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un message'),
                ),
                const SectionTitle('Bulles des personnages'),
                for (var i = 0; i < _tips.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                      child: Column(children: [
                        Row(children: [
                          DropdownButton<String>(
                            value: _tips[i].$1,
                            items: [
                              for (final e in characters.entries)
                                DropdownMenuItem(value: e.key, child: Text(e.value)),
                            ],
                            onChanged: (v) => setState(() => _tips[i] = (v!, _tips[i].$2)),
                          ),
                          const Spacer(),
                          IconButton(
                              icon: const Icon(Icons.close), onPressed: () => setState(() => _tips.removeAt(i))),
                        ]),
                        TextField(controller: _tips[i].$2, maxLines: 2, maxLength: 160),
                      ]),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => setState(() => _tips.add(('gainde', TextEditingController()))),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une bulle'),
                ),
                const SectionTitle('Bannière du moment'),
                TextField(
                  controller: _banner,
                  maxLines: 2,
                  maxLength: 140,
                  decoration: const InputDecoration(hintText: 'Ex. : Tabaski : ton mouton aussi fait la fête !'),
                ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await _date(_from);
                        if (d != null) setState(() => _from = d);
                      },
                      child: Text('Du ${_d(_from)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await _date(_to);
                        if (d != null) setState(() => _to = d);
                      },
                      child: Text('Au ${_d(_to)}'),
                    ),
                  ),
                ]),
                const SectionTitle('Blocs affichés'),
                for (final e in HomeConfig.blockNames.entries)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.value),
                    value: _blocks[e.key] ?? true,
                    onChanged: (v) => setState(() => _blocks[e.key] = v),
                  ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Publication…' : 'Publier')),
              ],
            ),
    );
  }
}
