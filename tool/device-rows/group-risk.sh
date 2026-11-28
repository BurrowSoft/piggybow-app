#!/usr/bin/env bash
# The captain's riskiest checks after #92 (groups C–F on master), staging
# debug, zone UTC, no fake_now, the device clock moved by root where needed:
#   RK-1 flow 93a: the Add sheet in another currency, top to bottom (chip,
#        rate, sentence, quick amounts); Repeat off with its line
#   RK-2 flow 93b: a euro save on a goal with a take-out: the edit below the
#        taken-out amount is refused; above it is kept, the goal right
#   RK-3 flows 93c + 93d: a backup with a weekly repeat and a euro spend,
#        restored on O1: both come back
#   RK-5 flows 93e + 93f: a repeat catching up when Piggybow comes back from
#        the background 8 days later (no restart)
# (RK-4, the widget's "+" with the app lock on, runs in group-d.sh.)
. "$(dirname "$0")/lib.sh"
guard_emulator

WORK=/tmp/group-risk; mkdir -p "$WORK"; DL=/sdcard/Download
setclock(){ # setclock <YYYY-MM-DD> <HH:MM:SS>, in UTC
  local d=$1 t=$2
  A shell date -u "${d:5:2}${d:8:2}${t:0:2}${t:3:2}${d:0:4}.${t:6:2}" >/dev/null
  echo "$(stamp) device clock: $(A shell date -u | tr -d '\r')"
}
cleanup(){
  A shell settings put global auto_time 1 >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT
between_rows(){ # a row starts clean whatever the last one left open (a sheet, the keyboard)
  A shell am force-stop "$APP_ID"; A shell input keyevent KEYCODE_HOME; sleep 1
}

A root >/dev/null 2>&1 || { sleep 3; A wait-for-device; A root >/dev/null 2>&1; }
sleep 3; A wait-for-device
[ "$(A shell id -u | tr -d '\r')" = 0 ] || { row RK-0 FAIL "no root: the clock can't be moved"; exit 1; }
A shell settings put global auto_time 0
install_verify || exit $?
D0=$(date -u +%Y-%m-%d)
setclock "$D0" 12:00:00

if mf flows/pb1/93a_currency_sheet_order.yaml; then
  row RK-1 PASS "flow 93a: chip, rate, 'That's \$4.20 at this rate.', then the baht quick amounts, top to bottom; Repeat off with 'Repeats work in your home currency for now.'; a quick amount keeps the rate (\$8.40)"
else
  row RK-1 FAIL "flow 93a"
fi

between_rows
if mf flows/pb1/93b_euro_save_take_out.yaml; then
  row RK-2 PASS "flow 93b: €100 at 1.10 (\$110), \$50 out (\$60); editing to €10 refused ('Some of this money was taken out of Bike…'); €120 kept with its rate: \$82.00"
else
  row RK-2 FAIL "flow 93b"
fi

between_rows
if mf flows/pb1/93c_backup_with_repeat_euro.yaml; then
  NAME=$(A shell run-as "$APP_ID" ls cache/export 2>/dev/null | tr -d '\r' | grep -E '^piggybow-backup-[0-9-]+\.piggybow$' | head -1 || true)
  if [ -n "$NAME" ]; then
    A exec-out run-as "$APP_ID" cat "cache/export/$NAME" > "$WORK/$NAME"
    A push "$WORK/$NAME" "$DL/$NAME" >/dev/null
    A shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$DL/$NAME" >/dev/null
    if mf flows/pb1/93d_restore_repeat_euro.yaml; then
      row RK-3 PASS "flows 93c + 93d: a backup ($(wc -c < "$WORK/$NAME") bytes) with a weekly repeat and a €20 spend at 1.10, restored on O1: the repeat in Me, the €20 with '= \$22.00' on Timeline"
    else
      row RK-3 FAIL "flow 93d (restore)"
    fi
  else
    row RK-3 FAIL "no backup file in cache/export while the sheet was open"
  fi
else
  row RK-3 FAIL "flow 93c"
fi

between_rows
if mf flows/pb1/93e_repeat_resume_a.yaml; then
  D8=$(date -u -d "$D0 + 8 days" +%Y-%m-%d)
  setclock "$D8" 12:00:00
  if mf flows/pb1/93f_repeat_resume_b.yaml; then
    row RK-5 PASS "flows 93e + 93f: back from the background 8 days later (no restart): 'Added from your repeats'"
  else
    row RK-5 FAIL "flow 93f (resume)"
  fi
else
  row RK-5 FAIL "flow 93e"
fi
