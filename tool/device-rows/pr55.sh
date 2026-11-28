#!/usr/bin/env bash
# Name your pig (#55) on the CI emulator, staging debug, zone UTC: flow 72 in
# light mode, then in night mode. The rows record the flow's checks; the shots
# (the dialog, Me's row, Home with a short and a 20-character name) are for
# the look.
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  A shell cmd uimode night no >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?

for mode in light dark; do
  if [ "$mode" = dark ]; then A shell cmd uimode night yes; else A shell cmd uimode night no; fi
  sleep 3
  echo "$(stamp) uimode: $(A shell cmd uimode night | tr -d '\r')"
  if MF_NAME="72-$mode" mf flows/pb1/72_pig_name.yaml -e MODE="$mode"; then
    row "PN-$mode" PASS "flow 72 ($mode): named Mochi on Me and Home; Cancel keeps it; empty removes it; 24 pasted -> 20 kept; kept after a relaunch"
  else
    row "PN-$mode" FAIL "flow 72 ($mode)"
  fi
done
