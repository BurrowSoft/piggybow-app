import 'package:flutter/material.dart';

import 'palettes.dart';

/// Piggybow brand palette (see the brand kit README). Same tokens as
/// piggybow-web/lib/theme.dart; keep the two in sync.
abstract final class PiggybowColors {
  static const cream = Color(0xFFFBF6F1);
  static const ink = Color(0xFF2B2438);
  static const peach = Color(0xFFF2A07B);
  static const rose = Color(0xFFE27D9A);
  static const deepRose = Color(0xFFA8456A);
  static const lavender = Color(0xFF9B84D6);

  /// The dark theme's accent (decision 150): buttons, Piggybow's voice and the
  /// non-mood charts share it; one rose family with deepRose.
  static const roseDark = Color(0xFFD88AA6);
  static const mutedLight = Color(0xFF6B6278);
  static const mutedDark = Color(0xFFC9C1D4);
}

/// Colors that differ between light and dark mode, exposed as a theme
/// extension so widgets don't branch on brightness themselves.
@immutable
class PiggybowPalette extends ThemeExtension<PiggybowPalette> {
  const PiggybowPalette({
    required this.background,
    required this.text,
    required this.mutedText,
    required this.accent,
    required this.onAccent,
    required this.pillBackground,
    required this.logoAsset,
  });

  final Color background;
  final Color text;
  final Color mutedText;

  /// Accent used for text, links and the button fill. Deep rose on light
  /// (contrast-safe on cream), rose on dark.
  final Color accent;
  final Color onAccent;
  final Color pillBackground;
  final String logoAsset;

  static const light = PiggybowPalette(
    background: PiggybowColors.cream,
    text: PiggybowColors.ink,
    mutedText: PiggybowColors.mutedLight,
    accent: PiggybowColors.deepRose,
    onAccent: PiggybowColors.cream,
    pillBackground: Color(0xFFF9EAEC),
    logoAsset: 'assets/brand/piggybow-logo-stacked-light.svg',
  );

  static const dark = PiggybowPalette(
    background: PiggybowColors.ink,
    text: PiggybowColors.cream,
    mutedText: PiggybowColors.mutedDark,
    accent: PiggybowColors.roseDark,
    onAccent: PiggybowColors.ink,
    pillBackground: Color(0xFF382C43),
    logoAsset: 'assets/brand/piggybow-logo-stacked-dark.svg',
  );

  @override
  PiggybowPalette copyWith({
    Color? background,
    Color? text,
    Color? mutedText,
    Color? accent,
    Color? onAccent,
    Color? pillBackground,
    String? logoAsset,
  }) {
    return PiggybowPalette(
      background: background ?? this.background,
      text: text ?? this.text,
      mutedText: mutedText ?? this.mutedText,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      pillBackground: pillBackground ?? this.pillBackground,
      logoAsset: logoAsset ?? this.logoAsset,
    );
  }

  @override
  PiggybowPalette lerp(PiggybowPalette? other, double t) {
    if (other == null) return this;
    return PiggybowPalette(
      background: Color.lerp(background, other.background, t)!,
      text: Color.lerp(text, other.text, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      pillBackground: Color.lerp(pillBackground, other.pillBackground, t)!,
      logoAsset: t < 0.5 ? logoAsset : other.logoAsset,
    );
  }
}

BorderSide _focusSide(PiggybowPalette palette) =>
    BorderSide(color: palette.text, width: 2);

/// The keyboard focus ring's side, as the buttons draw it: for focusable
/// things that aren't buttons (the prompt library's prompt text).
BorderSide keyboardFocusSide(BuildContext context) =>
    _focusSide(context.palette);

const _fontFamily = 'Poppins';

/// Poppins has no Thai glyphs, so Thai text falls back to Prompt.
const _fontFallback = ['Prompt'];

/// A pill at one line (the radius is half of the 52 dp button; Flutter limits
/// it on a shorter one), and modest corners on a tall one: a stadium's curve
/// grows with the height and cut into a wrapped label (the crisis card, PT at
/// 200 %). Under the buttons' side padding, so text never reaches the curve.
const appButtonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(26)),
);

/// Dark mode's raised surfaces (cards, sheets, dialogs, menus, the bars'
/// tracks): each a step lighter than the page, never darker. The seed's own
/// dark containers sit below the page's colour; these are the page with a
/// little more of the text colour in it, step by step.
ColorScheme raisedSurfacesLighter(ColorScheme s, PiggybowPalette palette) {
  Color step(double amount) => Color.alphaBlend(
    palette.text.withValues(alpha: amount),
    palette.background,
  );
  return s.copyWith(
    surfaceContainerLowest: step(0.03),
    surfaceContainerLow: step(0.06),
    surfaceContainer: step(0.08),
    surfaceContainerHigh: step(0.10),
    surfaceContainerHighest: step(0.13),
  );
}

/// [disableAnimations] (staging flavor) turns page transitions off so Maestro
/// flows don't wait on them.
///
/// [plusPalette]: Piggybow Plus's extra theme (null: the default).
ThemeData buildTheme(
  Brightness brightness, {
  bool disableAnimations = false,
  PlusPalette? plusPalette,
}) {
  final palette = paletteColours(plusPalette, brightness);

  final seeded =
      ColorScheme.fromSeed(
        seedColor: paletteSeed(plusPalette),
        brightness: brightness,
      ).copyWith(
        primary: palette.accent,
        onPrimary: palette.onAccent,
        surface: palette.background,
        onSurface: palette.text,
      );
  final scheme = brightness == Brightness.dark
      ? raisedSurfacesLighter(seeded, palette)
      : seeded;

  // Button themes take these styles directly, so they need the font family
  // themselves (ThemeData.fontFamily is only applied to the final text theme).
  final textTheme = TextTheme(
    headlineMedium: TextStyle(
      fontWeight: FontWeight.w500,
      height: 1.2,
      letterSpacing: -0.5,
      color: palette.text,
    ),
    bodyLarge: TextStyle(
      fontWeight: FontWeight.w400,
      height: 1.6,
      color: palette.mutedText,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: palette.mutedText,
    ),
    labelLarge: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    ),
  ).apply(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback);

  // A visible ring for keyboard focus; the default overlay alone is too faint.
  final focusRing = WidgetStateProperty.resolveWith<BorderSide?>(
    (states) =>
        states.contains(WidgetState.focused) ? _focusSide(palette) : null,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    textTheme: textTheme,
    scaffoldBackgroundColor: palette.background,
    extensions: [palette],
    // Hints and placeholders muted in every field (typed text: inputText).
    inputDecorationTheme: InputDecorationTheme(hintStyle: textTheme.bodyLarge),
    pageTransitionsTheme: disableAnimations
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _NoTransitionsBuilder(),
              TargetPlatform.iOS: _NoTransitionsBuilder(),
            },
          )
        : null,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.background,
      indicatorColor: palette.pillBackground,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.bodySmall?.copyWith(
          color: states.contains(WidgetState.selected)
              ? palette.accent
              : palette.mutedText,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w500
              : FontWeight.w400,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? palette.accent
              : palette.mutedText,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        minimumSize: const Size(200, 52),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        shape: appButtonShape,
        textStyle: textTheme.labelLarge,
      ).copyWith(side: focusRing),
    ),
    // Flutter's default has no vertical padding: a wrapped label touches the
    // edges. One line is still 40 dp high at normal text (20 + 2 × 10).
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        shape: appButtonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.accent,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        shape: const StadiumBorder(),
      ).copyWith(side: focusRing),
    ),
  );
}

/// iOS has no Back, and a multi-line field's Return is a new line, so nothing
/// else closes the keyboard: dragging a list does. Android keeps its Back.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => getPlatform(context) == TargetPlatform.iOS
      ? ScrollViewKeyboardDismissBehavior.onDrag
      : super.getKeyboardDismissBehavior(context);
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

extension PiggybowThemeX on BuildContext {
  PiggybowPalette get palette => Theme.of(this).extension<PiggybowPalette>()!;

  /// What the user types, in every text field: the ink colour (decision
  /// 206). Material 3 takes a field's colour from bodyLarge, which is our
  /// muted body text, so each field sets `style: context.inputText`.
  /// (Outside the Piggybow theme, e.g. a bare test app: the plain body style.)
  TextStyle? get inputText =>
      Theme.of(this).textTheme.bodyLarge
          ?.copyWith(color: Theme.of(this).extension<PiggybowPalette>()?.text);
}
