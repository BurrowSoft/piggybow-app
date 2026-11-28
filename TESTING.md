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

A run on master with no PR of its own (such as a smoke on the final master) takes `### master: <title>` in place of `### #<PR> <title>`; the other three fields stay.

Rules for a row:
- **Only what was observed.** Anything a debug build or an emulator can't prove is ⏳, with who checks it and on which build.
- **A ❌ points at a flow step** ("step N: expected …, saw …") and at the failure's screenshot.
- **Earlier ❌ heads stay in History.**
- **Public-safe:** rows name the sha, the CI emulator, the build kind, the flows and what was seen. They never name people, devices, serials, emails or internal notes.
- The file is LF.

---

<!-- rows start here -->

### master: pig tips, the app's side (#93 the client, #94 the screens) — deba760c — 🟢 (one finding, F-TI-1: a second tip call after off → on the same day, fixed in #95 and checked after it lands; other languages ⏳) — 2026-11-28 16:53 UTC
Build: staging debug with pig tips on, their server pointed at a mock on the runner (`kind=tips-mock`), built in the job from deba760c, APK sha256 1fa4dc48…; installed = built · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US; root moves the device clock for the following days
Rows: `tool/device-rows/group-tips.sh` (emulator run 46166682735, flows `tests/retro` @ 1a06c8f): 5 pass, 1 INFO (TI-7b), 0 fail. The mock (`tool/device-rows/tips_mock.py`) checks every tip request against the contract (`pig-tip-request.json`) and logs every request (`tips-mock.jsonl` in the evidence)
| Row / check | Result | Notes |
|---|---|---|
| Master's push CI, read per test (run 46166156562, this sha) | 🟢 | `+2786: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean; server tests (deno) 32 passed, 0 failed; the SQL asserts pass |
| The commits since e80101ed | 🟢 | 11, every one authored and committed by the noreply identity |
| Goldens at deba760c (render 46164465290 on 28ed141) | 🟢 | my own download: 361 PNGs = manifest = committed at deba760c, both ways, by sha256; against e80101ed: 353 identical, 8 new (the written tip, the report sheet, the tips sheet, Me with tips on; light and dark), all looked at |
| TI-1a nothing leaves before Yes | 🟢 | flow 94a: the built-in tip first; Your privacy names pig tips; Me's switch asks first; "Not now" leaves it off; the mock heard nothing |
| TI-1b Yes, and TI-6 the labels | 🟢 | flow 94b: one signup, one tip call with a contract-valid body; Home shows the written tip with "Written by AI", Report and Another idea |
| What a tip request carries | 🟢 | every body: language, weekday, category shares, feelings, saves, active goals, picks; no notes, no amounts |
| TI-4 Report | 🟢 | flow 94c: Report → Not helpful → thanks; one report with the tip, model and sig that were served; the built-in tip after it, also after a restart, with no new tip call |
| TI-2 off and on | 🟢 | flow 94d: off at once (forget accepted); on asks again and signs up a new id |
| TI-7b one written tip a day, whatever the toggles | ❌ seen | after off → on the same day, the new id made a second tip call (1 → 2): F-TI-1, fixed in #95; this row becomes a pass/fail check once #95 lands |
| TI-3 no tip from the server's side | 🟢 | flow 94e on six days: a timeout, 429, 503, 204, a 200 without sig, a 200 without x-tip-model → the built-in tip, nothing left loading, exactly one tip call each day; the session refreshed each day |
| ⏳ TI-5 other languages | | pig tips are in English only for now |
| ⏳ the real tips server | | a build with tips on against the real server, on a phone, with the release that turns tips on |
History: run 46164524390 on 28ed141 (#94's head) failed for the tests' own reasons: the mock didn't read chunked request bodies, and Me had grown past the flows' scroll (both fixed in the tests). Its APK was byte-identical to this one (1fa4dc48…)

### master: group B — Home's turns, the pig's name, the night pig, days noted, yesterday, the monthly letter — c6940f6 — 🟢 (retroactive, on master after the landing; one finding, F-B1) — 2026-11-28 15:06 UTC
Build: staging debug, built in the job from c6940f6, **no fake_now**: before each PR's rows, root sets the device's zone and clock to the moment those rows were written for, and each PR's rows script runs unchanged; installed = built · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, en-US
Rows: `tool/device-rows/group-b.sh` (emulator run 46155006260, flows `tests/retro` @ 523fe1f): 15 pass, 1 INFO, 0 fail
| Row / check | Result | Notes |
|---|---|---|
| The commits since 10a2bc9 | 🟢 | 30, every one authored and committed by the noreply identity |
| Goldens at c6940f6 (render 46151694713 on 3d2a069) | 🟢 | my own download: 229 PNGs = manifest = committed, both ways, by sha256; against 10a2bc9: 185 identical, 24 changed (Home's end and the themed Homes with the noted line; Me with the pig's name and the yesterday and letter switches), 20 new (the letter, the night pig, the named pig, days noted, yesterday), all looked at, light and dark |
| #55 the pig's name (UTC, 28 Nov 12:00) | 🟢 | PN-light, PN-dark: named on Me and Home; Cancel keeps it; empty removes it; 24 pasted → 20 kept; kept after a relaunch |
| #59 days noted (Bangkok, Wed 25 Nov 12:00) | 🟢 | DN-1, DN-2: one day no line; 2 days; a save counts; last Sunday doesn't; ×2 wraps |
| #53 the night pig (Bangkok, 28 Nov 23:00) | 🟢 | NP1 (C14 sleepy with the night line; C3 happy with its day line), NP2 light and dark (a save's reaction across a tab switch; the night line after hide and reopen) |
| #64 yesterday (UTC, 28 Nov 05:00) | 🟢 | YF-1 to YF-3: three rows at most, answers set the feelings, the fourth comes in; ×2; Me's switch; Not now for the day, also after a relaunch |
| #67 the monthly letter (UTC, 2 Dec 05:00) | 🟢 | ML-1 to ML-3: none without last month; "Your November" with its three lines; ×2; Thanks! puts it away for the month |
| #62 Home's turns (UTC, the clock moved by root) | 🟢 | TU-1: Home open across midnight reads the new day's idea with no tap; TU-2: back from the background days later, same process, the new day's idea; TU-3 INFO: 06:00 and 22:00 left to test/home_turns_test.dart |
| Finding F-B1 (the night pig at 05:00) | ❌ seen | sets at 05:00 local show the sleepy pig saying "It's getting late. I'll be here tomorrow." (night is 22:00 to 05:59): logged as a finding, a narrower window to follow |
| The C3 fixture's letter | ⚪ by design | the fixture freezes its own clock at 2 Dec, so its Home shows November's letter |
History: each PR's own rows ran earlier on its head with fake_now (in its PR's comments); this is the first run of all six on master, in one build

### master: groups A and A′ — the Plus line (yearly only), the Help and privacy links, themes, Patterns — 10a2bc9 — 🟢 (retroactive, on master after the landing; Plus is off in release builds) — 2026-11-28 14:30 UTC
Build: staging debug, built in each job from 10a2bc9: `kind=plus-rows` (Plus enabled, the rows' fake store: Plus stays off) and `kind=plus-owned` (the same, reporting one active yearly purchase with nothing bought); installed = built · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Rows: `tool/device-rows/group-a.sh` (emulator run 46152479393, flows `tests/retro` @ ecda764), `group-a-owned.sh` (run 46153951980, flows @ 2f0e48a)
| Row / check | Result | Notes |
|---|---|---|
| Master's push CI, read per test (run 46152426300, this sha) | 🟢 | `+2023: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean; all four jobs green |
| The commits since 31d7ae3 | 🟢 | 89, every one authored and committed by the noreply identity |
| Goldens at 10a2bc9 (render 46150795750 on 5195356) | 🟢 | my own download: 209 PNGs = manifest = committed, both ways, by sha256; against 6287372: 171 identical, 4 changed (Delete everything with Plus: the dialog the same, Me's list behind it longer), 34 new (Patterns, the four themes on Home, the picker, the swatches), all looked at, light and dark |
| PA-1 the paywall (Plus off) | 🟢 | Me's Plus row opens it: "Everything you have now stays free", three benefits, **one plan, yearly** ("Free for 7 days, then … a year"; no monthly plan), Restore, the store's cancel line, the Privacy Policy link; Start and Restore buy nothing; Back closes it |
| PA-2 the gates (Plus off) | 🟢 | a second goal and Add category each open the paywall and change nothing; hiding a built-in category is free (gone from Add, shown again) |
| PA-5 the themes' gate (Plus off) | 🟢 | Me → Theme: Strawberry, Plum, Apricot, Blueberry; Plum opens the paywall; the theme stays |
| ⏳ PA-3 the paywall at font scale 2.0 | | on the device with the next Plus run (two tries here stopped in the flow before the paywall); the yearly-only paywall at ×2 is in the goldens (320 × 2: offer, offer-end, pending), looked at |
| PA-4 the smoke and the journal, Plus enabled | 🟢 | flows 00 and 10 |
| PO-1 Plus on (with nothing bought) | 🟢 | Me "On. Thanks for your support!" with Manage subscription; the paywall "You have Piggybow Plus", Manage, no plans; a second goal opens the goal form with no paywall (two goals on Home); "Coffee runs" made in Categories and offered in Add; **Delete everything says "Your Plus subscription keeps running until you cancel it in Google Play." with Manage subscription**, and Cancel erases nothing. Every assertion about the app passed; the flow's own last wait (Me's top row after Cancel, with Me still scrolled to Delete) failed: fixed in the flow, proven next time |
| Patterns (#68, #69) | ⚪ device-free | the goldens above and the widget tests; Summary's teaser shows only once enough spends have a feeling |
| ⏳ Plus bought for real | | Play Billing on a device with the store's product (the Plus probe), before Plus can ship |
History: dry runs on #49 (Plus off, flows only) and an `adb root` flake (retried since, in #89)

### master: the store's build, the smoke before internal testing (6c) — 31d7ae3 — 🟢 (a store install on a real phone ⏳) — 2026-11-28 09:12 UTC
Build: prod release (R8, the workflow's throwaway signing key), built in the job from 31d7ae3; installed = built (APK sha256 `f84aa078…`) · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, the real clock, en-US
Rows: `tool/device-rows/smoke6c.sh` (emulator run 46127091775, flows `tests/smoke-6c` @ c95d54f); 12 of 12 rows
| Row / check | Result | Notes |
|---|---|---|
| Master's push CI, read per test (run 46126344816, this sha) | 🟢 | `+1720: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean; all four jobs green |
| The installed package | 🟢 | `com.burrowsoft.piggybow`, versionName 0.1.0; not debuggable; no INTERNET and no ACCESS_NETWORK_STATE requested |
| `00` smoke | 🟢 | every tab; alive after 60 s |
| The journal: `10`, `11`, `13`, `14` | 🟢 | add, edit, delete; a save with no goal; a double tap on Add; Timeline's filters |
| `30` onboarding | 🟢 | O1 to O3, the currency, the plan, Maybe later |
| `21` a goal reached once | 🟢 | the celebration |
| `42` the app lock | 🟢 | a PIN set; a cold start asks; a wrong PIN, then the right one. The lock screen's status bar: the clock, Wi-Fi, signal and battery all dark on the cream page |
| `48` the reminder | 🟢 | set through Me for 9:06 AM, posted by 09:08:15 UTC; `color=0xffa8456a` |
| ⏳ the store's build on a real phone (owner) | | the internal-testing install from Play |
History: 817805b 🟢 (run 46122239068, 12 of 12 rows; push CI 46122088415 `+1715`, 0 failed, 0 skipped; its shots showed the lock screen's Wi-Fi and signal icons white while the clock and battery were dark, fixed by #65) → 31d7ae3 🟢

### #65 Lock: dark status-bar icons from the first frame, on its own style — 31d7ae3 — 🟢 (Piggybow's own theme against the phone's mode ⏳) — 2026-11-28 08:32 UTC
Build: staging debug, built in the job from 31d7ae3; installed = built · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US · light mode, then night mode; the app on its default (System) theme
Rows: `tool/device-rows/pr65.sh` (emulator run 46125280256, flows `tests/pr-65` @ 6f25a6c); 14 frames looked at, with the window's appearance from `dumpsys window`
| Row / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46124822999, this head) | 🟢 | `+1720: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| LB1 light: a cold start with the lock on | 🟢 | three quick frames of the splash, the lock as it appears, and 3 s later: in all five the clock, Wi-Fi, signal and battery are dark; `LIGHT_STATUS_BARS` over the whole window at the lock and at +3 s |
| LB2 light: unlock, background, come back | 🟢 | the cover, the lock and 3 s later: all four icons dark; the same appearance |
| LB1 night: a cold start with the lock on | 🟢 | the splash on the dark background, the lock and 3 s later: all four icons white; no `LIGHT_STATUS_BARS` |
| LB2 night: unlock, background, come back | 🟢 | the lock and 3 s later: all four icons white |
| Before this PR | ❌ seen | the prod-release smoke on 817805b (run 46122239068): the lock's Wi-Fi and signal white while the clock and battery were dark; no frame on this head shows that mix |
| ⏳ Piggybow's own theme against the phone's mode | | Piggybow Light on a dark phone and Piggybow Dark on a light phone: the tester, a CI-emulator run on 31d7ae3 (`pr65b`); this PR covers the default System theme |
History: 31d7ae3 🟢 (landed as is, fast-forward)

### #52 Home and Timeline: each Add button has its own hero tag — dfd4452 — ⚪ (debug-only, UX waiver) — 2026-11-28 07:34 UTC
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46121138120, this head) | 🟢 | `+1715: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| Tester row | ⚪ | UX waiver naming dfd4452 (issuecomment-7236025327): a debug-only assert after both tabs were visited; nothing changes in release builds or on screen; the new test fails on the old code and passes here |

### #50 CI: cache Gradle's downloads, keyed on pubspec.lock too — 00f962b — 🟢 — 2026-11-28 07:24 UTC
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46118287646, this head) | 🟢 | `+1714: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean; the new gradle_cache_workflow_test among them |
| The cache saved on master | 🟢 | master's push run 46119091496 saved `gradle-Linux-apk-1e1acfd8…` (2.26 GiB) from merged code |
| The emulator restores it | 🟢 | emulator run 46120010855 (#48's row): "Cache restored from key: gradle-Linux-apk-1e1acfd8…", no download from Maven |

### #48 Reminder: the notification's accent is the app's berry — 9b4c7ad — 🟢 — 2026-11-28 07:24 UTC
Build: staging debug, built in the job from 9b4c7ad (b20fe4a merged with master 00f962b); installed = built · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Rows: `tool/device-rows/pr48.sh` (emulator run 46120010855, flows `tests/pr-48` @ 18aa3cf)
| Row / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46119130171, this head) | 🟢 | `+1714: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| The reminder posted | 🟢 | set through Me for 7:21 AM (the Time row read back); posted by 07:22 UTC |
| Its colour | 🟢 | `dumpsys notification`: `color=0xffa8456a` (berry #A8456A) |
| The shade, light and night | 🟢 | the small icon's circle in berry (teal before), a lighter berry at night; the eared silhouette |
| The header's app name | ⚪ | stays grey: Android 12 and later tint only the icon's circle |
History: two runs on b20fe4a tested nothing: one stopped at the APK build (Maven Central's 429), one before the install on the test's own fault (a variable name shared with the install check) → 9b4c7ad 🟢

### #44 The pig's ears: one up, one flopped — 6bc7303 — 🟢 (themed icon ⏳, UX waiver) — 2026-11-28 05:53 UTC
Build: staging debug, built in each job from 6bc7303; installed = built · Device: CI emulator, Android 14 (API 34), Pixel Launcher, 1080 × 2400, 420 dpi, UTC, en-US
Rows: `tool/device-rows/pr44.sh` (emulator run 46111109015, flows `tests/pr-44` @ b051191), then `tool/device-rows/pr44b.sh` for the two rows left open (run 46112948061, flows `tests/pr-44` @ 9f596a0)
| Row / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46110721146, this head) | 🟢 | `+1661: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| Goldens (render 46110158079 on af847b2, committed in b91f349) | 🟢 | 135 PNGs = manifest = committed, both ways, by sha256; the 24 pig PNGs that changed looked at; 0 PNG changes from b91f349 to 6bc7303 |
| Home's pig after a fresh install | 🟢 | the ears drawn |
| The splash at a cold start, light and dark | 🟢 | the eared pig, both ears whole, nothing clipped; 4 quick shots per theme, identical; the shadow shows in light only (by design) |
| The launcher icon in the app drawer | 🟢 | the rainbow and the eared pig inside the circle, nothing clipped |
| The reminder notification's small icon | 🟢 | the reminder set through Me for 5:49 AM and the Time row read back; posted by 05:50 UTC; the eared silhouette in the status bar and in the shade, nothing clipped |
| ⏳ the themed launcher icon | | not switched on on the emulator; UX accepted the icon generator's approved preview (UX waiver on the PR) |
History: the first run's reminder row ❌ was the test's own fault (the time picker's minute typed as 20 for 24, so the reminder was planned for the next day); flow 48 now selects each field and checks the Time row → 🟢, same head

### #42 Your privacy: the phone's backup only when it's encrypted — 47ffdf9 — ⚪ (copy only, UX waiver) — 2026-11-28 04:39 UTC
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46108187307, this head) | 🟢 | `+1637: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| Tester row | ⚪ | UX waiver naming 47ffdf9 (issuecomment-7234178657): one privacy line's copy and its regenerated goldens; no device behaviour change |

### #41 Seed leftovers: no /reset route, no translation-draft importer — 10752fd — ⚪ (cleanup, UX waiver) — 2026-11-28 06:07 UTC
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46114784824, this head) | 🟢 | `+1661: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| Tester row | ⚪ | UX waiver naming 10752fd (issuecomment-7235097006): an unused route constant and an unused tool script removed; no UI or device change |

### #39 The phone's own backup, encrypted only; the lock after a restore — 1575d09 — 🟢 (a real cloud backup ⏳) — 2026-11-28 04:22 UTC
Build: staging debug, built in each job from 1575d09; installed = built · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US · AOSP's local backup transport
Rows: `tool/device-rows/pr39b.sh` (emulator run 46105739991, flows `tests/pr-39` @ 7d2d860)
| Row / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46101795619) | 🟢 | `+1637: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| No real encryption (the transport's test flag only) | 🟢 as intended | the app's backup is refused with no file selected ("Error -1002", nothing measured); nothing comes back |
| Real client-side encryption reported | 🟢 | the backup measures and restores exactly `files/journal.db` and `shared_prefs/FlutterSharedPreferences.xml`; no secure storage (the PIN), no export, no cache |
| A device-to-device transfer | 🟢 | the same two files, no PIN, export or cache |
| The app after a restore (flow 46b, both rounds) | 🟢 | the goal and the spend back; no lock prompt; Me's App lock row reads "Off after a restore. Turn it on again." until opened, then "Off" |
| ⏳ a real cloud backup | | Google's transport on a real phone with a screen lock, and a restore on a new phone |
| ⏳ the reminder after a restore without the notification permission | | the relaunch granted it (the test tool's default); covered by unit tests only |
History: ce16ebb9 and 1575d09 runs 46101556335 / 46103938954 were not valid rows (the seed force-stopped the app; the encryption switch set only the transport's test flag), the test's own faults → 1575d09 🟢

### #38 Store screenshots: the STORE1 and STORE2 fixtures, and the shots' helpers — 4de5b0c — 🟢 (carried from cde6ea8; the Play shots ⏳) — 2026-11-28 05:03 UTC
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46094308831, cde6ea8) | 🟢 | `+1502: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| The merge f2e7323 | 🟢 | its tree equals the plain merge of 663e497 and master 76ae303; against master only this PR's 6 files differ |
| Out of store builds | 🟢 | the fixtures compile only in the staging flavour (`kLaunchFixtures = appFlavor == 'staging'`, used only inside `if (kLaunchFixtures)`) |
| The tests, read by name | 🟢 | `play_png` (RGBA in, RGB out; alpha, see-through pixels, the wrong size, extra chunks, 16-bit and a bad CRC refused), `play_shots` (every adb call names an emulator; the display put back even on failure), the store fixtures (STORE1, STORE2; only into a blank journal) |
| Carry to 4de5b0c (cde6ea8 merged with master 47ffdf9) | 🟢 | CI per test (run 46109939500): `+1653: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| ⏳ the six Play shots on a device | | `tool/device-rows/play.sh` on master after the system-bar PR lands; a dry run (46109693186) was looked at |
History: cde6ea8 🟢 → 4de5b0c 🟢 (carried, plain merge)

### #37 Summary: Spent and Saved stack rather than shrink below 1x — 76ae303 — 🟢 (on-device ⏳) — 2026-11-28 01:36 UTC
Build: no device for this row (CI logs + my own download of the golden render)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46093212933) | 🟢 | `+1486: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| The new check, read in the source | 🟢 | `expectTotalsWhole`: Spent and Saved are never shown below min(text scale, 1×) in any layout case; at 320 dp ×2 the largest week is stacked, Saved under Spent |
| Baselines = render | 🟢 | Goldens run 46092944946 (attempt 1, source 428a2df): 97 entries, each in the artifact and `test/goldens/` with the manifest's sha256, 8-bit RGBA; 0 extra either way; committed `manifest.json` = the run's |
| Against master dc062d9 | 🟢 | 92 identical, 5 changed (`summary_nine-at-max` and its `-end`), none new or removed |
| The 5, each looked at beside master's | 🟢 | "$89,999,999,999.91" whole at full size, Spent and Saved stacked full width; the rest unchanged; the `-end` pair differs only where the stacked card's edge shows |
| ⏳ on a device | | flow `31_summary_week_month` on the CI emulator |

### #36 A see-through status bar over pages with no app bar — 4d96c28 — 🟢 (carried from 8ad8c24; API 34 only, older Android ⏳ under a UX waiver) — 2026-11-28 06:19 UTC
Build: staging debug, built in the job from 8ad8c24; installed = built · Device: CI emulator, Android 14 (API 34), Pixel Launcher, 1080 × 2400, 420 dpi, UTC, en-US
Rows: `tool/device-rows/statusbar.sh` (emulator run 46114382401, flows `tests/pr-36` @ ead02d9): flows 50 and 51 with gesture navigation, then the 3-button bar, each in light and night mode; 8 of 8 rows, 32 shots
| Row / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46113865193, 8ad8c24) | 🟢 | `+1702: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| No black or grey strip behind the navigation bar | 🟢 | O1 Welcome, Home, the celebration, O1's currency list, the Add sheet, Me → What makes your pig happy, a goal's page: the page's own colour behind the handle and behind the 3 buttons, light and dark. Before this PR, Home had a black strip behind the handle |
| Nothing to read or tap under the navigation bar | 🟢 | the currency list's last row, the Add sheet's Add button, Me's Done and the tab bars end above the handle and the 3 buttons |
| The navigation bar's icons readable | 🟢 | dark on light pages, light on dark |
| The status bar (decision 65) | 🟢 | see-through with dark icons on light and light icons on dark; over the Add sheet, the sheet's dimmed barrier, the same as before this PR |
| Carry to 4d96c28 (8ad8c24 merged with master 10752fd) | 🟢 | the PR's own diff has the same patch-id (`e61f6619`); the merge's tree equals the plain merge; master's changes touch no styles, system-bar or layout code. CI per test (run 46115243914): `+1710: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines |
| ⏳ Android 9 and below; API 35/36 | | not run: the emulator workflow has one image (API 34). Android 7–9 are covered by a UX waiver (8–9 on the platform's reading, 7 on the unit tests) |
History: 8ad8c24 🟢 → 4d96c28 🟢 (carried, plain merge)

### #35 App lock: Forgot PIN uses the phone's own screen lock, or erases — 2e9c071, landed with #39 at 1575d09 — 🟢 on 1575d09 — 2026-11-28 04:04 UTC
Build: staging debug, built from 1575d09 (this PR's 2e9c071 plus #39) · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Rows: `tool/device-rows/pr35.sh` (emulator run 46102672427) and R6 with `pr35b.sh` (emulator run 46105004389), flows `tests/pr-35`
| Row / check | Result | Notes |
|---|---|---|
| Golden render (Goldens run 46098889268, source 3af7567), downloaded and checked | 🟢 | 133 entries; master's 123 byte-identical; 10 new lock PNGs, each looked at |
| R3 the PIN | 🟢 | set 1357 through Me → App lock; a cold start asks; a wrong PIN errs and the pad waits; the right one opens Home; Me's row reads "On" |
| R3b resume | 🟢 | the lock screen after Home and back |
| R4 recents | 🟢 | no FLAG_SECURE; the recents card blank while the lock is on |
| R5 Forgot PIN, no phone screen lock | 🟢 | erase only; the second confirm with the lock's own body and no "Export first"; Cancel keeps all; erase → O1 with the lock off |
| R6 Forgot PIN with the phone's own PIN | 🟢 | the phone's PIN in the system prompt, then a new Piggybow PIN; the old one refused, the new one opens |
History: 2e9c071 alone ❌ (Me's App lock row stayed "Off" after the lock was turned on; #39's Me listens, so the two landed together) → 1575d09: R6 ❌ in run 46102672427 (the flow waited for text in the system's PIN prompt, a secure window; fixed to wait for its number pad) → R6 🟢 in run 46105004389 → 1575d09 🟢

### #34 Polish: the offer's buttons stack full width, Reached under the button, a 3-line goal name — e3e86b9 — 🟢 (on-device ⏳) — 2026-11-28 00:23 UTC
Build: no device for this row (CI logs + my own download of the golden render)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46087158975, merge base 22b85c2 = master) | 🟢 | `+1425: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| Baselines = render | 🟢 | Goldens run 46086880847 (attempt 1, source 17e4c2e): 97 entries, each in the artifact and `test/goldens/` with the manifest's sha256, 8-bit RGBA; 0 extra either way; committed `manifest.json` = the run's |
| Against master 22b85c2 | 🟢 | 69 identical, 24 changed, 4 new, 0 removed |
| The 4 new PNGs, looked at | 🟢 | the reminder offer stacked at 320 dp ×2 (the yes full width on top, No thanks under it); "Reached: …" under "Start a goal" |
| The 24 changed PNGs, each looked at beside master's | 🟢 | the 40-character goal name on 3 lines; "Start my rainbow" and "Start a new goal" centred; the offer's stacked button on sleepy Home; Today's idea in the cards' body style, so Home's `-end` PNGs scroll differently, and the last row stays above the + |
| Covered by tests in the source | 🟢 | one line with No thanks first when there's room, else stacked full width, the yes on top, an 8 dp gap; the goal name 1–3 lines with Done, a typed line break kept as a space |
| ⏳ on a device | | the stacked offer and the 3-line goal name in the next CI-emulator runs with the reminder and goal flows |

### #33 Goldens: Home, the goal screens, the pig and the rainbow — 22b85c2 — 🟢 (carried from dfeec6e) — 2026-11-28 00:18 UTC
Build: no device for this row (CI logs + my own downloads of the golden renders)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46085946100 on dfeec6e) | 🟢 | `+1354: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| Render on dc8d494 (Goldens run 46085639996), downloaded and checked | 🟢 | 76 entries, each in the artifact and `test/goldens/` with the manifest's sha256, 8-bit RGBA; 0 extra either way; `manifest.json` byte-identical |
| Against what was already checked | 🟢 | 16 = master's PNGs; 46 = the PR 3 render I had checked on e0267cc; 14 dark PNGs differ (Home in six moods with each `-end`, the goal detail's end, the End goal dialog) |
| The 14, each looked at beside the older render | 🟢 | only the dark surface colour changed (cards, the dialog, the scrolled-under app bar), to the lighter surfaces from #31; text, wrapping, the pig and the layout identical |
| After #23: master merge f17d8e7 + baselines 22b85c2 | 🟢 | the only conflict was `test/goldens/manifest.json`; Goldens run 46086591464 (source f17d8e7): 93 entries, every PNG byte-identical to dfeec6e's set or to master's, 0 new or changed; committed = run |
| CI, read per test (run 46086844984 on 22b85c2) | 🟢 | `+1408: All tests passed!` (master's 1352 + 56), 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
History: dfeec6e 🟢 → 22b85c2 🟢 (carried: render byte-identical, CI green)

### #32 The daily reminder: Piggybow's words, a new one each day, skipped after an entry, and a tap opens Add — 826b63a — 🟢 (the app's rows; a posted reminder ⏳) — 2026-11-28 02:45 UTC
Build: staging debug, built from 826b63a · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Rows: `tool/device-rows/pr32.sh` (emulator run 46097533067) and R2 again with `pr32b.sh` (emulator run 46098720661), flows `tests/pr-32`
| Row / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46096905433) | 🟢 | `+1565: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| R0 No thanks | 🟢 | hides the offer for good, asks for no permission, leaves the reminder off |
| R1 Yes + Allow | 🟢 | the reminder on at 8:00 PM; not offered again |
| R1b the schedule, read from the device | 🟢 | 29 reminders (today dropped after today's entry), one a day at 20:00 from tomorrow; every title "Piggybow"; the body rotates by day, no two days alike, no digit |
| R2 Don't allow | 🟢 | "Notifications are off for Piggybow…"; Open settings opens the app's notification page; Back returns to Me |
| ⏳ a posted reminder in the shade, tapped | | the flow's setup was at fault twice; it runs again later |
History: 826b63a R2 ❌ on the flow's return step → 826b63a 🟢 (re-run). Merged on a UX waiver while the confirmation ran.

### #31 Polish: lighter dark surfaces, centred button labels, a 3-line note — 1298dfd — 🟢 (carried: same tree as 5352dc9) — 2026-11-27 23:49 UTC
Build: no device for this row (CI logs + my own download of the golden render)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46084314744, this head) | 🟢 | `+1112: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean. 1112 = master's 1100 + 12, incl. the note field and the dark surfaces (every raised surface lighter than the page, every text still 4.5:1 on it) |
| Same tree as the checked head | 🟢 | 1298dfd's tree `98c279b5…` equals 5352dc9's (three commits squashed into one); 0 raw U+2028 / U+2029 bytes in the diff |
| The note field | 🟢 | 1–3 lines, Done as the keyboard action, pasted line breaks become spaces |
| Wrapped button labels | 🟢 | every line centred |
| Golden render, downloaded and checked | 🟢 | Goldens run 46083284542, attempt 1, source 09993c1: 16 sha256 match the artifact and `test/goldens/`, 0 extra either way; `manifest.json` byte-identical |
| Changed baselines, each looked at | 🟢 | 13 of 16: the note on 3 lines, centred labels, dark sheets and dialogs a step lighter than the page, the last Timeline row clear of the + |
| ⏳ on a device | | the note's 3 lines and Done in the next journal run on the CI emulator |
History: 5352dc9 🟢 → 1298dfd 🟢 (same tree)

### #30 Emulator: run the flows on the store's build (prod, release, R8) — 862e160 — 🟢 (carried from 443cb5a) — 2026-11-28 00:28 UTC
Build: prod release, built in the job from 443cb5a; installed = built · Package: `com.burrowsoft.piggybow` · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Flows: `--include-tags smoke`, from 443cb5a · Emulator run 46086267678
| Flow / check | Result | Notes |
|---|---|---|
| `kind=prod-release` end to end | 🟢 | the store's flavour, release, R8, a throwaway key; the installed APK equals the built one (59.6 MB) |
| No network permission in the installed package | 🟢 | `dumpsys package`: no INTERNET, no ACCESS_NETWORK_STATE |
| `00_smoke_launch`, `10_journal_loop` | 🟢 | both pass in release mode |
| Carry to c203687, then 862e160 | 🟢 | each a conflict-free plain merge with master; the PR's own diff stays 3 files (the workflow, its test, `tool/emulator/run.sh`), no app code. CI per test: c203687 `+1353` (run 46086816532), 862e160 `+1426` (run 46087649406), 0 failed, 0 skipped, 0 `[E]` |
| ⏳ the integrated app as a store build | | the first prod-release run on master (run 46088333530) |
History: 443cb5a 🟢 → c203687 🟢 → 862e160 🟢 (carried, plain merges)

### #29 Me: your pig, money, reminders, privacy & security, appearance, about — a47fc5f — 🟢 — 2026-11-28 02:11 UTC
Build: staging debug, built in each job from the head named; installed = built every time · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Flows: `tests/pr-29` (bf1089b for the Me re-run) · Emulator runs 46095196738 (this head), 46090292844 and 46093235777 (9f9812f)
| Run / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46094297015, this head) | 🟢 | `+1560: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| From 9f9812f to this head | 🟢 carried | only master's Summary change came in: the same `git patch-id --stable` as that PR's own (`49be17f7eced`), and this PR's own diff against master unchanged (`e458b3c88138`) |
| `32_me_currency_lock` | 🟢 | the picker while nothing exists; "Currency is set" after the first entry; changeable again after Delete everything |
| `33_delete_everything` | 🟢 | Cancel keeps everything; Delete returns to O1 with no entries, goal, plan or picks |
| `34_remove_plan_unpicks` | 🟢 | Remove plan sets "Not set" and unpicks only the plan; as the only pick, the picker opens first: Back keeps the plan, Done with nothing picked shows "Pick at least one.", a new pick removes the plan |
| `35_privacy_screen` | 🟢 | lines 1, 2, 4 and 5; no crash-report line without a DSN; no Help row; "Version 0.1.0 (1)" |
| `36_me_appearance` | 🟢 | Same as device by default; Dark and Light apply at once and survive a relaunch |
| `15_export_share_sheet` | 🟢 | the system share sheet with `piggybow-2026-11-28.csv` |
| Onboarding, smoke and journal (run 46090292844) | 🟢 | onboarding into Home with the plan and Thai baht; every tab; the 4 journal flows |
| Goal, pig and rainbow (run 46093235777) | 🟢 | every pig mood and rainbow fixture, the celebration, the read-only reached goal, End goal, lowering the target; the reminder offer's stacked buttons |
| The launch | 🟢 | with the clear as its own step before the launch, 0 of 8 fresh launches needed the retry (5 of 12 before) |
| Screenshots looked at | 🟢 | 67 across the three runs |
History: 9f9812f ❌ (two Me flows and one goal flow failed on the flows' own assumptions; fixed) → a47fc5f 🟢

### #28 Release builds ask for no network; the store workflow takes pasted secrets — 658ce78 — 🟢 (on-device ⏳) — 2026-11-27 23:28 UTC
Build: no device for this row (CI logs + the merged release manifest printed in CI)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46082222335, this head) | 🟢 | `+1100: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean; all 7 tests in `test/release_no_network_test.dart` named in the log |
| The merged release manifest | 🟢 | stagingRelease asks for exactly POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, USE_BIOMETRIC, USE_FINGERPRINT, VIBRATE, com.android.vending.BILLING and the app's dynamic-receiver permission. No INTERNET, no ACCESS_NETWORK_STATE; identical to `android/expected-permissions.txt` |
| How it's removed | 🟢 | `src/release/AndroidManifest.xml`, `tools:node="remove"` for both |
| A release that would need the network stops | 🟢 | any Release task with `SENTRY_DSN` or `PLUS_ENABLED=true` fails, naming both files to change; tested |
| Debug and profile builds | 🟢 | keep both for the Flutter tool, listed in `android/debug-only-permissions.txt` |
| The secret masks | 🟢 | `release-aab.yaml` escapes `%` as `%25` in `::add-mask::`, pinned by a test |
| PR APK run 46082223883 | 🟢 | 0 artifacts uploaded |
| ⏳ on a device | | a release-build CI-emulator run: no network permission in the installed package, the app starts and the journal works offline; and the first store-build install |
History: fbed6eb 🟢 → 658ce78 🟢 (fresh row: one commit on fbed6eb)

### #27 Onboarding: Welcome, what makes the pig happy, the first goal; the currency picker — dc062d9 — 🟢 (carried from 3813bec; integrated on-device ⏳) — 2026-11-28 00:38 UTC
Build: staging debug, built in the job from 3813bec · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Flows: `--include-tags onboarding,smoke,journal`, from `tests/pr-27` at aa4475f · Emulator run 46084640911
| Flow / check | Result | Notes |
|---|---|---|
| All 6 flows | 🟢 | smoke, the 4 journal flows through onboarding, and `30_onboarding_paths` |
| O1 → the currency picker → Thai baht | 🟢 | the phone's currency first and checked, the rest by name with symbols |
| O2 with the plan pick, O3 empty and with both errors | 🟢 | "My weekly spending plan" with 2000; "Give your goal a name." / "Enter a goal amount." |
| Home after "Maybe later" | 🟢 | Spent ฿0.00 / Saved ฿0.00, Weekly plan ฿2,000.00; no permission prompt, no second onboarding |
| Carry to dc062d9 | 🟢 | the 5 commits' `git patch-id --stable` unchanged (whole range `1370e56b0fff`); the master merge's one conflict (the goal button's label) resolved as master's `ButtonLabel` with the onboarding label; one new commit (O3's "Maybe later" as a `ButtonLabel`), read. CI run 46088413577: `+1486`, 0 failed, 0 skipped, 0 `[E]`; goldens identical to master's |
| ⏳ on a device, integrated | | onboarding into the goal screens and Home from master: the staging run on the next head that contains it |
History: 3813bec ❌ (my flow's 4 s scroll to Thai baht) → 3813bec 🟢 (re-run) → dc062d9 🟢 (carried)

### #26 Maestro: the journal flows, and the onboarding branch's new ids — ae433ac — ⚪ (tests only; the flows ran on #9's head) — 2026-11-27 22:38 UTC
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46077155506, this head) | 🟢 | `+1093: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| The flows on a device | 🟢 | the four journal flows passed 4 of 4 on #9 @ 68e8f14 (emulator run 46073935616). The merged `.maestro/` differs from that run's flows only by 2 lines: the onboarding branch's new ids in `00_smoke_launch` and `to_timeline` |
| Master after the merge (f9c33e8), CI run 46077837737 | 🟢 | `+1093: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines |

### #25 Goldens: the add sheet, the delete dialog and Timeline — 5ee781c — 🟢 — 2026-11-27 22:36 UTC
Build: no device for this row (CI logs + my own download of the golden render)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46077278624) | 🟢 | `+1093: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean. The `golden` tag is not skipped, so the layout cases compared against these baselines |
| The render, downloaded and checked | 🟢 | Goldens run 46076896331, attempt 1, source 1d9fa3a, Flutter 3.47.5: 16 sha256 match the artifact and `test/goldens/`, 0 extra files either way; `manifest.json` byte-identical |
| PNG checks | 🟢 | all 16 valid, 960 × 2340, 8-bit RGBA |
| Stable renders | 🟢 | all 16 byte-identical to the earlier run 46076042739 |
| Looked at | 🟢 | all 16: whole words everywhere, the 40-character goal name wrapped, the Thai note rendered, the amount on its own line at ×2 |
| Test-only rendering | ⚪ | the + shows a solid ring: the tests' stand-in for an elevation shadow |

### #24 Launch fixtures for the on-device flows (staging builds only) — 353cbea — 🟢 — 2026-11-28 00:32 UTC
Build: staging debug, built in the job from 353cbea · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Flows: `--include-tags pig,rainbow`, from `tests/pr-18` at d49d602 · Emulator run 46087437379
| Flow / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46086253345) | 🟢 | `+1313: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| `25_home_moods` | 🟢 | C6 sleepy, C1/C2 calm, C3 happy, C4 delighted, C9 band 2 (its card agrees: $200.00 of $500.00, 40 %), C31 a goal reached then ended; no `fixture-error` |
| `26_rainbow_states` | 🟢 | R0 empty with no "Saves" header; R32 at $320.00 of $1,000.00; R100 on Home with the pig drawn |
| Screenshots looked at | 🟢 | all 10 |
| Landed | 🟢 | unchanged inside #27's dc062d9 (an ancestor); that tree's CI `+1486` |
History: d07b2e0 ❌ (R100 had no pig; C9's stamps disagreed with its card; R0 showed an empty "Saves" header; the rest were flow assumptions and one launch race) → 353cbea 🟢

### #23 Summary: the week or month at a glance — e133cb9 — 🟢 — 2026-11-28 00:10 UTC
Build: no device for this row (CI logs + my own download of the golden render)
| Check | Result | Notes |
|---|---|---|
| CI, read per test (run 46085814136, this head merged with master 19f3818) | 🟢 | `+1352: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| The code | 🟢 carried | `git diff 19f3818 2a8bac6 \| git patch-id --stable` = `4a8722ac45c3`, the same as at 44b272f over its first base; the later commits touch only `test/` |
| Fixture S1, my own arithmetic (at 44b272f) | 🟢 | this week $115.70 spent / $50.00 saved, home 86 · food 10 · transport 2 (floored), plan bar 11570 / 15000 = 77 %; December $15.70 / $50.00, food 79 · transport 20 |
| Baselines = render | 🟢 | `test/goldens/` (33 PNGs + `manifest.json`) byte-identical, 34 of 34, to Goldens run 46085547381 (attempt 1, source d447e0e) |
| The 17 Summary PNGs, each looked at | 🟢 | the numbers above; nine categories at the largest amount, 11 % each, no overflow; the empty week; dark cards a step lighter than the page. At 320 dp ×2 the largest Spent total shrinks below its 1× size (backlog) |
| ⏳ on a device | | flow `31_summary_week_month` on the CI emulator |
History: 44b272f 🟢 (device-free, on the goal branch) → e133cb9 🟢 (patch-id carried, plus its baselines)

### #21 Maestro: close another app's hung process instead of waiting on it — 9716e65 — 🟢 — 2026-11-27 22:01 UTC
Build: staging debug, built in the job from 9716e65 · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Flows: `--include-tags smoke`, from this head · Emulator run 46072653778
| Flow / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46071835717) | 🟢 | `+975: All tests passed!`, 0 failed, 0 skipped; analyze clean |
| Same patch as the reviewed head | 🟢 | `git patch-id --stable` `2787bd5a…` at 9c1401f and at 9716e65 |
| `00_smoke_launch` | 🟢 | 1 test, 0 failures; both dismiss rounds ran and found nothing; `start-error` not shown; the four tabs with whole labels; still on Home after 60 s |
| Logs only on a failure (#14) | 🟢 | first live proof: no `logs/` folder, since the flow passed |
| Evidence | 🟢 | 12 files; 0 installables |
| "Close app" on another app's ANR, live | 🟢 | first seen later, in emulator run 46084640911 (#27 @ 3813bec): "Pixel Launcher isn't responding" was up, the subflow left its `system-anr-closed` screenshot and closed it, and the flow passed |
History: the smoke on master 668df2b ❌ (the launcher's dialog came back after "Wait") → 9716e65 🟢

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

### #18 The goal and its rainbow, the pig, and Home — 9629c9d — ❌ flows only, UX waiver; merged as 19f3818; every goal flow 🟢 on master — 2026-11-28 02:20 UTC
Build: staging debug, built in the job from 9629c9d · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Flows: `--include-tags journal,goal`, from `tests/pr-18` at dccb6b5 · Emulator run 46080853711
| Flow / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46080515412) | 🟢 | `+1279: All tests passed!`, 0 failed, 0 skipped; analyze clean |
| The 4 journal flows | 🟢 | as on #9 |
| `22_goal_start_at_target` | 🟢 | one celebration at creation, Home after "Done", none after a relaunch |
| `24_goal_end` | 🟢 | "End this goal?" / "Your saves stay in your journal."; Cancel keeps it; End leaves the saves as "Saved for Bike" |
| The goal form | 🟢 | both errors on an empty Start |
| The celebration | 🟢 | "You did it!", the delighted pig, the full rainbow |
| The reached goal's detail | 🟢 | read-only: "$100.00 of $100.00", no "to go", no Add savings, no menu |
| `20_goal_first_band` | ❌ (flow) | step 35: the form stayed open after "back" (the real cause, found later: the keyboard's own Back in the navigation bar takes a back while the keyboard is up) |
| `21_goal_reached_once`, `23_goal_lower_target` | ❌ (flow) | "Done" returns to the goal's detail when the save was made there; the flows expected Home and now go back first |
| The merge commit 19f3818, CI read per test (run 46085227467) | 🟢 | `+1298: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean (the waiver's condition) |
| On master 862e160 as the store's build (prod, release, R8; emulator run 46088333530, flows `tests/pr-18` @ d49d602) | 🟢 | installed = built; no INTERNET or ACCESS_NETWORK_STATE in the installed package; smoke, the 4 journal flows and 4 goal flows pass (start at target, reached once with the celebration and the read-only goal, lower target, End goal); 23 screenshots looked at |
| On #29's head 9f9812f (master + Me; emulator run 46093235777) | 🟢 | the same goal flows pass again, with the pig's moods and the rainbow fixtures |
| `20_goal_first_band` on a47fc5f (master; emulator run 46096767989, flows `tests/pr-29` @ a97d168) | 🟢 | 141 of 141 commands: the form's errors; a $25.00 save fills band 1 ("Rainbow 25% filled", "$75.00 to go"); Home Delighted with "Band 1 of 5 colored in!" over the after-save reaction; the goal card at 25 %. Its earlier ❌s were the flow's own: a bare `tapOn "Back"` hit the keyboard's Back, then a tab was tapped on the goal's detail, which covers the tab bar |
History: 9629c9d ❌ flows only (waived) → merged as 19f3818 (CI 🟢) → master 862e160 store build: 4 of 5 goal flows 🟢 → a47fc5f: flow 20 🟢. The PR's earlier code was first exercised on a device in #24's run on d07b2e0 (see #24's row)

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

### #9 Journal core: the store, the add/edit sheet and Timeline — 68e8f14 — 🟢 — 2026-11-27 22:14 UTC
Build: staging debug, built in the job from 68e8f14 · Device: CI emulator, Android 14 (API 34), 1080 × 2400, 420 dpi, UTC, en-US
Flows: `--include-tags journal`, from `tests/pr-9` at dd48b2b · Emulator run 46073935616
| Flow / check | Result | Notes |
|---|---|---|
| CI, read per test (run 46073240502) | 🟢 | `+1093: All tests passed!`, 0 failed, 0 skipped, 0 `[E]` lines; analyze clean |
| `14_timeline_filters` | 🟢 | after the first add, + opened the sheet 2.8 s later while "Added" still showed; All / Spent / Saved show the right rows, and the day total follows the filter |
| `10_journal_loop` | 🟢 | the tab bar hidden under both sheets; add, edit, delete with Cancel; still empty after a relaunch |
| `11_add_save_no_goal` | 🟢 | "No goal yet. It still counts as saved.", "= $20.00", the row "+$20.00" |
| `13_double_tap_add` | 🟢 | one entry from a double tap, still one after a relaunch |
| Screenshots looked at | 🟢 | 11, incl. the + fully above "Added" and the edit sheet at full height |
| Evidence | 🟢 | 21 files; 0 installables; no `logs/` folder |
Merged as a merge commit of this head (8e559cf).
History: 0325176 ❌ (14 layout failures at text ×2) → 32e7e70 ❌ (another app's ANR covered the app; no evidence) → 32e7e70 ❌ ("Added" covered the +) → 68e8f14 🟢

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
