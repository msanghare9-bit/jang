import 'package:flutter/material.dart';

class JangColors {
  static const background = Color(0xFFF4F6F2);
  static const text = Color(0xFF16241F);
  static const textSecondary = Color(0xFF4E5E57);
  static const primary = Color(0xFF0F5C4A);
  static const surface = Colors.white;
  static const border = Color(0xFFD9DFD9);
  static const success = Color(0xFF1E7A46);
  static const successBg = Color(0xFFE3F2E8);
  static const error = Color(0xFFA1262E);
  static const errorBg = Color(0xFFF8E3E4);
  static const noteBg = Color(0xFFE6EFEA);

  /// Couleurs proposées pour les matières (la première série est celle du BFEM).
  static const subjectPalette = <String>[
    '#8C2F39', // Français
    '#1F4E8C', // Maths
    '#9A5A00', // Anglais
    '#5B3F8C', // SVT
    '#0F5C4A',
    '#2E6B73',
    '#7A4B2A',
    '#4A5A1F',
    '#6B2E5E',
    '#3A3F4A',
  ];

  static Color fromHex(String? hex, {Color fallback = primary}) {
    if (hex == null) return fallback;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }
}

const _titleFont = 'Bricolage';
const _bodyFont = 'Atkinson';

TextStyle titleStyle(double size, {Color color = JangColors.text, double weight = 700}) {
  return TextStyle(
    fontFamily: _titleFont,
    fontSize: size,
    color: color,
    height: 1.2,
    fontVariations: [FontVariation('wght', weight)],
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: JangColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: JangColors.primary,
    onPrimary: Colors.white,
    surface: JangColors.surface,
    onSurface: JangColors.text,
    onSurfaceVariant: JangColors.textSecondary,
    error: JangColors.error,
    outline: JangColors.border,
  );

  const body = TextStyle(fontFamily: _bodyFont, color: JangColors.text);
  final textTheme = TextTheme(
    displaySmall: titleStyle(30),
    headlineMedium: titleStyle(26),
    headlineSmall: titleStyle(22),
    titleLarge: titleStyle(20),
    titleMedium: body.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
    titleSmall: body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
    bodyLarge: body.copyWith(fontSize: 17, height: 1.5),
    bodyMedium: body.copyWith(fontSize: 16, height: 1.45),
    bodySmall: body.copyWith(fontSize: 14, color: JangColors.textSecondary),
    labelLarge: body.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
    labelMedium: body.copyWith(fontSize: 14),
  );

  const minButton = Size(64, 48);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: JangColors.background,
    fontFamily: _bodyFont,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: JangColors.background,
      foregroundColor: JangColors.text,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: titleStyle(20),
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
        side: const BorderSide(color: JangColors.primary, width: 1.4),
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: minButton,
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
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: JangColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: JangColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: JangColors.primary, width: 2),
      ),
      labelStyle: const TextStyle(color: JangColors.textSecondary),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: JangColors.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: JangColors.noteBg,
      height: 68,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontFamily: _bodyFont, fontSize: 13, color: JangColors.text),
      ),
    ),
    dividerTheme: const DividerThemeData(color: JangColors.border, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
