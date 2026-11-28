#!/usr/bin/env bash
# PR 5c, a diagnostic after pr39.sh: why the local transport rejected the
# app's backup ("Transport rejected package") even with its encryption switch.
#   R9e-diag  the encrypted round again (PIN + fake_encryption_flag=true), with
#             the backup service's own logcat lines kept for the exact reason
#   R9t       a device-to-device round (is_device_transfer=true): #39's
#             <device-transfer> section includes the same two files with no
#             encryption requirement. journal.db back -> the include paths are
#             right (the encrypted round's refusal is the test transport's);
#             still nothing -> the app's rules select nothing.
# Staging debug (run-as reads the app's files), zone UTC.
. "$(dirname "$0")/lib.sh"
guard_emulator

DEVPIN=1111
LTP=backup_local_transport_parameters

cleanup(){
  A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1
  A shell settings delete secure "$LTP" >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the log decides)"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1
A shell svc power stayon true
A shell input keyevent KEYCODE_WAKEUP
A shell bmgr enable true >/dev/null
A shell bmgr transport com.android.localtransport/.LocalTransport

# One round with the backup service's logcat kept: seed, backupnow, reinstall, restore.
diag_round(){ # diag_round <label>
  local lab=$1 set
  if mf flows/pb1/46a_backup_seed.yaml; then row "$lab-seed" PASS "flow 46a"; else row "$lab-seed" FAIL "flow 46a"; return 1; fi
  echo "stopped flag: $(A shell dumpsys package "$P" | tr -d '\r' | grep -m1 -oE 'stopped=(true|false)')"
  echo "transport parameters: $(A shell settings get secure "$LTP" | tr -d '\r')"
  A logcat -c
  BK=$(A shell bmgr backupnow "$P" | tr -d '\r'); echo "$BK"
  PK=$(echo "$BK" | grep -m1 "Package $P with result:" | sed 's/.*result: //')
  echo "the app's backup result: ${PK:-none}"
  A logcat -d | tr -d '\r' | grep -iE 'BackupManagerService|PFTBT|FullBackup|LocalTransport|BackupEligibility|KeyValueBackup|BackupAgent|piggybow' > "$OUT/$lab-backup-logcat.txt"
  echo "backup logcat ($(wc -l < "$OUT/$lab-backup-logcat.txt") lines):"; grep -iE 'piggybow|size|quota|reject|skip|encrypt|eligib|transfer|flag' "$OUT/$lab-backup-logcat.txt" | head -40
  set=$(A shell bmgr list sets | tr -d '\r' | awk 'NF { print $1; exit }'); echo "restore set: ${set:-none}"
  A uninstall "$P" >/dev/null; echo "reinstall: $(A install "$APK" | tail -1)"
  if [ -n "$set" ]; then A shell bmgr restore "$set" "$P" | tr -d '\r'; fi
  app_files > "$OUT/$lab-files-after.txt"; echo "files after: $(wc -l < "$OUT/$lab-files-after.txt")"; cat "$OUT/$lab-files-after.txt"
}

# R9e-diag: the encrypted round again, with the reason
A shell locksettings set-pin "$DEVPIN" >/dev/null 2>&1 && echo "screen lock set"
A shell settings put secure "$LTP" fake_encryption_flag=true
if diag_round r9e-diag; then
  row R9e-diag INFO "the app's result with the encryption switch: ${PK:-none} (reason lines in r9e-diag-backup-logcat.txt)"
  if grep -q 'journal\.db' "$OUT/r9e-diag-files-after.txt"; then row R9e-diag-journal PASS "journal.db came back"; else row R9e-diag-journal INFO "no journal.db after the restore"; fi
fi
A shell bmgr wipe com.android.localtransport/.LocalTransport "$P" >/dev/null 2>&1
A shell locksettings clear --old "$DEVPIN" >/dev/null 2>&1

# R9t: a device-to-device transfer, where #39 asks for no encryption
A shell settings put secure "$LTP" is_device_transfer=true
if diag_round r9t; then
  if [ "$PK" = Success ] && grep -q 'journal\.db' "$OUT/r9t-files-after.txt"; then
    row R9t PASS "device transfer: the app backed up and journal.db came back, so the include paths select the journal"
    if grep -q 'FlutterSharedPreferences\.xml' "$OUT/r9t-files-after.txt"; then row R9t-prefs PASS "FlutterSharedPreferences.xml came back"; else row R9t-prefs FAIL "no FlutterSharedPreferences.xml after the transfer"; fi
    if grep -qi 'FlutterSecureStorage' "$OUT/r9t-files-after.txt"; then row R9t-pin FAIL "secure storage (the PIN) came back"; else row R9t-pin PASS "no secure-storage file after the transfer"; fi
    if grep -qE 'piggybow-[0-9]{4}-[0-9]{2}-[0-9]{2}\.csv|/cache/' "$OUT/r9t-files-after.txt"; then row R9t-cache FAIL "an export or cache file came back"; else row R9t-cache PASS "no export or cache file after the transfer"; fi
  else
    row R9t FAIL "device transfer: the app's result ${PK:-none}; journal.db back: $(grep -c 'journal\.db' "$OUT/r9t-files-after.txt")"
  fi
fi
A shell settings delete secure "$LTP" >/dev/null 2>&1
