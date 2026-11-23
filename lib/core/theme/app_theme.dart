import 'package:flutter/material.dart';

/// Mirrors `src/constants/theme.ts` in id-animate-nodes.
class AppPalette extends ThemeExtension<AppPalette> {
  final Color text;
  final Color background;
  final Color backgroundElement;
  final Color backgroundSelected;
  final Color textSecondary;
  final Color border;

  const AppPalette({
    required this.text,
    required this.background,
    required this.backgroundElement,
    required this.backgroundSelected,
    required this.textSecondary,
    required this.border,
  });

  static const light = AppPalette(
    text: Color(0xFF000000),
    background: Color(0xFFFFFFFF),
    backgroundElement: Color(0xFFF0F0F3),
    backgroundSelected: Color(0xFFE0E1E6),
    textSecondary: Color(0xFF60646C),
    border: Color(0xFFD5D6DA),
  );

  static const dark = AppPalette(
    text: Color(0xFFFFFFFF),
    background: Color(0xFF000000),
    backgroundElement: Color(0xFF212225),
    backgroundSelected: Color(0xFF2E3135),
    textSecondary: Color(0xFFB0B4BA),
    border: Color(0xFF3A3D42),
  );

  AppPalette applyBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;

  @override
  AppPalette copyWith({
    Color? text,
    Color? background,
    Color? backgroundElement,
    Color? backgroundSelected,
    Color? textSecondary,
    Color? border,
  }) {
    return AppPalette(
      text: text ?? this.text,
      background: background ?? this.background,
      backgroundElement: backgroundElement ?? this.backgroundElement,
      backgroundSelected: backgroundSelected ?? this.backgroundSelected,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      text: Color.lerp(text, other.text, t)!,
      background: Color.lerp(background, other.background, t)!,
      backgroundElement:
          Color.lerp(backgroundElement, other.backgroundElement, t)!,
      backgroundSelected:
          Color.lerp(backgroundSelected, other.backgroundSelected, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

/// A small set of accent colors used across the editor, kept in sync with
/// the original palette used in SegmentInspector.
const List<Color> accentPalette = [
  Color(0xFF111827),
  Color(0xFF2563EB),
  Color(0xFF059669),
  Color(0xFFD97706),
  Color(0xFFDC2626),
  Color(0xFF7C3AED),
  Color(0xFFDB2777),
  Color(0xFF0D9488),
  Color(0xFF65A30D),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
];

ThemeData buildAppTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2563EB),
    brightness: brightness,
    surface: palette.background,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    fontFamily: 'Inter',
  );

  final textTheme = base.textTheme.apply(
    bodyColor: palette.text,
    displayColor: palette.text,
  );

  return base.copyWith(
    textTheme: textTheme,
    dividerColor: palette.border,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: palette.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardColor: palette.backgroundElement,
    dialogTheme: DialogThemeData(
      backgroundColor: palette.backgroundElement,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.backgroundElement,
    ),
    extensions: [palette],
  );
}

/// Convenience accessor: `Theme.of(context).appColors`.
extension AppColorsX on ThemeData {
  AppPalette get appColors => extension<AppPalette>() ?? AppPalette.light;
}
