import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/content_repo.dart';
import '../../theme.dart';

/// Recharge l'écran chaque fois que le contenu change.
mixin RepoListener<T extends StatefulWidget> on State<T> {
  Future<void> load();

  void _onRevision() => load();

  @override
  void initState() {
    super.initState();
    load();
    ContentRepo.instance.revision.addListener(_onRevision);
  }

  @override
  void dispose() {
    ContentRepo.instance.revision.removeListener(_onRevision);
    super.dispose();
  }
}

/// Ligne d'administration : titre + boutons monter / descendre / modifier / supprimer.
class AdminRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const AdminRow({
    super.key,
    required this.title,
    this.subtitle,
    this.color,
    this.onTap,
    this.onUp,
    this.onDown,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
            child: Row(
              children: [
                if (color != null) ...[
                  Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleMedium),
                        if (subtitle != null)
                          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
                if (onUp != null || onDown != null) ...[
                  IconButton(
                      tooltip: 'Monter',
                      onPressed: onUp,
                      icon: const Icon(Icons.arrow_upward)),
                  IconButton(
                      tooltip: 'Descendre',
                      onPressed: onDown,
                      icon: const Icon(Icons.arrow_downward)),
                ],
                if (onEdit != null || onDelete != null)
                  PopupMenuButton<String>(
                    tooltip: 'Options',
                    onSelected: (v) {
                      if (v == 'edit') onEdit?.call();
                      if (v == 'delete') onDelete?.call();
                    },
                    itemBuilder: (_) => [
                      if (onEdit != null) const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                      if (onDelete != null)
                        const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> askText(BuildContext context, String title, String label, {String? initial}) {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: titleStyle(20)),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.pop(c, v);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}

/// Création ou modification d'une matière (nom + couleur).
class SubjectDialog extends StatefulWidget {
  final Subject? subject;

  /// Toutes les classes, et la classe depuis laquelle on ouvre la fenêtre.
  final List<Exam> exams;
  final String examId;
  const SubjectDialog({super.key, this.subject, this.exams = const [], this.examId = ''});

  @override
  State<SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<SubjectDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.subject?.name ?? '');
  late String _color = widget.subject?.color ?? JangColors.subjectPalette.first;
  late final Set<String> _classes = {
    ...?widget.subject?.examIds,
    if (widget.subject == null && widget.examId.isNotEmpty) widget.examId,
  };

  /// Classe principale : elle reste toujours cochée.
  String get _main => widget.subject?.examId ?? widget.examId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.subject == null ? 'Nouvelle matière' : 'Modifier la matière',
          style: titleStyle(20)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nom de la matière'),
            ),
            const SizedBox(height: 16),
            const Text('Couleur'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: JangColors.subjectPalette.map((hex) {
                final selected = hex.toUpperCase() == _color.toUpperCase();
                return InkWell(
                  onTap: () => setState(() => _color = hex),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: JangColors.fromHex(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: selected ? JangColors.text : Colors.transparent, width: 3),
                    ),
                    child: selected ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                );
              }).toList(),
            ),
            if (widget.exams.length > 1) ...[
              const SizedBox(height: 18),
              const Text('Classes qui voient cette matière'),
              const SizedBox(height: 4),
              Text('Coche plusieurs classes pour partager les mêmes leçons (ex. 6e et 5e).',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in widget.exams)
                    FilterChip(
                      label: Text(e.name),
                      selected: _classes.contains(e.id),
                      onSelected: e.id == _main
                          ? null
                          : (v) => setState(() => v ? _classes.add(e.id) : _classes.remove(e.id)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final n = _name.text.trim();
            if (n.isNotEmpty) {
              Navigator.pop(context, (n, _color, {if (_main.isNotEmpty) _main, ..._classes}.toList()));
            }
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
