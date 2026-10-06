import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/mission_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/jang_ui.dart';
import '../mission/mission_screen.dart';

/// Éditeur d'une mission (format de contenus/missions.json).
/// Sert pour les missions officielles (admin) et les missions des profs.
class MissionEditorScreen extends StatefulWidget {
  /// La mission à modifier (une copie est modifiée ; l'original ne change pas).
  final Map<String, dynamic> initial;

  /// Titre de l'écran.
  final String title;

  /// Appelé avec la mission modifiée quand on appuie sur « Enregistrer ».
  final Future<void> Function(Map<String, dynamic> mission) onSave;

  /// Matière utilisée pour « Essayer » (bouton caché si null).
  final Subject? subject;
  const MissionEditorScreen({
    super.key,
    required this.initial,
    required this.onSave,
    this.title = 'Modifier la mission',
    this.subject,
  });

  /// Une mission vide, prête à remplir.
  static Map<String, dynamic> blank(String id) => {
        'id': id,
        'titre': '',
        'jesais': '',
        'expressions': <String>[],
        'mots': {'consigne': 'Quels mots vont avec l\'image ?', 'fond': 'classe', 'objets': <String>[], 'liste': <Map>[]},
        'scene': {'fond': 'classe', 'persos': ['awa', 'modou', 'gainde'], 'repliques': <Map>[], 'gainde': ''},
        'questions': <Map>[],
        'marches': <Map>[],
        'pourdevrai': <Map>[],
        'carnet': <String>[],
      };

  @override
  State<MissionEditorScreen> createState() => _MissionEditorScreenState();
}

/// Copie profonde (les listes et les tables sont recopiées).
dynamic _copy(dynamic v) {
  if (v is Map) return <String, dynamic>{for (final e in v.entries) '${e.key}': _copy(e.value)};
  if (v is List) return [for (final x in v) _copy(x)];
  return v;
}

String _str(dynamic v) => v is String ? v : (v == null ? '' : '$v');
int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : d;

class _MissionEditorScreenState extends State<MissionEditorScreen> {
  static const backgrounds = {
    'cour': 'La cour',
    'classe': 'La classe',
    'maison': 'La maison',
    'marche': 'Le marché',
    'mer': 'La mer',
    'nuit': 'La nuit',
    'plage': 'La plage',
    'terrain': 'Le terrain',
    'bibliotheque': 'La bibliothèque',
  };

  static const characters = {
    'gainde': 'Gaïndé',
    'awa': 'Awa',
    'modou': 'Modou',
    'doudou': 'Doudou',
    'kocc': 'Kocc Barma (le prof)',
    'mouton': 'Le mouton',
    'bouc': 'Le bouc',
  };

  static const stepTypes = {
    'choix': 'Choisir la bonne phrase',
    'ordre': 'Remettre les mots dans l\'ordre',
    'trou': 'Compléter le trou',
    'libre': 'Écrire tout seul',
  };

  late final Map<String, dynamic> _m;
  bool _dirty = false;
  bool _saving = false;

  /// Change quand on ajoute ou supprime une ligne : les champs se recréent avec les bonnes valeurs.
  int _gen = 0;

  /// Les parties ouvertes (elles restent ouvertes quand on fait défiler l'écran).
  final Set<String> _opened = {'L\'essentiel'};

  @override
  void initState() {
    super.initState();
    _m = Map<String, dynamic>.from(_copy(widget.initial) as Map);
    for (final st in _lmap(_m, 'marches')) {
      _normAides(st);
    }
  }

  // ---------------- Accès aux données ----------------

  Map<String, dynamic> _map(Map<String, dynamic> parent, String key) {
    final v = parent[key];
    if (v is Map<String, dynamic>) return v;
    final m = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    parent[key] = m;
    return m;
  }

  List<dynamic> _list(Map<String, dynamic> parent, String key) {
    final v = parent[key];
    if (v is List<dynamic>) return v;
    final l = <dynamic>[];
    parent[key] = l;
    return l;
  }

  /// Les lignes d'une liste (chaque ligne est une table).
  List<Map<String, dynamic>> _lmap(Map<String, dynamic> parent, String key) {
    final l = _list(parent, key);
    for (var i = 0; i < l.length; i++) {
      if (l[i] is! Map<String, dynamic>) l[i] = l[i] is Map ? Map<String, dynamic>.from(l[i] as Map) : <String, dynamic>{};
    }
    return l.cast<Map<String, dynamic>>();
  }

  /// Les 4 aides de Kocc Barma : question, {rejouer, texte}, modèle, sens.
  void _normAides(Map<String, dynamic> st) {
    final old = st['aides'] is List ? st['aides'] as List : const [];
    String s(int i) {
      if (i >= old.length) return '';
      final h = old[i];
      return h is Map ? _str(h['texte']) : _str(h);
    }

    final h1 = old.length > 1 ? old[1] : null;
    st['aides'] = <dynamic>[
      s(0),
      <String, dynamic>{'rejouer': h1 is Map ? _int(h1['rejouer'], -1) : -1, 'texte': s(1)},
      s(2),
      s(3),
    ];
  }

  /// Une marche d'un type : on ajoute les champs qui manquent.
  void _ensureStep(Map<String, dynamic> st) {
    switch (st['type']) {
      case 'choix':
        _list(st, 'options');
        st['reponse'] = _int(st['reponse']);
      case 'ordre':
        _list(st, 'tuiles');
        st['cible'] = _str(st['cible']);
        st['dit'] = _str(st['dit']);
      case 'trou':
        st['avant'] = _str(st['avant']);
        st['apres'] = _str(st['apres']);
        _list(st, 'accepte');
        st['dit'] = _str(st['dit']);
      case 'libre':
        _list(st, 'cles');
    }
    st['gainde'] = _str(st['gainde']);
    _normAides(st);
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// Changement de structure (ajout, suppression, liste déroulante).
  void _change(VoidCallback f) {
    setState(() {
      f();
      _dirty = true;
      _gen++;
    });
  }

  List<String> _replicas() => [
        for (final l in _lmap(_map(_m, 'scene'), 'repliques'))
          '${characters[_str(l['qui'])]?.split(' ').first ?? _str(l['qui'])} : ${_str(l['en'])}',
      ];

  // ---------------- Petits widgets ----------------

  Widget _text(String path, String label, String value, ValueChanged<String> onChanged,
      {int lines = 1, String? help}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: ValueKey('$_gen/$path'),
        initialValue: value,
        minLines: lines,
        maxLines: lines > 1 ? null : 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, helperText: help, helperMaxLines: 4),
        onChanged: (v) {
          onChanged(v);
          _touch();
        },
      ),
    );
  }

  /// Champ « une ligne = un élément » pour une liste de textes.
  Widget _lines(String path, String label, Map<String, dynamic> parent, String key, {String? help}) {
    final list = _list(parent, key);
    return _text(path, label, list.map(_str).join('\n'), (v) {
      list
        ..clear()
        ..addAll(v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty));
    }, lines: 3, help: help ?? 'Une par ligne.');
  }

  Widget _choice<T>(String label, T value, Map<T, String> items, ValueChanged<T> onChanged) {
    final all = {...items, if (!items.containsKey(value)) value: '$value'};
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            items: [
              for (final e in all.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v != null) _change(() => onChanged(v));
            },
          ),
        ),
      ),
    );
  }

  Widget _who(String label, Map<String, dynamic> item) =>
      _choice<String>(label, _str(item['qui']).isEmpty ? 'gainde' : _str(item['qui']), characters,
          (v) => item['qui'] = v);

  Widget _background(String label, Map<String, dynamic> parent) =>
      _choice<String>(label, _str(parent['fond']).isEmpty ? 'classe' : _str(parent['fond']), backgrounds,
          (v) => parent['fond'] = v);

  Widget _replay(String label, Map<String, dynamic> item) {
    final r = _replicas();
    return _choice<int>(label, _int(item['rejouer'], -1), {
      -1: 'Aucune',
      for (var i = 0; i < r.length; i++) i: '${i + 1}. ${r[i]}',
    }, (v) => item['rejouer'] = v);
  }

  Widget _addButton(String label, VoidCallback onTap) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          child: OutlinedButton.icon(onPressed: onTap, icon: const Icon(Icons.add), label: Text(label)),
        ),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: JangColors.noteBg, borderRadius: BorderRadius.circular(12)),
          child: Text(text, style: const TextStyle(fontSize: 14)),
        ),
      );

  /// Une ligne d'une liste (mot, réplique, question…), avec son bouton pour la supprimer.
  Widget _item(String title, VoidCallback onDelete, List<Widget> children, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 2, 4, 4),
        decoration: BoxDecoration(
          border: Border.all(color: JangColors.border, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: titleStyle(16, color: color ?? JangColors.text))),
            IconButton(tooltip: 'Supprimer', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
          ]),
          Padding(padding: const EdgeInsets.only(right: 8), child: Column(children: children)),
        ]),
      ),
    );
  }

  /// Les réponses proposées, avec la bonne réponse cochée.
  Widget _options(String path, Map<String, dynamic> item) {
    final opts = _list(item, 'options');
    final answer = _int(item['reponse']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('Réponses proposées (touche le rond pour choisir la bonne) :',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      for (var j = 0; j < opts.length; j++)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconButton(
            tooltip: 'C\'est la bonne réponse',
            onPressed: () => _change(() => item['reponse'] = j),
            icon: Icon(j == answer ? Icons.check_circle : Icons.radio_button_unchecked,
                color: j == answer ? JangColors.success : JangColors.textSecondary),
          ),
          Expanded(child: _text('$path/o$j', 'Réponse ${j + 1}', _str(opts[j]), (v) => opts[j] = v)),
          IconButton(
            tooltip: 'Supprimer',
            onPressed: () => _change(() {
              opts.removeAt(j);
              if (answer == j) {
                item['reponse'] = 0;
              } else if (answer > j) {
                item['reponse'] = answer - 1;
              }
            }),
            icon: const Icon(Icons.close),
          ),
        ]),
      _addButton('Ajouter une réponse', () => _change(() => opts.add(''))),
    ]);
  }

  // ---------------- Les parties ----------------

  Widget _section(String title, String subtitle, IconData icon, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: ValueKey('section/$title'),
          initiallyExpanded: _opened.contains(title),
          onExpansionChanged: (on) => on ? _opened.add(title) : _opened.remove(title),
          leading: Icon(icon, color: JangColors.primary),
          title: Text(title, style: titleStyle(17)),
          subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _basics() {
    final id = _str(_m['id']);
    return _section('L\'essentiel', 'Titre, « Je sais… », expressions', Icons.flag_outlined, [
      if (id.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Code de la mission : $id', style: Theme.of(context).textTheme.bodySmall),
        ),
      _text('titre', 'Titre de la mission', _str(_m['titre']), (v) => _m['titre'] = v),
      _text('jesais', 'Je sais…', _str(_m['jesais']), (v) => _m['jesais'] = v,
          help: 'Ce que l\'élève sait faire à la fin. Exemple : dire bonjour à un ami'),
      _lines('expressions', 'Expressions en anglais', _m, 'expressions',
          help: 'Une expression par ligne. Exemple : How are you?'),
    ]);
  }

  Widget _words() {
    final mots = _map(_m, 'mots');
    final list = _lmap(mots, 'liste');
    return _section('Temps 0 · Mes mots', '${list.length} mot${list.length > 1 ? 's' : ''}', Icons.image_outlined, [
      _text('mots/consigne', 'Consigne', _str(mots['consigne']), (v) => mots['consigne'] = v),
      _background('Le fond de l\'image', mots),
      _text('mots/objets', 'Les objets (emojis)', _list(mots, 'objets').map(_str).join(' '), (v) {
        _list(mots, 'objets')
          ..clear()
          ..addAll(v.split(RegExp(r'\s+')).where((e) => e.isNotEmpty));
      }, help: '3 ou 4 emojis, séparés par un espace. Exemple : 🏫 🌳 ⚽'),
      _note('Mets 4 ou 5 bons mots (on les voit sur l\'image) et 2 ou 3 pièges.'),
      for (var i = 0; i < list.length; i++)
        _item('Mot ${i + 1}', () => _change(() => list.removeAt(i)), [
          _text('mots/$i/mot', 'Le mot en anglais', _str(list[i]['mot']), (v) => list[i]['mot'] = v),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Bon mot'), icon: Icon(Icons.check)),
                ButtonSegment(value: false, label: Text('Piège'), icon: Icon(Icons.close)),
              ],
              selected: {list[i]['ok'] == true},
              onSelectionChanged: (s) => _change(() => list[i]['ok'] = s.first),
            ),
          ),
          _text('mots/$i/pourquoi', 'Explication', _str(list[i]['pourquoi']), (v) => list[i]['pourquoi'] = v,
              lines: 2, help: 'Exemple : Oui ! « Tree », c\'est l\'arbre de la cour.'),
        ]),
      _addButton('Ajouter un mot', () => _change(() => list.add(<String, dynamic>{'mot': '', 'ok': true, 'pourquoi': ''}))),
    ]);
  }

  Widget _scene() {
    final scene = _map(_m, 'scene');
    final persos = _list(scene, 'persos');
    final lines = _lmap(scene, 'repliques');
    return _section('Temps 1 · La scène', '${lines.length} réplique${lines.length > 1 ? 's' : ''}',
        Icons.theater_comedy_outlined, [
      _background('Le fond', scene),
      Text('Les personnages sur la scène :', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in characters.entries)
          FilterChip(
            label: Text(e.value.split(' (').first),
            selected: persos.contains(e.key),
            onSelected: (on) => _change(() => on ? persos.add(e.key) : persos.remove(e.key)),
          ),
      ]),
      const SizedBox(height: 14),
      _note('3 ou 4 répliques courtes. Il en faut au moins 2.'),
      for (var i = 0; i < lines.length; i++)
        _item('Réplique ${i + 1}', () => _change(() => lines.removeAt(i)), [
          _who('Qui parle ?', lines[i]),
          _text('scene/$i/en', 'En anglais', _str(lines[i]['en']), (v) => lines[i]['en'] = v),
          _text('scene/$i/fr', 'En français', _str(lines[i]['fr']), (v) => lines[i]['fr'] = v),
        ]),
      _addButton('Ajouter une réplique',
          () => _change(() => lines.add(<String, dynamic>{'qui': persos.isNotEmpty ? persos.first : 'awa', 'en': '', 'fr': ''}))),
      _text('scene/gainde', 'Ce que se demande Gaïndé', _str(scene['gainde']), (v) => scene['gainde'] = v,
          lines: 2, help: 'Après la scène. Curieux et drôle !'),
    ]);
  }

  Widget _questions() {
    final qs = _lmap(_m, 'questions');
    return _section('Temps 2 · Je comprends', '${qs.length} question${qs.length > 1 ? 's' : ''}',
        Icons.help_outline, [
      _note('2 questions, avec 3 réponses. « Réplique à réécouter » : celle qui aide à répondre.'),
      for (var i = 0; i < qs.length; i++)
        _item('Question ${i + 1}', () => _change(() => qs.removeAt(i)), [
          _text('q/$i/question', 'La question', _str(qs[i]['question']), (v) => qs[i]['question'] = v),
          _options('q/$i', qs[i]),
          _replay('Réplique à réécouter', qs[i]),
        ]),
      _addButton('Ajouter une question',
          () => _change(() => qs.add(<String, dynamic>{'question': '', 'options': <dynamic>['', '', ''], 'reponse': 0, 'rejouer': -1}))),
    ]);
  }

  Future<void> _addStep(List<Map<String, dynamic>> steps) async {
    final type = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Quelle marche ?', style: titleStyle(20)),
        children: [
          for (final e in stepTypes.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, e.key),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(e.value)),
            ),
        ],
      ),
    );
    if (type == null) return;
    _change(() {
      final st = <String, dynamic>{'type': type};
      _ensureStep(st);
      steps.add(st);
    });
  }

  Widget _stepFields(int i, Map<String, dynamic> st) {
    final p = 'm/$i';
    switch (st['type']) {
      case 'choix':
        return _options(p, st);
      case 'ordre':
        return Column(children: [
          _lines('$p/tuiles', 'Les tuiles (les mots mélangés)', st, 'tuiles',
              help: 'Un mot par ligne, dans le désordre.'),
          _text('$p/cible', 'La phrase juste, sans ponctuation', _str(st['cible']), (v) => st['cible'] = v,
              help: 'Exemple : How are you'),
          _text('$p/dit', 'La phrase écrite', _str(st['dit']), (v) => st['dit'] = v,
              help: 'Avec la ponctuation. Exemple : How are you?'),
        ]);
      case 'trou':
        return Column(children: [
          _text('$p/avant', 'Avant le trou', _str(st['avant']), (v) => st['avant'] = v),
          _text('$p/apres', 'Après le trou', _str(st['apres']), (v) => st['apres'] = v),
          _lines('$p/accepte', 'Les bonnes réponses', st, 'accepte',
              help: 'Toutes les réponses justes, une par ligne.'),
          _text('$p/dit', 'La phrase entière', _str(st['dit']), (v) => st['dit'] = v),
        ]);
      case 'libre':
        return _keys('$p/cles', st);
    }
    return const SizedBox.shrink();
  }

  Widget _keys(String path, Map<String, dynamic> item) => Column(children: [
        _note('Les clés : les mots que la réponse doit avoir. Mets un groupe par ligne. '
            'Dans une ligne, « a|b » veut dire « a ou b ». Exemple : hello|hi'),
        _lines(path, 'Les clés', item, 'cles', help: 'Un groupe par ligne. Mots courts et sûrs.'),
      ]);

  Widget _aides(int i, Map<String, dynamic> st) {
    final a = _list(st, 'aides');
    final h1 = a[1] as Map<String, dynamic>;
    final p = 'm/$i/aide';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      Text('Les 4 aides de Kocc Barma', style: titleStyle(15)),
      const SizedBox(height: 4),
      Text('Il les donne une par une. Ne donne jamais la réponse avant l\'aide 3.',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      _text('$p/0', '1. Une question pour réfléchir', _str(a[0]), (v) => a[0] = v, lines: 2),
      _replay('2. Réplique à réécouter', h1),
      _text('$p/1', '2. Ce qu\'il dit avant de la rejouer', _str(h1['texte']), (v) => h1['texte'] = v,
          help: 'Exemple : Écoute Modou :'),
      _text('$p/2', '3. Le modèle', _str(a[2]), (v) => a[2] = v,
          lines: 2, help: 'Exemple : Moi, je dis : « Hi, Gaïndé! »'),
      _text('$p/3', '4. Le sens', _str(a[3]), (v) => a[3] = v, lines: 2, help: 'Ce que ça veut dire, en français.'),
    ]);
  }

  Widget _steps() {
    final steps = _lmap(_m, 'marches');
    for (final st in steps) {
      _ensureStep(st);
    }
    return _section('Temps 3 · J\'aide Gaïndé', '${steps.length} marche${steps.length > 1 ? 's' : ''}',
        Icons.stairs_outlined, [
      _note('Il faut 4 marches, dans cet ordre : choisir, remettre dans l\'ordre, compléter, écrire tout seul. '
          'Gaïndé se trompe, et l\'élève l\'aide.'),
      for (var i = 0; i < steps.length; i++)
        _item('Marche ${i + 1} · ${stepTypes[steps[i]['type']] ?? _str(steps[i]['type'])}', () async {
          if (await confirm(context, 'Supprimer la marche ${i + 1} ?', 'Ses aides seront aussi supprimées.',
              ok: 'Supprimer')) {
            _change(() => steps.removeAt(i));
          }
        }, [
          _choice<String>('Type de marche', _str(steps[i]['type']), stepTypes, (v) {
            steps[i]['type'] = v;
            _ensureStep(steps[i]);
          }),
          _text('m/$i/gainde', 'Ce que dit Gaïndé (il se trompe)', _str(steps[i]['gainde']),
              (v) => steps[i]['gainde'] = v, lines: 2),
          _stepFields(i, steps[i]),
          _aides(i, steps[i]),
        ], color: JangColors.primaryDark),
      _addButton('Ajouter une marche', () => _addStep(steps)),
    ]);
  }

  Widget _turns() {
    final turns = _lmap(_m, 'pourdevrai');
    return _section('Temps 4 · Pour de vrai', '${turns.length} tour${turns.length > 1 ? 's' : ''} de parole',
        Icons.mic_none, [
      _note('Un personnage parle à l\'élève, et l\'élève lui répond pour de vrai. 1 ou 2 tours.'),
      for (var i = 0; i < turns.length; i++)
        _item('Tour ${i + 1}', () => _change(() => turns.removeAt(i)), [
          _who('Qui parle ?', turns[i]),
          _text('t/$i/en', 'Ce qu\'il dit en anglais', _str(turns[i]['en']), (v) => turns[i]['en'] = v),
          _text('t/$i/fr', 'En français', _str(turns[i]['fr']), (v) => turns[i]['fr'] = v),
          _keys('t/$i/cles', turns[i]),
          _text('t/$i/modele', 'Une bonne réponse (le modèle)', _str(turns[i]['modele']),
              (v) => turns[i]['modele'] = v, help: 'Elle doit contenir les clés.'),
          _text('t/$i/reponse', 'Ce qu\'il répond après', _str(turns[i]['reponse']),
              (v) => turns[i]['reponse'] = v),
        ]),
      _addButton(
          'Ajouter un tour',
          () => _change(() => turns
              .add(<String, dynamic>{'qui': 'gainde', 'en': '', 'fr': '', 'cles': <dynamic>[], 'modele': '', 'reponse': ''}))),
    ]);
  }

  Widget _notebook() {
    final n = _list(_m, 'carnet').length;
    return _section('Temps 5 · Le carnet', '$n expression${n > 1 ? 's' : ''} à garder', Icons.menu_book_outlined, [
      _lines('carnet', 'Les expressions à garder', _m, 'carnet', help: '2 à 5 expressions, une par ligne.'),
    ]);
  }

  // ---------------- Vérifier, essayer, enregistrer ----------------

  String? _validate() {
    if (_str(_m['titre']).trim().isEmpty) return 'Écris le titre de la mission (partie « L\'essentiel »).';
    final lines = _lmap(_map(_m, 'scene'), 'repliques');
    if (lines.length < 2) return 'La scène doit avoir au moins 2 répliques (partie « La scène »).';
    for (var i = 0; i < lines.length; i++) {
      if (_str(lines[i]['en']).trim().isEmpty) return 'La scène, réplique ${i + 1} : écris la phrase en anglais.';
    }
    String? options(Map<String, dynamic> item, String where) {
      final opts = _list(item, 'options');
      if (opts.where((o) => _str(o).trim().isNotEmpty).length < 2) return '$where : écris au moins 2 réponses.';
      final a = _int(item['reponse']);
      if (a < 0 || a >= opts.length || _str(opts[a]).trim().isEmpty) {
        return '$where : choisis la bonne réponse (touche le rond).';
      }
      return null;
    }

    final qs = _lmap(_m, 'questions');
    for (var i = 0; i < qs.length; i++) {
      final e = options(qs[i], 'Question ${i + 1}');
      if (e != null) return e;
    }
    final steps = _lmap(_m, 'marches');
    for (var i = 0; i < steps.length; i++) {
      if (steps[i]['type'] == 'choix') {
        final e = options(steps[i], 'Marche ${i + 1}');
        if (e != null) return e;
      }
    }
    return null;
  }

  /// La mission telle qu'elle sera enregistrée.
  Map<String, dynamic> _result() {
    final m = Map<String, dynamic>.from(_copy(_m) as Map);
    if (_str(m['histoire']).trim().isEmpty) m['histoire'] = _str(m['titre']);
    return m;
  }

  Future<void> _try() async {
    final error = _validate();
    if (error != null) {
      showMessage(context, error);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MissionScreen(mission: Mission.fromMap(_result()), subject: widget.subject!)),
    );
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      showMessage(context, error);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(_result());
    } catch (e) {
      debugPrint('Enregistrement de la mission : $e');
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Enregistrement impossible. Vérifie ta connexion, puis réessaie.');
      }
      return;
    }
    if (!mounted) return;
    showMessage(context, 'Mission enregistrée.');
    _leave();
  }

  void _leave() {
    setState(() => _dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirm(context, 'Quitter sans enregistrer ?',
            'Les modifications de cette mission seront perdues.',
            ok: 'Quitter');
        if (leave && context.mounted) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (widget.subject != null)
              IconButton(tooltip: 'Essayer', onPressed: _try, icon: const Icon(Icons.play_circle_outline)),
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
              )
            else
              TextButton(onPressed: _save, child: const Text('Enregistrer')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
          children: [
            _note('Touche une partie pour l\'ouvrir. Quand tu as fini, appuie sur « Enregistrer ».'),
            _basics(),
            _words(),
            _scene(),
            _questions(),
            _steps(),
            _turns(),
            _notebook(),
            if (widget.subject != null) ...[
              const SizedBox(height: 10),
              ChunkyButton(
                label: 'Essayer la mission',
                icon: Icons.play_arrow,
                color: JangColors.primary,
                onPressed: _try,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
