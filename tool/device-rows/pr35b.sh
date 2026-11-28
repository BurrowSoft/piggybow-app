#!/usr/bin/env bash
# PR 5b, R6 alone, repeated after pr35.sh: Forgot PIN with the phone's own
# screen lock (PIN 1111, set here and cleared in the EXIT trap) -> the
# system's credential prompt -> a new Piggybow PIN; the old one is refused.
# Staging debug, zone UTC; the screen stays on for the whole run.
. "$(dirname "$0")/lib.sh"
guard_emulator

DEVPIN=1111

cleanup(){
  A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the log and the screenshots decide)"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1
A shell svc power stayon true
A shell input keyevent KEYCODE_WAKEUP

if A shell locksettings set-pin "$DEVPIN" >/dev/null 2>&1; then
  echo "$(stamp) emulator screen lock set (PIN, CI emulator only)"
  if mf flows/pb1/44_forgot_pin_device.yaml; then row R6 PASS "flow 44"; else row R6 FAIL "flow 44"; fi
else
  row R6 FAIL "could not set the emulator's screen lock"
fi
A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1
