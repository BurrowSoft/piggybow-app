import 'package:flutter/material.dart' show Brightness, Color;

import 'theme.dart';

// Piggybow Plus: the extra themes (decision 246; UX ruled 11 Nov; the web's
// src/lib/plus/palettes.ts and paletteColours.ts, #277, value for value):
// Dusk (lavender), Sunrise (peach and gold) and Sea (blue-grey), beside the
// default, each with a light and a dark variant that follow Appearance.
// Kept on this device only, with the date Plus runs to: past it the default
// comes back by itself, before anything asks the server (and Me clears it
// once Plus has ended). The help card keeps the default colours in every
// theme; the mood colours are never a palette's.

enum PlusPalette { dusk, sunrise, sea }

/// One variant's colours (the web's tokens; the app has no separate surface
/// or border colour: cards use the pill colour).
const _tokens = <PlusPalette, ({PiggybowPalette light, PiggybowPalette dark})>{
  PlusPalette.dusk: (
    light: PiggybowPalette(
      background: Color(0xFFF5F2FB),
      text: Color(0xFF2B2438),
      mutedText: Color(0xFF5D5470),
      accent: Color(0xFF6A4FB3),
      onAccent: Color(0xFFFFFFFF),
      pillBackground: Color(0xFFECE6F8),
      logoAsset: 'assets/brand/piggybow-logo-stacked-light.svg',
    ),
    dark: PiggybowPalette(
      background: Color(0xFF221D33),
      text: Color(0xFFF3EFFB),
      mutedText: Color(0xFFC6BEDB),
      accent: Color(0xFFB9A6EC),
      onAccent: Color(0xFF221D33),
      pillBackground: Color(0xFF352D50),
      logoAsset: 'assets/brand/piggybow-logo-stacked-dark.svg',
    ),
  ),
  PlusPalette.sunrise: (
    light: PiggybowPalette(
      background: Color(0xFFFDF5EC),
      text: Color(0xFF2B2438),
      mutedText: Color(0xFF635546),
      accent: Color(0xFF9C4519),
      onAccent: Color(0xFFFFFFFF),
      pillBackground: Color(0xFFFBE9D6),
      logoAsset: 'assets/brand/piggybow-logo-stacked-light.svg',
    ),
    dark: PiggybowPalette(
      background: Color(0xFF2A2019),
      text: Color(0xFFFBF3EA),
      mutedText: Color(0xFFD9C7B4),
      accent: Color(0xFFE9B949),
      onAccent: Color(0xFF2A2019),
      pillBackground: Color(0xFF44331F),
      logoAsset: 'assets/brand/piggybow-logo-stacked-dark.svg',
    ),
  ),
  PlusPalette.sea: (
    light: PiggybowPalette(
      background: Color(0xFFF1F4F7),
      text: Color(0xFF1F2A36),
      mutedText: Color(0xFF4F5D6B),
      accent: Color(0xFF3C5A7A),
      onAccent: Color(0xFFFFFFFF),
      pillBackground: Color(0xFFE3EAF1),
      logoAsset: 'assets/brand/piggybow-logo-stacked-light.svg',
    ),
    dark: PiggybowPalette(
      background: Color(0xFF18212B),
      text: Color(0xFFEEF3F7),
      mutedText: Color(0xFFB7C4D1),
      accent: Color(0xFF9FB6D0),
      onAccent: Color(0xFF18212B),
      pillBackground: Color(0xFF2A3846),
      logoAsset: 'assets/brand/piggybow-logo-stacked-dark.svg',
    ),
  ),
};

/// The colour the theme's other tones are made from (Material's colour
/// scheme: cards, sheets, the Add button, chips): Piggybow's rose for the
/// default, so every theme's cards and buttons follow the theme instead of
/// staying pink.
Color paletteSeed(PlusPalette? palette) => switch (palette) {
  null => PiggybowColors.rose,
  PlusPalette.dusk => PiggybowColors.lavender,
  PlusPalette.sunrise => PiggybowColors.peach,
  PlusPalette.sea => const Color(0xFF6F8FB0),
};

/// The colours for [palette] (null: the default) in [brightness].
PiggybowPalette paletteColours(PlusPalette? palette, Brightness brightness) {
  final t = palette == null ? null : _tokens[palette]!;
  return switch ((t, brightness)) {
    (null, Brightness.light) => PiggybowPalette.light,
    (null, Brightness.dark) => PiggybowPalette.dark,
    (final t?, Brightness.light) => t.light,
    (final t?, Brightness.dark) => t.dark,
  };
}

PlusPalette? _byName(String name) {
  for (final p in PlusPalette.values) {
    if (p.name == name) return p;
  }
  return null;
}

/// "dusk@2027-11-11T12:00:00.000Z": the palette, while Plus runs (its date
/// hasn't passed); anything else, or past the date, is the default.
PlusPalette? parsePalette(String? stored, DateTime now) {
  if (stored == null) return null;
  final at = stored.indexOf('@');
  if (at < 0) return null;
  final p = _byName(stored.substring(0, at));
  final until = DateTime.tryParse(stored.substring(at + 1));
  return p != null && until != null && until.isAfter(now) ? p : null;
}

/// The stored choice's name, whatever its date: kept through a renewal, so
/// the theme comes back with Plus.
PlusPalette? storedPaletteName(String? stored) =>
    stored == null ? null : _byName(stored.split('@').first);

String encodePalette(PlusPalette palette, DateTime until) =>
    '${palette.name}@${until.toUtc().toIso8601String()}';
