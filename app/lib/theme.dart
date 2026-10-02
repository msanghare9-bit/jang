import 'package:flutter/material.dart';

/// Couleurs de Jàng : indigo, terre, ocre et vert, sur fond blanc.
class JangColors {
  static const background = Colors.white;
  static const text = Color(0xFF23255E);
  static const textSecondary = Color(0xFF66658A);
  static const primary = Color(0xFF2B2E83); // indigo
  static const primaryDark = Color(0xFF181A5A);
  static const accent = Color(0xFFD8562C); // terre
  static const accentDark = Color(0xFFAE3F1C);
  static const ocre = Color(0xFFEFA82E);
  static const ocreDark = Color(0xFFC9861A);
  static const surface = Colors.white;
  static const border = Color(0xFFEAE3D6);
  static const success = Color(0xFF22965A);
  static const successDark = Color(0xFF17703F);
  static const successBg = Color(0xFFE3F6EA);
  static const error = Color(0xFFD8562C);
  static const errorBg = Color(0xFFFCE7DF);
  static const noteBg = Color(0xFFE3F6EA);
  static const warning = Color(0xFFB0700D);
  static const warningBg = Color(0xFFFDF0D5);

  /// Couleurs proposées pour les matières (la première série : français, maths, anglais, SVT).
  static const subjectPalette = <String>[
    '#D8562C', // Français : terre
    '#2B2E83', // Maths : indigo
    '#EFA82E', // Anglais : ocre
    '#22965A', // SVT : vert
    '#0E8FB8', // bleu lagune
    '#8E3B8C', // bissap
    '#C2185B', // hibiscus
    '#7A4B2A', // terre de Kébémer
    '#00897B', // menthe
    '#5C6BC0', // lavande
  ];

  /// Anciennes couleurs des matières : affichées avec la nouvelle palette.
  static const _old = <String, String>{
    '8C2F39': '#D8562C',
    '1F4E8C': '#2B2E83',
    '9A5A00': '#EFA82E',
    '5B3F8C': '#22965A',
    '0F5C4A': '#0E8FB8',
    '2E6B73': '#8E3B8C',
    '4A5A1F': '#00897B',
    '6B2E5E': '#C2185B',
    '3A3F4A': '#5C6BC0',
  };

  static Color fromHex(String? hex, {Color fallback = primary}) {
    if (hex == null) return fallback;
    var h = hex.replaceAll('#', '').trim().toUpperCase();
    final mapped = _old[h];
    if (mapped != null) h = mapped.substring(1);
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  /// Couleur du texte à poser sur [c] (indigo sur les couleurs claires, blanc sinon).
  static Color on(Color c) => c.computeLuminance() > 0.4 ? text : Colors.white;

  /// Version plus foncée de [c], pour l'ombre des gros boutons.
  static Color darker(Color c, [double amount = 0.22]) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - amount).clamp(0.0, 1.0)).toColor();
  }
}

const titleFont = 'Baloo';
const bodyFont = 'Nunito';

FontWeight _weight(double w) => FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

TextStyle titleStyle(double size, {Color color = JangColors.text, double weight = 700}) {
  return TextStyle(
    fontFamily: titleFont,
    fontSize: size,
    color: color,
    height: 1.15,
    fontWeight: _weight(weight),
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: JangColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: JangColors.primary,
    onPrimary: Colors.white,
    secondary: JangColors.accent,
    onSecondary: Colors.white,
    surface: JangColors.surface,
    onSurface: JangColors.text,
    onSurfaceVariant: JangColors.textSecondary,
    error: JangColors.error,
    outline: JangColors.border,
  );

  const body = TextStyle(fontFamily: bodyFont, color: JangColors.text, fontWeight: FontWeight.w600);
  final textTheme = TextTheme(
    displaySmall: titleStyle(30, weight: 800),
    headlineMedium: titleStyle(26, weight: 800),
    headlineSmall: titleStyle(22, weight: 800),
    titleLarge: titleStyle(20, weight: 800),
    titleMedium: body.copyWith(fontSize: 17, fontWeight: FontWeight.w800),
    titleSmall: body.copyWith(fontSize: 15, fontWeight: FontWeight.w800),
    bodyLarge: body.copyWith(fontSize: 17, height: 1.5),
    bodyMedium: body.copyWith(fontSize: 16, height: 1.45),
    bodySmall: body.copyWith(fontSize: 14, color: JangColors.textSecondary),
    labelLarge: titleStyle(17, weight: 700),
    labelMedium: body.copyWith(fontSize: 14),
  );

  const minButton = Size(64, 52);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: JangColors.background,
    fontFamily: bodyFont,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: JangColors.background,
      foregroundColor: JangColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: titleStyle(22, weight: 800),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minButton,
        shape: shape,
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minButton,
        shape: shape,
        foregroundColor: JangColors.primary,
        side: const BorderSide(color: JangColors.border, width: 2),
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: JangColors.primary,
        textStyle: textTheme.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: JangColors.border, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: JangColors.border, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: JangColors.primary, width: 2),
      ),
      labelStyle: const TextStyle(color: JangColors.textSecondary),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: JangColors.border, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: JangColors.errorBg,
      height: 70,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? JangColors.accent : JangColors.textSecondary,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: s.contains(WidgetState.selected) ? JangColors.accent : JangColors.textSecondary,
          )),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    dividerTheme: const DividerThemeData(color: JangColors.border, space: 1, thickness: 2),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: JangColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
