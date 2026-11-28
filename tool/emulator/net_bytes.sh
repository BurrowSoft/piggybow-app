#!/usr/bin/env bash
# One app's own network use on the CI emulator, from netstats: the bytes its
# uid has received and sent since boot. For the evidence: with pig tips off,
# the store build sends nothing; with Plus on, what Play Billing sends. Only
# that uid's lines are kept, never another app's.
#
#   net_bytes.sh SERIAL APP_ID OUT_FILE
#
# Prints "uid <uid>: rx <bytes> tx <bytes>" (its buckets as netstats lists
# them, summed) and writes the uid's netstats lines to OUT_FILE.
# Exit 8 when the app's uid can't be read.
set -Eeuo pipefail
SERIAL=${1:?the emulator serial}
APP_ID=${2:?the app id}
OUT_FILE=${3:?the file for the uid lines}
A() { adb -s "$SERIAL" "$@"; }

uid=$(A shell cmd package list packages -U "$APP_ID" | tr -d '\r' \
  | awk -v p="package:$APP_ID" '$1 == p { sub(/^uid:/, "", $2); print $2 }')
[[ "$uid" =~ ^[0-9]+$ ]] || { echo "STOP: no uid for $APP_ID"; exit 8; }

# The counts as of now: netstats reads the kernel's first.
A shell dumpsys netstats --poll > /dev/null || true
# The uid's own entries (tag 0x0: its totals), each with its history lines.
A shell dumpsys netstats detail | tr -d '\r' \
  | awk -v uid="$uid" '
      /ident=/ { mine = index($0, " uid=" uid " ") > 0 && index($0, " tag=0x0") > 0 }
      mine' > "$OUT_FILE"
awk -v uid="$uid" '
  { for (i = 1; i <= NF; i++) {
      n = split($i, kv, "=")
      if (n == 2 && kv[1] == "rb") rx += kv[2]
      if (n == 2 && kv[1] == "tb") tx += kv[2]
  } }
  END { printf "uid %s: rx %d tx %d\n", uid, rx, tx }' "$OUT_FILE"
