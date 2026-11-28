#!/usr/bin/env bash
# Pig tips (A2 client + A3 screens) on the CI emulator, kind=tips-mock (AI
# tips on; TIPS_TEST_URL=http://10.0.2.2:8787, this runner's mock), zone UTC,
# the device clock moved by root for the one-call-a-day rows.
#   TI-1 consent first: nothing leaves before "Yes"; "Not now" sends nothing
#   TI-6 "Written by AI" and Report on a written tip only
#   TI-4 Report: one report with the tip, model and sig served; the built-in
#        tip for the rest of the day, also after a restart
#   TI-7 one tip call a day: a restart and off → on add none
#   TI-2 off calls forget (the old id is gone); on signs up a new id
#   TI-3 the next days, the mock timing out / 429 / 503 / 204 / no sig / no
#        model: the built-in tip, one call a day each
# Every pig-tip body is checked against the contract by the mock; any
# INVALID line in its log fails the run.
. "$(dirname "$0")/lib.sh"
guard_emulator

LOG="$OUT/tips-mock.jsonl"
CTL=http://127.0.0.1:8787
python3 "$HERE/tips_mock.py" 8787 "$LOG" "$HERE/pig-tip-request.json" &
MOCK=$!
setclock(){ local d=$1 t=$2
  A shell date -u "${d:5:2}${d:8:2}${t:0:2}${t:3:2}${d:0:4}.${t:6:2}" >/dev/null
  echo "$(stamp) device clock: $(A shell date -u | tr -d '\r')"
}
cleanup(){
  kill "$MOCK" 2>/dev/null
  A shell settings put global auto_time 1 >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT
mode(){ curl -fsS -X POST "$CTL/__mock/mode?m=$1" >/dev/null; }
count(){ # count <path>: requests to that path so far
  jq -s --arg p "$1" '[.[] | select(.path == $p)] | length' "$LOG"
}
ids(){ jq -s -r '[.[] | select(.path == "/auth/v1/signup") | .id] | unique | length' "$LOG"; }
invalid(){ jq -s '[.[] | select(has("INVALID"))] | length' "$LOG"; }
TIPCALL=/functions/v1/pig-tip

for i in $(seq 1 20); do curl -fsS "$CTL/__mock/log" >/dev/null 2>&1 && break; sleep 0.5; done
A root >/dev/null 2>&1 || { sleep 3; A wait-for-device; A root >/dev/null 2>&1; }
sleep 3; A wait-for-device
A shell settings put global auto_time 0
install_verify || exit $?
D0=$(date -u +%Y-%m-%d); setclock "$D0" 12:00:00
mode tip

# TI-1: nothing leaves before Yes
if mf flows/pb1/94a_tips_consent.yaml && [ "$(count /auth/v1/signup)" = 0 ] && [ "$(count $TIPCALL)" = 0 ]; then
  row TI-1a PASS "flow 94a: the built-in tip first; Your privacy names pig tips; the switch asks first; 'Not now' leaves it off; the mock heard nothing"
else
  row TI-1a FAIL "flow 94a, or the mock heard something before Yes (signup $(count /auth/v1/signup), tip $(count $TIPCALL))"
fi
if mf flows/pb1/94b_tips_yes.yaml -e "TIP=Try one no-spend day" && [ "$(count /auth/v1/signup)" = 1 ] && [ "$(count $TIPCALL)" = 1 ] && [ "$(invalid)" = 0 ]; then
  row TI-1b PASS "flow 94b: Yes → on; one signup, one tip call with a contract-valid body; Home shows the written tip with 'Written by AI' and Report (TI-6)"
else
  row TI-1b FAIL "flow 94b (signup $(count /auth/v1/signup), tip $(count $TIPCALL), invalid $(invalid))"
fi

# TI-4 and TI-7: report, then a restart the same day
before=$(count $TIPCALL)
if mf flows/pb1/94c_tips_report.yaml && [ "$(jq -s '[.[] | select(.path == "/functions/v1/pig-tip/report" and .code == 204)] | length' "$LOG")" = 1 ] && [ "$(count $TIPCALL)" = "$before" ]; then
  row TI-4 PASS "flow 94c: Report → Not helpful → thanks; one report accepted (the tip, model and sig served); the built-in tip after it, also after a restart, with no new tip call (TI-7)"
else
  row TI-4 FAIL "flow 94c (reports $(count /functions/v1/pig-tip/report), tip calls $before → $(count $TIPCALL))"
fi

# TI-2: off then on, the same day
before=$(count $TIPCALL)
if mf flows/pb1/94d_tips_off_on.yaml && [ "$(jq -s '[.[] | select(.path == "/functions/v1/pig-tip/forget" and .code == 204)] | length' "$LOG")" = 1 ] && [ "$(ids)" = 2 ]; then
  row TI-2 PASS "flow 94d: off at once (forget accepted); on asks again and signs up a NEW id"
else
  row TI-2 FAIL "flow 94d (forget $(count /functions/v1/pig-tip/forget), distinct ids $(ids))"
fi
# Off → on the same day: at most one written tip per phone per local day,
# whatever the toggles (UX's triage of F-TI-1), so the new id makes no tip call.
if [ "$(count $TIPCALL)" = "$before" ]; then
  row TI-7b PASS "off → on the same day: no new tip call ($before → $(count $TIPCALL)); one written tip per phone per day"
else
  row TI-7b FAIL "off → on the same day: tip calls $before → $(count $TIPCALL), expected none (F-TI-1)"
fi

# TI-3: the next days, each answer that means "no tip"
n=1; ok=0
for m in timeout cap 503 none nosig nomodel; do
  setclock "$(date -u -d "$D0 + $n days" +%Y-%m-%d)" 12:00:00; n=$((n+1))
  mode "$m"; before=$(count $TIPCALL)
  wait=3000; [ "$m" = timeout ] && wait=20000
  if MF_NAME=94e-$m mf flows/pb1/94e_tips_static_today.yaml -e MODE=$m -e WAIT=$wait && [ "$(count $TIPCALL)" = $((before+1)) ]; then
    ok=$((ok+1)); echo "$(stamp) INFO TI-3 $m: the built-in tip; one tip call that day"
  else
    echo "$(stamp) INFO TI-3 $m: FAILED (tip calls $before → $(count $TIPCALL))"
  fi
done
if [ "$ok" = 6 ] && [ "$(invalid)" = 0 ]; then
  row TI-3 PASS "flow 94e on six days: timeout, 429, 503, 204, a 200 without sig, a 200 without x-tip-model → the built-in tip, no spinner left, exactly one tip call each day; every body contract-valid"
else
  row TI-3 FAIL "flow 94e: $ok of 6 days right; invalid bodies $(invalid)"
fi
echo "$(stamp) the mock's log: $(wc -l < "$LOG") requests (kept as evidence: tips-mock.jsonl)"
