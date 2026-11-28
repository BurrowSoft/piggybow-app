#!/usr/bin/env bash
# PR 5a (the daily reminder) on the CI emulator, staging debug build, zone UTC.
# Rows print PASS/FAIL/INFO with their evidence; the tester reads the log and
# looks at every screenshot that decides a row.
#   R0  flow 39: No thanks hides the offer for good, asks nothing, reminder off
#   R2  flow 41: Don't allow -> "Notifications are off" + Open settings
#   R1  flow 40: Yes + Allow -> on at 8:00 PM
#   R1b the scheduled reminders (the plugin's own list, read with run-as on a
#       debug build) + dumpsys alarm: today's dropped after today's entry, one
#       per day from tomorrow at 20:00, title Piggybow, a new body each day
#   RS  (optional) a reminder a few minutes from now through Me's time picker:
#       posted, a shade shot, and a tap opens the Add sheet
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  A shell cmd statusbar collapse >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the log and the screenshots decide)"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
echo "$(stamp) device time: $(A shell date -u '+%Y-%m-%d %H:%M:%S UTC' | tr -d '\r'), zone $(A shell getprop persist.sys.timezone | tr -d '\r')"

# The plugin's scheduled list (flutter_local_notifications keeps it in its
# shared prefs). Prints the raw XML; empty if it can't be read.
sched_xml(){ A shell run-as "$P" cat shared_prefs/scheduled_notifications.xml 2>/dev/null | tr -d '\r'; }

if mf flows/pb1/39_reminder_offer_no_thanks.yaml; then row R0 PASS "flow 39"; else row R0 FAIL "flow 39"; fi
if mf flows/pb1/41_reminder_offer_deny.yaml; then row R2 PASS "flow 41"; else row R2 FAIL "flow 41"; fi

if mf flows/pb1/40_reminder_offer_allow.yaml; then row R1 PASS "flow 40"; else row R1 FAIL "flow 40"; fi
x=$(sched_xml); printf '%s\n' "$x" > "$OUT/r1b-scheduled.xml"
j=$(printf '%s' "$x" | sed 's/&quot;/"/g; s/&amp;/\&/g; s/&#10;/ /g')
n=$(printf '%s' "$j" | grep -oE '"scheduledDateTime":"[^"]*"' | wc -l)
first=$(printf '%s' "$j" | grep -oE '"scheduledDateTime":"[^"]*"' | head -1 | cut -d'"' -f4)
today=$(A shell date -u +%Y-%m-%d | tr -d '\r'); tomorrow=$(date -u -d "$today + 1 day" +%Y-%m-%d)
titles=$(printf '%s' "$j" | grep -oE '"title":"[^"]*"' | cut -d'"' -f4 | sort -u | tr '\n' '|')
printf '%s' "$j" | grep -oE '"body":"[^"]*"' | cut -d'"' -f4 > "$T/bodies.txt"
same_adjacent=$(awk 'NR > 1 && $0 == prev { c++ } { prev = $0 } END { print c + 0 }' "$T/bodies.txt")
distinct=$(sort -u "$T/bodies.txt" | wc -l)
echo "scheduled: $n | first $first | titles $titles | distinct bodies $distinct | adjacent repeats $same_adjacent"
if [ "$n" = 0 ]; then
  row R1b FAIL "no scheduled reminder could be read (see r1b-scheduled.xml)"
else
  [ "$n" = 29 ] && row R1b-count PASS "29 scheduled: 30 days minus today, which has an entry" || row R1b-count FAIL "$n scheduled (expected 29: today dropped after today's entry)"
  case "$first" in "$tomorrow"T20:00*) row R1b-first PASS "first at $first (tomorrow 20:00)" ;; *) row R1b-first FAIL "first at '$first' (expected ${tomorrow}T20:00)" ;; esac
  [ "$titles" = "Piggybow|" ] && row R1b-title PASS "every title 'Piggybow'" || row R1b-title FAIL "titles: $titles"
  if [ "$distinct" -ge 2 ] && [ "$same_adjacent" = 0 ]; then row R1b-words PASS "$distinct distinct bodies; no two days in a row alike"; else row R1b-words FAIL "$distinct distinct bodies, $same_adjacent adjacent repeats"; fi
  if grep -q '[0-9]' "$T/bodies.txt"; then row R1b-digits FAIL "a body has a digit"; else row R1b-digits PASS "no digit in any body"; fi
fi
na=$(A shell dumpsys alarm | tr -d '\r' | grep -c "$P")
row R1b-alarm INFO "dumpsys alarm: $na lines for $P"

# RS (optional): a reminder ~3 minutes from now, posted, shot, tapped
now=$(A shell date -u +%s | tr -d '\r'); at=$((now + 180))
H24=$(date -u -d "@$at" +%-H); MM=$(date -u -d "@$at" +%M)
if [ "$H24" -ge 12 ]; then AMPM=PM; else AMPM=AM; fi
H12=$(( H24 % 12 )); [ "$H12" = 0 ] && H12=12
echo "$(stamp) reminder-soon at $(date -u -d "@$at" +%H:%M) UTC ($H12:$MM $AMPM)"
if mf flows/pb1/48_reminder_soon.yaml -e HH="$H12" -e MM="$MM" -e AMPM="$AMPM"; then
  got=""
  for i in $(seq 1 60); do   # up to 5 minutes (an inexact alarm may run a little late)
    A shell dumpsys notification --noredact | tr -d '\r' > "$T/notif.txt"
    if grep -q "pkg=$P" "$T/notif.txt"; then got=1; break; fi
    sleep 5
  done
  if [ -z "$got" ]; then
    row RS FAIL "no notification from $P within 5 minutes of $(date -u -d "@$at" +%H:%M) UTC"
  else
    title=$(grep -A60 "pkg=$P" "$T/notif.txt" | grep -m1 -oE 'android\.title=String \(.*\)' | sed -E 's/.*\((.*)\)/\1/')
    text=$(grep -A60 "pkg=$P" "$T/notif.txt" | grep -m1 -oE 'android\.text=String \(.*\)' | sed -E 's/.*\((.*)\)/\1/')
    row RS PASS "posted at $(A shell date -u +%H:%M:%S | tr -d '\r') UTC: title '$title', body '$text'"
    A shell cmd statusbar expand-notifications; sleep 2; snap rs-shade
    if mf flows/pb1/49_reminder_tap_opens_add.yaml; then row RS-tap PASS "flow 49: the tap opened the Add sheet"; else row RS-tap FAIL "flow 49"; fi
    A shell cmd statusbar collapse >/dev/null 2>&1
  fi
else
  row RS INFO "flow 48 (setting the time through the picker) did not finish: no shade shot this run"
fi
