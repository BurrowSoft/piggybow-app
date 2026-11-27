# Piggybow

A private money journal for what you spend and what you save, with a friendly
pig. Everything stays on your phone: no account, no bank login, no ads and no
tracking.

A Flutter app for Android and iPhone, by BurrowSoft.

## Build and test

- Flutter 3.47.5 (Dart 3.13), as pinned in `.github/workflows/` and `codemagic.yaml`.
- Flavors: `dev`, `staging` and `prod`, each with its own `env/<flavor>.json`:

  ```sh
  flutter pub get
  flutter run --flavor dev --dart-define-from-file=env/dev.json
  flutter test
  ```

- Checks CI runs too: `flutter analyze`, `dart run tool/check_l10n.dart`,
  `dart run tool/check_hardcoded_text.dart`, `dart run tool/check_hidden_chars.dart`.
- On-device tests run on a CI emulator only (`.github/workflows/emulator.yaml`,
  started by hand or by the `emulator` label): it builds the APK it tests from
  the commit under test and keeps only the evidence (logs and screenshots) for
  3 days.
- Every user-facing string lives in `lib/l10n/app_en.arb`.

## How this repo started

Piggybow was seeded from BurrowSoft's Moodbow app. `tool/seed/` holds the
recipe, so the first commit can be reproduced from Moodbow's source:

1. `seed.mjs`: the mechanical part (removed features, server code and
   tooling; blanked backend values; the rename).
2. Hand edits on top of that (the seed pull request lists them).
3. `prune_arb.mjs`: drops every string no code uses.
4. `placeholder_icons.mjs`: placeholder launcher icons until the real ones land.
