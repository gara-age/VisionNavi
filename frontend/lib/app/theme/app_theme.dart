import 'package:flutter/material.dart';

import 'colors.dart';
import 'typography.dart';

ThemeData buildAppTheme() {
  final base = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
  );

  final textTheme = buildTextTheme(base.textTheme).apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.shellBackground,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
    ),
    textTheme: textTheme,
    dividerColor: AppColors.border,
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background,
      hintStyle: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 13,
      ),
      labelStyle: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 13,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    extensions: const <ThemeExtension<dynamic>>[
      AppSurfaceTheme(
        shellBackground: AppColors.shellBackground,
        contentBackground: AppColors.background,
        surface: AppColors.surface,
        textPrimary: AppColors.textPrimary,
        textMuted: AppColors.textMuted,
        border: AppColors.border,
        accent: AppColors.accent,
      ),
    ],
  );
}

@immutable
class AppSurfaceTheme extends ThemeExtension<AppSurfaceTheme> {
  const AppSurfaceTheme({
    required this.shellBackground,
    required this.contentBackground,
    required this.surface,
    required this.textPrimary,
    required this.textMuted,
    required this.border,
    required this.accent,
  });

  final Color shellBackground;
  final Color contentBackground;
  final Color surface;
  final Color textPrimary;
  final Color textMuted;
  final Color border;
  final Color accent;

  @override
  AppSurfaceTheme copyWith({
    Color? shellBackground,
    Color? contentBackground,
    Color? surface,
    Color? textPrimary,
    Color? textMuted,
    Color? border,
    Color? accent,
  }) {
    return AppSurfaceTheme(
      shellBackground: shellBackground ?? this.shellBackground,
      contentBackground: contentBackground ?? this.contentBackground,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      accent: accent ?? this.accent,
    );
  }

  @override
  AppSurfaceTheme lerp(ThemeExtension<AppSurfaceTheme>? other, double t) {
    if (other is! AppSurfaceTheme) {
      return this;
    }

    return AppSurfaceTheme(
      shellBackground: Color.lerp(shellBackground, other.shellBackground, t)!,
      contentBackground: Color.lerp(contentBackground, other.contentBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}
