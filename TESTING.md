# Piggybow app: test log

One writer: the mobile tester. Rows land through **docs-only PRs off a fresh `master`**, never on a code branch. Newest PR first.

- A 🟢 names the exact head sha. It never carries over to a new head unless the patch is proven identical, and the row names the method.
- Every row reads CI **per test** (passed, failed, skipped), not just the job's colour.

Legend: 🟢 seen and passing · ❌ failing (repro in the row) · ⏳ not provable here (who checks it, and on which build) · ⚪ not applicable

## Row format

```
### #<PR> <title> — <sha7> — <🟢|❌|⏳> — <YYYY-MM-DD HH:MM UTC>
Build: <flavor> <debug|release> built in the job from <sha7> · Device: CI emulator, Android <API>, <WxH>, en-US
Flows: `maestro test -e APP_ID=<id> <paths or --include-tags …>`
| Flow / check | Result | Notes |
|---|---|---|
| <flow or check> | 🟢 | <what was seen> |
| <flow or check> | ❌ | step N: expected …, saw … Repro: … |
| ⏳ store build (owner) | | <what only a store build on a real phone proves> |
History: <older sha7 ❌ reason> → <newer sha7 🟢>
```

Rules for a row:
- **Only what was observed.** Anything a debug build or an emulator can't prove is ⏳, with who checks it and on which build.
- **A ❌ points at a flow step** ("step N: expected …, saw …") and at the failure's screenshot.
- **Earlier ❌ heads stay in History.**
- **Public-safe:** rows name the sha, the CI emulator, the build kind, the flows and what was seen. They never name people, devices, serials, emails or internal notes.
- The file is LF.

---

<!-- rows start here -->

### #1 Seed: Piggybow v0.1 from a trimmed copy of Moodbow — 8c62b73 — 🟢 (emulator smoke ⏳, UX waiver) — 2026-11-27 19:34 UTC
Build: no device for this row (CI logs + a read of the tree at the head) · head `8c62b73801d5c81c8e08be48621966537c1cdbb7`
| Check | Result | Notes |
|---|---|---|
| CI analyze + test + l10n, read per test | 🟢 | run 46055784879: `+200: All tests passed!`, 0 failed, 0 skipped. l10n parity, hard-coded text, untranslated messages and `flutter analyze` green |
| The two tests that failed at ffd093e | 🟢 | both ran and passed |
| No tracking dependencies | 🟢 | `verifyNoTrackingDeps` green (same run) |
| APK badging (staging debug, run 46056082373) | 🟢 | `com.burrowsoft.piggybow.staging`, versionCode 1, versionName 0.1.0, targetSdk 36, label "Piggybow Staging" |
| Merged permissions = `android/expected-permissions.txt` | 🟢 | the diff ran and was empty (9 entries: network state, internet, notifications, boot completed, biometric, fingerprint, vibrate, billing, the app's dynamic-receiver permission) |
| Phone backup off in the seed | 🟢 | `allowBackup=false`, `fullBackupContent=false`; the data-extraction rules exclude every domain for cloud backup and device-to-device transfer |
| No installable build in public artifacts | 🟢 | the APK run uploaded 0 artifacts |
| No server SDK, no network client | 🟢 | `supabase_flutter` not in `pubspec.lock`; no `package:http` or `HttpClient` in `lib/`; no runtime font fetching |
| Sentry options | 🟢 | `sendDefaultPii`, `attachScreenshot` and `attachViewHierarchy` off; the scrubber is on events and breadcrumbs |
| Rename and leftovers | 🟢 | package ids per flavor; app names per flavor (Android and iOS); no deep-link schemes; only `app_en.arb`; the source app's name only in the README credit and `tool/seed/`; none of its backend ids; no device serials; no internal documents |
| Removed features | 🟢 | the watch module and the health, sounds, widget and voice code are gone; the lock's Help link and the 12-month account notice are gone; 179 removed tests listed, none present; no `skip:` |
| Emulator smoke launch + screen walk | ⏳ | UX waiver on the PR naming 8c62b738: runs on master right after the Maestro workflow PR lands, and must pass before PR 2 merges |

Patch identity: the tree checks were read at ffd093e. GitHub's compare ffd093e → 8c62b73 = 2 test files only (+5 −4).
Follow-ups: the scrubber drops bare numbers before any DSN (PR 2); the sign-in-based lock paths go with the new Forgot PIN (PR 5).
History: ffd093e ❌ (2 of 200 tests: a text-field count floor and a Plus-store wiring assertion carried from the source app) → 8c62b73 🟢
