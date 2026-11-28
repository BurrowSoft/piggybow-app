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
# Widgets bound to Piggybow's provider. Android 14 prints a bound widget's
# provider as "provider=ProviderId{user:0, app:<uid>, cname:ComponentInfo{<pkg>/…}}"
# (the first version of this row grepped "provider=ComponentInfo{" and read 0
# with the widget on screen). The control: the dump lists Piggybow's provider
# from the install on, bound or not, so a dump that doesn't name its
# component at all can't be read as 0 (STOP).
# Each reading keeps the dump's lines that name the app, as evidence.
bound(){ # bound <label>: the count on stdout; the lines in $OUT/wd-appwidget-<label>.txt
  local d n
  d=$(A shell dumpsys appwidget | tr -d '\r')
  printf '%s\n' "$d" | grep -n "ComponentInfo{$APP_ID/" > "$OUT/wd-appwidget-$1.txt" || true
  if ! printf '%s\n' "$d" | grep -q "ComponentInfo{$APP_ID/"; then
    echo "$(stamp) STOP: dumpsys appwidget doesn't list Piggybow's provider ($1); the count can't be read" >&2
    echo STOP; return
  fi
  n=$(printf '%s\n' "$d" | grep -c "provider=.*ComponentInfo{$APP_ID/" || true)
  echo "${n:-0}"
}
stop_if(){ [ "$1" != STOP ] || { row WD-1 FAIL "the widget count couldn't be read: dumpsys appwidget doesn't list Piggybow's provider ($2)"; exit 1; }; }

if ! mf flows/pb1/92a_widget_place.yaml; then
  row WD-1 FAIL "flow 92a: the picker"; exit 1
fi
before=$(bound before); stop_if "$before" before
# The preview's centre on this 1080 × 2400 image (from the picker's hierarchy:
# widget_preview_container [183,887][897,1473]); a long press starts the drag
# and the launcher shows the home screen to drop on. Two ways, a shot after
# each: input draganddrop (one call), then, if nothing bound, the picker again
# and a long press held 1.5 s by motionevents, a slow move up, and the drop.
shot(){ A exec-out screencap -p > "$OUT/$1.png" 2>/dev/null || true; }
drag_motion(){
  A shell input motionevent DOWN 540 1180
  sleep 1.5
  for y in 1150 1100 1050 1000 950 900; do A shell input motionevent MOVE 540 "$y"; sleep 0.15; done
  sleep 1
  A shell input motionevent UP 540 900
}
how="input draganddrop"
A shell input draganddrop 540 1180 540 1000 2500
sleep 3
shot wd-after-drag-1
after=$(bound after-drag-1); stop_if "$after" after-drag-1
echo "$(stamp) widgets bound for $APP_ID after the drag: before $before, after $after"
if [ "$after" -le "$before" ]; then
  A shell input keyevent KEYCODE_HOME; sleep 2
  if MF_NAME=92a-again mf flows/pb1/92a_widget_place.yaml; then
    how="a held long press (motionevents)"
    drag_motion
    sleep 3
    shot wd-after-drag-2
    after=$(bound after-drag-2); stop_if "$after" after-drag-2
    echo "$(stamp) widgets bound for $APP_ID after the held long press: before $before, after $after"
  fi
fi
if [ "$after" -le "$before" ]; then
  row WD-1 FAIL "neither drag bound a Piggybow widget (dumpsys appwidget: $before → $after; shots wd-after-drag-1, -2)"; exit 1
fi
# The launcher keeps a dropped widget in its resize frame; Back closes the
# frame, so 92b's tap reaches the widget itself
A shell input keyevent KEYCODE_BACK; sleep 2
shot wd-placed
if mf flows/pb1/92b_widget_read.yaml -e "EXPECT=$EXPECT" -e SHOT=92-opened; then
  row WD-1 PASS "flows 92a + 92b ($KIND): in the picker (3×2, 'Today's spending and your goal'); placed by $how and bound; it shows '$face'; a tap opens Piggybow"
else
  row WD-1 FAIL "flow 92b ($KIND): bound, but not read or opened"; exit 1
fi

# RK-4 (the captain's risk 4): the widget with the app lock on
if mf flows/pb1/92c_widget_locked.yaml; then
  row WD-2 PASS "flow 92c: lock on → the widget shows only the pig and 'Tap to open' (no amount); its '+' (or body) shows the lock first; after the PIN, the app"
else
  row WD-2 FAIL "flow 92c (the widget with the lock on)"
fi
