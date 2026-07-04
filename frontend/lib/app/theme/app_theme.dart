import 'package:flutter/material.dart';

import 'colors.dart';
import 'typography.dart';

ThemeData buildAppTheme({
  bool darkTheme = false,
  bool highContrast = false,
  bool largeText = false,
}) {
  final brightness = darkTheme ? Brightness.dark : Brightness.light;

  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Pretendard',
  );

  final background = highContrast
      ? Colors.black
      : (darkTheme ? const Color(0xFF101214) : AppColors.background);

  final surface = highContrast
      ? const Color(0xFF000000)
      : (darkTheme ? const Color(0xFF181B20) : AppColors.surface);

  final scaffold = highContrast
      ? const Color(0xFF000000)
      : (darkTheme ? const Color(0xFF0D1117) : AppColors.shellBackground);

  final textPrimary = highContrast
      ? Colors.white
      : (darkTheme ? const Color(0xFFF3F4F6) : AppColors.textPrimary);

  final textMuted = highContrast
      ? const Color(0xFFE5E7EB)
      : (darkTheme ? const Color(0xFFCBD5E1) : AppColors.textMuted);

  final border = highContrast
      ? const Color(0xFFFFFFFF)
      : (darkTheme ? const Color(0xFF3A4250) : AppColors.border);

  final accent = highContrast
      ? AppColors.accent
      : (darkTheme ? const Color(0xFF60A5FA) : AppColors.accent);

  final rawTextTheme = buildTextTheme(base.textTheme).apply(
    bodyColor: textPrimary,
    displayColor: textPrimary,
    fontFamily: 'Pretendard',
  );
  final resolvedTextTheme = rawTextTheme.copyWith(
    displayLarge: rawTextTheme.displayLarge?.copyWith(color: textPrimary),
    displayMedium: rawTextTheme.displayMedium?.copyWith(color: textPrimary),
    displaySmall: rawTextTheme.displaySmall?.copyWith(color: textPrimary),
    headlineLarge: rawTextTheme.headlineLarge?.copyWith(color: textPrimary),
    headlineMedium: rawTextTheme.headlineMedium?.copyWith(color: textPrimary),
    headlineSmall: rawTextTheme.headlineSmall?.copyWith(color: textPrimary),
    titleLarge: rawTextTheme.titleLarge?.copyWith(color: textPrimary),
    titleMedium: rawTextTheme.titleMedium?.copyWith(color: textPrimary),
    titleSmall: rawTextTheme.titleSmall?.copyWith(color: textPrimary),
    bodyLarge: rawTextTheme.bodyLarge?.copyWith(color: textPrimary),
    bodyMedium: rawTextTheme.bodyMedium?.copyWith(color: textPrimary),
    bodySmall: rawTextTheme.bodySmall?.copyWith(color: textMuted),
    labelLarge: rawTextTheme.labelLarge?.copyWith(color: textPrimary),
    labelMedium: rawTextTheme.labelMedium?.copyWith(color: textPrimary),
    labelSmall: rawTextTheme.labelSmall?.copyWith(color: textMuted),
  );

  final textTheme =
      _scaleTextTheme(resolvedTextTheme, largeText ? 1.14 : 1.0);

  return base.copyWith(
    scaffoldBackgroundColor: scaffold,
    canvasColor: background,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: highContrast ? Colors.black : Colors.white,
      secondary: accent,
      onSecondary: highContrast ? Colors.black : Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
    ),
    textTheme: textTheme,
    iconTheme: IconThemeData(color: textPrimary),
    dividerColor: border,
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      hintStyle: TextStyle(
        fontFamily: 'Pretendard',
        color: textMuted,
        fontSize: 13,
      ),
      labelStyle: TextStyle(
        fontFamily: 'Pretendard',
        color: textMuted,
        fontSize: 13,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: highContrast ? 2 : 1.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: highContrast ? Colors.black : Colors.white,
        minimumSize: const Size(0, 54),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: largeText ? 15 : 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 54),
        backgroundColor: surface,
        side: BorderSide(color: border),
        foregroundColor: textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: largeText ? 15 : 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: highContrast ? accent : textPrimary,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: highContrast ? 0.35 : 0.22),
      selectionHandleColor: accent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accent;
        }
        return highContrast ? Colors.white : null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accent.withValues(alpha: highContrast ? 0.65 : 0.45);
        }
        return highContrast ? const Color(0xFF222222) : null;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return highContrast ? Colors.white : null;
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: accent.withValues(alpha: 0.14),
      disabledColor: surface,
      side: BorderSide(color: border, width: highContrast ? 1.4 : 1.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      labelStyle: TextStyle(
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      brightness: brightness,
    ),
    extensions: <ThemeExtension<dynamic>>[
      AppSurfaceTheme(
        shellBackground: scaffold,
        contentBackground: background,
        surface: surface,
        textPrimary: textPrimary,
        textMuted: textMuted,
        border: border,
        accent: accent,
      ),
    ],
  );
}

TextTheme _scaleTextTheme(TextTheme theme, double factor) {
  if (factor == 1.0) {
    return theme;
  }

  TextStyle? scale(TextStyle? style) => style?.copyWith(
        fontSize: style.fontSize == null ? null : style.fontSize! * factor,
      );

  return theme.copyWith(
    displayLarge: scale(theme.displayLarge),
    displayMedium: scale(theme.displayMedium),
    displaySmall: scale(theme.displaySmall),
    headlineLarge: scale(theme.headlineLarge),
    headlineMedium: scale(theme.headlineMedium),
    headlineSmall: scale(theme.headlineSmall),
    titleLarge: scale(theme.titleLarge),
    titleMedium: scale(theme.titleMedium),
    titleSmall: scale(theme.titleSmall),
    bodyLarge: scale(theme.bodyLarge),
    bodyMedium: scale(theme.bodyMedium),
    bodySmall: scale(theme.bodySmall),
    labelLarge: scale(theme.labelLarge),
    labelMedium: scale(theme.labelMedium),
    labelSmall: scale(theme.labelSmall),
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
