import 'package:flutter/material.dart';

/// STEP identity, taken from step-v2: --step-blue #05056a carries every action,
/// its #eef2ff tint marks selection, and blue-600 is reserved for links and
/// interactive accents. Neutrals are the Tailwind gray scale step-v2 already
/// uses, so a screen here sits beside a page there without a seam.
///
/// step-v2 is light-only; the dark set below is this app's own extension.
/// These values are mirrored in chat-app/resources/css/app.css — change both.
abstract final class StepPalette {
  // Light
  static const background = Color(0xfff9fafb);
  static const foreground = Color(0xff111827);
  static const card = Color(0xffffffff);
  static const muted = Color(0xfff3f4f6);
  static const mutedForeground = Color(0xff6b7280);
  static const border = Color(0xffe5e7eb);
  static const brand = Color(0xff05056a);
  static const brandForeground = Color(0xffeef2ff);
  static const accentSurface = Color(0xffeef2ff);
  static const highlight = Color(0xff2563eb);
  static const destructive = Color(0xffdc2626);
  static const messageIncoming = Color(0xffffffff);

  // Dark
  static const backgroundDark = Color(0xff0a0c18);
  static const foregroundDark = Color(0xffe8eaf3);
  static const cardDark = Color(0xff12152a);
  static const mutedDark = Color(0xff1b1f38);
  static const mutedForegroundDark = Color(0xff9aa1bd);
  static const borderDark = Color(0xff252a4a);
  static const brandDark = Color(0xffb3bcff);
  static const brandSolidDark = Color(0xff2a2a8f);
  static const accentSurfaceDark = Color(0xff1d2350);
  static const highlightDark = Color(0xff60a5fa);
  static const destructiveDark = Color(0xfff87171);
  static const messageIncomingDark = Color(0xff181c33);

  /// Presence and read receipts. Green keeps "live" separate from the blue
  /// that every interactive thing already uses.
  static const online = Color(0xff16a34a);
  static const onlineDark = Color(0xff4ade80);

  static Color onlineFor(Brightness brightness) =>
      brightness == Brightness.dark ? onlineDark : online;
}

/// Shape and spacing scale shared with the web client.
abstract final class StepShape {
  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusLarge = 16.0;
  static const radiusBubble = 20.0;
  static const gutter = 20.0;
}

/// The colour a message bubble takes, by author and theme.
({Color surface, Color onSurface}) bubbleColors(
  BuildContext context, {
  required bool mine,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (mine) {
    return (
      surface: dark ? StepPalette.brandSolidDark : StepPalette.brand,
      onSurface: StepPalette.brandForeground,
    );
  }
  return (
    surface: dark
        ? StepPalette.messageIncomingDark
        : StepPalette.messageIncoming,
    onSurface: dark ? StepPalette.foregroundDark : StepPalette.foreground,
  );
}

ThemeData stepTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final colors =
      ColorScheme.fromSeed(
        seedColor: StepPalette.brand,
        brightness: brightness,
      ).copyWith(
        primary: dark ? StepPalette.brandDark : StepPalette.brand,
        onPrimary: dark ? const Color(0xff05056a) : StepPalette.brandForeground,
        primaryContainer: dark
            ? StepPalette.accentSurfaceDark
            : StepPalette.accentSurface,
        onPrimaryContainer: dark ? StepPalette.brandDark : StepPalette.brand,
        secondary: dark ? StepPalette.highlightDark : StepPalette.highlight,
        onSecondary: dark ? const Color(0xff06183a) : Colors.white,
        error: dark ? StepPalette.destructiveDark : StepPalette.destructive,
        onError: dark ? const Color(0xff2a0b0b) : Colors.white,
        surface: dark ? StepPalette.backgroundDark : StepPalette.background,
        surfaceContainerLowest: dark
            ? StepPalette.backgroundDark
            : StepPalette.card,
        surfaceContainerLow: dark ? StepPalette.cardDark : StepPalette.card,
        surfaceContainer: dark ? StepPalette.cardDark : StepPalette.muted,
        surfaceContainerHigh: dark ? StepPalette.mutedDark : StepPalette.muted,
        surfaceContainerHighest: dark
            ? StepPalette.mutedDark
            : StepPalette.accentSurface,
        onSurface: dark ? StepPalette.foregroundDark : StepPalette.foreground,
        onSurfaceVariant: dark
            ? StepPalette.mutedForegroundDark
            : StepPalette.mutedForeground,
        outlineVariant: dark ? StepPalette.borderDark : StepPalette.border,
      );

  // The web client sets Plus Jakarta Sans; mobile keeps the platform face so
  // text renders natively, and matches on scale and weight instead.
  const textTheme = TextTheme(
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -.7,
    ),
    headlineSmall: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -.4,
    ),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    bodyLarge: TextStyle(fontSize: 15.5, height: 1.4),
    bodyMedium: TextStyle(fontSize: 14.5, height: 1.4),
    labelLarge: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: .3,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    textTheme: textTheme,
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? StepPalette.cardDark : StepPalette.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StepShape.radiusLarge),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? StepPalette.cardDark : StepPalette.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(StepShape.radiusMedium),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(StepShape.radiusMedium),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(StepShape.radiusMedium),
        borderSide: BorderSide(color: colors.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StepShape.radiusMedium),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: colors.outlineVariant),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StepShape.radiusMedium),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: dark ? StepPalette.cardDark : StepPalette.card,
      selectedColor: dark
          ? StepPalette.accentSurfaceDark
          : StepPalette.accentSurface,
      side: BorderSide(color: colors.outlineVariant),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StepShape.radiusMedium),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    badgeTheme: BadgeThemeData(
      // Matches the web unread badge, which fills with the brand.
      backgroundColor: dark ? StepPalette.brandSolidDark : StepPalette.brand,
      textColor: StepPalette.brandForeground,
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: dark ? StepPalette.brandSolidDark : StepPalette.brand,
      foregroundColor: StepPalette.brandForeground,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StepShape.radiusLarge),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? StepPalette.cardDark : StepPalette.card,
      indicatorColor: dark
          ? StepPalette.accentSurfaceDark
          : StepPalette.accentSurface,
      elevation: 0,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? StepPalette.cardDark : StepPalette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(StepShape.radiusLarge),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StepShape.radiusMedium),
      ),
    ),
  );
}
