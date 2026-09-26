import 'package:flutter/material.dart';

import 'store.dart';

final themeMode = ValueNotifier(ThemeMode.values.asNameMap()[prefs.getString('theme')] ?? ThemeMode.system);

Future<void> setThemeMode(ThemeMode m) async {
  themeMode.value = m;
  await prefs.setString('theme', m.name);
}

/// money in / money out colors, readable on both light and dark surfaces
Color moneyColor(BuildContext context, int signed) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (signed > 0) return dark ? const Color(0xFF6FD69A) : const Color(0xFF16713D);
  if (signed < 0) return dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E);
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  // the seed alone comes out a duller green, so pin the brand one
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0E7C66),
    brightness: brightness,
  ).copyWith(primary: dark ? const Color(0xFF4FBFA5) : const Color(0xFF0E7C66));
  // pill buttons and chips everywhere, like Google's own apps
  const pill = StadiumBorder();
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52), shape: pill),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52), shape: pill),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), shape: pill),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(elevation: 2, shape: pill),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    chipTheme: const ChipThemeData(shape: pill),
  );
}
