import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

String durationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 60) return '$minutes min';
  return minutes % 60 == 0
      ? '${minutes ~/ 60} hr'
      : '${minutes ~/ 60} hr ${minutes % 60} min';
}

ThemeData lockinTheme(Brightness brightness, {Color? accent}) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF111113) : const Color(0xFFF7F7F9);
  final ink = dark ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F);
  final secondary = dark ? const Color(0xFFB1B1B7) : const Color(0xFF55555B);
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF0066CC),
        brightness: brightness,
      ).copyWith(
        primary:
            accent ??
            (dark ? const Color(0xFF74B3FF) : const Color(0xFF0066CC)),
        onPrimary: accent != null
            ? Colors.black
            : (dark ? const Color(0xFF002C59) : Colors.white),
        surface: dark ? const Color(0xFF1C1C1E) : Colors.white,
        onSurface: ink,
        onSurfaceVariant: secondary,
        surfaceContainerHighest: dark
            ? const Color(0xFF303034)
            : const Color(0xFFE9E9ED),
        surfaceContainerLow: background,
        outline: dark ? const Color(0xFF65656C) : const Color(0xFF98989E),
        outlineVariant: dark
            ? const Color(0xFF353539)
            : const Color(0xFFDDDDE2),
        tertiary: dark ? const Color(0xFFE5C07B) : const Color(0xFF85570D),
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    fontFamily: 'Inter',
  );
  return base.copyWith(
    scaffoldBackgroundColor: background,
    dividerColor: colors.outlineVariant,
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: .5,
      space: 1,
    ),
    textTheme: base.textTheme
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
            color: ink,
            height: 1.15,
          ),
          headlineSmall: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            letterSpacing: -.5,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            letterSpacing: -.3,
            color: ink,
          ),
          bodyLarge: TextStyle(fontSize: 15, color: ink, height: 1.5),
          bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.5),
          bodySmall: TextStyle(
            fontSize: 13,
            color: secondary,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        )
        .apply(fontFamily: 'Inter'),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: colors.primary,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(fontFamily: 'Inter', fontSize: 14, color: ink),
        actionTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 17,
          color: colors.primary,
        ),
        tabLabelTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: background,
        elevation: 0,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: colors.outlineVariant),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      helperMaxLines: 3,
      errorMaxLines: 3,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: .15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant, width: .5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.transparent,
      selectedColor: colors.surfaceContainerHighest,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: secondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        height: 1.6,
        color: secondary,
      ),
    ),
  );
}
