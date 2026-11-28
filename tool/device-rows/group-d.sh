#!/usr/bin/env bash
# The home-screen widget (#71, #72, group D), retroactively on master
# (decision 86). Kind decides the face: plus-owned (Plus on, nothing bought)
# shows the data faces; plus-rows (Plus enabled, off) shows "Part of Plus".
#   WD-1 flow 92a: Pixel Launcher's picker lists it (3×2, "Today's spending
#        and your goal"); the script drags the preview onto the home screen
#        (this launcher has no Add button); dumpsys shows it bound; flow 92b:
#        it shows the face for this build, and a tap opens the app
# The full checklist (both sizes, lock on, light/dark, midnight, reboot,
# TalkBack labels) follows once placement is proven on this image.
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
bound(){ A shell "dumpsys appwidget | grep -c 'provider=ComponentInfo{$APP_ID/'" | tr -d '\r' || true; }

if ! mf flows/pb1/92a_widget_place.yaml; then
  row WD-1 FAIL "flow 92a: the picker"; exit 1
fi
before=$(bound)
# The preview's centre on this 1080 × 2400 image (from the picker's hierarchy:
# widget_preview_container [183,887][897,1473]); a long press starts the drag
# and the launcher shows the home screen to drop on
A shell input draganddrop 540 1180 540 1000 2500
sleep 3
after=$(bound)
echo "$(stamp) widgets bound for $APP_ID: before ${before:-0}, after ${after:-0}"
if [ "${after:-0}" -le "${before:-0}" ]; then
  row WD-1 FAIL "the drag didn't bind a Piggybow widget (dumpsys appwidget: ${before:-0} → ${after:-0})"; exit 1
fi
if mf flows/pb1/92b_widget_read.yaml -e "EXPECT=$EXPECT" -e SHOT=92-opened; then
  row WD-1 PASS "flows 92a + 92b ($KIND): in the picker (3×2, 'Today's spending and your goal'); dragged to the home screen and bound; it shows '$face'; a tap opens Piggybow"
else
  row WD-1 FAIL "flow 92b ($KIND): bound, but not read or opened"; exit 1
fi

# RK-4 (the captain's risk 4): the widget with the app lock on
if mf flows/pb1/92c_widget_locked.yaml; then
  row WD-2 PASS "flow 92c: lock on → the widget shows only the pig and 'Tap to open' (no amount); its '+' (or body) shows the lock first; after the PIN, the app"
else
  row WD-2 FAIL "flow 92c (the widget with the lock on)"
fi
