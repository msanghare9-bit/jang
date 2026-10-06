import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/mission_service.dart';
import '../../theme.dart';
import '../../widgets/characters.dart';
import '../subject_screen.dart';
import 'course_screen.dart';

/// Deux façons d'apprendre une matière qui a un parcours en missions :
/// pratiquer avec Gaïndé (missions) ou lire le cours (leçons, quiz, cartes).
/// L'élève choisit la première fois, puis peut changer quand il veut.
class LearnMode {
  static const practice = 'missions';
  static const read = 'cours';

  static String _key(Subject s) => 'learn_mode_${subjectKey(s.name)}';

  static Future<String?> of(Subject s) async {
    try {
      return (await SharedPreferences.getInstance()).getString(_key(s));
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(Subject s, String mode) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key(s), mode);
    } catch (_) {}
  }

  /// Ouvre la matière dans la façon choisie (et la demande la première fois).
  static Future<void> open(BuildContext context, Subject subject) async {
    final examId = AuthService.instance.profile.value?.examId ?? '';
    final course = await MissionService.instance.courseFor(subject, examId);
    if (!context.mounted) return;
    if (course == null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectScreen(subject: subject)));
      return;
    }
    var mode = await of(subject);
    if (!context.mounted) return;
    if (mode == null) {
      mode = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ChooseSheet(subject: subject),
      );
      if (mode == null || !context.mounted) return;
      await set(subject, mode);
      if (!context.mounted) return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screenFor(mode!, subject, course)));
  }

  static Widget screenFor(String mode, Subject subject, Course course) => mode == read
      ? SubjectScreen(subject: subject, course: course)
      : CourseScreen(course: course, subject: subject);

  /// Change de façon d'apprendre depuis l'un des deux écrans.
  static Future<void> switchTo(BuildContext context, String mode, Subject subject, Course course) async {
    await set(subject, mode);
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screenFor(mode, subject, course),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }
}

class _ChooseSheet extends StatelessWidget {
  final Subject subject;
  const _ChooseSheet({required this.subject});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Comment veux-tu apprendre ?', style: titleStyle(24, weight: 800), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          const Text('Tu peux changer quand tu veux.', textAlign: TextAlign.center),
          const SizedBox(height: 14),
          _Choice(
            character: Chars.lion,
            title: 'Je pratique avec Gaïndé',
            text: 'Tu écoutes, tu parles, tu aides Gaïndé. Des histoires drôles arrivent en route.',
            color: const Color(0xFFFFF4D6),
            onTap: () => Navigator.pop(context, LearnMode.practice),
          ),
          const SizedBox(height: 10),
          _Choice(
            character: Chars.modou,
            title: 'Je lis le cours',
            text: 'Tu lis la leçon, puis tu fais le quiz et les cartes de révision.',
            color: const Color(0xFFE8F1FF),
            onTap: () => Navigator.pop(context, LearnMode.read),
          ),
        ]),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String character;
  final String title;
  final String text;
  final Color color;
  final VoidCallback onTap;
  const _Choice({required this.character, required this.title, required this.text, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CharacterView(character, size: 64),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: titleStyle(19, weight: 800)),
                const SizedBox(height: 2),
                Text(text),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

/// Le sélecteur visible en haut des deux écrans.
class LearnModeSwitch extends StatelessWidget {
  final String current;
  final Subject subject;
  final Course course;
  const LearnModeSwitch({super.key, required this.current, required this.subject, required this.course});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: LearnMode.practice, icon: Icon(Icons.record_voice_over_outlined), label: Text('Je pratique')),
        ButtonSegment(value: LearnMode.read, icon: Icon(Icons.menu_book_outlined), label: Text('Je lis le cours')),
      ],
      selected: {current},
      onSelectionChanged: (s) {
        if (s.first != current) LearnMode.switchTo(context, s.first, subject, course);
      },
    );
  }
}
