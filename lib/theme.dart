import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
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

/// White and neutral grey surfaces, with the brand green only on things you tap or pick.
ColorScheme _scheme(Brightness brightness) => brightness == Brightness.dark
    ? const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFF4FBFA5),
        onPrimary: Color(0xFF00382D),
        primaryContainer: Color(0xFF1B4D42),
        onPrimaryContainer: Color(0xFFBDEBDD),
        secondary: Color(0xFFABAEAE),
        onSecondary: Color(0xFF1F1F1F),
        secondaryContainer: Color(0xFF1B4D42),
        onSecondaryContainer: Color(0xFFBDEBDD),
        tertiary: Color(0xFFA3C9EC),
        onTertiary: Color(0xFF0F2C44),
        tertiaryContainer: Color(0xFF22374A),
        onTertiaryContainer: Color(0xFFCFE3F7),
        error: Color(0xFFF2B8B5),
        onError: Color(0xFF601410),
        errorContainer: Color(0xFF8C1D18),
        onErrorContainer: Color(0xFFF9DEDC),
        surface: Color(0xFF131314),
        onSurface: Color(0xFFE3E3E3),
        onSurfaceVariant: Color(0xFFC4C7C5),
        surfaceBright: Color(0xFF37393A),
        surfaceContainerLowest: Color(0xFF0E0E0F),
        surfaceContainerLow: Color(0xFF1B1B1C),
        surfaceContainer: Color(0xFF1F2020),
        surfaceContainerHigh: Color(0xFF2A2B2C),
        surfaceContainerHighest: Color(0xFF353637),
        outline: Color(0xFF8E918F),
        outlineVariant: Color(0xFF3A3C3C),
        inverseSurface: Color(0xFFE3E3E3),
        onInverseSurface: Color(0xFF2F3030),
        inversePrimary: Color(0xFF0E7C66),
        surfaceTint: Colors.transparent,
      )
    : const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF0E7C66),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFD3EEE6),
        onPrimaryContainer: Color(0xFF0B3D33),
        secondary: Color(0xFF5F6368),
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: Color(0xFFD3EEE6),
        onSecondaryContainer: Color(0xFF0B3D33),
        tertiary: Color(0xFF3B6A8F),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFDCE9F7),
        onTertiaryContainer: Color(0xFF0F2C44),
        error: Color(0xFFB3261E),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFF9DEDC),
        onErrorContainer: Color(0xFF410E0B),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF1F1F1F),
        onSurfaceVariant: Color(0xFF5F6368),
        surfaceDim: Color(0xFFDADCDC),
        surfaceContainerLow: Color(0xFFF8F9F9),
        surfaceContainer: Color(0xFFF3F4F4),
        surfaceContainerHigh: Color(0xFFEDEEEE),
        surfaceContainerHighest: Color(0xFFE6E8E8),
        outline: Color(0xFF747878),
        outlineVariant: Color(0xFFE3E5E4),
        inverseSurface: Color(0xFF2F3030),
        onInverseSurface: Color(0xFFF1F1F1),
        inversePrimary: Color(0xFF7FD8C0),
        surfaceTint: Colors.transparent,
      );

ThemeData buildTheme(Brightness brightness) {
  final scheme = _scheme(brightness);
  // pill buttons and chips everywhere, like Google's own apps
  const pill = StadiumBorder();
  final base = ThemeData(colorScheme: scheme, fontFamily: 'Inter');
  final text = base.textTheme;
  final muted = scheme.onSurfaceVariant;
  return base.copyWith(
    textTheme: text.copyWith(
      bodySmall: text.bodySmall?.copyWith(color: muted),
      labelSmall: text.labelSmall?.copyWith(color: muted),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -.2,
        color: scheme.onSurface,
      ),
    ),
    // a light outline instead of a filled box, so groups read as one piece without weight
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52), shape: pill),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: pill,
        side: BorderSide(color: scheme.outlineVariant),
        foregroundColor: scheme.onSurface,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), shape: pill),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(elevation: 1, highlightElevation: 2, shape: pill),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      subtitleTextStyle: text.bodyMedium?.copyWith(color: muted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? scheme.onSurface : muted,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: BorderSide(color: scheme.outlineVariant),
        selectedBackgroundColor: scheme.secondaryContainer,
        selectedForegroundColor: scheme.onSecondaryContainer,
        foregroundColor: muted,
        minimumSize: const Size(48, 48),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    popupMenuTheme: PopupMenuThemeData(color: scheme.surfaceContainerHigh),
    chipTheme: ChipThemeData(
      shape: pill,
      // a selected chip is filled green, so it needs no outline
      side: WidgetStateBorderSide.resolveWith(
        (s) => s.contains(WidgetState.selected) ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(linearTrackColor: scheme.surfaceContainerHighest),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
