import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../services/speech_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/jang_ui.dart';
import '../home_screen.dart' show formatDate;
import '../tutor_screen.dart';

/// Devoir d'un prof : la consigne, la réponse de l'élève, puis la note du prof.
class HomeworkScreen extends StatefulWidget {
  final ClassItem item;
  final Subject subject;
  const HomeworkScreen({super.key, required this.item, required this.subject});

  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  final _ctl = TextEditingController();
  Submission? _sub;
  bool _loading = true;
  bool _loadError = false;
  bool _editing = false;
  bool _sending = false;

  /// Micro : seulement en anglais (la reconnaissance vocale écoute l'anglais).
  bool _mic = false;
  bool _listening = false;
  String _before = '';

  bool get _late => widget.item.dueAt != null && DateTime.now().isAfter(widget.item.dueAt!);

  @override
  void initState() {
    super.initState();
    _load();
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
    super.dispose();
  }

  Future<void> _load() async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final s = await ClassService.instance.mySubmission(widget.item.id, p.uid);
      if (!mounted) return;
      setState(() {
        _sub = s;
        _editing = s == null;
        if (s != null) _ctl.text = s.text;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  Future<void> _listen() async {
    if (_listening) {
      await SpeechInput.instance.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final t = _ctl.text.trimRight();
    _before = t.isEmpty ? '' : '$t ';
    setState(() => _listening = true);
    final ok = await SpeechInput.instance.listen(
      onText: (said) {
        if (!mounted) return;
        _ctl.text = '$_before$said';
        _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
      },
      onDone: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!ok && mounted) {
      setState(() => _listening = false);
      showMessage(context, 'Le micro ne marche pas. Écris ta réponse.');
    }
  }

  Future<void> _send() async {
    final p = AuthService.instance.profile.value;
    if (p == null || _sending) return;
    if (_late) {
      showMessage(context, 'Le délai de ce devoir est dépassé.');
      return;
    }
    if (_ctl.text.trim().isEmpty) {
      showMessage(context, 'Écris ta réponse avant de rendre ton devoir.');
      return;
    }
    await SpeechInput.instance.stop();
    setState(() {
      _sending = true;
      _listening = false;
    });
    try {
      await ClassService.instance.submit(widget.item, p, _ctl.text);
      if (!mounted) return;
      showMessage(context, 'Devoir rendu ! Ton prof va le lire.');
      setState(() => _sending = false);
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showMessage(context, 'Pas de connexion internet. Ta réponse est gardée ici : réessaie plus tard.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = JangColors.fromHex(widget.subject.color);
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title.isEmpty ? 'Devoir' : widget.item.title)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  Text('La consigne', style: titleStyle(19, weight: 800)),
                  const SizedBox(height: 8),
                  if (widget.item.dueAt != null) ...[
                    Row(children: [
                      Icon(_late ? Icons.event_busy : Icons.event,
                          color: _late ? JangColors.errorDark : JangColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _late
                              ? 'Délai dépassé'
                              : 'À rendre avant le ${widget.item.dueAt!.day.toString().padLeft(2, '0')}/${widget.item.dueAt!.month.toString().padLeft(2, '0')}/${widget.item.dueAt!.year} à ${widget.item.dueAt!.hour.toString().padLeft(2, '0')}:${widget.item.dueAt!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: _late ? JangColors.errorDark : JangColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
                    ),
                    child: widget.item.body.trim().isEmpty
                        ? const Text('Ton prof t\'expliquera le devoir en classe.')
                        : LessonText(widget.item.body, accent: color),
                  ),
                  if (!(AuthService.instance.profile.value?.isStaff ?? false)) ...[
                    const SizedBox(height: 10),
                    ChunkyButton(
                      label: 'Demander un indice à Kocc Bàrma',
                      icon: Icons.lightbulb_outline,
                      outlined: true,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TutorScreen(
                            lesson: widget.item.asLesson(widget.subject),
                            subject: widget.subject,
                            homeworkCoach: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (widget.item.ownerName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Donné par ${widget.item.ownerName}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 20),
                  if (_loadError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('Pas de connexion : je ne sais pas si tu as déjà rendu ce devoir.',
                          style: TextStyle(color: JangColors.errorDark, fontWeight: FontWeight.w700)),
                    ),
                  if (_sub != null && !_editing) ..._done(_sub!) else ..._form(),
                ],
              ),
      ),
    );
  }

  List<Widget> _done(Submission s) {
    final t = Theme.of(context).textTheme;
    return [
      Row(children: [
        const Icon(Icons.check_circle_rounded, color: JangColors.success),
        const SizedBox(width: 8),
        Expanded(child: Text('Tu as rendu ton devoir', style: titleStyle(19, weight: 800))),
      ]),
      const SizedBox(height: 4),
      Text(s.at == null ? 'À l\'instant' : 'Le ${formatDate(s.at!)}', style: t.bodySmall),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SelectableText(s.text, style: t.bodyLarge),
        ),
      ),
      const SizedBox(height: 16),
      if (s.graded)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: JangColors.successBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Corrigé par ton prof', style: titleStyle(17, color: JangColors.successDark, weight: 800)),
            if (s.grade.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Note : ${s.grade}', style: titleStyle(26, weight: 900)),
            ],
            if (s.comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(s.comment, style: t.bodyLarge),
            ],
          ]),
        )
      else ...[
        Text(_late
            ? 'Le délai est dépassé. Ton prof peut encore consulter ta réponse.'
            : 'Ton prof n\'a pas encore corrigé. Tu peux encore changer ta réponse.', style: t.bodyMedium),
        const SizedBox(height: 12),
        ChunkyButton(
          label: 'Modifier ma réponse',
          icon: Icons.edit_rounded,
          outlined: true,
          color: JangColors.primary,
          onPressed: _late ? null : () => setState(() => _editing = true),
        ),
      ],
    ];
  }

  List<Widget> _form() {
    return [
      Text('Ma réponse', style: titleStyle(19, weight: 800)),
      const SizedBox(height: 8),
      TextField(
        controller: _ctl,
        minLines: 8,
        maxLines: 20,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.w600),
        decoration: InputDecoration(hintText: _listening ? 'Je t\'écoute…' : 'Écris ta réponse ici.'),
      ),
      if (_mic) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _listen,
            icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded,
                color: _listening ? JangColors.error : JangColors.primary),
            label: Text(_listening ? 'J\'arrête' : 'Dire ma réponse'),
          ),
        ),
      ],
      const SizedBox(height: 16),
      ChunkyButton(
        label: _late ? 'Délai dépassé' : (_sending ? 'Envoi…' : 'Rendre mon devoir'),
        icon: Icons.send_rounded,
        onPressed: _sending || _late ? null : _send,
      ),
      if (_sub != null) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: _sending
              ? null
              : () => setState(() {
                    _editing = false;
                    _ctl.text = _sub!.text;
                  }),
          child: const Text('Annuler'),
        ),
      ],
    ];
  }
}
