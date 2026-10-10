import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
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

class _LudoJangScreenState extends State<LudoJangScreen>
    with SingleTickerProviderStateMixin {
  static const _domains = <String>[
    'vocabulaire',
    'francais_anglais',
    'anglais_francais',
    'grammaire',
    'synonymes',
    'antonymes',
  ];
  static const _playerColors = <Color>[
    Color(0xFFE31B23),
    Color(0xFF00853F),
    Color(0xFFF4D000),
    Color(0xFF159FE8),
  ];
  static const _startCells = <int>[0, 13, 26, 39];
  static const _safeCells = <int>{0, 8, 13, 21, 26, 34, 39, 47};
  static const _track = <(int, int)>[
    (6, 1), (6, 2), (6, 3), (6, 4), (6, 5), (5, 6), (4, 6), (3, 6),
    (2, 6), (1, 6), (0, 6), (0, 7), (0, 8), (1, 8), (2, 8), (3, 8),
    (4, 8), (5, 8), (6, 9), (6, 10), (6, 11), (6, 12), (6, 13), (6, 14),
    (7, 14), (8, 14), (8, 13), (8, 12), (8, 11), (8, 10), (8, 9), (9, 8),
    (10, 8), (11, 8), (12, 8), (13, 8), (14, 8), (14, 7), (14, 6), (13, 6),
    (12, 6), (11, 6), (10, 6), (9, 6), (8, 5), (8, 4), (8, 3), (8, 2),
    (8, 1), (8, 0), (7, 0), (6, 0),
  ];

  String _level = 'debutant';
  final Set<String> _selectedDomains = {..._domains};
  int _playerCount = 2;
  bool _busy = false;
  bool _soundEnabled = true;
  final AudioPlayer _dicePlayer = AudioPlayer();
  final AudioPlayer _pawnMovePlayer = AudioPlayer();
  late final AnimationController _pawnMoveController;
  int? _movingPlayer;
  int? _movingPawn;
  int? _movingFrom;
  int? _movingTo;
  int _lastMoveSoundStep = -1;
  String? _lastMoveId;
  bool _moveInitiatedLocally = false;
  bool _moveIsRollback = false;
  bool _onlineMode = false;
  bool _onlineReady = false;
  String? _roomId;
  String? _roomCode;
  List<String> _roomUids = [];
  List<String> _roomNames = [];
  final List<String> _localPlayerNames = List.filled(4, '');
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSub;
  Timer? _questionTimer;
  Timer? _moveTimer;
  DateTime? _questionDeadline;
  int _secondsRemaining = 20;
  bool _waitingForSquareQuestion = false;
  bool _resolvingQuestion = false;
  int? _pendingPawnIndex;
  int? _pendingOrigin;
  int? _pendingTarget;
  final _roomCodeController = TextEditingController();
  List<BankQuestion> _questions = const [];
  int _questionIndex = 0;
  int _turn = 0;
  late List<int> _streaks;
  late List<int> _missesSinceSix;
  int _die = 0;
  int? _rollingPlayer;
  bool _isDieAnimating = false;
  String? _message;
  bool _done = false;
  bool _shieldAvailable = false;
  late List<List<int>> _pawns;
  late List<Set<int>> _shieldedPawns;

  @override
  void initState() {
    super.initState();
    _pawnMoveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )
      ..addListener(_onPawnMoveFrame)
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed || _movingPlayer == null) return;
        if (_moveInitiatedLocally) {
          if (_moveIsRollback) {
            _finishRollbackMove();
          } else {
            _finishPawnMove();
          }
        } else {
          _clearPawnMoveVisual();
        }
      });
    _pawns = List.generate(4, (_) => List.filled(4, -1));
    _shieldedPawns = List.generate(4, (_) => <int>{});
    _streaks = List.filled(4, 0);
    _missesSinceSix = List.filled(4, 0);
    unawaited(_loadSoundPreference());
  }

  Future<void> _loadSoundPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _soundEnabled = prefs.getBool('ludo_jang_sound_enabled') ?? true);
  }

  Future<void> _toggleSound() async {
    final next = !_soundEnabled;
    setState(() => _soundEnabled = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ludo_jang_sound_enabled', next);
  }

  Future<void> _playDiceSound() async {
    if (!_soundEnabled) return;
    try {
      await _dicePlayer.stop();
      await _dicePlayer.play(AssetSource('sounds/dice_roll.wav'));
    } catch (_) {
      // The visual roll remains available if this device cannot play audio.
    }
  }

  void _onPawnMoveFrame() {
    if (!mounted) return;
    final from = _movingFrom;
    final to = _movingTo;
    if (from != null && to != null) {
      final step = ((to - from) * _pawnMoveController.value).floor();
      if (step > _lastMoveSoundStep) {
        _lastMoveSoundStep = step;
        unawaited(_playPawnMoveSound());
      }
    }
    setState(() {});
  }

  Future<void> _playPawnMoveSound() async {
    if (!_soundEnabled) return;
    try {
      await _pawnMovePlayer.stop();
      await _pawnMovePlayer.play(AssetSource('sounds/pawn_move.wav'));
    } catch (_) {
      // Les animations restent disponibles si le périphérique ne lit pas l'audio.
    }
  }

  String _firebaseErrorLabel(Object error, {String action = 'Créer la partie'}) {
    if (error is FirebaseException) {
      final detail = switch (error.code) {
        'permission-denied' => 'Accès refusé par les règles Firestore. Publiez les règles Firestore du projet.',
        'unauthenticated' => 'La session a expiré. Déconnectez-vous puis reconnectez-vous.',
        'unavailable' || 'deadline-exceeded' => 'Firebase ne répond pas. Vérifiez le réseau puis réessayez.',
        'resource-exhausted' => 'La limite d’utilisation Firestore est atteinte.',
        'not-found' => 'La base Firestore ou le document demandé est introuvable.',
        'invalid-argument' => 'Les données de la salle ont été refusées par Firestore.',
        'failed-precondition' => 'Firestore n’est pas prêt ou n’est pas configuré pour ce projet.',
        _ => error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Erreur Firestore ${error.code}.',
      };
      return '$action : $detail';
    }
    return '$action : ${error.toString()}';
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _questionTimer?.cancel();
    _moveTimer?.cancel();
    _roomCodeController.dispose();
    _pawnMoveController.dispose();
    unawaited(_dicePlayer.dispose());
    unawaited(_pawnMovePlayer.dispose());
    super.dispose();
  }

  BankQuestion get _question => _questions[_questionIndex % _questions.length];
  bool get _playing => _questions.isNotEmpty && !_done;
  bool get _canAct {
    if (!_onlineMode) return true;
    final uid = AuthService.instance.profile.value?.uid;
    return uid != null && _turn < _roomUids.length && _roomUids[_turn] == uid;
  }

  int _seatOf(int player) => _playerCount == 2 ? player * 2 : player;

  String _playerName(int player) {
    if (player < _roomNames.length && _roomNames[player].trim().isNotEmpty) {
      return _roomNames[player];
    }
    if (player < _localPlayerNames.length && _localPlayerNames[player].trim().isNotEmpty) {
      return _localPlayerNames[player].trim();
    }
    return 'Joueur ${player + 1}';
  }

  Color _colorOf(int player) => _playerColors[_seatOf(player)];

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
            'Lancez le dé sans répondre à une question. Il faut obtenir 6 pour sortir un pion de sa base. Après trois lancers consécutifs sans 6, le prochain lancer donnera 6. Un 6 donne un deuxième tour. Touchez ensuite le pion à déplacer.\n\n'
            'Quand un pion arrive sur une case, vous avez 20 secondes pour répondre à une question tirée au hasard parmi les catégories et le niveau choisis. Une bonne réponse le laisse sur cette case. Une mauvaise réponse le ramène à sa position d’avant le déplacement; ce retour ne capture jamais de pion.\n\n'
            'Si le délai de 20 secondes expire, le pion retourne lui aussi à la case qu’il occupait avant son déplacement.\n\n'
            'Les cases colorées et étoilées sont des refuges : aucun pion ne peut y être capturé. Cinq bonnes réponses d’affilée donnent un bouclier Ndimbal pour protéger un pion pendant un tour.\n\n'
            'Le premier joueur qui amène ses quatre pions à l’arrivée gagne.',
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
    if (!_onlineMode && _localPlayerNames.take(_playerCount).any((name) => name.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisissez le prénom de chaque joueur.')),
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
    } catch (error) {
      debugPrint('Échec création partie Ludo : $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_firebaseErrorLabel(error))),
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
      _questionIndex = -1;
      _turn = 0;
      _roomNames = _localPlayerNames.take(players).map((name) => name.trim()).toList();
      _streaks = List.filled(players, 0);
      _missesSinceSix = List.filled(players, 0);
      _die = 0;
      _rollingPlayer = null;
      _message = 'Au tour de ${_playerName(0)}';
      _done = false;
      _shieldAvailable = false;
      _pawns = List.generate(players, (_) => List.filled(4, -1));
      _shieldedPawns = List.generate(players, (_) => <int>{});
      _questionDeadline = null;
      _waitingForSquareQuestion = false;
      _resolvingQuestion = false;
      _pendingPawnIndex = null;
      _pendingOrigin = null;
      _pendingTarget = null;
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

  List<int> _encodePawns(List<List<int>> pawns) =>
      [for (final row in pawns) ...row];

  List<List<int>> _decodePawns(dynamic value, int playerCount) {
    final raw = value is List ? value : const [];
    // Read old room documents if one was written by a previous app version.
    if (raw.isNotEmpty && raw.first is List) {
      return raw
          .map((row) => List<int>.from(row as List))
          .toList();
    }
    final flat = raw.map((position) => (position as num).toInt()).toList();
    return List.generate(
      playerCount,
      (player) => List.generate(
        4,
        (pawn) => player * 4 + pawn < flat.length
            ? flat[player * 4 + pawn]
            : -1,
      ),
    );
  }

  List<int> _encodeShieldedPawns(List<Set<int>> shields) => [
        for (var player = 0; player < shields.length; player++)
          for (final pawn in shields[player]) player * 4 + pawn,
      ];

  List<Set<int>> _decodeShieldedPawns(dynamic value, int playerCount) {
    final raw = value is List ? value : const [];
    final shields = List.generate(playerCount, (_) => <int>{});
    // Read old room documents if one was written by a previous app version.
    if (raw.isNotEmpty && raw.first is List) {
      for (var player = 0; player < raw.length && player < playerCount; player++) {
        shields[player].addAll(List<int>.from(raw[player] as List));
      }
      return shields;
    }
    for (final value in raw) {
      if (value is! num) continue;
      final index = value.toInt();
      final player = index ~/ 4;
      final pawn = index % 4;
      if (index >= 0 && player < playerCount) shields[player].add(pawn);
    }
    return shields;
  }

  Future<void> _createOnlineRoom(List<BankQuestion> questions) async {
    final profile = AuthService.instance.profile.value;
    if (profile == null) throw StateError('Connectez-vous avant de créer une partie en ligne.');
    final code = await _newRoomCode();
    final ref = FirebaseFirestore.instance.collection('ludoGames').doc(code);
    const players = 2;
    final initialPawns = List.filled(players * 4, -1);
    await ref.set({
      'code': code,
      'hostUid': profile.uid,
      'status': 'waiting',
      'playerUids': [profile.uid],
      'playerNames': [profile.publicName],
      'level': _level,
      'domains': _selectedDomains.toList(),
      'questions': [for (final q in questions) q.toMap()],
      'questionIndex': -1,
      'questionDeadline': DateTime.now().millisecondsSinceEpoch,
      'waitingForSquareQuestion': false,
      'resolvingQuestion': false,
      'turn': 0,
      'streaks': [0, 0],
      'missesSinceSix': [0, 0],
      'die': 0,
      'rollingPlayer': null,
      'message': 'En attente d’un autre joueur…',
      'done': false,
        'shieldAvailable': false,
        'pawns': initialPawns,
        'shieldedPawns': <int>[],
        'moveAnimation': null,
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
          'questionDeadline': DateTime.now().millisecondsSinceEpoch,
          'waitingForSquareQuestion': false,
          'resolvingQuestion': false,
        });
        _watchRoom(doc.id);
      }
      if (mounted) setState(() { _onlineMode = true; _roomId = doc.id; _roomCode = code; });
    } catch (error) {
      debugPrint('Échec pour rejoindre le Ludo : $error');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_firebaseErrorLabel(error, action: 'Rejoindre la partie'))));
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
      final pawns = _decodePawns(data['pawns'], uids.length.clamp(2, 4).toInt());
      final shielded = _decodeShieldedPawns(
        data['shieldedPawns'],
        uids.length.clamp(2, 4).toInt(),
      );
      final previousDie = _die;
      final previousTurn = _turn;
      final rawDeadline = data['questionDeadline'];
      final deadline = rawDeadline is num
          ? DateTime.fromMillisecondsSinceEpoch(rawDeadline.toInt())
          : DateTime.now();
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
        _questionIndex = (data['questionIndex'] as num? ?? -1).toInt();
        _waitingForSquareQuestion = data['waitingForSquareQuestion'] == true;
        _resolvingQuestion = data['resolvingQuestion'] == true;
        _pendingPawnIndex = (data['pendingPawnIndex'] as num?)?.toInt();
        _pendingOrigin = (data['pendingOrigin'] as num?)?.toInt();
        _pendingTarget = (data['pendingTarget'] as num?)?.toInt();
        _turn = (data['turn'] as num? ?? 0).toInt();
        _streaks = List<int>.from(data['streaks'] ?? List.filled(_playerCount, 0));
        _missesSinceSix = List<int>.from(data['missesSinceSix'] ?? List.filled(_playerCount, 0));
        _die = (data['die'] as num? ?? 0).toInt();
        _rollingPlayer = (data['rollingPlayer'] as num?)?.toInt();
        _message = '${data['message'] ?? ''}';
        _done = data['done'] == true;
        _shieldAvailable = data['shieldAvailable'] == true;
        _pawns = pawns;
        _shieldedPawns = shielded;
        _onlineReady = data['status'] == 'playing';
      });
      final rawMove = data['moveAnimation'];
      if (rawMove is Map) {
        final moveId = '${rawMove['id'] ?? ''}';
        if (moveId.isNotEmpty && moveId != _lastMoveId) {
          _startPawnMoveVisual(
            id: moveId,
            player: (rawMove['player'] as num? ?? 0).toInt(),
            pawn: (rawMove['pawn'] as num? ?? 0).toInt(),
            from: (rawMove['from'] as num? ?? -1).toInt(),
            to: (rawMove['to'] as num? ?? 0).toInt(),
            durationMs: (rawMove['durationMs'] as num? ?? 2000).toInt(),
            startedAtMs: DateTime.now().millisecondsSinceEpoch,
            initiatedLocally: false,
            rollback: rawMove['rollback'] == true,
          );
        }
      } else if (_movingPlayer != null && !_moveInitiatedLocally) {
        _clearPawnMoveVisual();
      }
      if (_waitingForSquareQuestion && _questionDeadline != deadline) {
        _questionDeadline = deadline;
        _startQuestionTimer(deadline);
      } else if (!_waitingForSquareQuestion) {
        _questionTimer?.cancel();
      }
      if (_die > 0 && !_waitingForSquareQuestion && _canAct && (previousDie != _die || previousTurn != _turn)) {
        _moveTimer?.cancel();
        _moveTimer = Timer(const Duration(seconds: 10), _autoMove);
      } else if (_die == 0 || _waitingForSquareQuestion || !_canAct) {
        _moveTimer?.cancel();
      }
    }, onError: (Object error) {
      debugPrint('Écoute Firestore Ludo interrompue : $error');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_firebaseErrorLabel(error, action: 'Connexion à la partie interrompue'))));
    });
  }

  Future<void> _saveOnlineState({Map<String, dynamic>? moveAnimation}) async {
    if (!_onlineMode || _roomId == null) return;
    try {
      await FirebaseFirestore.instance.collection('ludoGames').doc(_roomId).update({
        'questionIndex': _questionIndex,
        'questionDeadline': _questionDeadline?.millisecondsSinceEpoch,
        'waitingForSquareQuestion': _waitingForSquareQuestion,
        'resolvingQuestion': _resolvingQuestion,
        'pendingPawnIndex': _pendingPawnIndex,
        'pendingOrigin': _pendingOrigin,
        'pendingTarget': _pendingTarget,
        'turn': _turn,
        'streaks': _streaks,
        'missesSinceSix': _missesSinceSix,
        'die': _die,
        'rollingPlayer': _rollingPlayer,
        'message': _message,
        'done': _done,
        'shieldAvailable': _shieldAvailable,
        'pawns': _encodePawns(_pawns),
        'shieldedPawns': _encodeShieldedPawns(_shieldedPawns),
        'moveAnimation': moveAnimation,
      });
    } catch (error) {
      debugPrint('Échec synchronisation Ludo : $error');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_firebaseErrorLabel(error, action: 'Synchronisation de la partie'))));
    }
  }

  void _answer(int selected) {
    if (!_playing || !_canAct || !_waitingForSquareQuestion || _secondsRemaining <= 0) return;
    _questionTimer?.cancel();
    _resolveSquareQuestion(selected == _question.answer);
  }

  void _resolveSquareQuestion(bool correct, {bool timedOut = false}) {
    if (!_waitingForSquareQuestion || _pendingPawnIndex == null || _pendingOrigin == null || _pendingTarget == null) return;
    _questionTimer?.cancel();
    final pawnIndex = _pendingPawnIndex!;
    final origin = _pendingOrigin!;
    final target = _pendingTarget!;
    final pawns = [for (final row in _pawns) [...row]];
    final shields = [for (final row in _shieldedPawns) {...row}];
    var captured = false;
    if (correct) {
      _streaks[_turn]++;
      if (_streaks[_turn] >= 5) {
        _shieldAvailable = true;
        _streaks[_turn] = 0;
      }
      final targetCell = target < 51 ? (_startCells[_seatOf(_turn)] + target) % 52 : -1;
      if (_shieldAvailable) shields[_turn].add(pawnIndex);
      if (targetCell >= 0 && !_safeCells.contains(targetCell)) {
        for (var player = 0; player < _playerCount; player++) {
          if (player == _turn) continue;
          for (var pawn = 0; pawn < 4; pawn++) {
            final progress = pawns[player][pawn];
            final cell = progress < 0 || progress >= 51 ? -1 : (_startCells[_seatOf(player)] + progress) % 52;
            if (cell == targetCell) {
              if (shields[player].remove(pawn)) continue;
              pawns[player][pawn] = -1;
              captured = true;
            }
          }
        }
      }
    } else {
      _streaks[_turn] = 0;
      // The return is animated too; it never captures a pawn.
      final player = _turn;
      final moveId = '${DateTime.now().microsecondsSinceEpoch}-$player-$pawnIndex-back';
      final durationMs = max(2000, max(1, target - origin) * 340).toInt();
      final startedAtMs = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _shieldedPawns = shields;
        _waitingForSquareQuestion = false;
        _resolvingQuestion = true;
        _pendingPawnIndex = null;
        _pendingOrigin = null;
        _pendingTarget = null;
        _questionDeadline = null;
        _message = timedOut
            ? 'Temps écoulé : le pion retourne à sa case précédente.'
            : 'Mauvaise réponse : le pion retourne à sa case précédente.';
      });
      if (_onlineMode && _roomId != null) {
        _lastMoveId = moveId;
        unawaited(_saveOnlineState(moveAnimation: {
          'id': moveId,
          'player': player,
          'pawn': pawnIndex,
          'from': target,
          'to': origin,
          'rollback': true,
          'startedAtMs': startedAtMs,
          'durationMs': durationMs,
        }));
      }
      _startPawnMoveVisual(
        id: moveId,
        player: player,
        pawn: pawnIndex,
        from: target,
        to: origin,
        durationMs: durationMs,
        startedAtMs: startedAtMs,
        initiatedLocally: true,
        rollback: true,
      );
      return;
    }
    final won = correct && pawns[_turn].every((position) => position == 57);
    final extraTurn = _die == 6;
    setState(() {
      _pawns = pawns;
      _shieldedPawns = shields;
      _waitingForSquareQuestion = false;
      _resolvingQuestion = true;
      _pendingPawnIndex = null;
      _pendingOrigin = null;
      _pendingTarget = null;
      _done = won;
      _message = won
          ? 'Bonne réponse ! ${_playerName(_turn)} remporte la partie !'
          : correct
              ? captured ? 'Bonne réponse ! Pion adverse capturé.' : _shieldAvailable ? 'Bonne réponse ! Ndimbal gagné.' : 'Bonne réponse ! Le pion reste sur sa case.'
              : timedOut ? 'Temps écoulé : le pion revient à sa position précédente.' : 'Mauvaise réponse : le pion revient à sa position précédente.';
    });
    if (won) {
      _saveOnlineState();
      return;
    }
    _saveOnlineState();
    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (mounted && !_waitingForSquareQuestion && !_done) _nextTurn(extraTurn: extraTurn);
    });
  }

  Future<void> _roll() async {
    if (!_canAct || _die != 0 || _done || _waitingForSquareQuestion || _resolvingQuestion || _movingPlayer != null) return;
    final guaranteedSix = _missesSinceSix[_turn] >= 3;
    final value = guaranteedSix ? 6 : Random().nextInt(6) + 1;
    final misses = [..._missesSinceSix];
    misses[_turn] = value == 6 ? 0 : misses[_turn] + 1;
    final available = _pawns[_turn];
    final hasMove = available.any((position) => position < 57 &&
        (position < 0 ? value == 6 : position + value <= 57));
    setState(() {
      _die = value;
      _isDieAnimating = true;
      _missesSinceSix = misses;
      _rollingPlayer = _turn;
      if (!hasMove) {
        _message = guaranteedSix
            ? 'Après trois lancers sans 6, le 6 est garanti. Aucun pion ne peut avancer.'
            : 'Vous avez obtenu $value. Aucun pion ne peut avancer.';
      } else {
        _message = guaranteedSix ? 'Le 6 est garanti après trois essais. Choisissez un pion.' : 'Vous avez obtenu $value. Choisissez un pion.';
      }
    });
    unawaited(_playDiceSound());
    _saveOnlineState();
    await Future<void>.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    setState(() => _isDieAnimating = false);
    if (!hasMove) {
      Future<void>.delayed(const Duration(milliseconds: 900), () => _nextTurn(extraTurn: value == 6));
    } else {
      _moveTimer?.cancel();
      _moveTimer = Timer(const Duration(seconds: 10), _autoMove);
    }
  }

  void _autoMove() {
    if (!mounted || !_canAct || _die == 0 || _waitingForSquareQuestion || _resolvingQuestion || _done) return;
    final movable = List<int>.generate(4, (i) => i).where((i) {
      final p = _pawns[_turn][i];
      return p != 57 && (p < 0 ? _die == 6 : p + _die <= 57);
    }).toList();
    if (movable.isNotEmpty) _movePawn(movable.first);
  }

  Future<void> _movePawn(int pawnIndex) async {
    if (!_canAct || _rollingPlayer != _turn || _die == 0 || _done || _waitingForSquareQuestion || _resolvingQuestion || _movingPlayer != null) return;
    final current = _pawns[_turn][pawnIndex];
    if (current < 0 && _die != 6) return;
    final target = current < 0 ? 0 : current + _die;
    if (target > 57) return;
    _moveTimer?.cancel();
    final player = _turn;
    final moveId = '${DateTime.now().microsecondsSinceEpoch}-$player-$pawnIndex';
    final durationMs = max(2000, max(1, target - current) * 340).toInt();
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    if (_onlineMode && _roomId != null) {
      _lastMoveId = moveId;
      try {
        await FirebaseFirestore.instance.collection('ludoGames').doc(_roomId).update({
          'moveAnimation': {
            'id': moveId,
            'player': player,
            'pawn': pawnIndex,
            'from': current,
            'to': target,
            'rollback': false,
            'startedAtMs': startedAtMs,
            'durationMs': durationMs,
          },
        });
      } catch (error) {
        debugPrint('Échec synchronisation du déplacement Ludo : $error');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_firebaseErrorLabel(error, action: 'Déplacer le pion'))));
        return;
      }
    }
    _startPawnMoveVisual(
      id: moveId,
      player: player,
      pawn: pawnIndex,
      from: current,
      to: target,
      durationMs: durationMs,
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
      initiatedLocally: true,
    );
  }

  void _startPawnMoveVisual({
    required String id,
    required int player,
    required int pawn,
    required int from,
    required int to,
    required int durationMs,
    required int startedAtMs,
    required bool initiatedLocally,
    bool rollback = false,
  }) {
    if (!mounted || player < 0 || player >= _playerCount || pawn < 0 || pawn >= 4) return;
    _lastMoveId = id;
    _moveInitiatedLocally = initiatedLocally;
    _movingPlayer = player;
    _movingPawn = pawn;
    _movingFrom = from;
    _movingTo = to;
    _lastMoveSoundStep = 0;
    _moveIsRollback = rollback;
    final duration = Duration(milliseconds: max(2000, durationMs).toInt());
    _pawnMoveController.duration = duration;
    final elapsed = DateTime.now().millisecondsSinceEpoch - startedAtMs;
    final progress = (elapsed / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
    setState(() {});
    if (progress >= 1) {
      if (initiatedLocally) {
        if (rollback) {
          _finishRollbackMove();
        } else {
          _finishPawnMove();
        }
      } else {
        _clearPawnMoveVisual();
      }
      return;
    }
    _pawnMoveController.forward(from: progress);
  }

  void _finishPawnMove() {
    if (!mounted || _movingPlayer == null || _movingPawn == null || _movingTo == null) return;
    final player = _movingPlayer!;
    final pawn = _movingPawn!;
    final origin = _movingFrom!;
    final target = _movingTo!;
    final pawns = [for (final row in _pawns) [...row]];
    pawns[player][pawn] = target;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    setState(() {
      _pawns = pawns;
      _questionIndex = (_questionIndex + 1) % _questions.length;
      _pendingPawnIndex = pawn;
      _pendingOrigin = origin;
      _pendingTarget = target;
      _waitingForSquareQuestion = true;
      _questionDeadline = deadline;
      _secondsRemaining = 20;
      _message = '${_playerName(player)}, réponds à la question de cette case.';
      _movingPlayer = null;
      _movingPawn = null;
      _movingFrom = null;
      _movingTo = null;
      _moveIsRollback = false;
    });
    _startQuestionTimer(deadline);
    _saveOnlineState();
  }

  void _finishRollbackMove() {
    if (!mounted || _movingPlayer == null || _movingPawn == null || _movingTo == null) return;
    final player = _movingPlayer!;
    final pawn = _movingPawn!;
    final origin = _movingTo!;
    final pawns = [for (final row in _pawns) [...row]];
    pawns[player][pawn] = origin;
    final extraTurn = _die == 6;
    setState(() {
      _pawns = pawns;
      _movingPlayer = null;
      _movingPawn = null;
      _movingFrom = null;
      _movingTo = null;
      _moveIsRollback = false;
    });
    _saveOnlineState();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted && !_done) _nextTurn(extraTurn: extraTurn);
    });
  }

  void _clearPawnMoveVisual() {
    if (!mounted || _movingPlayer == null) return;
    setState(() {
      _movingPlayer = null;
      _movingPawn = null;
      _movingFrom = null;
      _movingTo = null;
      _moveIsRollback = false;
    });
  }

  void _nextTurn({bool extraTurn = false}) {
    if (!mounted || _done) return;
    _moveTimer?.cancel();
    setState(() {
      if (!extraTurn) _turn = (_turn + 1) % _playerCount;
      if (!extraTurn) _shieldedPawns[_turn].clear();
      _rollingPlayer = null;
      _die = 0;
      _shieldAvailable = false;
      _message = extraTurn ? 'Vous avez obtenu 6 : ${_playerName(_turn)} rejoue !' : 'Au tour de ${_playerName(_turn)}';
      _questionDeadline = null;
      _waitingForSquareQuestion = false;
      _resolvingQuestion = false;
    });
    _saveOnlineState();
  }

  void _startQuestionTimer(DateTime deadline) {
    _questionTimer?.cancel();
    if (_onlineMode && !_onlineReady) return;
    void tick() {
      if (!mounted) return;
      final remaining = max(0, (deadline.difference(DateTime.now()).inMilliseconds / 1000).ceil());
      if (_secondsRemaining != remaining) setState(() => _secondsRemaining = remaining);
      if (remaining == 0) {
        _questionTimer?.cancel();
        if (_playing && _canAct && _waitingForSquareQuestion) _timeoutQuestion();
      }
    }
    tick();
    _questionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
  }

  void _timeoutQuestion() {
    if (!_playing || !_canAct || !_waitingForSquareQuestion || _secondsRemaining > 0) return;
    _questionTimer?.cancel();
    _resolveSquareQuestion(false, timedOut: true);
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
              : 'Jouez à plusieurs sur ce téléphone. Lancez le dé et répondez à la question de la case où arrive votre pion.'),
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
          if (!_onlineMode) ...[
            const SizedBox(height: 10),
            for (var player = 0; player < _playerCount; player++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextFormField(
                  key: ValueKey('local-ludo-player-$player'),
                  initialValue: _localPlayerNames[player],
                  maxLength: 24,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Prénom du joueur ${player + 1}',
                    counterText: '',
                    prefixIcon: Icon(Icons.person, color: _colorOf(player)),
                  ),
                  onChanged: (name) => _localPlayerNames[player] = name,
                ),
              ),
          ],
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
              ListTile(leading: CircleAvatar(backgroundColor: _playerColors[i * 2], child: Text('${i + 1}', style: const TextStyle(color: Colors.white))), title: Text(_roomNames[i])),
            if (_roomNames.length < 2) const ListTile(leading: CircularProgressIndicator(), title: Text('En attente d’un autre joueur…')),
          ])),
        ],
      );

  Widget _gameView() => LayoutBuilder(builder: (context, constraints) {
        final double boardSide = min(constraints.maxWidth - 20, max(190.0, constraints.maxHeight * .53)).toDouble();
        final activeName = _playerName(_turn);
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(children: [
            _TurnGlow(
              color: _colorOf(_turn),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(children: [
                  CircleAvatar(radius: 15, backgroundColor: _colorOf(_turn), child: Text('${_turn + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_message ?? 'Au tour de $activeName', maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle(15, weight: 800))),
                  IconButton(
                    tooltip: _soundEnabled ? 'Couper les effets sonores' : 'Activer les effets sonores',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    padding: EdgeInsets.zero,
                    onPressed: _toggleSound,
                    icon: Icon(_soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 20),
                  ),
                  if ((_message ?? '').startsWith('Bonne réponse'))
                    const Icon(Icons.check_circle, color: JangColors.snGreen, size: 20),
                  if ((_message ?? '').startsWith('Mauvaise réponse') || (_message ?? '').startsWith('Temps écoulé'))
                    const Icon(Icons.cancel, color: Color(0xFFE31B23), size: 20),
                  for (var player = 0; player < _playerCount; player++)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Tooltip(
                        message: '${_playerName(player)} · ${_pawns[player].where((p) => p == 57).length}/4 arrivés · série ${_streaks[player]}/5',
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: player == _turn ? _colorOf(player) : _colorOf(player).withValues(alpha: .35),
                          child: Text('${_pawns[player].where((p) => p == 57).length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(width: boardSide, height: boardSide, child: _board(boardSide)),
            if (_shieldAvailable)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 3),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.shield, color: JangColors.snGreen, size: 18),
                  SizedBox(width: 5),
                  Text('Ndimbal protège un pion pendant un tour.'),
                ]),
              ),
            Expanded(child: _waitingForSquareQuestion ? _questionPanel() : _turnPanel()),
            if (_done)
              FilledButton.icon(
                onPressed: () {
                  _roomSub?.cancel();
                  setState(() { _questions = const []; _done = false; _onlineReady = false; _roomId = null; _roomCode = null; });
                },
                icon: const Icon(Icons.replay),
                label: const Text('Nouvelle partie'),
              ),
          ]),
        );
      });

  Widget _turnPanel() => Center(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_movingPlayer != null) ...[
              Text(
                _moveIsRollback
                    ? 'Le pion retourne à sa case précédente…'
                    : '${_playerName(_movingPlayer!)} déplace son pion…',
                textAlign: TextAlign.center,
                style: titleStyle(16, weight: 800),
              ),
            ] else if (!_canAct) ...[
              Text('Le dé de ${_playerName(_turn)} apparaîtra ici à son tour.',
                  textAlign: TextAlign.center, style: titleStyle(15, weight: 800)),
            ] else if (_die == 0) ...[
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                CircleAvatar(radius: 14, backgroundColor: _colorOf(_turn), child: Text('${_turn + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                Text('Dé de ${_playerName(_turn)}', textAlign: TextAlign.center, style: titleStyle(17, weight: 800)),
              ]),
              const SizedBox(height: 6),
              _AnimatedDie(
                value: 0,
                rolling: false,
                enabled: !_done && !_resolvingQuestion,
                color: _colorOf(_turn),
                size: 88,
                onTap: _roll,
              ),
              const Text('Le dé apparaît devant le joueur actif. Touchez-le pour lancer.'),
              if (_pawns[_turn].any((p) => p < 0) && _missesSinceSix[_turn] > 0)
                Text('Lancers sans 6 : ${_missesSinceSix[_turn]}/3', style: titleStyle(13, color: JangColors.textSecondary)),
            ] else ...[
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _AnimatedDie(
                  value: _die,
                  rolling: _isDieAnimating,
                  enabled: false,
                  color: _colorOf(_turn),
                  size: 72,
                  onTap: _roll,
                ),
                const SizedBox(width: 10),
                Flexible(child: Text('Résultat : $_die · déplacez un pion dans les 10 secondes', textAlign: TextAlign.center, style: titleStyle(14, weight: 700))),
              ]),
              const SizedBox(height: 5),
              const Text('Touchez un de vos pions sur le plateau pour le déplacer. Une question apparaîtra à son arrivée.'),
            ],
          ]),
        ),
      );

  bool _canMovePawn(int i) {
    if (!_canAct || _die == 0 || _waitingForSquareQuestion || _resolvingQuestion || _done || _movingPlayer != null) return false;
    final position = _pawns[_turn][i];
    return position != 57 && (position < 0 ? _die == 6 : position + _die <= 57);
  }

  Widget _questionPanel() {
    final question = _question;
    final panel = Card(
      margin: const EdgeInsets.only(top: 5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Question · ${QuizBank.levelLabel(_level)}', style: titleStyle(14, weight: 800))),
            Text('$_secondsRemaining s', style: titleStyle(14, weight: 800, color: _secondsRemaining <= 5 ? const Color(0xFFE31B23) : JangColors.snGreen)),
          ]),
          LinearProgressIndicator(value: _secondsRemaining / 20, color: _secondsRemaining <= 5 ? const Color(0xFFE31B23) : JangColors.snGreen, minHeight: 4),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: max(220, MediaQuery.sizeOf(context).width - 48).toDouble(),
                  child: Text(question.text.isEmpty ? question.question : '${question.text}\n${question.question}',
                      textAlign: TextAlign.center, style: titleStyle(18, weight: 700)),
                ),
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: 40, crossAxisSpacing: 6, mainAxisSpacing: 4),
            itemCount: question.options.length,
            itemBuilder: (context, i) => OutlinedButton(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 5), visualDensity: VisualDensity.compact),
              onPressed: !_canAct || _secondsRemaining <= 0 ? null : () => _answer(i),
              child: Text(question.options[i], maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            ),
          ),
        ]),
      ),
    );
    return _seatOf(_turn) >= 2 ? RotatedBox(quarterTurns: 2, child: panel) : panel;
  }

  Widget _board(double side) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _handleBoardTap(details.localPosition, side - 14),
            child: CustomPaint(
              painter: _ClassicLudoBoardPainter(
                colors: _playerColors,
                pawns: _pawns,
                shields: _shieldedPawns,
                seats: List.generate(_playerCount, _seatOf),
                movingPlayer: _movingPlayer,
                movingPawn: _movingPawn,
                movingFrom: _movingFrom,
                movingTo: _movingTo,
                moveProgress: Curves.easeInOutCubic.transform(_pawnMoveController.value),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

  void _handleBoardTap(Offset point, double side) {
    if (_die == 0 || !_canAct || _waitingForSquareQuestion || _done) return;
    final unit = side / 15;
    final homeOrigins = <(int, int)>[(0, 0), (0, 9), (9, 9), (9, 0)];
    const yardSlots = <(int, int)>[(2, 2), (4, 2), (2, 4), (4, 4)];
    const pawnOffsets = <Offset>[Offset.zero, Offset(-.2, -.2), Offset(.2, -.2), Offset.zero];
    var closest = -1;
    var distance = unit * .9;
    for (var pawn = 0; pawn < 4; pawn++) {
      if (!_canMovePawn(pawn)) continue;
      final progress = _pawns[_turn][pawn];
      late Offset center;
      if (progress < 0) {
        final (r, c) = homeOrigins[_seatOf(_turn)];
        final (dr, dc) = yardSlots[pawn];
        center = Offset((c + dc) * unit, (r + dr) * unit);
      } else if (progress == 57) {
        center = Offset(7.5 * unit, 7.5 * unit);
      } else {
        final seat = _seatOf(_turn);
        final (r, c) = progress < 51
            ? _ClassicLudoBoardPainter.track[(_startCells[seat] + progress) % 52]
            : _ClassicLudoBoardPainter.lanes[seat][progress - 51];
        center = Offset((c + .5) * unit, (r + .5) * unit) + pawnOffsets[pawn] * unit;
      }
      final d = (point - center).distance;
      if (d < distance) {
        distance = d;
        closest = pawn;
      }
    }
    if (closest >= 0) _movePawn(closest);
  }
}

/// Shows a single physical-looking die for the active player and tumbles it
/// when tapped. The die stays hidden on devices whose player is not active.
class _AnimatedDie extends StatefulWidget {
  const _AnimatedDie({
    required this.value,
    required this.rolling,
    required this.enabled,
    required this.color,
    required this.size,
    required this.onTap,
  });

  final int value;
  final bool rolling;
  final bool enabled;
  final Color color;
  final double size;
  final VoidCallback onTap;

  @override
  State<_AnimatedDie> createState() => _AnimatedDieState();
}

class _AnimatedDieState extends State<_AnimatedDie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  @override
  void initState() {
    super.initState();
    if (widget.rolling) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _AnimatedDie oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rolling && !oldWidget.rolling) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = widget.value == 0 || widget.rolling
        ? Icons.casino_outlined
        : _faceFor(widget.value);
    return Semantics(
      button: widget.enabled,
      label: widget.value == 0 ? 'Lancer le dé' : 'Résultat du dé : ${widget.value}',
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.rotate(
            angle: _controller.value * pi * 8,
            child: Transform.scale(
              scale: 1 + sin(_controller.value * pi) * .16,
              child: child,
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: widget.color, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: .22),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(face, size: widget.size * .72, color: widget.color),
          ),
        ),
      ),
    );
  }

  IconData _faceFor(int value) => switch (value) {
        1 => Icons.looks_one_rounded,
        2 => Icons.looks_two_rounded,
        3 => Icons.looks_3_rounded,
        4 => Icons.looks_4_rounded,
        5 => Icons.looks_5_rounded,
        _ => Icons.looks_6_rounded,
      };
}

class _ClassicLudoBoardPainter extends CustomPainter {
  final List<Color> colors;
  final List<List<int>> pawns;
  final List<Set<int>> shields;
  final List<int> seats;
  final int? movingPlayer;
  final int? movingPawn;
  final int? movingFrom;
  final int? movingTo;
  final double moveProgress;

  const _ClassicLudoBoardPainter({
    required this.colors,
    required this.pawns,
    required this.shields,
    required this.seats,
    required this.movingPlayer,
    required this.movingPawn,
    required this.movingFrom,
    required this.movingTo,
    required this.moveProgress,
  });

  static const _startCells = <int>[0, 13, 26, 39];
  static const _safeCells = <int>{0, 8, 13, 21, 26, 34, 39, 47};
  static const _track = <(int, int)>[
    (6, 1), (6, 2), (6, 3), (6, 4), (6, 5), (5, 6), (4, 6), (3, 6),
    (2, 6), (1, 6), (0, 6), (0, 7), (0, 8), (1, 8), (2, 8), (3, 8),
    (4, 8), (5, 8), (6, 9), (6, 10), (6, 11), (6, 12), (6, 13), (6, 14),
    (7, 14), (8, 14), (8, 13), (8, 12), (8, 11), (8, 10), (8, 9), (9, 8),
    (10, 8), (11, 8), (12, 8), (13, 8), (14, 8), (14, 7), (14, 6), (13, 6),
    (12, 6), (11, 6), (10, 6), (9, 6), (8, 5), (8, 4), (8, 3), (8, 2),
    (8, 1), (8, 0), (7, 0), (6, 0),
  ];
  static const _lanes = <List<(int, int)>>[
    [(7, 1), (7, 2), (7, 3), (7, 4), (7, 5), (7, 6)],
    [(1, 7), (2, 7), (3, 7), (4, 7), (5, 7), (6, 7)],
    [(7, 13), (7, 12), (7, 11), (7, 10), (7, 9), (7, 8)],
    [(13, 7), (12, 7), (11, 7), (10, 7), (9, 7), (8, 7)],
  ];

  static List<(int, int)> get track => _track;
  static List<List<(int, int)>> get lanes => _lanes;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 15;
    Rect cellRect(int row, int col) => Rect.fromLTWH(col * unit, row * unit, unit, unit);
    final border = Paint()..color = const Color(0xFF33413A)..style = PaintingStyle.stroke..strokeWidth = max(0.7, unit * .035);
    final fill = Paint()..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF6F8F6));

    // Four colored bases and their white pawn yards.
    const houses = <(int, int, int, int)>[(0, 0, 6, 6), (0, 9, 6, 6), (9, 9, 6, 6), (9, 0, 6, 6)];
    for (var player = 0; player < 4; player++) {
      final (row, col, height, width) = houses[player];
      fill.color = colors[player];
      canvas.drawRect(Rect.fromLTWH(col * unit, row * unit, width * unit, height * unit), fill);
      final yard = Rect.fromLTWH((col + 1) * unit, (row + 1) * unit, 4 * unit, 4 * unit);
      fill.color = Colors.white;
      canvas.drawRRect(RRect.fromRectAndRadius(yard, Radius.circular(unit * .12)), fill);
      canvas.drawRRect(RRect.fromRectAndRadius(yard, Radius.circular(unit * .12)), border);
      final slots = <Offset>[
        Offset((col + 2) * unit, (row + 2) * unit),
        Offset((col + 4) * unit, (row + 2) * unit),
        Offset((col + 2) * unit, (row + 4) * unit),
        Offset((col + 4) * unit, (row + 4) * unit),
      ];
      final playerIndex = seats.indexOf(player);
      if (playerIndex < 0) continue;
      for (var pawn = 0; pawn < 4; pawn++) {
        final progress = pawn < pawns[playerIndex].length ? pawns[playerIndex][pawn] : -1;
        final isMoving = playerIndex == movingPlayer && pawn == movingPawn;
        if (progress < 0 && !isMoving) _drawPawn(canvas, slots[pawn], unit * .43, colors[player], shield: false);
        if (progress == 57 && !isMoving) {
          final goal = Offset(7.5 * unit, 7.5 * unit);
          _drawPawn(canvas, goal + Offset((pawn % 2 - .5) * unit * .35, (pawn ~/ 2 - .5) * unit * .35), unit * .24, colors[player], shield: false);
        }
      }
    }

    // The 52 shared track squares.
    for (var index = 0; index < _track.length; index++) {
      final (row, col) = _track[index];
      final rect = cellRect(row, col);
      fill.color = _startCells.contains(index) ? colors[_startCells.indexOf(index)] : Colors.white;
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, border);
      if (_safeCells.contains(index) && !_startCells.contains(index)) {
        _drawStar(canvas, rect.center, unit * .29, const Color(0xFF52635A));
      }
    }

    // Colored home lanes lead from the track into the center.
    for (var player = 0; player < _lanes.length; player++) {
      for (final (row, col) in _lanes[player]) {
        final rect = cellRect(row, col);
        fill.color = colors[player];
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, border);
      }
    }

    // The four triangular paths meet in the finish square.
    final center = Rect.fromLTWH(6 * unit, 6 * unit, 3 * unit, 3 * unit);
    final middle = center.center;
    final triangles = <(Offset, Offset, Offset, Color)>[
      (Offset(6 * unit, 6 * unit), Offset(9 * unit, 6 * unit), middle, colors[0]),
      (Offset(9 * unit, 6 * unit), Offset(9 * unit, 9 * unit), middle, colors[1]),
      (Offset(9 * unit, 9 * unit), Offset(6 * unit, 9 * unit), middle, colors[2]),
      (Offset(6 * unit, 9 * unit), Offset(6 * unit, 6 * unit), middle, colors[3]),
    ];
    for (final (a, b, c, color) in triangles) {
      final path = Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..lineTo(c.dx, c.dy)..close();
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, border);
    }

    // Pieces on the shared route and in their colored home lane.
    for (var player = 0; player < min(seats.length, pawns.length); player++) {
      final seat = seats[player];
      final color = colors[seat];
      for (var pawn = 0; pawn < min(4, pawns[player].length); pawn++) {
        if (player == movingPlayer && pawn == movingPawn) continue;
        final progress = pawns[player][pawn];
        if (progress < 0 || progress == 57) continue;
        final (row, col) = progress < 51
            ? _track[(_startCells[seat] + progress) % 52]
            : _lanes[seat][progress - 51];
        final offsets = <Offset>[Offset.zero, Offset(-.2, -.2), Offset(.2, -.2), Offset.zero];
        final offset = offsets[pawn] * unit;
        _drawPawn(canvas, Offset((col + .5) * unit, (row + .5) * unit) + offset,
            progress < 51 ? unit * .43 : unit * .43, color,
            shield: player < shields.length && shields[player].contains(pawn));
      }
    }

    if (movingPlayer != null && movingPawn != null && movingFrom != null && movingTo != null &&
        movingPlayer! < seats.length) {
      final seat = seats[movingPlayer!];
      final progress = movingFrom! + (movingTo! - movingFrom!) * moveProgress;
      final center = _centerForProgress(seat, movingPawn!, progress, unit);
      _drawPawn(canvas, center, unit * .45, colors[seat], shield: false);
    }
  }

  Offset _centerForProgress(int seat, int pawn, double progress, double unit) {
    final offsets = <Offset>[Offset.zero, Offset(-.2, -.2), Offset(.2, -.2), Offset.zero];
    final pawnOffset = offsets[pawn] * unit;
    Offset cell((int, int) position) => Offset((position.$2 + .5) * unit, (position.$1 + .5) * unit) + pawnOffset;
    final goal = Offset(7.5 * unit, 7.5 * unit) + Offset((pawn % 2 - .5) * unit * .35, (pawn ~/ 2 - .5) * unit * .35);
    if (progress < 0) {
      const homes = <(int, int)>[(0, 0), (0, 9), (9, 9), (9, 0)];
      const yardSlots = <(int, int)>[(2, 2), (4, 2), (2, 4), (4, 4)];
      final (homeRow, homeCol) = homes[seat];
      final (slotRow, slotCol) = yardSlots[pawn];
      final base = Offset((homeCol + slotCol) * unit, (homeRow + slotRow) * unit);
      final first = cell(_track[_startCells[seat]]);
      return Offset.lerp(base, first, (progress + 1).clamp(0.0, 1.0).toDouble())!;
    }
    if (progress < 50) {
      final index = progress.floor();
      final fraction = progress - index;
      final start = cell(_track[(_startCells[seat] + index) % 52]);
      final next = cell(_track[(_startCells[seat] + index + 1) % 52]);
      return Offset.lerp(start, next, fraction)!;
    }
    if (progress < 51) {
      final from = cell(_track[(_startCells[seat] + 50) % 52]);
      return Offset.lerp(from, cell(_lanes[seat][0]), progress - 50)!;
    }
    if (progress < 56) {
      final lanePosition = progress - 51;
      final index = lanePosition.floor().clamp(0, 4).toInt();
      return Offset.lerp(cell(_lanes[seat][index]), cell(_lanes[seat][index + 1]), lanePosition - index)!;
    }
    if (progress < 57) return Offset.lerp(cell(_lanes[seat][5]), goal, progress - 56)!;
    return goal;
  }

  void _drawPawn(Canvas canvas, Offset center, double radius, Color color, {required bool shield}) {
    canvas.drawOval(Rect.fromCenter(center: center + Offset(0, radius * .88), width: radius * 1.25, height: radius * .42),
        Paint()..color = const Color(0x30000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    final body = Path()
      ..moveTo(center.dx, center.dy + radius * 1.18)
      ..cubicTo(center.dx - radius * .08, center.dy + radius * .72, center.dx - radius * .78, center.dy + radius * .20, center.dx - radius * .78, center.dy - radius * .16)
      ..cubicTo(center.dx - radius * .78, center.dy - radius * .70, center.dx + radius * .78, center.dy - radius * .70, center.dx + radius * .78, center.dy - radius * .16)
      ..cubicTo(center.dx + radius * .78, center.dy + radius * .20, center.dx + radius * .08, center.dy + radius * .72, center.dx, center.dy + radius * 1.18)
      ..close();
    canvas.drawPath(body, Paint()..color = Colors.white);
    canvas.drawPath(body.shift(Offset(0, -radius * .08)), Paint()..color = color);
    canvas.drawCircle(center + Offset(0, -radius * .30), radius * .46, Paint()..color = Colors.white);
    canvas.drawCircle(center + Offset(0, -radius * .30), radius * .34, Paint()..color = Color.lerp(color, Colors.white, .20)!);
    if (shield) {
      final text = TextPainter(text: const TextSpan(text: '◆', style: TextStyle(color: Colors.white, fontSize: 8)), textDirection: TextDirection.ltr)..layout();
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final text = TextPainter(text: TextSpan(text: '★', style: TextStyle(color: color, fontSize: radius * 2)), textDirection: TextDirection.ltr)..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ClassicLudoBoardPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.pawns != pawns || oldDelegate.shields != shields ||
      oldDelegate.seats != seats || oldDelegate.moveProgress != moveProgress ||
      oldDelegate.movingPlayer != movingPlayer || oldDelegate.movingPawn != movingPawn ||
      oldDelegate.movingFrom != movingFrom || oldDelegate.movingTo != movingTo;
}

class _TurnGlow extends StatefulWidget {
  final Color color;
  final Widget child;
  const _TurnGlow({required this.color, required this.child});

  @override
  State<_TurnGlow> createState() => _TurnGlowState();
}

class _TurnGlowState extends State<_TurnGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Color.lerp(Colors.white, widget.color.withOpacity(.14), _pulse.value),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.color.withOpacity(.25 + _pulse.value * .45)),
            boxShadow: [BoxShadow(color: widget.color.withOpacity(.05 + _pulse.value * .16), blurRadius: 5 + _pulse.value * 7)],
          ),
          child: child,
        ),
        child: widget.child,
      );
}

