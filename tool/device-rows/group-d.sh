#!/usr/bin/env bash
# The home-screen widget (#71, #72, group D), retroactively on master
# (decision 86). Kind decides the face: plus-owned (Plus on, nothing bought)
# shows the data faces; plus-rows (Plus enabled, off) shows "Part of Plus".
#   WD-1 flow 92a: placed from the picker; it shows the face for this build;
#        a tap opens the app
# The full checklist (both sizes, lock on, light/dark, midnight, reboot,
# TalkBack labels) follows once placement is proven on this image: see
# apps/piggybow/testing (plan-72) and flows 92b+.
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?

case "$KIND" in
  plus-owned) EXPECT="(?s).*Spent today.*" ; face="Spent today" ;;
  *)          EXPECT="(?s).*Part of Plus.*" ; face="Part of Plus" ;;
esac

if mf flows/pb1/92a_widget_place.yaml -e "EXPECT=$EXPECT" -e SHOT=92-opened; then
  row WD-1 PASS "flow 92a ($KIND): placed from Pixel Launcher's picker; it shows '$face'; a tap opens Piggybow"
else
  row WD-1 FAIL "flow 92a ($KIND)"
fi
