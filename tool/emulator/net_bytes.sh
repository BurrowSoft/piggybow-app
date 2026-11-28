#!/usr/bin/env bash
# One app's own network use on the CI emulator, from netstats: the bytes its
# uid has received and sent since boot. For the evidence: with pig tips off,
# the store build sends nothing; with Plus on, what Play Billing sends. Only
# that uid's lines are kept, never another app's.
#
#   net_bytes.sh SERIAL APP_ID OUT_FILE [CONTROL_UID]
#
# Prints "netstats entries: <n>" (every entry in the dump, counted only);
# with CONTROL_UID, "control uid <uid>: rx <bytes> tx <bytes>" (a uid the
# caller has just made talk, net_control.sh); then the app's "uid <uid>: rx
# <bytes> tx <bytes>" (its buckets as netstats lists them, summed), the only
# line that starts with "uid ". Writes the app uid's netstats lines to
# OUT_FILE. The dump itself is read once and never kept.
# Exit 8 when the app's uid can't be read, when netstats printed no entries
# at all, or when the control uid shows no bytes: a reading that couldn't
# see traffic is never zero bytes.
set -Eeuo pipefail
SERIAL=${1:?the emulator serial}
APP_ID=${2:?the app id}
OUT_FILE=${3:?the file for the uid lines}
CONTROL_UID=${4:-}
A() { adb -s "$SERIAL" "$@"; }
stop() { rm -f "$OUT_FILE"; echo "STOP: $1"; exit 8; }

[[ -z "$CONTROL_UID" || "$CONTROL_UID" =~ ^[0-9]+$ ]] || stop "the control uid isn't a number: $CONTROL_UID"
uid=$(A shell cmd package list packages -U "$APP_ID" | tr -d '\r' \
  | awk -v p="package:$APP_ID" '$1 == p { sub(/^uid:/, "", $2); print $2 }')
[[ "$uid" =~ ^[0-9]+$ ]] || stop "no uid for $APP_ID"

# The counts as of now: netstats reads the kernel's first.
A shell dumpsys netstats --poll > /dev/null || true
# One pass over the dump: every entry counted (the count only, nothing else
# of another app's); the control uid's totals (tag 0x0) summed; the app's
# own entries (tag 0x0: its totals), each with its history lines, kept.
: > "$OUT_FILE"
counts=$(A shell dumpsys netstats detail | tr -d '\r' \
  | awk -v uid="$uid" -v control="$CONTROL_UID" -v out="$OUT_FILE" '
      /ident=/ {
        entries++
        mine = index($0, " uid=" uid " ") > 0 && index($0, " tag=0x0") > 0
        ctl = control != "" && index($0, " uid=" control " ") > 0 && index($0, " tag=0x0") > 0
      }
      mine { print > out }
      ctl {
        for (i = 1; i <= NF; i++) {
          n = split($i, kv, "=")
          if (n == 2 && kv[1] == "rb") crx += kv[2]
          if (n == 2 && kv[1] == "tb") ctx += kv[2]
        }
      }
      END { printf "%d %d %d\n", entries, crx, ctx }')
read -r entries crx ctx <<< "$counts"
echo "netstats entries: $entries"
[ "$entries" -gt 0 ] || stop "netstats printed no entries"
if [ -n "$CONTROL_UID" ]; then
  echo "control uid $CONTROL_UID: rx $crx tx $ctx"
  [ "$crx" -gt 0 ] && [ "$ctx" -gt 0 ] || stop "the control uid $CONTROL_UID shows no bytes"
fi
awk -v uid="$uid" '
  { for (i = 1; i <= NF; i++) {
      n = split($i, kv, "=")
      if (n == 2 && kv[1] == "rb") rx += kv[2]
      if (n == 2 && kv[1] == "tb") tx += kv[2]
  } }
  END { printf "uid %s: rx %d tx %d\n", uid, rx, tx }' "$OUT_FILE"
