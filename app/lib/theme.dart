import 'package:flutter/material.dart';

/// Palette de Jàng : vert profond et blanc, avec des tons neutres pour la lisibilité.
class JangColors {
  static const background = Colors.white;
  static const text = Color(0xFF3C3C3C);
  static const textSecondary = Color(0xFF777777);
  static const primary = Color(0xFF00853F); // vert Jàng
  static const primaryDark = Color(0xFF00602D);
  static const accent = Color(0xFF00853F); // vert Jàng
  static const accentDark = Color(0xFF00602D);
  static const ocre = Color(0xFFFFC800); // jaune
  static const ocreDark = Color(0xFFE5A500);
  static const surface = Colors.white;
  static const border = Color(0xFFE5E5E5);
  static const success = Color(0xFF58CC02);
  static const successDark = Color(0xFF58A700);
  static const successBg = Color(0xFFD7FFB8);
  static const error = Color(0xFFFF4B4B);
  static const errorDark = Color(0xFFEA2B2B);
  static const errorBg = Color(0xFFFFDFE0);
  static const noteBg = Color(0xFFDDF4FF);
  static const warning = Color(0xFFFF9600);
  static const warningBg = Color(0xFFFFF4D6);

  /// Couleurs du drapeau du Sénégal (accueil).
  static const snGreen = Color(0xFF00853F);
  static const snGreenDark = Color(0xFF00602D);
  static const snYellow = Color(0xFFFDEF42);
  static const snRed = Color(0xFFE31B23);

  /// Couleurs proposées pour les matières (français, maths, anglais, SVT…).
  static const subjectPalette = <String>[
    '#00853F',
    '#00602D',
  ];

  /// Anciennes couleurs des matières : affichées avec la nouvelle palette.
  static const _old = <String, String>{
    '8C2F39': '#FF4B4B',
    '1F4E8C': '#1CB0F6',
    '9A5A00': '#FFC800',
    '5B3F8C': '#58CC02',
    '0F5C4A': '#2B70C9',
    '2E6B73': '#CE82FF',
    '4A5A1F': '#26890C',
    '6B2E5E': '#E21B3C',
    '3A3F4A': '#1368CE',
    'D8562C': '#FF4B4B',
    '2B2E83': '#1CB0F6',
    'EFA82E': '#FFC800',
    '22965A': '#58CC02',
    '0E8FB8': '#2B70C9',
    '8E3B8C': '#CE82FF',
    'C2185B': '#E21B3C',
    '7A4B2A': '#FF9600',
    '00897B': '#26890C',
    '5C6BC0': '#1368CE',
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

  /// Couleur du texte à poser sur [c] (gris foncé sur les couleurs claires, blanc sinon).
  static Color on(Color c) => c.computeLuminance() > 0.55 ? text : Colors.white;

  /// Version plus foncée de [c], pour l'ombre des gros boutons.
  static Color darker(Color c, [double amount = 0.22]) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - amount).clamp(0.0, 1.0)).toColor();
  }
}

const titleFont = 'Nunito';
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
      indicatorColor: JangColors.noteBg,
      height: 70,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? JangColors.primary : JangColors.textSecondary,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: s.contains(WidgetState.selected) ? JangColors.primary : JangColors.textSecondary,
          )),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    dividerTheme: const DividerThemeData(color: JangColors.border, space: 1, thickness: 2),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: JangColors.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
