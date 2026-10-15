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
import '../../widgets/fun.dart';
import '../../widgets/jang_ui.dart';
import 'xarit_screen.dart';

/// A Ludo game whose moves are earned by answering English questions.
class LudoJangScreen extends StatefulWidget {
  /// Set when opened from an accepted Xarit challenge: joins this room code
  /// automatically instead of showing the setup screen.
  final String? joinCode;
  /// Set when opened to challenge a Xarit friend to Ludo: creates an online
  /// room as usual, but also sends that friend a match invitation once the
  /// room's code is known.
  final String? challengeFriendUid;
  final String? challengeFriendName;
  const LudoJangScreen({super.key, this.joinCode, this.challengeFriendUid, this.challengeFriendName});

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
  final Set<String> _selectedDomains = {};
  int _playerCount = 2;
  int _pawnsPerPlayer = 4;
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
  Timer? _rollTimer;
  /// Consecutive times each player let the 10-second roll timeout play for
  /// them instead of rolling themselves. Resets to 0 the moment they roll
  /// on their own; reaching 3 forfeits the match for them.
  List<int> _autoRollStreak = List.filled(4, 0);
  static const _quickMessages = <String>['👋 Salut !', '👏 Bravo !', '😂 Haha !', '😮 Oh non !', '🔥 Vas-y !', '😅 Pas de chance !'];
  static const _quickEmojis = <String>['👋', '👏', '😂', '😮', '🔥', '😅', '❤️', '👍'];
  int? _chatBubblePlayer;
  String? _chatBubbleText;
  Timer? _chatBubbleTimer;
  String? _lastChatId;
  DateTime? _questionDeadline;
  int _secondsRemaining = 20;
  bool _waitingForSquareQuestion = false;
  bool _resolvingQuestion = false;
  // Lets any player flip the question panel 180° just by tapping it —
  // handy when the panel's corner isn't easy for them to read from.
  int _questionRotation = 0;
  int? _pendingPawnIndex;
  int? _pendingOrigin;
  int? _pendingTarget;
  final _roomCodeController = TextEditingController();
  List<BankQuestion> _questions = const [];
  int _questionIndex = 0;
  int _turn = 0;
  late List<int> _streaks;
  late List<int> _missesSinceSix;
  late List<int> _correctAnswers;
  late List<int> _incorrectAnswers;
  int _die = 0;
  int? _rollingPlayer;
  bool _isDieAnimating = false;
  String? _message;
  bool _done = false;
  bool _shieldAvailable = false;
  late List<List<int>> _pawns;
  late List<Set<int>> _shieldedPawns;
  late List<List<int>> _shieldTurnsRemaining;

  /// Classement : 0 tant qu'un joueur n'est pas arrivé, sinon sa place
  /// (1er, 2e, 3e…), dans l'ordre où les joueurs ont terminé leurs pions.
  late List<int> _finishRank;

  /// Petit feu d'artifice affiché quelques secondes quand un joueur termine.
  bool _showFireworks = false;
  Timer? _fireworksTimer;

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
    _pawns = List.generate(4, (_) => List.filled(_pawnsPerPlayer, -1));
    _shieldedPawns = List.generate(4, (_) => <int>{});
    _shieldTurnsRemaining = List.generate(4, (_) => List.filled(_pawnsPerPlayer, 0));
    _finishRank = List.filled(4, 0);
    _streaks = List.filled(4, 0);
    _missesSinceSix = List.filled(4, 0);
    _correctAnswers = List.filled(4, 0);
    _incorrectAnswers = List.filled(4, 0);
    unawaited(_loadSoundPreference());
    // Opened from an accepted Xarit challenge, or to challenge a Xarit
    // friend: both start from the "En ligne" setup, so switch to it now.
    if (widget.joinCode != null || widget.challengeFriendUid != null) {
      _onlineMode = true;
    }
    if (widget.joinCode != null) {
      _roomCodeController.text = widget.joinCode!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _joinOnlineRoom();
      });
    }
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
    _rollTimer?.cancel();
    _fireworksTimer?.cancel();
    _chatBubbleTimer?.cancel();
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

  /// Local face-to-face: anyone sharing the device can send as any player.
  /// Online: only the person whose own phone this is can send as themselves.
  bool _canSendChatAs(int player) {
    if (!_onlineMode) return true;
    final uid = AuthService.instance.profile.value?.uid;
    return uid != null && player < _roomUids.length && _roomUids[player] == uid;
  }

  /// Can offer to add [player] as a Xarit (friend): only in online matches,
  /// only for opponents (not myself), and only when we know their uid.
  bool _canAddXarit(int player) {
    final uid = AuthService.instance.profile.value?.uid;
    return _onlineMode &&
        uid != null &&
        player >= 0 &&
        player < _roomUids.length &&
        _roomUids[player].isNotEmpty &&
        _roomUids[player] != uid;
  }

  Future<void> _addXarit(int player) async {
    final me = AuthService.instance.profile.value;
    if (me == null || player >= _roomUids.length) return;
    try {
      await XaritService.instance.requestFriendByUid(me, _roomUids[player], _playerName(player));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Demande envoyée à ${_playerName(player)}.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _openQuickMessages(int player) async {
    final controller = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Envoyer un emoji', style: titleStyle(14, weight: 800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final emoji in _quickEmojis)
                      InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => Navigator.pop(ctx, emoji),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(emoji, style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 24),
                Text('Messages rapides', style: titleStyle(14, weight: 800)),
                for (final message in _quickMessages)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(message, style: const TextStyle(fontSize: 17)),
                    onTap: () => Navigator.pop(ctx, message),
                  ),
                const Divider(height: 24),
                Text('Ou écrivez votre message', style: titleStyle(14, weight: 800)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        maxLength: 40,
                        textInputAction: TextInputAction.send,
                        decoration: const InputDecoration(
                          hintText: 'Votre message…',
                          isDense: true,
                          counterText: '',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (value) {
                          final trimmed = value.trim();
                          if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.send),
                      onPressed: () {
                        final trimmed = controller.text.trim();
                        if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    _showChatBubble(player, text);
    if (_onlineMode && _roomId != null) {
      final id = '${DateTime.now().microsecondsSinceEpoch}-$player';
      _lastChatId = id;
      try {
        await FirebaseFirestore.instance.collection('ludoGames').doc(_roomId).update({
          'chatMessage': {'id': id, 'player': player, 'text': text},
        });
      } catch (_) {}
    }
  }

  void _showChatBubble(int player, String text) {
    if (!mounted) return;
    _chatBubbleTimer?.cancel();
    setState(() {
      _chatBubblePlayer = player;
      _chatBubbleText = text;
    });
    _chatBubbleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() { _chatBubblePlayer = null; _chatBubbleText = null; });
    });
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
            'Les cases colorées et étoilées sont des refuges : aucun pion ne peut y être capturé. Cinq bonnes réponses d’affilée donnent un Aar : tous vos pions sont protégés contre les captures pendant les deux prochains tours des adversaires.\n\n'
            'Le premier joueur qui amène tous ses pions à l’arrivée gagne.',
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
      _correctAnswers = List.filled(players, 0);
      _incorrectAnswers = List.filled(players, 0);
      _autoRollStreak = List.filled(players, 0);
      _die = 0;
      _rollingPlayer = null;
      _message = null;
      _done = false;
      _shieldAvailable = false;
      _pawns = List.generate(players, (_) => List.filled(_pawnsPerPlayer, -1));
      _shieldedPawns = List.generate(players, (_) => <int>{});
      _shieldTurnsRemaining = List.generate(players, (_) => List.filled(_pawnsPerPlayer, 0));
      _finishRank = List.filled(players, 0);
      _showFireworks = false;
      _questionDeadline = null;
      _waitingForSquareQuestion = false;
      _resolvingQuestion = false;
      _pendingPawnIndex = null;
      _pendingOrigin = null;
      _pendingTarget = null;
      _questionRotation = 0;
    });
    _armRollTimer();
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

  // `pawnsPerPlayer` must match what was used to encode this room's data —
  // it is read from the room document itself (see `_watchRoom`), never
  // hardcoded, so both phones agree on how many pawns each player has.
  List<List<int>> _decodePawns(dynamic value, int playerCount, int pawnsPerPlayer) {
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
        pawnsPerPlayer,
        (pawn) => player * pawnsPerPlayer + pawn < flat.length
            ? flat[player * pawnsPerPlayer + pawn]
            : -1,
      ),
    );
  }

  List<int> _encodeShieldedPawns(List<Set<int>> shields, int pawnsPerPlayer) => [
        for (var player = 0; player < shields.length; player++)
          for (final pawn in shields[player]) player * pawnsPerPlayer + pawn,
      ];

  List<int> _encodeShieldTurns(List<List<int>> turns) =>
      [for (final row in turns) ...row];

  List<Set<int>> _decodeShieldedPawns(dynamic value, int playerCount, int pawnsPerPlayer) {
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
      final player = index ~/ pawnsPerPlayer;
      final pawn = index % pawnsPerPlayer;
      if (index >= 0 && player < playerCount) shields[player].add(pawn);
    }
    return shields;
  }

  List<List<int>> _decodeShieldTurns(
    dynamic value,
    int playerCount,
    int pawnsPerPlayer,
    List<Set<int>> shields,
  ) {
    final raw = value is List ? value : const [];
    final flat = raw.whereType<num>().map((turns) => turns.toInt()).toList();
    return List.generate(
      playerCount,
      (player) => List.generate(pawnsPerPlayer, (pawn) {
        final index = player * pawnsPerPlayer + pawn;
        if (index < flat.length) return flat[index].clamp(0, 2).toInt();
        // Older rooms used a one-turn Ndimbal marker.
        return player < shields.length && shields[player].contains(pawn) ? 1 : 0;
      }),
    );
  }

  Future<void> _createOnlineRoom(List<BankQuestion> questions) async {
    final profile = AuthService.instance.profile.value;
    if (profile == null) throw StateError('Connectez-vous avant de créer une partie en ligne.');
    final code = await _newRoomCode();
    final ref = FirebaseFirestore.instance.collection('ludoGames').doc(code);
    const players = 2;
    final pawnsPerPlayer = _pawnsPerPlayer;
    final initialPawns = List.filled(players * pawnsPerPlayer, -1);
    await ref.set({
      'code': code,
      'hostUid': profile.uid,
      'status': 'waiting',
      'playerUids': [profile.uid],
      'playerNames': [profile.publicName],
      'level': _level,
      'domains': _selectedDomains.toList(),
      'pawnsPerPlayer': pawnsPerPlayer,
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
        'shieldTurnsRemaining': List.filled(players * pawnsPerPlayer, 0),
        'correctAnswers': List.filled(players, 0),
        'incorrectAnswers': List.filled(players, 0),
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
    if (widget.challengeFriendUid != null) {
      try {
        await XaritService.instance.inviteToLudo(profile, widget.challengeFriendUid!, code);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Défi envoyé à ${widget.challengeFriendName ?? "ton Xarit"}.')),
          );
        }
      } catch (_) {
        // The room is still created and joinable by code even if the
        // Xarit invitation itself fails to send (e.g. offline briefly).
      }
    }
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
      // Older rooms were always created with 4 pawns per player; read the
      // field when present so both phones in a room always agree.
      final pawnsPerPlayer = (data['pawnsPerPlayer'] as num? ?? 4).toInt().clamp(1, 4).toInt();
      final pawns = _decodePawns(data['pawns'], uids.length.clamp(2, 4).toInt(), pawnsPerPlayer);
      final shielded = _decodeShieldedPawns(
        data['shieldedPawns'],
        uids.length.clamp(2, 4).toInt(),
        pawnsPerPlayer,
      );
      final shieldTurns = _decodeShieldTurns(
        data['shieldTurnsRemaining'],
        uids.length.clamp(2, 4).toInt(),
        pawnsPerPlayer,
        shielded,
      );
      final previousDie = _die;
      final previousTurn = _turn;
      final wasDone = _done;
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
        _pawnsPerPlayer = pawnsPerPlayer;
        _questionIndex = (data['questionIndex'] as num? ?? -1).toInt();
        _waitingForSquareQuestion = data['waitingForSquareQuestion'] == true;
        _resolvingQuestion = data['resolvingQuestion'] == true;
        _pendingPawnIndex = (data['pendingPawnIndex'] as num?)?.toInt();
        _pendingOrigin = (data['pendingOrigin'] as num?)?.toInt();
        _pendingTarget = (data['pendingTarget'] as num?)?.toInt();
        _turn = (data['turn'] as num? ?? 0).toInt();
        _streaks = List<int>.from(data['streaks'] ?? List.filled(_playerCount, 0));
        _missesSinceSix = List<int>.from(data['missesSinceSix'] ?? List.filled(_playerCount, 0));
        _correctAnswers = List<int>.from(data['correctAnswers'] ?? List.filled(_playerCount, 0));
        _incorrectAnswers = List<int>.from(data['incorrectAnswers'] ?? List.filled(_playerCount, 0));
        _die = (data['die'] as num? ?? 0).toInt();
        _rollingPlayer = (data['rollingPlayer'] as num?)?.toInt();
        _message = '${data['message'] ?? ''}';
        _done = data['done'] == true;
        _shieldAvailable = data['shieldAvailable'] == true;
        _pawns = pawns;
        _shieldedPawns = shielded;
        _shieldTurnsRemaining = shieldTurns;
        _finishRank = List<int>.from(data['finishRank'] ?? List.filled(_playerCount, 0));
        _onlineReady = data['status'] == 'playing';
      });
      // The match just ended on the other phone (a win, a quit, or a
      // timeout forfeit) — tell this player clearly instead of letting the
      // banner text change silently underneath them.
      if (!wasDone && _done) {
        _announceMatchEnd(_message?.isNotEmpty == true ? _message! : 'La partie est terminée.');
      }
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
      final rawChat = data['chatMessage'];
      if (rawChat is Map) {
        final chatId = '${rawChat['id'] ?? ''}';
        final chatText = '${rawChat['text'] ?? ''}';
        if (chatId.isNotEmpty && chatId != _lastChatId && chatText.isNotEmpty) {
          _lastChatId = chatId;
          _showChatBubble((rawChat['player'] as num? ?? 0).toInt(), chatText);
        }
      }
      if (_waitingForSquareQuestion && _questionDeadline != deadline) {
        _questionDeadline = deadline;
        _startQuestionTimer(deadline);
      } else if (!_waitingForSquareQuestion) {
        _questionTimer?.cancel();
      }
      if (_die > 0 && !_waitingForSquareQuestion && _canAct && (previousDie != _die || previousTurn != _turn)) {
        _moveTimer?.cancel();
        _moveTimer = Timer(const Duration(seconds: 15), _autoMove);
      } else if (_die == 0 || _waitingForSquareQuestion || !_canAct) {
        _moveTimer?.cancel();
      }
      _armRollTimer();
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
        'shieldedPawns': _encodeShieldedPawns(_shieldedPawns, _pawnsPerPlayer),
        'shieldTurnsRemaining': _encodeShieldTurns(_shieldTurnsRemaining),
        'finishRank': _finishRank,
        'correctAnswers': _correctAnswers,
        'incorrectAnswers': _incorrectAnswers,
        'moveAnimation': moveAnimation,
      });
    } catch (error) {
      debugPrint('Échec synchronisation Ludo : $error');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_firebaseErrorLabel(error, action: 'Synchronisation de la partie'))));
    }
  }

  /// Classement final, du 1er au dernier, un joueur par ligne.
  String _classementText() {
    final order = List.generate(_playerCount, (p) => p)
      ..sort((a, b) {
        final ra = _finishRank[a] == 0 ? _playerCount : _finishRank[a];
        final rb = _finishRank[b] == 0 ? _playerCount : _finishRank[b];
        return ra.compareTo(rb);
      });
    return [
      for (final p in order) '${_finishRank[p] > 0 ? _finishRank[p] : _playerCount}. ${_playerName(p)}',
    ].join('\n');
  }

  /// Un petit feu d'artifice de quelques secondes pour fêter l'arrivée d'un joueur.
  void _celebrateFinish() {
    _fireworksTimer?.cancel();
    setState(() => _showFireworks = true);
    _fireworksTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showFireworks = false);
    });
  }

  void _answer(int selected) {
    if (!_playing || !_canAct || !_waitingForSquareQuestion || _secondsRemaining <= 0) return;
    _questionTimer?.cancel();
    _resolveSquareQuestion(selected == _question.answer);
  }

  void _resolveSquareQuestion(bool correct, {bool timedOut = false}) {
    if (!_waitingForSquareQuestion || _pendingPawnIndex == null || _pendingOrigin == null || _pendingTarget == null) return;
    _questionTimer?.cancel();
    // Captured before anything else so every opponent — not just the player
    // who answered — sees the right option, shown in the message banner
    // visible to everyone around the table.
    final correctOptionText = _question.options[_question.answer];
    final pawnIndex = _pendingPawnIndex!;
    final origin = _pendingOrigin!;
    final target = _pendingTarget!;
    final pawns = [for (final row in _pawns) [...row]];
    final shields = [for (final row in _shieldedPawns) {...row}];
    final shieldTurns = [for (final row in _shieldTurnsRemaining) [...row]];
    final correctAnswers = [..._correctAnswers];
    final incorrectAnswers = [..._incorrectAnswers];
    var captured = false;
    if (correct) {
      correctAnswers[_turn]++;
      _streaks[_turn]++;
      if (_streaks[_turn] >= 5) {
        _shieldAvailable = true;
        _streaks[_turn] = 0;
      }
      final targetCell = target < 51 ? (_startCells[_seatOf(_turn)] + target) % 52 : -1;
      if (_shieldAvailable) {
        for (var pawn = 0; pawn < pawns[_turn].length; pawn++) {
          shields[_turn].add(pawn);
          shieldTurns[_turn][pawn] = 2;
        }
      }
      if (targetCell >= 0 && !_safeCells.contains(targetCell)) {
        for (var player = 0; player < _playerCount; player++) {
          if (player == _turn) continue;
          for (var pawn = 0; pawn < pawns[player].length; pawn++) {
            final progress = pawns[player][pawn];
            final cell = progress < 0 || progress >= 51 ? -1 : (_startCells[_seatOf(player)] + progress) % 52;
            if (cell == targetCell) {
              if (shields[player].contains(pawn)) continue;
              pawns[player][pawn] = -1;
              captured = true;
            }
          }
        }
      }
    } else {
      incorrectAnswers[_turn]++;
      _streaks[_turn] = 0;
      // The return is animated too; it never captures a pawn.
      final player = _turn;
      final moveId = '${DateTime.now().microsecondsSinceEpoch}-$player-$pawnIndex-back';
      final durationMs = max(2000, max(1, target - origin) * 340).toInt();
      final startedAtMs = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _shieldedPawns = shields;
        _shieldTurnsRemaining = shieldTurns;
        _correctAnswers = correctAnswers;
        _incorrectAnswers = incorrectAnswers;
        _waitingForSquareQuestion = false;
        _resolvingQuestion = true;
        _pendingPawnIndex = null;
        _pendingOrigin = null;
        _pendingTarget = null;
        _questionDeadline = null;
        _message = timedOut
            ? 'Temps écoulé : la bonne réponse était « $correctOptionText ». Le pion retourne à sa case précédente.'
            : 'Mauvaise réponse : la bonne réponse était « $correctOptionText ». Le pion retourne à sa case précédente.';
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
    // Ce joueur vient-il de ramener son dernier pion ? (seulement s'il
    // n'était pas déjà classé — on ne reclasse jamais quelqu'un.)
    final justFinished =
        correct && _finishRank[_turn] == 0 && pawns[_turn].every((position) => position == 57);
    final finishRank = [..._finishRank];
    var matchDone = false;
    String? endMessage;
    if (justFinished) {
      finishRank[_turn] = finishRank.where((r) => r > 0).length + 1;
      // Il ne reste plus qu'un seul joueur sans classement : la partie est
      // terminée, il prend automatiquement la dernière place.
      final stillPlaying = <int>[
        for (var p = 0; p < _playerCount; p++)
          if (finishRank[p] == 0) p,
      ];
      if (stillPlaying.length <= 1) {
        for (final p in stillPlaying) {
          finishRank[p] = finishRank.where((r) => r > 0).length + 1;
        }
        matchDone = true;
      }
    }
    final extraTurn = _die == 6;
    setState(() {
      _pawns = pawns;
      _shieldedPawns = shields;
      _shieldTurnsRemaining = shieldTurns;
      _correctAnswers = correctAnswers;
      _incorrectAnswers = incorrectAnswers;
      _waitingForSquareQuestion = false;
      _resolvingQuestion = true;
      _pendingPawnIndex = null;
      _pendingOrigin = null;
      _pendingTarget = null;
      _finishRank = finishRank;
      _done = matchDone;
      _message = justFinished
          ? '${_playerName(_turn)} termine ${_ordinal(finishRank[_turn])} !'
          : captured
              ? 'Bonne réponse (« $correctOptionText ») ! Pion adverse capturé.'
              : _shieldAvailable
                  ? 'Bonne réponse (« $correctOptionText ») ! Aar gagné.'
                  : 'Bonne réponse (« $correctOptionText ») ! Le pion reste sur sa case.';
      if (justFinished) {
        endMessage = matchDone
            ? 'Partie terminée !\n\nClassement :\n${_classementText()}'
            : '${_playerName(_turn)} termine ${_ordinal(finishRank[_turn])} ! La partie continue pour les autres.';
      }
    });
    if (justFinished) _celebrateFinish();
    if (matchDone) {
      _saveOnlineState();
      _announceMatchEnd(endMessage!);
      return;
    }
    _saveOnlineState();
    Future<void>.delayed(Duration(milliseconds: justFinished ? 2200 : 1300), () {
      if (mounted && !_waitingForSquareQuestion && !_done) _nextTurn(extraTurn: justFinished ? false : extraTurn);
    });
  }

  /// « 1er », « 2e », « 3e »…
  static String _ordinal(int n) => n == 1 ? '1er' : '${n}e';

  /// Arms (or cancels) the 10-second roll timeout: if nobody rolls in time,
  /// the system rolls for them, and 3 such auto-rolls in a row for the same
  /// player forfeits the match for them. Safe to call after any state
  /// change — it only actually starts a timer when it's genuinely someone's
  /// turn to roll.
  void _armRollTimer() {
    _rollTimer?.cancel();
    if (_canAct &&
        _die == 0 &&
        !_done &&
        !_waitingForSquareQuestion &&
        !_resolvingQuestion &&
        _movingPlayer == null &&
        _finishRank[_turn] == 0) {
      _rollTimer = Timer(const Duration(seconds: 10), () => _roll(auto: true));
    }
  }

  Future<void> _roll({bool auto = false}) async {
    if (!_canAct ||
        _die != 0 ||
        _done ||
        _waitingForSquareQuestion ||
        _resolvingQuestion ||
        _movingPlayer != null ||
        _finishRank[_turn] != 0) return;
    _rollTimer?.cancel();
    if (auto) {
      _autoRollStreak[_turn]++;
      if (_autoRollStreak[_turn] >= 3) {
        await _forfeitForInactivity('n’a pas lancé le dé');
        return;
      }
    } else {
      _autoRollStreak[_turn] = 0;
    }
    final guaranteedSix = _missesSinceSix[_turn] >= 3;
    final value = guaranteedSix ? 6 : Random().nextInt(6) + 1;
    final misses = [..._missesSinceSix];
    misses[_turn] = value == 6 ? 0 : misses[_turn] + 1;
    final movable = List<int>.generate(_pawns[_turn].length, (i) => i).where((i) {
      final p = _pawns[_turn][i];
      return p != 57 && (p < 0 ? value == 6 : p + value <= 57);
    }).toList();
    final hasMove = movable.isNotEmpty;
    setState(() {
      _die = value;
      _isDieAnimating = true;
      _missesSinceSix = misses;
      _rollingPlayer = _turn;
      if (!hasMove) {
        _message = guaranteedSix
            ? 'Après trois lancers sans 6, le 6 est garanti. Aucun pion ne peut avancer.'
            : 'Vous avez obtenu $value. Aucun pion ne peut avancer.';
      } else if (movable.length == 1) {
        _message = 'Vous avez obtenu $value. Un seul pion peut jouer : il avance tout seul.';
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
    } else if (movable.length == 1) {
      // Only one legal move: play it automatically, no need to wait for a tap.
      Future<void>.delayed(const Duration(milliseconds: 500), () => _movePawn(movable.first));
    } else {
      _moveTimer?.cancel();
      _moveTimer = Timer(const Duration(seconds: 15), _autoMove);
    }
  }

  void _autoMove() {
    if (!mounted || !_canAct || _die == 0 || _waitingForSquareQuestion || _resolvingQuestion || _done) return;
    final movable = List<int>.generate(_pawns[_turn].length, (i) => i).where((i) {
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
    if (!mounted || player < 0 || player >= _playerCount || pawn < 0 || pawn >= _pawns[player].length) return;
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
      _questionRotation = 0;
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
    final shields = [for (final row in _shieldedPawns) {...row}];
    final shieldTurns = [for (final row in _shieldTurnsRemaining) [...row]];
    // Each completed opponent turn consumes one of the protected pawn's two
    // turns — including a bonus turn from rolling a 6, which is still a
    // turn the opponent takes against the shielded player. Only skip the
    // shield owner's own turn (whether or not it's a bonus one), since that
    // isn't an opponent acting.
    for (var owner = 0; owner < _playerCount; owner++) {
      if (owner == _turn) continue;
      for (var pawn = 0; pawn < shieldTurns[owner].length; pawn++) {
        if (shieldTurns[owner][pawn] <= 0) continue;
        shieldTurns[owner][pawn]--;
        if (shieldTurns[owner][pawn] == 0) shields[owner].remove(pawn);
      }
    }
    setState(() {
      if (!extraTurn) {
        // Un joueur qui a déjà ramené tous ses pions ne rejoue plus : on
        // passe directement au prochain joueur encore en course.
        var next = (_turn + 1) % _playerCount;
        var guard = 0;
        while (_finishRank[next] != 0 && guard < _playerCount) {
          next = (next + 1) % _playerCount;
          guard++;
        }
        _turn = next;
      }
      _shieldedPawns = shields;
      _shieldTurnsRemaining = shieldTurns;
      _rollingPlayer = null;
      _die = 0;
      _shieldAvailable = false;
      _message = extraTurn ? 'Vous avez obtenu 6 : ${_playerName(_turn)} rejoue !' : null;
      _questionDeadline = null;
      _waitingForSquareQuestion = false;
      _resolvingQuestion = false;
    });
    _saveOnlineState();
    _armRollTimer();
  }

  Future<void> _showPlayerAnswerStats(int player) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Questions de ${_playerName(player)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.check_circle, color: JangColors.snGreen),
                const SizedBox(width: 8),
                Text('Bonnes réponses : ${_correctAnswers[player]}'),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.cancel, color: Color(0xFFE31B23)),
                const SizedBox(width: 8),
                Text('Réponses fausses : ${_incorrectAnswers[player]}'),
              ]),
              const SizedBox(height: 12),
              Text('Série actuelle : ${_streaks[player]}/5'),
              if (_shieldedPawns[player].isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Aar actif : ${_shieldTurnsFor(player)} ${_shieldTurnsFor(player) == 1 ? 'tour adverse restant' : 'tours adverses restants'}.',
                ),
              ],
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
        ),
      );

  int _shieldTurnsFor(int player) => _shieldTurnsRemaining[player].fold<int>(
        0,
        (remaining, turns) => turns > remaining ? turns : remaining,
      );

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
    return PopScope(
      canPop: !_playing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmQuit() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Ludo Jàng')),
        body: _onlineMode && !_onlineReady && _roomId != null
            ? _waitingRoomView()
            // Une fois la partie terminée (_done), on reste sur le plateau
            // (avec le classement et le bouton « Nouvelle partie ») au lieu
            // de revenir tout de suite à l'écran de configuration.
            : _questions.isNotEmpty
                ? _gameView()
                : _setupView(),
      ),
    );
  }

  /// Quitting mid-match counts as a forfeit: the player who leaves loses,
  /// and (online) the opponent is told the match is over so they aren't left
  /// waiting forever.
  Future<bool> _confirmQuit() async {
    if (!_playing) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter la partie ?'),
        content: Text(_onlineMode
            ? 'Si tu quittes maintenant, tu abandonnes : tu perds et ton adversaire gagne.'
            : 'Si tu quittes maintenant, la partie s\'arrête et tu perds.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rester')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitter, j’abandonne')),
        ],
      ),
    );
    if (ok != true) return false;
    await _forfeitMatch();
    return true;
  }

  Future<void> _forfeitMatch() async {
    _questionTimer?.cancel();
    _moveTimer?.cancel();
    _rollTimer?.cancel();
    if (_onlineMode && _roomId != null) {
      final uid = AuthService.instance.profile.value?.uid;
      final leavingIndex = uid != null ? _roomUids.indexOf(uid) : -1;
      final winnerIndex = leavingIndex == 0 ? 1 : 0;
      try {
        await FirebaseFirestore.instance.collection('ludoGames').doc(_roomId).update({
          'done': true,
          'message': leavingIndex >= 0
              ? '${_playerName(leavingIndex)} a quitté la partie : ${_playerName(winnerIndex)} gagne !'
              : 'La partie est terminée.',
        });
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _done = true;
        _message = 'Tu as quitté la partie : tu as perdu.';
      });
    }
  }

  /// Ends the match because the active player ([_turn]) let the system play
  /// for them three times in a row — used for the 3-strikes roll timeout.
  Future<void> _forfeitForInactivity(String reasonLabel) async {
    _questionTimer?.cancel();
    _moveTimer?.cancel();
    _rollTimer?.cancel();
    final loser = _turn;
    final winner = loser == 0 ? 1 : 0;
    final message = '${_playerName(loser)} $reasonLabel trois fois de suite : ${_playerName(winner)} gagne !';
    if (_onlineMode && _roomId != null) {
      try {
        await FirebaseFirestore.instance.collection('ludoGames').doc(_roomId).update({
          'done': true,
          'message': message,
        });
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _done = true;
        _message = message;
      });
      _announceMatchEnd(message);
    }
  }

  /// Always tells everyone, clearly, that the match is over, why, and who
  /// won or lost — instead of just changing a line of text in the banner —
  /// then lets them choose what to do next.
  Future<void> _announceMatchEnd(String message) async {
    if (!mounted) return;
    final myUid = AuthService.instance.profile.value?.uid;
    final opponent = myUid == null
        ? -1
        : _roomUids.indexWhere((uid) => uid.isNotEmpty && uid != myUid);
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Partie terminée'),
        content: Text(message),
        actions: [
          if (_canAddXarit(opponent))
            TextButton.icon(
              onPressed: () => _addXarit(opponent),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Ajouter comme Xarit'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, 'quit'), child: const Text('Quitter')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'replay'), child: const Text('Nouvelle partie')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'replay') {
      await _replay();
    } else if (choice == 'quit') {
      Navigator.pop(context);
    }
  }

  /// Rejoue directement avec les mêmes réglages (nombre de joueurs,
  /// catégories, niveau), sans repasser par l’écran de configuration — en
  /// mode « un téléphone » seulement : en ligne, il faut repartir à l’écran
  /// de configuration pour créer ou rejoindre une nouvelle partie avec son
  /// adversaire.
  Future<void> _replay() async {
    if (_onlineMode) {
      setState(() {
        _questions = const [];
        _done = false;
        _onlineReady = false;
        _roomId = null;
        _roomCode = null;
      });
      return;
    }
    await _start();
  }

  Widget _setupView() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Apprenez en jouant', style: titleStyle(22, weight: 800)),
          const SizedBox(height: 8),
          if (widget.challengeFriendName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Défi à ${widget.challengeFriendName} : choisis les options puis crée la partie.',
                  style: titleStyle(14, weight: 700, color: JangColors.snGreen)),
            ),
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
          Text('Nombre de pions', style: titleStyle(18, weight: 800)),
          const SizedBox(height: 4),
          const Text('Avec moins de 4 pions, la partie va plus vite : chaque joueur gagne dès que tous ses pions sont arrivés.'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
            ],
            selected: {_pawnsPerPlayer},
            onSelectionChanged: (value) => setState(() => _pawnsPerPlayer = value.first),
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
              ListTile(leading: CircleAvatar(backgroundColor: _playerColors[i * 2], child: Text('${i + 1}', style: const TextStyle(color: Colors.white))), title: Text(_roomNames[i])),
            if (_roomNames.length < 2) const ListTile(leading: CircularProgressIndicator(), title: Text('En attente d’un autre joueur…')),
          ])),
        ],
      );

  Widget _gameView() => LayoutBuilder(builder: (context, constraints) {
        // The board takes up as much of the screen as it can — bigger than
        // before — while still leaving room above and below for the player
        // row, the shield banner, and the legend.
        final double boardSide = min(constraints.maxWidth - 8, max(220.0, constraints.maxHeight * .68)).toDouble();
        final activeName = _playerName(_turn);
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Column(children: [
            _TurnGlow(
              color: _colorOf(_turn),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(children: [
                  // En face à face, le dé est déjà dans la case du joueur dont
                  // c'est le tour : pas besoin de dire « Joueur 1 » ou « Joueur 2 ».
                  // En ligne, chaque joueur est sur son propre téléphone, donc on
                  // garde le nom pour savoir qui joue.
                  if (_onlineMode) ...[
                    CircleAvatar(radius: 15, backgroundColor: _colorOf(_turn), child: Text('${_turn + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text(_message ?? (_onlineMode ? activeName : ''), maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle(15, weight: 800))),
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
                        message: _finishRank[player] > 0
                            ? '${_playerName(player)} · ${_ordinal(_finishRank[player])}'
                            : '${_playerName(player)} · ${_pawns[player].where((p) => p == 57).length}/${_pawns[player].length} arrivés · série ${_streaks[player]}/5',
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: player == _turn ? _colorOf(player) : _colorOf(player).withValues(alpha: .35),
                          child: _finishRank[player] > 0
                              ? const Icon(Icons.emoji_events, color: Colors.white, size: 14)
                              : Text('${_pawns[player].where((p) => p == 57).length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 34,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var player = 0; player < _playerCount; player++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          OutlinedButton.icon(
                            onPressed: () => _showPlayerAnswerStats(player),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(0, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: Icon(
                              _shieldedPawns[player].isNotEmpty ? Icons.shield_outlined : Icons.quiz_outlined,
                              size: 16,
                              color: _colorOf(player),
                            ),
                            label: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(_playerName(player), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(width: 6),
                              const Icon(Icons.check, size: 14, color: JangColors.snGreen),
                              Text('${_correctAnswers[player]}'),
                              const SizedBox(width: 4),
                              const Icon(Icons.close, size: 14, color: Color(0xFFE31B23)),
                              Text('${_incorrectAnswers[player]}'),
                            ]),
                          ),
                          if (_canSendChatAs(player))
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Tooltip(
                                message: 'Envoyer un petit message',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => _openQuickMessages(player),
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(color: _colorOf(player), shape: BoxShape.circle),
                                    child: const Icon(Icons.chat_bubble, size: 19, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          if (_canAddXarit(player))
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Tooltip(
                                message: 'Ajouter comme Xarit',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => _addXarit(player),
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(color: _colorOf(player), shape: BoxShape.circle),
                                    child: const Icon(Icons.person_add_alt, size: 18, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ),
                  ],
                ),
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
                  Text('Aar rend tous les pions invincibles pendant deux tours adverses.'),
                ]),
              ),
            // Local face-to-face mode shows the question anchored in the
            // active player's own corner of the board (see _board /
            // _cornerQuestionPanel), not here, so this area stays empty
            // while waiting for an answer.
            Expanded(
              child: _waitingForSquareQuestion
                  ? (_onlineMode ? _questionPanel() : const SizedBox.shrink())
                  : _turnPanel(),
            ),
            if (_done)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: JangColors.snGreen,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    if (_onlineMode) _roomSub?.cancel();
                    _replay();
                  },
                  icon: const Icon(Icons.replay),
                  label: const Text('Nouvelle partie'),
                ),
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
              Text(
                _onlineMode
                    ? 'Le dé de ${_playerName(_turn)} apparaîtra ici à son tour.'
                    : 'Le dé de ${_playerName(_turn)} apparaît dans sa case, sur le plateau.',
                textAlign: TextAlign.center,
                style: titleStyle(15, weight: 800),
              ),
            ] else if (_onlineMode) ...[
              // Online: each player has their own phone, so the die stays
              // centered here — there is no shared table to anchor it to.
              if (_die == 0) ...[
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
                const Text('Touchez le dé pour lancer.'),
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
            ] else ...[
              // Face-to-face local play: the die lives in the active
              // player's own corner of the board and the top banner already
              // shows whose turn it is, so this area stays empty instead of
              // repeating "Au tour de…" / "Touchez le dé…" instructions.
              if (_die == 0 && _pawns[_turn].any((p) => p < 0) && _missesSinceSix[_turn] > 0)
                Text('Lancers sans 6 : ${_missesSinceSix[_turn]}/3', style: titleStyle(13, color: JangColors.textSecondary)),
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
    // The bubble's background is the color of whoever has to answer, so
    // it's obvious at a glance whose question this is — with the text
    // color flipped to stay readable on a light color like yellow.
    final activeColor = _colorOf(_turn);
    final onColor = activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    final panel = Card(
      margin: const EdgeInsets.only(top: 5),
      color: activeColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Question · ${QuizBank.levelLabel(_level)}', style: titleStyle(14, weight: 800, color: onColor))),
            Text('$_secondsRemaining s', style: titleStyle(14, weight: 800, color: onColor)),
          ]),
          LinearProgressIndicator(value: _secondsRemaining / 20, color: onColor, backgroundColor: onColor.withValues(alpha: .25), minHeight: 4),
          Expanded(
            // Uses the panel's own actual width (not the full screen width)
            // so the text fills the space it really has instead of being
            // scaled down as if it had the whole screen to work with —
            // that mismatch is what made the question text look tiny in
            // the player's corner.
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Text(question.text.isEmpty ? question.question : '${question.text}\n${question.question}',
                        textAlign: TextAlign.center, style: titleStyle(21, weight: 700, color: onColor)),
                  ),
                ),
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: 44, crossAxisSpacing: 6, mainAxisSpacing: 4),
            itemCount: question.options.length,
            itemBuilder: (context, i) => OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: Colors.white, width: 1.4),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: !_canAct || _secondsRemaining <= 0 ? null : () => _answer(i),
              child: Text(question.options[i], maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black)),
            ),
          ),
        ]),
      ),
    );
    // The panel never rotates — questions always display upright, exactly
    // like the die, whoever's turn it is.
    return panel;
  }

  /// Fixed screen positions (not board-rotated) for each of the four house
  /// corners, used to anchor the face-to-face die so it always appears in
  /// front of the active player without rotating anything.
  static const _seatAlignments = <Alignment>[
    Alignment(-0.6, -0.6), // seat 0 — top-left house
    Alignment(0.6, -0.6), // seat 1 — top-right house
    Alignment(0.6, 0.6), // seat 2 — bottom-right house
    Alignment(-0.6, 0.6), // seat 3 — bottom-left house
  ];

  /// Local face-to-face only: the die appears right next to the active
  /// player's own name card above the board — like the die next to the
  /// avatar in the reference screenshot — instead of sitting on the board.
  /// Back to the original layout: in local face-to-face play, each player's
  /// die sits directly on the board, in their own corner — not next to
  /// their name card.
  Widget _cornerDie(int seat, double paintSide) {
    var player = -1;
    for (var p = 0; p < _playerCount; p++) {
      if (_seatOf(p) == seat) {
        player = p;
        break;
      }
    }
    if (player == -1) return const SizedBox.shrink();
    final isActive = !_onlineMode &&
        _turn == player &&
        _canAct &&
        _movingPlayer == null &&
        !_waitingForSquareQuestion &&
        !_resolvingQuestion &&
        !_done;
    if (!isActive) return const SizedBox.shrink();
    return Align(
      alignment: _seatAlignments[seat],
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: _AnimatedDie(
          value: _die,
          rolling: _isDieAnimating,
          enabled: _die == 0,
          color: _colorOf(player),
          size: paintSide * .16,
          onTap: _roll,
        ),
      ),
    );
  }

  /// Une fois qu'un joueur a ramené tous ses pions, sa place (1er, 2e…)
  /// s'affiche bien visible dans sa case de départ, à la place de ses pions.
  Widget _cornerRankBadge(int seat) {
    var player = -1;
    for (var p = 0; p < _playerCount; p++) {
      if (_seatOf(p) == seat) {
        player = p;
        break;
      }
    }
    if (player == -1 || _finishRank[player] == 0) return const SizedBox.shrink();
    const medalColors = <Color>[
      Color(0xFFF4C430), // or (1er)
      Color(0xFFC0C0C0), // argent (2e)
      Color(0xFFCD7F32), // bronze (3e)
      Color(0xFF9AA5B1), // 4e
    ];
    final rank = _finishRank[player];
    final color = medalColors[(rank - 1).clamp(0, medalColors.length - 1)];
    return Align(
      alignment: _seatAlignments[seat],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.emoji_events, color: Colors.white, size: 20),
          Text(_ordinal(rank), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
      ),
    );
  }

  /// Local face-to-face only: the question (with its answers) appears
  /// anchored in the active player's own corner of the board, exactly like
  /// the die, instead of in a shared spot below the board — leaning toward
  /// that corner while staying large enough to read and tap comfortably.
  Widget _cornerQuestionPanel(double paintSide) {
    final seat = _seatOf(_turn);
    return Align(
      alignment: _seatAlignments[seat],
      child: SizedBox(
        width: paintSide * .92,
        height: paintSide * .92,
        // Tapping the panel (outside the answer buttons) turns it a quarter
        // turn further each time — 0°, 90°, 180°, 270° — so it can be spun
        // all the way around to face whichever side of the table someone
        // is sitting on.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => setState(
            () => _questionRotation = (_questionRotation + 1) % 4,
          ),
          child: RotatedBox(
            quarterTurns: _questionRotation,
            child: _questionPanel(),
          ),
        ),
      ),
    );
  }

  /// A small speech bubble showing a quick message a player just sent,
  /// anchored near their own corner of the board, visible to everyone —
  /// online or face-to-face — for a few seconds before it fades away.
  Widget _chatBubbleOverlay(double paintSide) {
    final player = _chatBubblePlayer!;
    final seat = _seatOf(player);
    return Align(
      alignment: _seatAlignments[seat],
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: paintSide * .55),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _colorOf(player), width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Text(
            _chatBubbleText ?? '',
            textAlign: TextAlign.center,
            style: titleStyle(14, weight: 700),
          ),
        ),
      ),
    );
  }

  Widget _board(double side) {
    final paintSide = side - 14;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _handleBoardTap(details.localPosition, paintSide),
          child: SizedBox(
            width: paintSide,
            height: paintSide,
            child: Stack(children: [
              CustomPaint(
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
              if (!_onlineMode)
                for (var seat = 0; seat < 4; seat++) _cornerDie(seat, paintSide),
              for (var seat = 0; seat < 4; seat++) _cornerRankBadge(seat),
              if (!_onlineMode && _waitingForSquareQuestion) _cornerQuestionPanel(paintSide),
              if (_chatBubblePlayer != null && _chatBubblePlayer! < _playerCount) _chatBubbleOverlay(paintSide),
              if (_showFireworks) const Positioned.fill(child: IgnorePointer(child: Confetti())),
            ]),
          ),
        ),
      ),
    );
  }

  void _handleBoardTap(Offset point, double side) {
    if (_die == 0 || !_canAct || _waitingForSquareQuestion || _done) return;
    final unit = side / 15;
    final homeOrigins = <(int, int)>[(0, 0), (0, 9), (9, 9), (9, 0)];
    const yardSlots = <(int, int)>[(2, 2), (4, 2), (2, 4), (4, 4)];
    const pawnOffsets = <Offset>[Offset.zero, Offset(-.2, -.2), Offset(.2, -.2), Offset.zero];
    var closest = -1;
    var distance = unit * .9;
    for (var pawn = 0; pawn < _pawns[_turn].length; pawn++) {
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
      // Only draw the pawns this player actually has — with fewer than 4
      // pawns chosen for the game, the unused yard slots stay empty instead
      // of showing phantom pawns.
      for (var pawn = 0; pawn < pawns[playerIndex].length; pawn++) {
        final progress = pawns[playerIndex][pawn];
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
    if (shield) {
      // A ring sized relative to the pawn itself (not a fixed font size) so
      // it stays clearly visible whatever the pawn's on-screen size is —
      // the old fixed 8px diamond glyph was effectively invisible.
      canvas.drawCircle(
        center + Offset(0, radius * .05),
        radius * 1.45,
        Paint()
          ..color = const Color(0xFFFFC107)
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.6, radius * .26),
      );
    }
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
      // A small gold badge on the pawn's head, scaled with the pawn — easy
      // to spot even when several pawns are packed close together.
      final badgeCenter = center + Offset(radius * .52, -radius * .62);
      final badgeRadius = max(3.0, radius * .36);
      canvas.drawCircle(badgeCenter, badgeRadius, Paint()..color = const Color(0xFFFFC107));
      canvas.drawCircle(badgeCenter, badgeRadius, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = max(.8, badgeRadius * .18));
      final text = TextPainter(
        text: TextSpan(text: '◆', style: TextStyle(color: Colors.white, fontSize: badgeRadius * 1.3)),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, badgeCenter - Offset(text.width / 2, text.height / 2));
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
