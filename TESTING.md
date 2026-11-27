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

### #20 iOS privacy manifest: declare nothing collected while no build has a crash-report DSN — 3edf475 — 🟢 (merged privacy report ⏳) — 2026-11-27 21:25 UTC
Build: no device for this row (CI logs + a read of the tree at the head; no iOS build exists yet)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46069655370) | 🟢 | `+974: All tests passed!`, 0 failed, 0 skipped; analyze clean; 19 distinct `ios_flavors_test` names in the log |
| The manifest | 🟢 | tracking false; tracking domains, accessed API types and collected data types all empty |
| No DSN where iOS builds from | 🟢 | `SENTRY_DSN` empty in every env file; `codemagic.yaml` uses only the staging and prod env files, with no `--dart-define=` |
| Tied to the DSN | 🟢 | no DSN → nothing collected; a DSN → exactly crash data + other diagnostics, not linked, not tracking, app functionality only. A DSN without a manifest update fails CI |
| The app's own code | 🟢 | no required-reason API names in `ios/Runner` (the test) or anywhere in `ios/` outside Pods (my scan) |
| ⏳ merged privacy report | | Xcode's generated report on the first iOS build, which merges the plugins' own manifests |

### #19 Emulator: make evidence file names safe for the upload — d74f4a2 — 🟢 (live proof ⏳) — 2026-11-27 21:27 UTC
Build: no device for this row (CI logs + a read of the workflow step)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46069769358) | 🟢 | `+971: All tests passed!`, 0 failed, 0 skipped; analyze clean; the new naming test ran |
| The rename | 🟢 | in the guard step (also after a failed flow), before the installable check and the upload; deepest paths first; `" : < > \| * ?` → `_` |
| A clash fails closed | 🟢 | an existing target fails the step; `mv -n` never overwrites |
| ⏳ live proof | | the next run whose flow names need it (current names are already upload-safe) |

Merged as a merge commit onto 3edf475: the merged tree differs from master only by this PR's 2 files.

### #17 Maestro: dismiss another app's ANR dialog on the CI emulator — fe0ab6e — ⚪ (tests only, merged without a device row) — 2026-11-27 21:31 UTC
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46067631330) | 🟢 | `+935`, 0 failed, 0 skipped |
| Live use: the smoke on master 668df2b (emulator run 46069360939) | ❌ | the subflow fired as designed (the launcher's dialog, "Wait" tapped), but the launcher stayed hung and the dialog came back, covering a healthy Home for 60 s. Superseded by #21 ("Close app") |

### #16 Pin every workflow action to a commit sha, and bundletool to its sha256 — 668df2b — 🟢 — 2026-11-27 21:14 UTC
Build: no device for this row (CI logs + a scan of every workflow)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46068666393) | 🟢 | `+970: All tests passed!`, 0 failed, 0 skipped; analyze clean; the 5 pin tests named in the log |
| Every `uses:` pinned | 🟢 | my scan: 23 `uses:` lines, all a full 40-hex commit sha (at 714dc25) |
| Emulator concurrency on the job | 🟢 | a pull-request event whose job is skipped no longer displaces a waiting dispatch |

Patch identity: `git patch-id --stable` = `9bfda454…` at 714dc25 (over dfec61d), 260c277 (over bc0f3bc) and 668df2b (over 14426f3).
History: 714dc25 🟢 → 260c277 🟢 (rebase) → 668df2b 🟢 (rebase)

### #15 Golden baselines: render them on CI, and prove the committed ones match — 14426f3 — 🟢 (end to end ⏳) — 2026-11-27 21:13 UTC
Build: no device for this row (CI logs + a read of the workflow and tests)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46068664269) | 🟢 | `+965: All tests passed!`, 0 failed, 0 skipped; analyze clean; 965 = 935 + 30 golden tests |
| Rendered where compared | 🟢 | `ubuntu-latest`, the same Flutter version as the CI test job (pinned by a test) |
| Manual and contained | 🟢 | `workflow_dispatch` only; read-only permissions; only PNGs + `manifest.json` leave, kept 3 days |
| The manifest, both ways | 🟢 | no extra or missing file; a changed PNG or a pasted image of another kind refused; run id, source sha and Flutter version recorded |
| ⏳ end to end | | the first real baseline render (PR 2–4): its artifact checked against the committed manifest, each PNG looked at |

Patch identity: `git patch-id --stable` = `6c01249d…` at 1f66994 (over dfec61d), bc0f3bc (over d66e82a) and 14426f3 (over fe0ab6e).
History: 1f66994 🟢 (CI +964) → bc0f3bc 🟢 (rebase) → 14426f3 🟢 (rebase)

### #14 Emulator: Maestro's logs only when a flow fails — d66e82a — 🟢 (live proof ⏳) — 2026-11-27 20:56 UTC
Build: no device for this row (CI logs + a read of `tool/emulator/run.sh` at the head)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46066121985) | 🟢 | `+935: All tests passed!`, 0 failed, 0 skipped; `flutter analyze` clean; the new run.sh test ran |
| A failing flow keeps its logs | 🟢 | `set -euo pipefail`, and the `maestro … test` call is not inside an `if` or followed by an or-list, so a failure ends the script before the `logs/` removal |
| A pass drops them | 🟢 | `--test-output-dir` makes `$OUT/maestro` exist, so the removal can't fail; the rows path never reaches it |
| ⏳ live proof | | the first emulator dispatch from master after the merge: on a pass, no `logs/` folder in the evidence |

### #13 Add the reminder and lock rules — f3f0f4f — 🟢 — 2026-11-27 20:35 UTC
Build: no device for this row (pure Dart)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46064367481) | 🟢 | `+911: All tests passed!`, 0 failed, 0 skipped; analyze clean; no-guilt 62 messages, 0 hits |
| Reminder body rotation | 🟢 | `(dayOfYear − 1) mod 3` on the local date; leap and common years; only the date counts on a DST day; agrees with the pig's rotation over two years |
| After a restore | 🟢 | on in the settings but not scheduled → scheduled again |
| The lock | 🟢 | on only when a PIN exists; a restored phone is never locked out; Me's subtitle On / Off / off-after-restore |
| Forgot PIN | 🟢 | the screen-lock path first when there is one; the erase path erases before it clears the PIN; no path skips proving the owner |
| ⏳ screens | | the reminder wiring, the 20:00 default and the copy come with PR 5's screens and their CI-emulator rows |

Patch identity: `git patch-id --stable` of 338f2a2 over 04fa1fc = of f3f0f4f over c75653b = `e8263352…`.
History: 338f2a2 🟢 (CI +900) → f3f0f4f 🟢 (rebase)

### #12 Add the settings rules — c75653b — 🟢 — 2026-11-27 20:31 UTC
Build: no device for this row (pure Dart)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46063766407) | 🟢 | `+897: All tests passed!`, 0 failed, 0 skipped; analyze clean; all 11 settings-rules tests ran |
| Currency lock | 🟢 | changeable only while no entry and no goal exist; negative counts refused |
| Picks check | 🟢 | nothing picked → pick one; plan picked without an amount → plan needed; a plan without the pick is valid |
| Remove plan | 🟢 | with other picks it is unpicked at once; as the only pick the picker opens first; inputs never changed |
| Me subtitle | 🟢 | save, plan, worth, joined by " · " |
| ⏳ UI | | the picker flow on the Me screen (PR 4) |

### #11 Add today's idea: the 20 tips and their rotation — 04fa1fc — 🟢 — 2026-11-27 20:21 UTC
Build: no device for this row (pure Dart + copy)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46062622503) | 🟢 | `+886: All tests passed!`, 0 failed, 0 skipped; analyze clean; no-guilt 62 messages, 0 hits |
| The copy | 🟢 | the 20 tips equal the agreed table character for character (compared by script); an independent no-guilt scan finds 0 hits |
| Rotation | 🟢 | `tips[(dayOfYear − 1) mod 20]` on calendar dates (DST-proof); 2 Dec 2026 is tip 16; agrees with the pig's rotation over two years |
| "Another idea" | 🟢 | steps forward, wraps 20 → 1, visits every tip once in 20 steps |

### #10 Add the savings goal's maths — 3343315 — 🟢 — 2026-11-27 20:16 UTC
Build: no device for this row (pure Dart)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46062006129) | 🟢 | `+874: All tests passed!`, 0 failed, 0 skipped; analyze clean; 23 goal tests ran |
| Percent and bands (target 1000) | 🟢 | 0/199/200/399/400/999/1000/2500 → 0/19/20/39/40/99/100/100 %, bands 0/0/1/1/2/4/5/5; reached only at ≥ target |
| Edges | 🟢 | target 3 (33 %, 66 %); target 999999999999 never overflows |
| Sticky stamps | 🟢 | a deleted save redraws the band but keeps its stamp; raising the target never unsets a stamp; "already saved" ≥ target reaches it at creation |
| No floating point | 🟢 | 0 hits in `lib/goal/`; the no-float scan now covers it |

### #8 Add the launcher icons and the splash — e5dec36 — 🟢 (on-device ⏳) — 2026-11-27 20:07 UTC
Build: no device for this row (generated assets read at the head)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46060942164) | 🟢 | `+851: All tests passed!`, 0 failed, 0 skipped; analyze clean; all 10 icon tests ran |
| The art | 🟢 | the source SVGs are byte-identical to the approved design files (sha256) |
| iOS icons | 🟢 | all 15 PNGs 8-bit RGB, no alpha channel, no tRNS chunk; 1024 × 1024 included |
| Adaptive icon safe zone | 🟢 | background `#FBF6F1`, foreground and monochrome layers; the farthest point of the art is 30.28 dp from the centre, inside the 33 dp radius |
| Legacy mipmaps | 🟢 | 48 / 72 / 96 / 144 / 192 px |
| Splash | 🟢 | cream `#FBF6F1`, dark `#2B2438`, Android pre-12 and 12+ and the iOS colour set |
| Notification icon | 🟢 | white only, used by the reminder scheduler, kept from shrinking |
| Looked at by the tester | 🟢 | the icons, the themed and notification previews and the Android 12 splash |
| ⏳ real launcher and notification shade | | a CI-emulator screenshot later; the first store-build install |

Patch identity: `git patch-id --stable` of 4523752 over 69f0718 = of e5dec36 over e48c62d = `bb403481…`; the art bytes hash the same.
History: 4523752 🟢 → e5dec36 🟢 (rebase)

### #7 CI: an emulator job for Maestro flows and device rows — 7581bc0 — 🟢 — 2026-11-27 20:44 UTC
Build: staging debug, built in the job from 7581bc0 · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Flows: `maestro test -e APP_ID=com.burrowsoft.piggybow.staging --include-tags smoke .maestro`
| Flow / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46063745604) | 🟢 | `+909: All tests passed!`, 0 failed, 0 skipped; analyze clean |
| Emulator run 46064007503 | 🟢 | every step green; head = flows = 7581bc0; the installed APK equals the built one |
| `00_smoke_launch` | 🟢 | JUnit 1 test, 0 failures; all commands completed except the onboarding branch (none in the seed) and the 60 s wait (by design) |
| The screen walk | 🟢 | the four tabs opened; 6 screenshots looked at |
| Alive after 60 s | 🟢 | still on Home; no crash or not-responding dialog |
| Evidence | 🟢 | 14 files; 0 installables |

History: 55c9e22 ❌ (the emulator never booted: no disk space for its data partition; no flow ran) → 7581bc0 🟢

### #6 Add the Summary's calculations — e48c62d — 🟢 — 2026-11-27 20:01 UTC
Build: no device for this row (pure Dart)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46060177966) | 🟢 | `+841: All tests passed!`, 0 failed, 0 skipped; analyze clean |
| Fixture S1 in all four views | 🟢 | this week 11570 (floored 86 % share), the week before 4500, December 1570, November 14500; the plan only in the current week |
| Period labels (en_US) | 🟢 | `Nov 30 – Dec 6`, `December 2026`, `Dec 28, 2026 – Jan 3, 2027` and others; Monday start; February 2028 |
| No floating point | 🟢 | 0 hits in `lib/summary/` |

Patch identity: `git patch-id --stable` of 3a936c7 over 60c3472 = of e48c62d over 24ebc0c = `6e1db0ca…`.
History: 3a936c7 🟢 (CI +823) → e48c62d 🟢 (rebase)

### #5 Add the pig's mood function and its shared contract — 24ebc0c — 🟢 — 2026-11-27 20:01 UTC
Build: no device for this row (pure Dart)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46060180417) | 🟢 | `+823: All tests passed!`, 0 failed, 0 skipped; analyze clean |
| The shared contract | 🟢 | `test/contracts/pig_mood_cases.json` sha256 `d23c4c68a6f9…`, 35 cases; an independent reference implementation gives all 35 expected results; CI shows all 35 case ids running |
| Pure function | 🟢 | no clock read in `lib/pig/pig_mood.dart`; "now" and "today" are inputs |
| Property test | 🟢 | 3,000 seeded inputs |

Patch identity: `git patch-id --stable` of 60c3472 over 6481d4a = of 24ebc0c over d0b0e8b = `74dc74b1…`.
History: 60c3472 🟢 (CI +805) → 24ebc0c 🟢 (rebase; an earlier run on it was cancelled by concurrency, not failed)

### #3 Add the money core and the spreadsheet export — d0b0e8b — 🟢 — 2026-11-27 20:01 UTC
Build: no device for this row (pure Dart)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46060178592) | 🟢 | `+773: All tests passed!`, 0 failed, 0 skipped; analyze clean |
| No floating point | 🟢 | 0 hits for `double`, `toDouble(`, `double.parse`, `num.parse`, `/ 100`, `.round(` in `lib/money/` and `lib/export/` |
| Digits table | 🟢 | 33 currencies, each against intl 0.20.3; 0-digit: CLP, COP, HUF, IDR, JPY, KRW, VND |
| Format oracle | 🟢 | 13 locales; Indian grouping, CHF, the narrow no-break space, the RTL mark; no plain space |
| Parsing | 🟢 | accepts `12`, `12.5`, `12,5`, `0.05`, 12 digits; refuses 13 digits, 3 decimals, two marks, `-5`, `1e3`, `$12.50`, Thai digits; JPY refuses decimals |
| Sums | 🟢 | 10,000 seeded amounts add exactly; category totals = the grand total |
| CSV | 🟢 | exact header, BOM, CRLF, RFC 4180 quoting, the formula-injection prefix, `piggybow-YYYY-MM-DD.csv` |

Patch identity: `git patch-id --stable` of 6481d4a over 8c62b73 = of d0b0e8b over 69f0718 = `ab3ce8ce…`.
History: 6481d4a 🟢 (CI +755) → d0b0e8b 🟢 (rebase)

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

Closed (2026-11-27 21:34 UTC): the emulator smoke ⏳ above is closed by the smoke that passed at 7581bc0 (see #7's row: start screen, all 4 tabs, alive after 60 s). The app code at 7581bc0 is this row's, except one regex in the Plus price formatter whose literal invisible spaces became `\u` escapes (the same characters). The smokes on master dfec61d and 668df2b failed only on the emulator launcher's "isn't responding" dialog, with the app healthy behind it, so they add no evidence about the seed. The master smoke stays as a regular check once #21 lands.
