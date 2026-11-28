# Piggybow device-row helpers for the CI emulator. Source from a prN.sh.
#
# - Emulator only: the guard refuses any serial that isn't an emulator, and
#   any device that doesn't report itself as one.
# - Every adb call names the device: A …  (adb -s "$SERIAL" …). Never a bare adb.
# - No server and no fixtures to delete: flows start from clearState or a
#   launch-argument fixture (test builds only).
# - Rows print "ROW <id> PASS|FAIL: <evidence>". The tester reads the log
#   and looks at every screenshot that decides a row; the exit code is not
#   the verdict.
#
# env: APK (the APK under test, built by the SAME job from HEAD_SHA:
#      public artifacts hold no installable builds, decision 31 amended),
#      HEAD_SHA (the commit built and tested; required, so every row names it),
#      WANT (an expected APK sha256; optional), OUT (log, screenshots, maestro
#      output), SERIAL (default emulator-5554), APP_ID (default
#      com.burrowsoft.piggybow.staging), FLOWS (the .maestro folder; default
#      ../../.maestro from here)
set -u
[ -n "${HEAD_SHA:-}" ] || { echo "HEAD_SHA missing: the rows must name the commit they test"; exit 2; }
SERIAL=${SERIAL:-emulator-5554}
P=${APP_ID:-com.burrowsoft.piggybow.staging}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FLOWS=${FLOWS:-$HERE/../../.maestro}
T=${RUNNER_TEMP:-/tmp}
mkdir -p "$OUT/shots" "$OUT/maestro"
exec > >(tee "$OUT/log.txt") 2>&1

A(){ adb -s "$SERIAL" "$@"; }
stamp(){ date -u +%T; }
snap(){ A exec-out screencap -p > "$OUT/shots/$1.png"; echo "$(stamp) shot $1.png"; }

PASSES=0; FAILS=0
row(){ # row <id> PASS|FAIL|INFO <evidence>   (INFO: recorded, not counted)
  echo "$(stamp) ROW $1 $2: $3"
  case "$2" in PASS) PASSES=$((PASSES + 1)) ;; INFO) ;; *) FAILS=$((FAILS + 1)) ;; esac
}

# Refuse anything that isn't an emulator (a real phone may be attached to a
# machine that runs this by mistake).
guard_emulator(){
  local q
  case "$SERIAL" in emulator-*) ;; *) echo "REFUSING: '$SERIAL' is not an emulator serial"; exit 9 ;; esac
  q=$(A shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')
  [ "$q" = 1 ] || q=$(A shell getprop ro.boot.qemu 2>/dev/null | tr -d '\r')
  [ "$q" = 1 ] || { echo "REFUSING: $SERIAL does not report an emulator"; exit 9; }
  echo "$(stamp) emulator $SERIAL, Android $(A shell getprop ro.build.version.release | tr -d '\r') (API $(A shell getprop ro.build.version.sdk | tr -d '\r'))"
}

# One Maestro flow, with its own output folder. Returns Maestro's exit code.
# Decision 45: Maestro's logs/ (the whole device logcat) stays in the evidence
# only when the flow fails; on a pass it's deleted.
mf(){ # mf <path under .maestro> [extra maestro args…]   (MF_NAME=… names the output folder when one flow runs twice)
  local f=$1; shift
  local name; name=${MF_NAME:-$(basename "$f" .yaml)}
  echo "$(stamp) flow $f"
  if maestro --device "$SERIAL" test -e APP_ID="$P" --test-output-dir "$OUT/maestro/$name" "$@" "$FLOWS/$f"; then
    find "$OUT/maestro/$name" -type d -name logs -prune -exec rm -rf {} + 2>/dev/null
    return 0
  else
    echo "$(stamp) flow $f FAILED: its logs/ are kept in the evidence"
    return 1
  fi
}

# The APK: built from HEAD_SHA in this job; its sha256 logged (and checked
# against WANT when given); then the installed base.apk byte-equal to it.
# Any mismatch stops the run before a row.
install_verify(){
  local S IS B
  [ -f "$APK" ] || { echo "APK missing: $APK"; return 2; }
  S=$(sha256sum < "$APK" | cut -c1-64)
  echo "head $HEAD_SHA | APK sha256 $S (built in this job)"
  if [ -n "${WANT:-}" ] && [ "$S" != "$WANT" ]; then echo "APK sha $S != posted $WANT: STOP"; return 8; fi
  A uninstall "$P" >/dev/null 2>&1
  echo "APK $S | install: $(A install "$APK" | tail -1)"
  B=$(A shell pm path "$P" | head -1 | cut -d: -f2 | tr -d '\r')
  A pull "$B" "$T/installed.apk" >/dev/null 2>&1
  IS=$(sha256sum < "$T/installed.apk" | cut -c1-64); rm -f "$T/installed.apk"
  if [ "$IS" = "$S" ]; then echo "INSTALLED = APK ($IS)"; else echo "INSTALLED $IS DIFFERS: STOP"; return 8; fi
}

# The app's uid.
app_uid(){ A shell dumpsys package "$P" | grep -m1 -oE 'userId=[0-9]+' | cut -d= -f2; }

# Sum of rb + tb over netstats' UID-stats buckets whose ident line names uid
# $1. Prints nothing if netstats can't be read at all, so callers fail closed.
uid_bytes(){
  A shell dumpsys netstats detail 2>/dev/null | tr -d '\r' | awk -v u="uid=$1" '
    /ident=/ { mine = (index($0, " " u " ") > 0 || $0 ~ (" " u "$")); seen = 1 }
    mine && /rb=/ { for (i = 1; i <= NF; i++) { if ($i ~ /^rb=/) s += substr($i, 4); if ($i ~ /^tb=/) s += substr($i, 4) } }
    END { if (seen) print s + 0 }'
}
# A positive control for the parser: the bytes of all uids together (the
# emulator's own services use the network). 0 or empty = the parser is blind.
all_bytes(){
  A shell dumpsys netstats detail 2>/dev/null | tr -d '\r' | awk '
    /rb=/ { for (i = 1; i <= NF; i++) { if ($i ~ /^rb=/) s += substr($i, 4); if ($i ~ /^tb=/) s += substr($i, 4) } }
    END { print s + 0 }'
}

# The app's private files, as a sorted list (debuggable builds only).
app_files(){ A shell run-as "$P" find . -type f 2>/dev/null | tr -d '\r' | sort; }
