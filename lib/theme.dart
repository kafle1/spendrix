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
  if (signed > 0) return dark ? const Color(0xFF7DD3A0) : const Color(0xFF1B7443);
  if (signed < 0) return dark ? const Color(0xFFF4978B) : const Color(0xFFB4332A);
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

// warm paper and ink, picked by hand so it doesn't read as a seeded palette
const _light = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF0E7C66),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFDCEFE8),
  onPrimaryContainer: Color(0xFF064537),
  secondary: Color(0xFF56625E),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFEFEBE2),
  onSecondaryContainer: Color(0xFF2E5249),
  tertiary: Color(0xFF8A5A00),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFF7E8C9),
  onTertiaryContainer: Color(0xFF3B2600),
  error: Color(0xFFB4332A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF9E0DC),
  onErrorContainer: Color(0xFF5C130E),
  surface: Color(0xFFF7F5F0),
  onSurface: Color(0xFF1C1B18),
  onSurfaceVariant: Color(0xFF5F5A51),
  surfaceDim: Color(0xFFE3DED4),
  surfaceBright: Color(0xFFFFFFFF),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFF3F0EA),
  surfaceContainerHigh: Color(0xFFEEEAE3),
  surfaceContainerHighest: Color(0xFFE6E1D7),
  outline: Color(0xFF8A8478),
  outlineVariant: Color(0xFFE4DFD4),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF2B2925),
  onInverseSurface: Color(0xFFF3EFE7),
  inversePrimary: Color(0xFF4FBFA5),
  surfaceTint: Colors.transparent,
);

const _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF4FBFA5),
  onPrimary: Color(0xFF00382D),
  primaryContainer: Color(0xFF133F35),
  onPrimaryContainer: Color(0xFFBDEBDD),
  secondary: Color(0xFFB7C9C2),
  onSecondary: Color(0xFF1F2D29),
  secondaryContainer: Color(0xFF2B2925),
  onSecondaryContainer: Color(0xFFB9DDD1),
  tertiary: Color(0xFFE7B865),
  onTertiary: Color(0xFF3F2A00),
  tertiaryContainer: Color(0xFF45320F),
  onTertiaryContainer: Color(0xFFF6E1B8),
  error: Color(0xFFF4978B),
  onError: Color(0xFF4A0C06),
  errorContainer: Color(0xFF5C1A14),
  onErrorContainer: Color(0xFFFFDAD5),
  surface: Color(0xFF151412),
  onSurface: Color(0xFFECE8E0),
  onSurfaceVariant: Color(0xFFB3ADA2),
  surfaceDim: Color(0xFF151412),
  surfaceBright: Color(0xFF3A3732),
  surfaceContainerLowest: Color(0xFF100F0D),
  surfaceContainerLow: Color(0xFF1E1C19),
  surfaceContainer: Color(0xFF221F1C),
  surfaceContainerHigh: Color(0xFF2A2825),
  surfaceContainerHighest: Color(0xFF35322E),
  outline: Color(0xFF8F897E),
  outlineVariant: Color(0xFF34312C),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFECE8E0),
  onInverseSurface: Color(0xFF22201C),
  inversePrimary: Color(0xFF0B6B58),
  surfaceTint: Colors.transparent,
);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _dark : _light;
  final card = scheme.surfaceContainerLow;
  final line = scheme.outlineVariant;
  // a step stronger than the card hairline, for things you tap or type into
  final field = dark ? const Color(0xFF4A463F) : const Color(0xFFD3CCBF);

  // sizes baked in, since component themes (app bar, chips, nav) never get the geometry merged later
  final base = Typography.englishLike2021.merge(ThemeData(colorScheme: scheme, fontFamily: 'Inter').textTheme);
  TextStyle serif(TextStyle? s, double spacing) =>
      s!.copyWith(fontFamily: 'Newsreader', fontWeight: FontWeight.w600, letterSpacing: spacing);
  TextStyle sans(TextStyle? s, [FontWeight? w]) => s!.copyWith(letterSpacing: 0, fontWeight: w);
  final text = base.copyWith(
    displayLarge: serif(base.displayLarge, -1),
    displayMedium: serif(base.displayMedium, -.8),
    displaySmall: serif(base.displaySmall, -.6),
    headlineLarge: serif(base.headlineLarge, -.4),
    headlineMedium: serif(base.headlineMedium, -.3),
    headlineSmall: serif(base.headlineSmall, -.2),
    titleLarge: serif(base.titleLarge, -.1),
    titleMedium: sans(base.titleMedium, FontWeight.w600),
    titleSmall: sans(base.titleSmall, FontWeight.w600),
    bodyLarge: sans(base.bodyLarge),
    bodyMedium: sans(base.bodyMedium),
    bodySmall: sans(base.bodySmall),
    labelLarge: sans(base.labelLarge, FontWeight.w600),
    labelMedium: sans(base.labelMedium),
    labelSmall: base.labelSmall!.copyWith(letterSpacing: .2),
  );

  bool on(Set<WidgetState> s) => s.contains(WidgetState.selected);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Inter',
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineSmall!.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: card,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: line),
      ),
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      iconColor: scheme.onSurfaceVariant,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      activeIndicatorBorder: WidgetStateBorderSide.resolveWith((s) {
        final focused = s.contains(WidgetState.focused);
        if (s.contains(WidgetState.error)) return BorderSide(color: scheme.error, width: focused ? 1.6 : 1);
        if (focused) return BorderSide(color: scheme.primary, width: 1.6);
        return BorderSide(color: s.contains(WidgetState.disabled) ? line : field);
      }),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52), shape: rounded),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: rounded,
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: field),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: text.labelLarge,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: field),
        foregroundColor: scheme.onSurfaceVariant,
        selectedForegroundColor: scheme.onPrimaryContainer,
        selectedBackgroundColor: scheme.primaryContainer,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
      color: WidgetStateColor.resolveWith((s) => on(s) ? scheme.primaryContainer : Colors.transparent),
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(color: on(s) ? scheme.primary.withValues(alpha: .5) : field),
      ),
      labelStyle: text.labelLarge!.copyWith(
        fontWeight: FontWeight.w500,
        color: WidgetStateColor.resolveWith((s) => on(s) ? scheme.onPrimaryContainer : scheme.onSurface),
      ),
      iconTheme: IconThemeData(size: 18, color: scheme.onSurfaceVariant),
    ),
    switchTheme: SwitchThemeData(
      // same size thumb on and off, no outlined track
      thumbIcon: const WidgetStatePropertyAll(Icon(null)),
      thumbColor: WidgetStateColor.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return scheme.onSurface.withValues(alpha: .3);
        return on(s) ? scheme.onPrimary : scheme.outline;
      }),
      trackColor: WidgetStateColor.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return scheme.onSurface.withValues(alpha: .08);
        return on(s) ? scheme.primary : scheme.surfaceContainerHighest;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      indicatorShape: rounded,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(size: 24, color: on(s) ? scheme.primary : scheme.onSurfaceVariant),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium!.copyWith(
          color: on(s) ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: on(s) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: Colors.transparent,
      indicatorShape: rounded,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: text.labelMedium!.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: text.labelMedium!.copyWith(color: scheme.onSurfaceVariant),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      dragHandleColor: scheme.outline,
      backgroundColor: card,
      modalBackgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
