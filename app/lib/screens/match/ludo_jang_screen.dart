import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/quiz_bank.dart';
import '../../theme.dart';
import '../../widgets/jang_ui.dart';

/// A Ludo game whose moves are earned by answering English questions.
class LudoJangScreen extends StatefulWidget {
  const LudoJangScreen({super.key});

  @override
  State<LudoJangScreen> createState() => _LudoJangScreenState();
}

class _LudoJangScreenState extends State<LudoJangScreen> {
  static const _domains = <String>[
    'vocabulaire',
    'francais_anglais',
    'anglais_francais',
    'grammaire',
    'synonymes',
    'antonymes',
  ];
  static const _playerColors = <Color>[
    Color(0xFF00853F),
    Color(0xFFE31B23),
    Color(0xFF1565C0),
    Color(0xFFF5A623),
  ];

  String _level = 'debutant';
  final Set<String> _selectedDomains = {..._domains};
  int _playerCount = 2;
  bool _busy = false;
  bool _onlineMode = false;
  bool _onlineReady = false;
  String? _roomId;
  String? _roomCode;
  List<String> _roomUids = [];
  List<String> _roomNames = [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSub;
  final _roomCodeController = TextEditingController();
  List<BankQuestion> _questions = const [];
  int _questionIndex = 0;
  int _turn = 0;
  late List<int> _streaks;
  int _die = 0;
  int? _rollingPlayer;
  String? _message;
  bool _done = false;
  bool _shieldAvailable = false;
  late List<List<int>> _pawns;
  late List<Set<int>> _shieldedPawns;

  @override
  void initState() {
    super.initState();
    _pawns = List.generate(4, (_) => [-1, -1]);
    _shieldedPawns = List.generate(4, (_) => <int>{});
    _streaks = List.filled(4, 0);
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _roomCodeController.dispose();
    super.dispose();
  }

  BankQuestion get _question => _questions[_questionIndex % _questions.length];
  bool get _playing => _questions.isNotEmpty && !_done;
  bool get _canAct {
    if (!_onlineMode) return true;
    final uid = AuthService.instance.profile.value?.uid;
    return uid != null && _turn < _roomUids.length && _roomUids[_turn] == uid;
  }

  Future<void> _showRulesIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'ludo_jang_games_started';
    final started = prefs.getInt(key) ?? 0;
    if (started >= 3 || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Comment jouer ? (${started + 1}/3)'),
        content: const SingleChildScrollView(
          child: Text(
            'Répondez à une question pour lancer le dé. Une bonne réponse vous permet de déplacer un pion du nombre de cases indiqué. Il faut obtenir 6 pour sortir un pion.\n\n'
            'Une mauvaise réponse passe le tour au joueur suivant. Les cases sûres empêchent les captures. Cinq bonnes réponses d’affilée donnent un bouclier pour protéger un pion pendant un tour.\n\n'
            'Le premier joueur qui amène ses deux pions à l’arrivée gagne.',
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('C’est compris')),
        ],
      ),
    );
    await prefs.setInt(key, started + 1);
  }

  Future<void> _start() async {
    if (_selectedDomains.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez au moins une catégorie.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final questions = await QuizBank.instance.drawDomains(
        _selectedDomains.toList(), _level, 80,
      );
      if (!mounted) return;
      if (questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Questions indisponibles. Vérifiez votre connexion puis réessayez.')),
        );
        return;
      }
      await _showRulesIfNeeded();
      if (!mounted) return;
      if (_onlineMode) {
        await _createOnlineRoom(questions);
      } else {
        _resetGame(questions, _playerCount);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de créer la partie. Vérifiez votre connexion et réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetGame(List<BankQuestion> questions, int players) {
    setState(() {
      _questions = questions;
      _playerCount = players;
      _questionIndex = 0;
      _turn = 0;
      _streaks = List.filled(players, 0);
      _die = 0;
      _rollingPlayer = null;
      _message = 'Au tour du joueur 1';
      _done = false;
      _shieldAvailable = false;
      _pawns = List.generate(players, (_) => [-1, -1]);
      _shieldedPawns = List.generate(players, (_) => <int>{});
    });
  }

  Future<String> _newRoomCode() async {
    final games = FirebaseFirestore.instance.collection('ludoGames');
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = (100000 + Random().nextInt(900000)).toString();
      final existing = await games.doc(code).get();
      if (!existing.exists) return code;
    }
    throw StateError('Impossible de créer un code. Réessayez.');
  }

  Future<void> _createOnlineRoom(List<BankQuestion> questions) async {
    final profile = AuthService.instance.profile.value;
    if (profile == null) return;
    final code = await _newRoomCode();
    final ref = FirebaseFirestore.instance.collection('ludoGames').doc(code);
    const players = 2;
    final initialPawns = List.generate(players, (_) => [-1, -1]);
    await ref.set({
      'code': code,
      'hostUid': profile.uid,
      'status': 'waiting',
      'playerUids': [profile.uid],
      'playerNames': [profile.publicName],
      'level': _level,
      'domains': _selectedDomains.toList(),
      'questions': [for (final q in questions) q.toMap()],
      'questionIndex': 0,
      'turn': 0,
      'streaks': [0, 0],
      'die': 0,
      'rollingPlayer': null,
      'message': 'En attente d’un autre joueur…',
      'done': false,
      'shieldAvailable': false,
      'pawns': initialPawns,
      'shieldedPawns': [<int>[], <int>[]],
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    setState(() {
      _roomId = ref.id;
      _roomCode = code;
      _roomUids = [profile.uid];
      _roomNames = [profile.publicName];
      _onlineReady = false;
      _playerCount = 2;
      _questions = questions;
    });
    _watchRoom(ref.id);
  }

  Future<void> _joinOnlineRoom() async {
    final profile = AuthService.instance.profile.value;
    final code = _roomCodeController.text.trim();
    if (profile == null || code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saisissez un code de 6 chiffres.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('ludoGames').doc(code).get();
      if (!doc.exists || doc.data()?['status'] != 'waiting') {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ce code est introuvable ou la partie a commencé.')));
        return;
      }
      final data = doc.data()!;
      final uids = List<String>.from(data['playerUids'] ?? const <String>[]);
      final names = List<String>.from(data['playerNames'] ?? const <String>[]);
      if (uids.contains(profile.uid)) {
        _watchRoom(doc.id);
      } else if (uids.length >= 2) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cette partie est complète.')));
        return;
      } else {
        await _showRulesIfNeeded();
        await doc.reference.update({
          'playerUids': [...uids, profile.uid],
          'playerNames': [...names, profile.publicName],
          'status': 'playing',
          'message': 'La partie commence !',
        });
        _watchRoom(doc.id);
      }
      if (mounted) setState(() { _onlineMode = true; _roomId = doc.id; _roomCode = code; });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de rejoindre. Vérifiez votre connexion et réessayez.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _watchRoom(String id) {
    _roomSub?.cancel();
    _roomSub = FirebaseFirestore.instance.collection('ludoGames').doc(id).snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (data == null || !mounted) return;
      final questions = (data['questions'] as List? ?? const [])
          .whereType<Map>()
          .map((question) => BankQuestion.fromMap(question))
          .toList();
      final uids = List<String>.from(data['playerUids'] ?? const <String>[]);
      final names = List<String>.from(data['playerNames'] ?? const <String>[]);
      final pawns = (data['pawns'] as List? ?? const [])
          .map((row) => List<int>.from(row as List))
          .toList();
      final shielded = (data['shieldedPawns'] as List? ?? const [])
          .map((row) => Set<int>.from(row as List))
          .toList();
      if (questions.isEmpty || pawns.isEmpty) return;
      setState(() {
        _onlineMode = true;
        _roomId = id;
        _roomCode = '${data['code'] ?? ''}';
        _roomUids = uids;
        _roomNames = names;
        _questions = questions;
        _level = '${data['level'] ?? _level}';
        _selectedDomains
          ..clear()
          ..addAll(List<String>.from(data['domains'] ?? const <String>[]));
        _playerCount = uids.length.clamp(2, 4).toInt();
        _questionIndex = (data['questionIndex'] as num? ?? 0).toInt();
        _turn = (data['turn'] as num? ?? 0).toInt();
        _streaks = List<int>.from(data['streaks'] ?? List.filled(_playerCount, 0));
        _die = (data['die'] as num? ?? 0).toInt();
        _rollingPlayer = (data['rollingPlayer'] as num?)?.toInt();
        _message = '${data['message'] ?? ''}';
        _done = data['done'] == true;
        _shieldAvailable = data['shieldAvailable'] == true;
        _pawns = pawns;
        _shieldedPawns = shielded;
        _onlineReady = data['status'] == 'playing';
      });
    }, onError: (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connexion à la partie interrompue.')));
    });
  }

  Future<void> _saveOnlineState() async {
    if (!_onlineMode || _roomId == null) return;
    try {
      await FirebaseFirestore.instance.collection('ludoGames').doc(_roomId).update({
        'questionIndex': _questionIndex,
        'turn': _turn,
        'streaks': _streaks,
        'die': _die,
        'rollingPlayer': _rollingPlayer,
        'message': _message,
        'done': _done,
        'shieldAvailable': _shieldAvailable,
        'pawns': _pawns,
        'shieldedPawns': [for (final row in _shieldedPawns) row.toList()],
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La partie n’a pas pu être synchronisée.')));
    }
  }

  void _answer(int selected) {
    if (!_playing || !_canAct || _rollingPlayer != null || _message?.startsWith('Bonne réponse') == true) return;
    final correct = selected == _question.answer;
    setState(() {
      if (correct) {
        _streaks[_turn]++;
        if (_streaks[_turn] >= 5) {
          _shieldAvailable = true;
          _streaks[_turn] = 0;
          _message = 'Bonne réponse ! Bouclier Ndimbal gagné. Lancez le dé.';
        } else {
          _message = 'Bonne réponse ! Lancez le dé.';
        }
        _rollingPlayer = _turn;
      } else {
        _streaks[_turn] = 0;
        _message = 'Pas cette fois. Au tour du joueur suivant.';
      }
    });
    _saveOnlineState();
    if (!correct) _nextTurn();
  }

  void _roll() {
    if (!_canAct || _rollingPlayer != _turn || _done) return;
    final value = Random().nextInt(6) + 1;
    final available = _pawns[_turn];
    final hasMove = available.any((position) => position < 24 &&
        (position < 0 ? value == 6 : position + value <= 24));
    setState(() {
      _die = value;
      if (!hasMove) {
        _message = 'Vous avez obtenu $value. Aucun pion ne peut avancer.';
      } else {
        _message = 'Vous avez obtenu $value. Choisissez un pion.';
      }
    });
    _saveOnlineState();
    if (!hasMove) Future<void>.delayed(const Duration(milliseconds: 900), _nextTurn);
  }

  void _movePawn(int pawnIndex) {
    if (!_canAct || _rollingPlayer != _turn || _die == 0 || _done) return;
    final current = _pawns[_turn][pawnIndex];
    if (current < 0 && _die != 6) return;
    final target = current < 0 ? 0 : current + _die;
    if (target > 24) return;
    final targetCell = (_turn * 6 + target) % 24;
    final pawns = [for (final row in _pawns) [...row]];
    pawns[_turn][pawnIndex] = target;
    var captured = false;
    final shields = [for (final row in _shieldedPawns) {...row}];
    if (_shieldAvailable) {
      shields[_turn].add(pawnIndex);
    }
    if (target < 24 && !const {0, 6, 12, 18}.contains(targetCell)) {
      for (var player = 0; player < _playerCount; player++) {
        if (player == _turn) continue;
        for (var pawn = 0; pawn < 2; pawn++) {
          final opponentProgress = pawns[player][pawn];
          final opponentCell = opponentProgress < 0 || opponentProgress >= 24
              ? -1
              : (player * 6 + opponentProgress) % 24;
          if (opponentCell == targetCell) {
            if (shields[player].remove(pawn)) {
              captured = false;
            } else {
              pawns[player][pawn] = -1;
              captured = true;
            }
          }
        }
      }
    }
    final won = pawns[_turn].every((position) => position == 24);
    setState(() {
      _pawns = pawns;
      _shieldedPawns = shields;
      _message = won
          ? 'Joueur ${_turn + 1} remporte la partie !'
          : captured
              ? 'Pion adverse renvoyé à sa base !'
              : 'Pion déplacé.';
      _done = won;
      _shieldAvailable = false;
    });
    if (won) {
      _saveOnlineState();
    } else {
      _nextTurn();
    }
  }

  void _nextTurn() {
    if (!mounted || _done) return;
    setState(() {
      _questionIndex++;
      _turn = (_turn + 1) % _playerCount;
      _shieldedPawns[_turn].clear();
      _rollingPlayer = null;
      _die = 0;
      _shieldAvailable = false;
      _message = 'Au tour du joueur ${_turn + 1}';
    });
    _saveOnlineState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ludo Jàng')),
      body: _onlineMode && !_onlineReady && _roomId != null
          ? _waitingRoomView()
          : _playing
              ? _gameView()
              : _setupView(),
    );
  }

  Widget _setupView() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Apprenez en jouant', style: titleStyle(22, weight: 800)),
          const SizedBox(height: 8),
          Text(_onlineMode
              ? 'Créez une partie et partagez son code, ou rejoignez un ami avec son code.'
              : 'Jouez à plusieurs sur ce téléphone. Répondez aux questions pour faire avancer vos pions.'),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Un téléphone')),
              ButtonSegment(value: true, label: Text('En ligne')),
            ],
            selected: {_onlineMode},
            onSelectionChanged: (value) => setState(() {
              _onlineMode = value.first;
              _onlineReady = false;
              _roomId = null;
              _roomCode = null;
              _roomSub?.cancel();
            }),
          ),
          if (_onlineMode) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _roomCodeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Code de la partie à rejoindre', counterText: ''),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _joinOnlineRoom,
              icon: const Icon(Icons.login),
              label: const Text('Rejoindre avec un code'),
            ),
          ],
          const SizedBox(height: 20),
          Text('Niveau des questions', style: titleStyle(18, weight: 800)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'debutant', label: Text('Débutant')),
              ButtonSegment(value: 'intermediaire', label: Text('Intermédiaire')),
              ButtonSegment(value: 'avance', label: Text('Avancé')),
            ],
            selected: {_level},
            onSelectionChanged: (value) => setState(() => _level = value.first),
          ),
          const SizedBox(height: 20),
          Text('Catégories', style: titleStyle(18, weight: 800)),
          const SizedBox(height: 4),
          const Text('Vocabulaire, traductions, grammaire simple, synonymes et antonymes.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final domain in _domains)
                FilterChip(
                  label: Text(QuizBank.domainLabel(domain)),
                  selected: _selectedDomains.contains(domain),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selectedDomains.add(domain);
                    } else {
                      _selectedDomains.remove(domain);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(_onlineMode ? 'Partie en ligne' : 'Nombre de joueurs', style: titleStyle(18, weight: 800)),
          const SizedBox(height: 8),
          if (!_onlineMode) SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
            ],
            selected: {_playerCount},
            onSelectionChanged: (value) => setState(() => _playerCount = value.first),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(_onlineMode ? 'Créer une partie et obtenir un code' : 'Commencer la partie'),
          ),
        ],
      );

  Widget _waitingRoomView() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.casino_outlined, size: 58, color: JangColors.snGreen),
          const SizedBox(height: 12),
          Text('Partagez ce code', textAlign: TextAlign.center, style: titleStyle(23, weight: 800)),
          const SizedBox(height: 10),
          SelectableText(_roomCode ?? '', textAlign: TextAlign.center, style: titleStyle(36, color: JangColors.snGreen, weight: 800)),
          const SizedBox(height: 8),
          const Text('Votre ami choisit « En ligne », saisit le code et rejoint la partie.', textAlign: TextAlign.center),
          const SizedBox(height: 18),
          Card(child: Column(children: [
            for (var i = 0; i < _roomNames.length; i++)
              ListTile(leading: CircleAvatar(backgroundColor: _playerColors[i], child: Text('${i + 1}', style: const TextStyle(color: Colors.white))), title: Text(_roomNames[i])),
            if (_roomNames.length < 2) const ListTile(leading: CircularProgressIndicator(), title: Text('En attente d’un autre joueur…')),
          ])),
        ],
      );

  Widget _gameView() {
    final question = _question;
    final answered = _rollingPlayer == _turn;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Text(_message ?? 'Au tour du joueur ${_turn + 1}',
                  textAlign: TextAlign.center, style: titleStyle(18, weight: 800)),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                children: [
                  for (var player = 0; player < _playerCount; player++)
                    Chip(
                      avatar: CircleAvatar(backgroundColor: _playerColors[player], child: Text('${player + 1}', style: const TextStyle(color: Colors.white))),
                    label: Text('${_roomNames.length > player ? _roomNames[player] : 'Joueur ${player + 1}'}: ${_pawns[player].where((p) => p == 24).length}/2 · série ${_streaks[player]}/5'),
                      backgroundColor: player == _turn ? JangColors.successBg : null,
                    ),
                ],
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        _board(),
        if (_shieldAvailable)
          Card(color: JangColors.successBg, child: const ListTile(
            leading: Icon(Icons.shield, color: JangColors.snGreen),
            title: Text('Ndimbal disponible'),
            subtitle: Text('Votre bouclier protège un pion pendant le prochain tour.'),
          )),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Question · ${QuizBank.levelLabel(_level)}', style: titleStyle(15, weight: 800)),
              const SizedBox(height: 8),
              Text(question.text.isEmpty ? question.question : '${question.text}\n\n${question.question}',
                  style: titleStyle(20, weight: 700)),
              const SizedBox(height: 12),
              for (var i = 0; i < question.options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: !_canAct || answered || _die > 0 ? null : () => _answer(i),
                    child: Text(question.options[i]),
                  ),
                ),
              if (answered && _die == 0)
                FilledButton.icon(onPressed: _canAct ? _roll : null, icon: const Icon(Icons.casino), label: const Text('Lancer le dé')),
              if (_die > 0 && answered) ...[
                Text('Dé : $_die', textAlign: TextAlign.center, style: titleStyle(22, weight: 800)),
                const SizedBox(height: 8),
                Text('Touchez un pion pour le déplacer :', style: titleStyle(14, weight: 700)),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    for (var i = 0; i < 2; i++)
                      ActionChip(
                        avatar: Icon(Icons.circle, color: _playerColors[_turn]),
                        label: Text(_pawns[_turn][i] < 0 ? 'Pion ${i + 1} · base' : _pawns[_turn][i] == 24 ? 'Pion ${i + 1} · arrivé' : 'Pion ${i + 1} · case ${_pawns[_turn][i] + 1}'),
                        onPressed: !_canAct || _pawns[_turn][i] == 24 || (_pawns[_turn][i] < 0 && _die != 6) || (_pawns[_turn][i] >= 0 && _pawns[_turn][i] + _die > 24)
                            ? null
                            : () => _movePawn(i),
                      ),
                  ],
                ),
              ],
            ]),
          ),
        ),
        if (_done)
          FilledButton.icon(
            onPressed: () {
              _roomSub?.cancel();
              setState(() { _questions = const []; _done = false; _onlineReady = false; _roomId = null; _roomCode = null; });
            },
            icon: const Icon(Icons.replay),
            label: const Text('Nouvelle partie'),
          ),
      ],
    );
  }

  Widget _board() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Piste', style: titleStyle(17, weight: 800)),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 49,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemBuilder: (context, index) {
                final row = index ~/ 7;
                final col = index % 7;
                int? cell;
                if (row == 0) cell = col;
                else if (col == 6) cell = 6 + row;
                else if (row == 6) cell = 18 - col;
                else if (col == 0) cell = 24 - row;
                final home = row == 3 && col == 3;
                final protectedSquare = cell != null && const {0, 6, 12, 18}.contains(cell);
                final colorsHere = <Color>[];
                final shieldHere = <bool>[];
                if (cell != null) {
                  for (var player = 0; player < _playerCount; player++) {
                    for (final pawn in _pawns[player].asMap().entries) {
                      if (pawn.value >= 0 && pawn.value < 24 &&
                          (player * 6 + pawn.value) % 24 == cell) {
                        colorsHere.add(_playerColors[player]);
                        shieldHere.add(_shieldedPawns[player].contains(pawn.key));
                      }
                    }
                  }
                }
                return Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: home || protectedSquare
                        ? const Color(0xFFE5F3E9)
                        : cell != null
                            ? Colors.white
                            : Colors.black.withOpacity(0.035),
                    borderRadius: BorderRadius.circular(6),
                    border: cell != null || home
                        ? Border.all(color: protectedSquare || home ? JangColors.snGreen : Colors.black26)
                        : null,
                  ),
                  child: home
                      ? const Icon(Icons.flag, color: JangColors.snGreen, size: 17)
                      : cell == null
                          ? null
                          : colorsHere.isEmpty
                              ? protectedSquare
                                  ? const Icon(Icons.shield_outlined, color: JangColors.snGreen, size: 14)
                                  : Text('${cell + 1}', style: const TextStyle(fontSize: 9, color: Colors.black54))
                              : Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 0,
                                  children: [
                                    for (var i = 0; i < colorsHere.length; i++)
                                      Icon(shieldHere[i] ? Icons.shield : Icons.circle,
                                          size: 13, color: colorsHere[i]),
                                  ],
                                ),
                );
              },
            ),
            const SizedBox(height: 6),
            const Text('Les cases vert clair sont sûres : aucun pion ne peut y être renvoyé à sa base.'),
            for (var player = 0; player < _playerCount; player++)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Joueur ${player + 1} · ${_pawns[player].where((p) => p < 0).length} en base · ${_pawns[player].where((p) => p == 24).length} arrivé'),
              ),
          ]),
        ),
      );
}

