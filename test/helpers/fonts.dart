import 'package:flutter/services.dart';

/// The app's real fonts for a test that measures text: Poppins, Prompt (its
/// Thai fallback) and the Material icons. The default test font draws every
/// glyph 1 em wide. Opt-in: most tests keep the default font.
Future<void> loadAppFonts() async {
  final poppins = FontLoader('Poppins')
    ..addFont(rootBundle.load('assets/fonts/Poppins-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Poppins-Medium.ttf'));
  final prompt = FontLoader('Prompt')
    ..addFont(rootBundle.load('assets/fonts/Prompt-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Prompt-Medium.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await Future.wait([poppins.load(), prompt.load(), icons.load()]);
}
