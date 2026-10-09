import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models.dart';

/// Creates printable lesson PDFs and opens the platform share/save flow.
class LessonPdfService {
  static const _green = PdfColor.fromInt(0xFF00853F);
  static const _ink = PdfColor.fromInt(0xFF20312A);
  static const _muted = PdfColor.fromInt(0xFF5F6F66);

  static Future<void> shareLesson(
    Lesson lesson, {
    required String subjectName,
    String levelName = '',
  }) async {
    await _share(
      title: lesson.title,
      body: lesson.body,
      author: lesson.createdByName,
      subject: subjectName,
      level: levelName,
      quiz: lesson.quiz,
    );
  }

  static Future<void> shareClassItem(ClassItem item, {String levelName = ''}) async {
    final extra = <pw.Widget>[];
    if (item.gapItems.isNotEmpty) {
      extra.add(_heading('Exercices – texte à trous'));
      for (var i = 0; i < item.gapItems.length; i++) {
        final gap = item.gapItems[i];
        extra.add(pw.Text('${i + 1}. ${gap.before} ____ ${gap.after}', style: const pw.TextStyle(color: _ink)));
      }
      extra.add(_heading('Corrigé'));
      for (var i = 0; i < item.gapItems.length; i++) {
        extra.add(pw.Text('${i + 1}. ${item.gapItems[i].answers.join(' / ')}',
            style: const pw.TextStyle(color: _ink)));
      }
    }
    await _share(
      title: item.title,
      body: item.body,
      author: item.ownerName,
      subject: item.subject,
      level: levelName,
      quiz: item.quiz,
      extra: extra,
    );
  }

  static Future<void> _share({
    required String title,
    required String body,
    required String author,
    required String subject,
    required String level,
    List<QuizQuestion> quiz = const [],
    List<pw.Widget> extra = const [],
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Nunito-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Nunito-Bold.ttf'));
    final logo = pw.MemoryImage(
      (await rootBundle.load('tool/icons/mipmap-xxxhdpi/ic_launcher.png')).buffer.asUint8List(),
    );
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      title: title,
      author: author.isEmpty ? 'Équipe Jàng' : author,
      creator: 'Jàng',
    );
    final content = <pw.Widget>[
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Image(logo, width: 42, height: 42),
        pw.SizedBox(width: 10),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Jàng', style: pw.TextStyle(font: bold, fontSize: 22, color: _green)),
          pw.Text('APPRENDRE · PARTAGER · PROGRESSER',
              style: pw.TextStyle(font: bold, fontSize: 8, color: _muted, letterSpacing: 0.6)),
        ]),
      ]),
      pw.SizedBox(height: 16),
      pw.Text(title.trim().isEmpty ? 'Leçon' : title,
          style: pw.TextStyle(font: bold, fontSize: 23, color: _ink)),
      pw.SizedBox(height: 7),
      pw.Wrap(spacing: 6, runSpacing: 5, children: [
        if (subject.trim().isNotEmpty) _tag(subject),
        if (level.trim().isNotEmpty) _tag(level),
        _tag('Ressource créée sur Jàng'),
      ]),
      pw.SizedBox(height: 14),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F7F2), borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('À propos de Jàng', style: pw.TextStyle(font: bold, fontSize: 12, color: _green)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Jàng est une application éducative conçue au Sénégal pour accompagner les élèves dans l’apprentissage. '
            'Elle rassemble des leçons, des exercices et des jeux pour apprendre à l’école et en autonomie.',
            style: const pw.TextStyle(fontSize: 10, color: _ink),
          ),
        ]),
      ),
      pw.SizedBox(height: 9),
      pw.Text('Concepteur : ${author.trim().isEmpty ? 'Équipe Jàng' : author.trim()}',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _muted)),
      pw.SizedBox(height: 16),
      ..._bodyWidgets(body, regular, bold),
      ...extra,
      if (quiz.isNotEmpty) _heading('Exercices'),
      for (var i = 0; i < quiz.length; i++) ..._questionWidgets(quiz[i], i, regular, bold),
      if (quiz.isNotEmpty) _heading('Corrigé détaillé'),
      for (var i = 0; i < quiz.length; i++) ..._answerWidgets(quiz[i], i, regular),
    ];

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 45, 42, 48),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text('Jàng · ${title.trim().isEmpty ? 'Leçon' : title.trim()}',
                  style: const pw.TextStyle(fontSize: 8, color: _muted)),
            ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text('Créé sur Jàng · ${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ),
      build: (_) => content,
    ));

    final safeName = (title.trim().isEmpty ? 'lecon-jang' : title.trim())
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    await Printing.sharePdf(bytes: await pdf.save(), filename: '$safeName-jang.pdf');
  }

  static pw.Widget _tag(String text) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8F3EB), borderRadius: pw.BorderRadius.circular(5)),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 8, color: _green)),
      );

  static pw.Widget _heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 7),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _green)),
      );

  static List<pw.Widget> _bodyWidgets(String body, pw.Font regular, pw.Font bold) {
    final widgets = <pw.Widget>[];
    for (final raw in body.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(pw.SizedBox(height: 4));
      } else if (line.startsWith('### ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Text(_clean(line.substring(4)), style: pw.TextStyle(font: bold, fontSize: 12, color: _green)),
        ));
      } else if (line.startsWith('## ') || line.startsWith('# ')) {
        widgets.add(_heading(_clean(line.replaceFirst(RegExp(r'^#+\s*'), ''))));
      } else if (RegExp(r'^\s*[-*•]\s+').hasMatch(line)) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 8, bottom: 3),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('•  ', style: pw.TextStyle(font: bold, color: _green)),
            pw.Expanded(child: pw.Text(_clean(line.replaceFirst(RegExp(r'^\s*[-*•]\s+'), '')), style: const pw.TextStyle(fontSize: 10, color: _ink))),
          ]),
        ));
      } else {
        widgets.add(pw.Text(_clean(line), style: const pw.TextStyle(fontSize: 10, lineSpacing: 2, color: _ink)));
      }
    }
    return widgets;
  }

  static List<pw.Widget> _questionWidgets(QuizQuestion q, int index, pw.Font regular, pw.Font bold) => [
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
          child: pw.Text('${index + 1}. ${_clean(q.question)}', style: pw.TextStyle(font: bold, fontSize: 11, color: _ink)),
        ),
        for (var i = 0; i < q.options.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, bottom: 2),
            child: pw.Text('${String.fromCharCode(65 + i)}. ${_clean(q.options[i])}', style: pw.TextStyle(font: regular, fontSize: 10, color: _ink)),
          ),
      ];

  static List<pw.Widget> _answerWidgets(QuizQuestion q, int index, pw.Font regular) {
    final correct = q.answer >= 0 && q.answer < q.options.length ? q.options[q.answer] : '';
    final explanation = q.explanation.trim();
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Text('${index + 1}. $correct${explanation.isEmpty ? '' : ' — ${_clean(explanation)}'}',
            style: pw.TextStyle(font: regular, fontSize: 10, color: _ink)),
      ),
    ];
  }

  static String _clean(String text) => text
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAll('`', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
