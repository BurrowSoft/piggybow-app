import 'package:flutter/material.dart' show Brightness, Color;

import 'theme.dart';

// Piggybow Plus's themes (plus-spec §1; PB UX & PM named them 28 Nov):
// Strawberry, the default (rose, free), and three Plus themes, Plum (lavender),
// Apricot (peach and gold) and Blueberry (blue-grey), each with a light and a
// dark variant that follow Appearance.
//
// What's applied follows Plus as it is now (appliedPalette): the chosen
// theme while Plus is active, Strawberry the moment it isn't. Only the
// choice's name is kept on the device, so it comes back with Plus; never a
// date (a restored phone has the backed-up choice without Plus). The pig and
// the rainbow's arcs keep Piggybow's own colours in every theme.

/// The Plus themes (Strawberry, the default, is null).
enum PlusPalette { plum, apricot, blueberry }

/// The rainbow's empty track on a light page, in every theme.
const _trackLight = Color(0xFFECE6F0);

/// One variant's colours (the app has no separate surface or border colour:
/// cards use the pill colour). In dark, the rainbow's empty track is a dim
/// tint of the theme's seed (16 % of it over the page).
const _tokens = <PlusPalette, ({PiggybowPalette light, PiggybowPalette dark})>{
  PlusPalette.plum: (
    light: PiggybowPalette(
      background: Color(0xFFF5F2FB),
      text: Color(0xFF2B2438),
      mutedText: Color(0xFF5D5470),
      accent: Color(0xFF6A4FB3),
      onAccent: Color(0xFFFFFFFF),
      pillBackground: Color(0xFFECE6F8),
      rainbowTrack: _trackLight,
      logoAsset: 'assets/brand/piggybow-logo-stacked-light.svg',
    ),
    dark: PiggybowPalette(
      background: Color(0xFF221D33),
      text: Color(0xFFF3EFFB),
      mutedText: Color(0xFFC6BEDB),
      accent: Color(0xFFB9A6EC),
      onAccent: Color(0xFF221D33),
      pillBackground: Color(0xFF352D50),
      rainbowTrack: Color(0xFF352D4D),
      logoAsset: 'assets/brand/piggybow-logo-stacked-dark.svg',
    ),
  ),
  PlusPalette.apricot: (
    light: PiggybowPalette(
      background: Color(0xFFFDF5EC),
      text: Color(0xFF2B2438),
      mutedText: Color(0xFF635546),
      accent: Color(0xFF9C4519),
      onAccent: Color(0xFFFFFFFF),
      pillBackground: Color(0xFFFBE9D6),
      rainbowTrack: _trackLight,
      logoAsset: 'assets/brand/piggybow-logo-stacked-light.svg',
    ),
    dark: PiggybowPalette(
      background: Color(0xFF2A2019),
      text: Color(0xFFFBF3EA),
      mutedText: Color(0xFFD9C7B4),
      accent: Color(0xFFE9B949),
      onAccent: Color(0xFF2A2019),
      pillBackground: Color(0xFF44331F),
      rainbowTrack: Color(0xFF4A3429),
      logoAsset: 'assets/brand/piggybow-logo-stacked-dark.svg',
    ),
  ),
  PlusPalette.blueberry: (
    light: PiggybowPalette(
      background: Color(0xFFF1F4F7),
      text: Color(0xFF1F2A36),
      mutedText: Color(0xFF4F5D6B),
      accent: Color(0xFF3C5A7A),
      onAccent: Color(0xFFFFFFFF),
      pillBackground: Color(0xFFE3EAF1),
      rainbowTrack: _trackLight,
      logoAsset: 'assets/brand/piggybow-logo-stacked-light.svg',
    ),
    dark: PiggybowPalette(
      background: Color(0xFF18212B),
      text: Color(0xFFEEF3F7),
      mutedText: Color(0xFFB7C4D1),
      accent: Color(0xFF9FB6D0),
      onAccent: Color(0xFF18212B),
      pillBackground: Color(0xFF2A3846),
      rainbowTrack: Color(0xFF263340),
      logoAsset: 'assets/brand/piggybow-logo-stacked-dark.svg',
    ),
  ),
};

/// The colour the theme's other tones are made from (Material's colour
/// scheme: cards, sheets, the Add button, chips), so every theme's cards and
/// buttons follow the theme instead of staying pink. Strawberry's is
/// Piggybow's rose.
Color paletteSeed(PlusPalette? palette) => switch (palette) {
  null => PiggybowColors.rose,
  PlusPalette.plum => PiggybowColors.lavender,
  PlusPalette.apricot => PiggybowColors.peach,
  PlusPalette.blueberry => const Color(0xFF6F8FB0),
};

/// The colours for [palette] (null: Strawberry) in [brightness].
PiggybowPalette paletteColours(PlusPalette? palette, Brightness brightness) {
  final t = palette == null ? null : _tokens[palette]!;
  return switch ((t, brightness)) {
    (null, Brightness.light) => PiggybowPalette.light,
    (null, Brightness.dark) => PiggybowPalette.dark,
    (final t?, Brightness.light) => t.light,
    (final t?, Brightness.dark) => t.dark,
  };
}

/// The stored choice: a theme's name. Anything else (nothing, an unknown
/// name) is Strawberry. Only the part before an "@" counts, so a value with
/// a date after it still reads as its name.
PlusPalette? paletteByName(String? stored) {
  if (stored == null) return null;
  final name = stored.split('@').first;
  for (final p in PlusPalette.values) {
    if (p.name == name) return p;
  }
  return null;
}

/// What the app shows: the [chosen] theme while Plus is active, else
/// Strawberry. Never the stored choice on its own.
PlusPalette? appliedPalette(PlusPalette? chosen, {required bool plusActive}) =>
    plusActive ? chosen : null;
