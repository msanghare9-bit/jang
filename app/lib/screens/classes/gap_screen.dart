import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/progress_repo.dart';
import '../../services/speech_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/jang_ui.dart';
import '../mission/mission_screen.dart' show normAnswer;

/// Texte à trous d'un prof : une phrase à la fois, l'élève écrit le mot qui manque.
class GapScreen extends StatefulWidget {
  final ClassItem item;
  final Subject subject;
  const GapScreen({super.key, required this.item, required this.subject});

  @override
  State<GapScreen> createState() => _GapScreenState();
}

class _GapScreenState extends State<GapScreen> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  int _index = 0;
  bool _checked = false;
  bool _ok = false;
  final List<bool> _results = [];
  bool _saved = false;

  /// Micro : seulement en anglais (la reconnaissance vocale écoute l'anglais).
  bool _mic = false;
  bool _listening = false;

  List<GapItem> get _items => widget.item.gapItems.where((g) => g.answers.isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    if (Speech.isEnglish(widget.subject.name)) {
      SpeechInput.instance.available().then((ok) {
        if (mounted) setState(() => _mic = ok);
      });
    }
  }

  @override
  void dispose() {
    SpeechInput.instance.stop();
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    if (_listening) {
      await SpeechInput.instance.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    final ok = await SpeechInput.instance.listen(
      onText: (t) {
        if (mounted && !_checked) setState(() => _ctl.text = t);
      },
      onDone: (t) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!ok && mounted) {
      setState(() => _listening = false);
      showMessage(context, 'Le micro ne marche pas. Écris ta réponse.');
    }
  }

  void _check() {
    final a = normAnswer(_ctl.text);
    if (a.isEmpty) {
      showMessage(context, 'Écris le mot qui manque.');
      return;
    }
    SpeechInput.instance.stop();
    final g = _items[_index];
    final ok = g.answers.expand((x) => x.split('|')).map(normAnswer).where((x) => x.isNotEmpty).contains(a);
    setState(() {
      _checked = true;
      _ok = ok;
      _listening = false;
      _results.add(ok);
    });
  }

  void _next() {
    setState(() {
      _index++;
      _checked = false;
      _ok = false;
      _ctl.clear();
    });
    if (_index >= _items.length && !_saved) {
      _saved = true;
      ProgressRepo.instance.recordQuiz(widget.item.asLesson(widget.subject), List.of(_results));
    } else {
      _focus.requestFocus();
    }
  }

  void _restart() => setState(() {
        _index = 0;
        _checked = false;
        _ok = false;
        _saved = false;
        _results.clear();
        _ctl.clear();
      });

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final color = JangColors.fromHex(widget.subject.color);
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title.isEmpty ? 'Texte à trous' : widget.item.title)),
      body: SafeArea(
        child: items.isEmpty
            ? const EmptyState(
                icon: Icons.hourglass_empty,
                title: 'Pas encore de phrase',
                message: 'Ton prof n\'a pas encore écrit les phrases.')
            : _index >= items.length
                ? _end(items.length)
                : _question(items[_index], items.length, color),
      ),
    );
  }

  Widget _question(GapItem g, int total, Color color) {
    final t = Theme.of(context).textTheme;
    final blank = _checked ? (_ok ? _ctl.text.trim() : g.answers.first) : '______';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(children: [
          Expanded(child: ProgressBar(value: _index / total, color: color)),
          const SizedBox(width: 10),
          Text('${_index + 1} / $total', style: t.titleSmall),
        ]),
        const SizedBox(height: 18),
        Text('Écris le mot qui manque.', style: t.bodyMedium!.copyWith(color: JangColors.textSecondary)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JangColors.noteBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text.rich(
            TextSpan(children: [
              if (g.before.trim().isNotEmpty) TextSpan(text: '${g.before.trim()} '),
              TextSpan(
                text: blank,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _checked ? (_ok ? JangColors.successDark : JangColors.errorDark) : JangColors.primaryDark,
                  decoration: TextDecoration.underline,
                ),
              ),
              if (g.after.trim().isNotEmpty) TextSpan(text: ' ${g.after.trim()}'),
            ]),
            style: titleStyle(22, weight: 700).copyWith(height: 1.5),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctl,
              focusNode: _focus,
              enabled: !_checked,
              autofocus: true,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              decoration: InputDecoration(hintText: _listening ? 'Je t\'écoute…' : 'Ta réponse'),
              onSubmitted: (_) => _checked ? null : _check(),
            ),
          ),
          if (_mic && !_checked) ...[
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Dire ma réponse',
              style: IconButton.styleFrom(
                minimumSize: const Size(52, 52),
                backgroundColor: _listening ? JangColors.error : JangColors.primary,
              ),
              onPressed: _listen,
              icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white),
            ),
          ],
        ]),
        const SizedBox(height: 16),
        if (_checked)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _ok ? JangColors.successBg : JangColors.errorBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Icon(_ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: _ok ? JangColors.successDark : JangColors.errorDark, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _ok ? 'Bravo, c\'est juste !' : 'Pas tout à fait. La bonne réponse : « ${g.answers.first} »',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _ok ? JangColors.successDark : JangColors.errorDark),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 16),
        ChunkyButton(
          label: _checked ? (_index + 1 < total ? 'Continuer' : 'Voir mon score') : 'Vérifier',
          color: _checked && !_ok ? JangColors.error : JangColors.accent,
          onPressed: _checked ? _next : _check,
        ),
      ],
    );
  }

  Widget _end(int total) {
    final score = _results.where((r) => r).length;
    final pct = total == 0 ? 0 : (score * 100 / total).round();
    final msg = pct >= 80
        ? 'Excellent ! Tu as très bien travaillé.'
        : pct >= 50
            ? 'C\'est bien ! Recommence pour faire encore mieux.'
            : 'Courage ! Relis la leçon et recommence.';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 28),
      children: [
        Icon(pct >= 50 ? Icons.emoji_events_rounded : Icons.favorite_rounded,
            size: 72, color: pct >= 50 ? JangColors.ocre : JangColors.error),
        const SizedBox(height: 12),
        Text('$score / $total', textAlign: TextAlign.center, style: titleStyle(44, weight: 900)),
        Text('$pct %', textAlign: TextAlign.center, style: titleStyle(20, color: JangColors.textSecondary)),
        const SizedBox(height: 12),
        Text(msg, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 28),
        ChunkyButton(label: 'Recommencer', icon: Icons.replay_rounded, onPressed: _restart),
        const SizedBox(height: 8),
        ChunkyButton(
          label: 'Retour',
          outlined: true,
          color: JangColors.primary,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
