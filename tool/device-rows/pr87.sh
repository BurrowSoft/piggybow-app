#!/usr/bin/env bash
# The backup file's screens (#87, feature 21) on the CI emulator, staging
# debug (the feature is on outside release builds), zone UTC:
#   BK-1 (P1a) Back up opens the share sheet; while it's open, the file is
#        copied from the app's cache/export (run-as, a debug build: the CI
#        emulator has no share target that saves to Downloads) and pushed to
#        /sdcard/Download
#   BK-5 (P5)  the sheet dismissed: the screen stays, passwords kept, no
#        message; cache/export empty after
#   BK-2 (P1b) Delete all my data → O1 → Restore from the file → "Your journal
#        is back." → the journal back; the time Restore → done (an x86
#        emulator, not a phone: informational)
#   BK-3 (P2)  a wrong password: the wrong-password line, the password kept
#   BK-4 (P3, P3b, P3c) 1 GB of zeros, 52 MB of zeros, 49 MB of random bytes:
#        "This isn't a Piggybow backup file.", no crash; meminfo around each
#   BK-6 (P6)  one byte changed in a copy: the wrong-password line
#   BK-7 (P4)  the app's cache after all of it: nothing from the picks
. "$(dirname "$0")/lib.sh"
guard_emulator

WORK=/tmp/pr87
mkdir -p "$WORK"
DL=/sdcard/Download

cleanup(){
  A shell rm -f "$DL/big-video.mp4" "$DL/over-cap.bin" "$DL/under-cap.bin" >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

scan(){ # make a pushed or made file visible to the picker
  A shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$DL/$1" >/dev/null
}
heap(){ # heap <label>: the app's memory, from meminfo (App Summary + TOTAL)
  echo "$(stamp) meminfo $1: $(A shell dumpsys meminfo "$APP_ID" | tr -d '\r' | grep -E 'TOTAL PSS|Java Heap|Native Heap|^ *TOTAL ' | tr -s ' ' | tr '\n' ' ')"
}
alive(){ [ -n "$(A shell pidof "$APP_ID" | tr -d '\r')" ]; }

install_verify || exit $?

# BK-1: Back up, the share sheet open
if mf flows/pb1/91a_backup_share.yaml; then
  NAME=$(A shell run-as "$APP_ID" ls cache/export 2>/dev/null | tr -d '\r' | grep -E '^piggybow-backup-[0-9]{4}-[0-9]{2}-[0-9]{2}\.piggybow$' | head -1 || true)
  if [ -n "$NAME" ]; then
    A exec-out run-as "$APP_ID" cat "cache/export/$NAME" > "$WORK/$NAME"
    A push "$WORK/$NAME" "$DL/$NAME" >/dev/null && scan "$NAME"
    row BK-1 PASS "flow 91a: Back up opened the share sheet with $NAME ($(wc -c < "$WORK/$NAME") bytes, sha256 $(sha256sum < "$WORK/$NAME" | cut -c1-12)…), copied to Downloads for the restore rows"
  else
    row BK-1 FAIL "no piggybow-backup-<day>.piggybow in cache/export while the sheet was open"; exit 1
  fi
else
  row BK-1 FAIL "flow 91a"; exit 1
fi

# BK-5: the sheet dismissed
if mf flows/pb1/91b_backup_dismissed.yaml; then
  left=$(A shell run-as "$APP_ID" ls cache/export 2>/dev/null | tr -d '\r' | grep -c . || true)
  if [ "${left:-0}" = 0 ]; then
    row BK-5 PASS "flow 91b: dismissed, the screen stays with both passwords, no message; cache/export empty after"
  else
    row BK-5 FAIL "flow 91b passed, but cache/export still holds $left file(s)"
  fi
else
  row BK-5 FAIL "flow 91b"
fi

# BK-2: the round trip, timed
if mf flows/pb1/91c_restore_new_phone.yaml; then
  CJ=$(find "$OUT/maestro/91c_restore_new_phone" -name commands.json | head -1)
  MS=$(jq '[.[] | select(.metadata.evaluatedCommand.assertConditionCommand.condition.visible.idRegex? == "restore-done") | .metadata.duration] | first' "$CJ" 2>/dev/null || echo "?")
  row BK-2 PASS "flow 91c: Delete all my data → O1 'Moving from another phone?' → the file → Restore → 'Your journal is back.' → Done → 'Coffee with Mai' on Timeline; Restore → done ${MS} ms (x86 CI emulator, not a phone)"
else
  row BK-2 FAIL "flow 91c"
fi

# BK-3: a wrong password
if MF_NAME=91d-wrong mf flows/pb1/91d_restore_wrong_password.yaml -e FILE=piggybow-backup- -e "PASSWORD=wrong horse battery" -e SHOT=91-wrong-password; then
  row BK-3 PASS "flow 91d: 'This password doesn't open this backup. Check it and try again.'; the password kept"
else
  row BK-3 FAIL "flow 91d (wrong password)"
fi

# BK-4: not a backup, from 1 GB down to just under the cap
A shell dd if=/dev/zero of="$DL/big-video.mp4" bs=1048576 count=1024 2>/dev/null; scan big-video.mp4
A shell dd if=/dev/zero of="$DL/over-cap.bin" bs=1048576 count=52 2>/dev/null; scan over-cap.bin
A shell dd if=/dev/urandom of="$DL/under-cap.bin" bs=1048576 count=49 2>/dev/null; scan under-cap.bin
ok=0
for item in "big-video:P3 1 GB of zeros" "over-cap:P3b 52 MB of zeros" "under-cap:P3c 49 MB of random bytes"; do
  f=${item%%:*}; what=${item#*:}
  heap "before the pick, $f"
  if MF_NAME=91e-$f mf flows/pb1/91e_restore_not_backup.yaml -e FILE="$f" -e SHOT="91-not-backup-$f"; then
    heap "at the 'isn't a backup' line, $f"
    sleep 10
    heap "10 s later, $f"
    if alive; then
      ok=$((ok+1)); echo "$(stamp) INFO $what: refused as not a backup, the app alive"
    else
      echo "$(stamp) INFO $what: the app is gone after the refusal"
    fi
  else
    heap "after the failed flow, $f"; echo "$(stamp) INFO $what: FAILED"
  fi
  A shell input keyevent 4 >/dev/null   # Back, off the restore screen
  sleep 2
done
if [ "$ok" = 3 ]; then
  row BK-4 PASS "flow 91e ×3: 1 GB, 52 MB and 49 MB (random) each 'This isn't a Piggybow backup file.', no crash or ANR; meminfo before and after each in the log"
else
  row BK-4 FAIL "flow 91e: $ok of 3 refused cleanly"
fi

# BK-6: one byte changed
python3 - "$WORK/$NAME" "$WORK/tampered-copy.piggybow" <<'PY'
import sys
data = bytearray(open(sys.argv[1], 'rb').read())
i = len(data) // 2
while not chr(data[i]).isalnum():
    i += 1
data[i] = ord('B') if data[i] != ord('B') else ord('C')
open(sys.argv[2], 'wb').write(data)
print("changed byte", i, "of", len(data))
PY
A push "$WORK/tampered-copy.piggybow" "$DL/tampered-copy.piggybow" >/dev/null && scan tampered-copy.piggybow
if MF_NAME=91d-tampered mf flows/pb1/91d_restore_wrong_password.yaml -e FILE=tampered-copy -e "PASSWORD=correct horse battery" -e SHOT=91-tampered; then
  row BK-6 PASS "flow 91d on a copy with one byte changed: the wrong-password line, no crash"
else
  row BK-6 FAIL "flow 91d (tampered copy)"
fi

# BK-7: the cache after it all
LS=$(A shell run-as "$APP_ID" ls -R cache 2>/dev/null | tr -d '\r')
echo "$(stamp) cache listing:"; printf '%s\n' "$LS" | sed 's/^/    /'
if printf '%s\n' "$LS" | grep -qE 'big-video|over-cap|under-cap|tampered|piggybow-backup|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}'; then
  row BK-7 FAIL "the cache holds something from the picks (listing above)"
else
  row BK-7 PASS "the cache holds nothing from the picks: no copies, no random-id folder (listing above)"
fi
