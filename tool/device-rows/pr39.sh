#!/usr/bin/env bash
# PR 5c (the phone's own backup, encrypted only) on the CI emulator, staging
# debug build (run-as reads the app's files), zone UTC. Rows print
# PASS/FAIL/INFO with their evidence; the tester reads the log and looks at
# every screenshot that decides a row.
#
# The CI emulator has no Google account, so bmgr uses AOSP's local transport.
# That transport doesn't look at the screen lock itself: it reports
# client-side encryption only when its test switch fake_encryption_flag=true
# is set (Settings.Secure backup_local_transport_parameters). So:
#   R9n  no screen lock, the switch off -> nothing of Piggybow is backed up
#        (cloud-backup disableIfNoEncryptionCapabilities="true")
#   R9e  a screen lock and the switch on -> the journal and the settings come
#        back; the PIN, caches and exports don't; the lock is off with
#        "Off after a restore. Turn it on again." until the row is opened
# If bmgr or the transport behaves differently on this image, the rows say
# what they saw; the verdict comes from the app's files and flows 46b/46c.
. "$(dirname "$0")/lib.sh"
guard_emulator

DEVPIN=1111                             # the emulator's own screen lock, for R9e only
LTP=backup_local_transport_parameters   # the local transport's test switches

cleanup(){
  A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1
  A shell settings delete secure "$LTP" >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the log and the screenshots decide)"
}
trap cleanup EXIT

install_verify || exit $?
A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1   # start with no screen lock
# With a screen lock set, a screen that turns off comes back behind the keyguard
# and every flow stalls: keep the emulator's screen on for the whole run.
A shell svc power stayon true
A shell input keyevent KEYCODE_WAKEUP

# One round: 46a seeds, backupnow, reinstall, restore. Sets BK for the caller.
backup_round(){ # backup_round <label>
  local lab=$1 set
  if mf flows/pb1/46a_backup_seed.yaml; then row "$lab-seed" PASS "flow 46a (a spend, the reminder, a goal, the lock, one export)"; else row "$lab-seed" FAIL "flow 46a"; return 1; fi
  app_files > "$OUT/$lab-files-before.txt"; echo "files before: $(wc -l < "$OUT/$lab-files-before.txt")"; cat "$OUT/$lab-files-before.txt"
  BK=$(A shell bmgr backupnow "$P" | tr -d '\r'); echo "$BK"
  set=$(A shell bmgr list sets | tr -d '\r' | awk 'NF { print $1; exit }'); echo "restore set: ${set:-none}"
  A uninstall "$P" >/dev/null; echo "reinstall: $(A install "$APK" | tail -1)"   # auto-restore may run here
  if [ -n "$set" ]; then A shell bmgr restore "$set" "$P" | tr -d '\r'; fi
  app_files > "$OUT/$lab-files-after.txt"; echo "files after: $(wc -l < "$OUT/$lab-files-after.txt")"; cat "$OUT/$lab-files-after.txt"
}

A shell bmgr enable true >/dev/null
A shell bmgr transport com.android.localtransport/.LocalTransport
echo "transports: $(A shell bmgr list transports | tr -d '\r' | tr '\n' ' ')"

# R9n No encryption: nothing is backed up
A shell settings delete secure "$LTP" >/dev/null 2>&1
A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1
if backup_round r9n; then
  row R9n-bmgr INFO "backupnow said: $(echo "$BK" | grep -m1 -E "$P|Backup" || echo '(nothing about the package)')"
  if grep -qiE 'journal\.db|FlutterSharedPreferences\.xml' "$OUT/r9n-files-after.txt"; then
    row R9n FAIL "app data came back without encryption (see r9n-files-after.txt)"
  else
    row R9n PASS "no journal.db or FlutterSharedPreferences.xml after the restore"
  fi
  if mf flows/pb1/46c_no_backup_without_encryption.yaml; then row R9n-app PASS "flow 46c (O1, a blank journal)"; else row R9n-app FAIL "flow 46c"; fi
fi
A shell bmgr wipe com.android.localtransport/.LocalTransport "$P" >/dev/null 2>&1   # a clean slate for R9e

# R9e Encrypted: a phone screen lock, and the transport reporting client-side encryption
if ! A shell locksettings set-pin "$DEVPIN" >/dev/null 2>&1; then row R9e FAIL "could not set the emulator's screen lock"; else
  A shell settings put secure "$LTP" fake_encryption_flag=true
  echo "transport parameters: $(A shell settings get secure "$LTP" | tr -d '\r')"
  if backup_round r9e; then
    if echo "$BK" | grep -qi 'Success'; then row R9e-bmgr PASS "backupnow: Success"; else row R9e-bmgr FAIL "backupnow: $(echo "$BK" | tail -1)"; fi
    if grep -q 'journal\.db' "$OUT/r9e-files-after.txt"; then row R9e-journal PASS "journal.db came back"; else row R9e-journal FAIL "no journal.db after the restore"; fi
    if grep -qi 'FlutterSecureStorage' "$OUT/r9e-files-after.txt"; then row R9e-pin FAIL "secure storage (the PIN) came back"; else row R9e-pin PASS "no secure-storage file after the restore"; fi
    if grep -qE 'piggybow-[0-9]{4}-[0-9]{2}-[0-9]{2}\.csv' "$OUT/r9e-files-after.txt"; then row R9e-export FAIL "an export file came back"; else row R9e-export PASS "no export file after the restore"; fi
    if grep -qiE '/cache/' "$OUT/r9e-files-after.txt"; then row R9e-cache FAIL "cache files came back (see r9e-files-after.txt)"; else row R9e-cache PASS "no cache files after the restore"; fi
    if mf flows/pb1/46b_after_restore.yaml; then row R9e-app PASS "flow 46b (data back, no lock prompt, 'Off after a restore' until opened)"; else row R9e-app FAIL "flow 46b"; fi
    n=$(A shell dumpsys alarm | tr -d '\r' | grep -c "$P")
    row R9e-reminder INFO "$n alarm lines for $P after the first start (LOOK: 46b-me-reminder-after-restore: the switch on, or 'Notifications are off', since a reinstall drops the permission)"
  fi
fi
A shell settings delete secure "$LTP" >/dev/null 2>&1
A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1
