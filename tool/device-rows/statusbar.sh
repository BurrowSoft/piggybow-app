#!/usr/bin/env bash
# System-bar shots on the CI emulator, for PB UX & PM's look: the top and the
# bottom of O1, Home, the goal celebration (flow 50), and of the end of O1's
# currency list, the Add sheet, a Me sub-page and the end of a goal's page
# (flow 51). Each in light and night mode, with gesture navigation and then
# with the 3-button bar. The rows record that the shots were taken; the
# verdict is the look: no black or grey strip behind the navigation bar,
# nothing to read or tap under it, its icons readable, the status bar as before.
# Run by tool/emulator/run.sh with rows=statusbar (it exports APK, HEAD_SHA,
# OUT, SERIAL, APP_ID, KIND and FLOWS).
. "$(dirname "$0")/lib.sh"
guard_emulator

GESTURE=com.android.internal.systemui.navbar.gestural
BUTTONS=com.android.internal.systemui.navbar.threebutton

navmode(){ # navmode gesture|buttons
  local pkg=$GESTURE
  [ "$1" = buttons ] && pkg=$BUTTONS
  A shell cmd overlay enable-exclusive --category "$pkg" >/dev/null 2>&1
  sleep 4
  echo "$(stamp) navigation $1: $(A shell cmd overlay list | tr -d '\r' | grep -E 'navbar\.(gestural|threebutton)$' | tr -s ' ' | tr '\n' ' ')"
}

cleanup(){
  A shell cmd uimode night no >/dev/null 2>&1
  navmode gesture >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the shots decide)"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?

for nav in gesture buttons; do
  navmode "$nav"
  for mode in light dark; do
    if [ "$mode" = dark ]; then A shell cmd uimode night yes; else A shell cmd uimode night no; fi
    sleep 3
    echo "$(stamp) uimode: $(A shell cmd uimode night | tr -d '\r')"
    if MF_NAME="50-$nav-$mode" mf flows/pb1/50_status_bar_shots.yaml -e MODE="$mode" -e NAV="$nav"; then
      row "SB-$nav-$mode" PASS "shots 50-{o1,home,celebration}-$nav-$mode taken"
    else
      row "SB-$nav-$mode" FAIL "flow 50 ($nav, $mode)"
    fi
    if MF_NAME="51-$nav-$mode" mf flows/pb1/51_system_bars_more.yaml -e MODE="$mode" -e NAV="$nav"; then
      row "NB-$nav-$mode" PASS "shots 51-{currency-end,add,add-end,me-happy,goal-end}-$nav-$mode taken"
    else
      row "NB-$nav-$mode" FAIL "flow 51 ($nav, $mode)"
    fi
  done
done
