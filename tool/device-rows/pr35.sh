#!/usr/bin/env bash
# PR 5b (the app lock) on the CI emulator, staging debug build, zone UTC.
# Rows print PASS/FAIL/INFO with their evidence; the tester reads the log and
# looks at every screenshot that decides a row.
#   R3  flow 42: set PIN 1357; a cold start asks; a wrong PIN errs; the right one opens
#   R3b the lock again after Home + resume (Lock after: Immediately, the default)
#   R4  no FLAG_SECURE on the app's windows; LOOK at the in-app and recents shots
#   R5  flow 43: Forgot PIN with no phone screen lock: erase only, the second
#       confirm, Cancel keeps all, erase -> O1 with the lock off
#   R6  flow 44: Forgot PIN with the phone's own screen lock (PIN 1111, set here
#       and cleared in the EXIT trap): the phone's PIN, then a new Piggybow PIN
. "$(dirname "$0")/lib.sh"
guard_emulator

DEVPIN=1111   # the emulator's own screen lock, for R6 only

cleanup(){
  A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the log and the screenshots decide)"
}
trap cleanup EXIT

install_verify || exit $?
A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1   # start with no screen lock
# With a screen lock set, a screen that turns off comes back behind the keyguard
# and every flow stalls: keep the emulator's screen on for the whole run.
A shell svc power stayon true
A shell input keyevent KEYCODE_WAKEUP

# R3 The lock: a cold start asks; a wrong PIN errs; the right one opens
if mf flows/pb1/42_lock_pin.yaml; then row R3 PASS "flow 42"; else row R3 FAIL "flow 42"; fi

# R3b Resume with "Lock after: Immediately" (the default) -> the lock
A shell input keyevent KEYCODE_HOME; sleep 3
A shell monkey -p "$P" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 4
A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
if A exec-out cat /sdcard/ui.xml | grep -q 'resource-id="lock-screen"'; then row R3b PASS "lock-screen after Home + resume"; else row R3b FAIL "no lock-screen on resume"; fi
snap r3b-resume

# R4 The recents preview is hidden while the lock is on; no FLAG_SECURE
# (in-app screenshots still work). Judged by eye on the two shots.
mf flows/pb1/42_lock_pin.yaml >/dev/null 2>&1   # back to an unlocked app with the lock on
snap r4-in-app
A shell input keyevent KEYCODE_APP_SWITCH; sleep 3; snap r4-recents
A shell input keyevent KEYCODE_HOME
sec=$(A shell dumpsys window windows | tr -d '\r' | grep -A6 "$P" | grep -c 'SECURE')
if [ "$sec" = 0 ]; then row R4 PASS "no FLAG_SECURE on $P's windows; LOOK: r4-in-app shows content, r4-recents shows none"; else row R4 FAIL "FLAG_SECURE present ($sec lines)"; fi

# R5 Forgot PIN with no screen lock on the phone: erase only
if mf flows/pb1/43_forgot_pin_erase.yaml; then row R5 PASS "flow 43"; else row R5 FAIL "flow 43"; fi

# R6 Forgot PIN with the phone's own screen lock
if A shell locksettings set-pin "$DEVPIN" >/dev/null 2>&1; then
  echo "$(stamp) emulator screen lock set (PIN, CI emulator only)"
  if mf flows/pb1/44_forgot_pin_device.yaml; then row R6 PASS "flow 44"; else row R6 FAIL "flow 44"; fi
else
  row R6 FAIL "could not set the emulator's screen lock"
fi
A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1
