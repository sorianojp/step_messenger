import 'package:flutter/material.dart';

/// The web client's design tokens, copied from the `:root` and `.dark` blocks
/// of chat-app/resources/css/app.css (Tailwind slate neutrals, STEP navy
/// brand). Change both files together so the apps stay identical.
abstract final class StepPalette {
  // Light (:root)
  static const background = Color(0xfff5f7fb);
  static const foreground = Color(0xff0f172a);
  static const card = Color(0xffffffff);
  static const muted = Color(0xfff1f5f9);
  static const mutedForeground = Color(0xff64748b);
  static const secondary = Color(0xffe2e8f0);
  static const border = Color(0xffe2e8f0);
  static const ring = Color(0xff3c53a9);
  static const brand = Color(0xff1a2d61);
  static const brandForeground = Color(0xffffffff);
  static const destructive = Color(0xffdc2626);
  static const messageIncoming = Color(0xffffffff);

  // Dark (.dark)
  static const backgroundDark = Color(0xff0f172a);
  static const foregroundDark = Color(0xfff1f5f9);
  static const cardDark = Color(0xff1e293b);
  static const mutedDark = Color(0xff273449);
  static const mutedForegroundDark = Color(0xff94a3b8);
  static const secondaryDark = Color(0xff334155);
  static const borderDark = Color(0xff334155);
  static const ringDark = Color(0xff748bd4);

  /// `--brand` in dark mode: text and icons on dark surfaces.
  static const brandDark = Color(0xff9eafe4);

  /// `--brand-solid` in dark mode: filled buttons and outgoing bubbles.
  static const brandSolidDark = Color(0xff324388);
  static const destructiveDark = Color(0xfff87171);
  static const messageIncomingDark = Color(0xff1e293b);

  /// `bg-brand/10`: the selected conversation row and tinted chips.
  static const accentSurface = Color(0x1a1a2d61);
  static const accentSurfaceDark = Color(0x269eafe4);

  /// Presence and read receipts (`--online`).
  static const online = Color(0xff16a34a);
  static const onlineDark = Color(0xff4ade80);

  static Color onlineFor(Brightness brightness) =>
      brightness == Brightness.dark ? onlineDark : online;
}

/// Tailwind's radius scale as the web uses it.
abstract final class StepShape {
  /// rounded-lg
  static const radiusSmall = 8.0;

  /// rounded-xl: inputs, buttons, conversation rows.
  static const radiusMedium = 12.0;

  /// rounded-2xl: cards, sheets, message bubbles.
  static const radiusLarge = 16.0;

  /// rounded-md: the bubble corner next to its author.
  static const radiusBubbleTail = 6.0;
  static const gutter = 16.0;
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

/// Tailwind `shadow-sm`, used by bubbles and cards on the web.
const stepShadowSmall = [
  BoxShadow(color: Color(0x0d000000), blurRadius: 2, offset: Offset(0, 1)),
];

const _text = 'Inter';
const _heading = 'PlusJakartaSans';

ThemeData stepTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final brandSolid = dark ? StepPalette.brandSolidDark : StepPalette.brand;

  final colors =
      ColorScheme.fromSeed(
        seedColor: StepPalette.brand,
        brightness: brightness,
      ).copyWith(
        // `--primary`: filled actions. Brand-coloured text uses [brandText].
        primary: brandSolid,
        onPrimary: StepPalette.brandForeground,
        primaryContainer: dark
            ? StepPalette.accentSurfaceDark
            : StepPalette.accentSurface,
        onPrimaryContainer: dark ? StepPalette.brandDark : StepPalette.brand,
        secondary: dark ? StepPalette.ringDark : StepPalette.ring,
        onSecondary: Colors.white,
        secondaryContainer: dark
            ? StepPalette.secondaryDark
            : StepPalette.secondary,
        onSecondaryContainer: dark
            ? StepPalette.foregroundDark
            : StepPalette.foreground,
        tertiary: dark ? StepPalette.brandDark : StepPalette.brand,
        error: dark ? StepPalette.destructiveDark : StepPalette.destructive,
        onError: dark ? const Color(0xff2a0b0b) : Colors.white,
        surface: dark ? StepPalette.backgroundDark : StepPalette.background,
        surfaceContainerLowest: dark
            ? StepPalette.backgroundDark
            : StepPalette.card,
        surfaceContainerLow: dark ? StepPalette.cardDark : StepPalette.card,
        surfaceContainer: dark ? StepPalette.cardDark : StepPalette.card,
        surfaceContainerHigh: dark ? StepPalette.mutedDark : StepPalette.muted,
        surfaceContainerHighest: dark
            ? StepPalette.secondaryDark
            : StepPalette.secondary,
        onSurface: dark ? StepPalette.foregroundDark : StepPalette.foreground,
        onSurfaceVariant: dark
            ? StepPalette.mutedForegroundDark
            : StepPalette.mutedForeground,
        outline: dark ? StepPalette.borderDark : StepPalette.border,
        outlineVariant: dark ? StepPalette.borderDark : StepPalette.border,
        surfaceTint: Colors.transparent,
      );

  // Web: body is Inter 500 with -0.01em tracking; headings are Plus Jakarta
  // Sans with -0.025em.
  const textTheme = TextTheme(
    headlineMedium: TextStyle(
      fontFamily: _heading,
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -.7,
    ),
    headlineSmall: TextStyle(
      fontFamily: _heading,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -.55,
    ),
    titleLarge: TextStyle(
      fontFamily: _heading,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -.5,
    ),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 15, height: 1.5, letterSpacing: -.15),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45, letterSpacing: -.14),
    bodySmall: TextStyle(fontSize: 12, height: 1.4),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
  );

  final radiusMedium = BorderRadius.circular(StepShape.radiusMedium);
  final radiusLarge = BorderRadius.circular(StepShape.radiusLarge);

  return ThemeData(
    useMaterial3: true,
    fontFamily: _text,
    colorScheme: colors,
    textTheme: textTheme,
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      // Web headers sit on the card colour with a bottom border.
      backgroundColor: dark ? StepPalette.cardDark : StepPalette.card,
      foregroundColor: colors.onSurface,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: colors.outlineVariant)),
      titleTextStyle: TextStyle(
        fontFamily: _heading,
        color: colors.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -.45,
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? StepPalette.cardDark : StepPalette.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radiusLarge),
    ),
    // Web inputs: h-11, rounded-xl, `bg-secondary/70`, no border until focus.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: (dark ? StepPalette.secondaryDark : StepPalette.secondary)
          .withValues(alpha: .7),
      hintStyle: TextStyle(color: colors.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: radiusMedium,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radiusMedium,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radiusMedium,
        borderSide: BorderSide(
          color: (dark ? StepPalette.ringDark : StepPalette.ring).withValues(
            alpha: .45,
          ),
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brandSolid,
        foregroundColor: StepPalette.brandForeground,
        minimumSize: const Size(0, 44),
        textStyle: const TextStyle(
          fontFamily: _text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: radiusMedium),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: colors.onSurface,
        side: BorderSide(color: colors.outlineVariant),
        textStyle: const TextStyle(
          fontFamily: _text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: radiusMedium),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? StepPalette.brandDark : StepPalette.brand,
        textStyle: const TextStyle(
          fontFamily: _text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: radiusMedium),
      ),
    ),
    // Web segmented tabs: muted track, selected item on the card colour.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: dark ? StepPalette.mutedDark : StepPalette.muted,
        selectedBackgroundColor: dark ? StepPalette.cardDark : StepPalette.card,
        selectedForegroundColor: dark
            ? StepPalette.brandDark
            : StepPalette.brand,
        foregroundColor: colors.onSurfaceVariant,
        side: BorderSide.none,
        textStyle: const TextStyle(
          fontFamily: _text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: radiusMedium),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: dark ? StepPalette.mutedDark : StepPalette.muted,
      // Selected: `bg-brand/15 text-brand`, as on the web's toggles.
      selectedColor: (dark ? StepPalette.brandDark : StepPalette.brand)
          .withValues(alpha: .15),
      secondaryLabelStyle: TextStyle(
        fontFamily: _text,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: dark ? StepPalette.brandDark : StepPalette.brand,
      ),
      side: BorderSide.none,
      labelStyle: TextStyle(
        fontFamily: _text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.onSurfaceVariant,
      titleTextStyle: TextStyle(
        fontFamily: _text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: _text,
        fontSize: 12,
        color: colors.onSurfaceVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: radiusMedium),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    badgeTheme:
        const BadgeThemeData(
          textStyle: TextStyle(
            fontFamily: _text,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ).copyWith(
          backgroundColor: brandSolid,
          textColor: StepPalette.brandForeground,
        ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: brandSolid,
      foregroundColor: StepPalette.brandForeground,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: radiusLarge),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? StepPalette.cardDark : StepPalette.card,
      indicatorColor: dark
          ? StepPalette.accentSurfaceDark
          : StepPalette.accentSurface,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: _text,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? (dark ? StepPalette.brandDark : StepPalette.brand)
              : colors.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? (dark ? StepPalette.brandDark : StepPalette.brand)
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? StepPalette.cardDark : StepPalette.card,
      shape: RoundedRectangleBorder(borderRadius: radiusLarge),
      titleTextStyle: TextStyle(
        fontFamily: _heading,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -.45,
        color: colors.onSurface,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? StepPalette.cardDark : StepPalette.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(StepShape.radiusLarge),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radiusMedium),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: dark ? StepPalette.brandDark : StepPalette.brand,
    ),
  );
}

/// Brand-coloured text and icons (`text-brand` on the web).
Color brandText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? StepPalette.brandDark
    : StepPalette.brand;
