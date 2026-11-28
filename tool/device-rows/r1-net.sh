#!/usr/bin/env bash
# R1's gate (#95, the Reviewer's ruling): the store build (kind=prod-release:
# Plus off, pig tips off) sends NOTHING. The app's own network bytes, read by
# ci/tool/emulator/net_bytes.sh (that uid's netstats lines only), before and
# after a session that touches every screen: expected rx 0 and tx 0 both
# times. Dispatch with --ref feat/tips-in-release (net_bytes.sh lives there).
#   R1-1 flow 95a: cold start, a spend and a save, Timeline, Summary, Me, an
#        export to the share sheet and back, background and resume
#   R1-2 the bytes: 0 before, 0 after (a minute's wait for anything deferred)
# The positive control (the Reviewer's terms), before each reading: the
# device's shell (uid 2000) fetches a small file from a listener on this
# runner (10.0.2.2 is the runner's 127.0.0.1), so a known uid has just
# talked. The run stops (a failed run, never zero) when the dump has no
# entries at all, when the fetch didn't arrive, when uid 2000 shows no bytes,
# or when its bytes didn't grow from before to after. Only counts and uid
# 2000's sums are printed; the dump itself never leaves the runner.
. "$(dirname "$0")/lib.sh"
guard_emulator

NETB="$GITHUB_WORKSPACE/ci/tool/emulator/net_bytes.sh"
CTL_PORT=8788
CTL_DIR=$(mktemp -d)
echo "piggybow-r1-control" > "$CTL_DIR/control.txt"
python3 -m http.server "$CTL_PORT" --bind 127.0.0.1 --directory "$CTL_DIR" >/dev/null 2>&1 &
CTL_PID=$!
cleanup(){
  kill "$CTL_PID" 2>/dev/null
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT
for i in $(seq 1 20); do curl -fsS "http://127.0.0.1:$CTL_PORT/control.txt" >/dev/null 2>&1 && break; sleep 0.5; done

uid_bytes(){ # uid_bytes <uid> < dump: "<rx> <tx>" summed over the uid's tag-0 entries (net_bytes.sh's reading)
  awk -v uid="$1" '
    /ident=/ { mine = index($0, " uid=" uid " ") > 0 && index($0, " tag=0x0") > 0 }
    mine { for (i = 1; i <= NF; i++) { n = split($i, kv, "=")
             if (n == 2 && kv[1] == "rb") rx += kv[2]
             if (n == 2 && kv[1] == "tb") tx += kv[2] } }
    END { printf "%d %d\n", rx, tx }'
}
control(){ # control <before|after>: the reader's positive control; any miss stops the run
  local n crx ctx
  A shell "printf 'GET /control.txt HTTP/1.0\r\n\r\n' | nc -w 3 10.0.2.2 $CTL_PORT" > "$OUT/control-$1.fetch" 2>&1 || true
  if ! grep -q piggybow-r1-control "$OUT/control-$1.fetch"; then
    echo "$(stamp) STOP: control $1: the shell's fetch from the runner didn't arrive ($(head -c 120 "$OUT/control-$1.fetch" | tr '\n' ' '))"
    row R1-2 FAIL "control $1: no known traffic made: a failed run, not zero"; exit 1
  fi
  A shell dumpsys netstats --poll >/dev/null 2>&1 || true
  A shell dumpsys netstats detail | tr -d '\r' > "$T/dump-$1.txt"
  n=$(grep -c 'ident=' "$T/dump-$1.txt" || true)
  read -r crx ctx < <(uid_bytes 2000 < "$T/dump-$1.txt")
  rm -f "$T/dump-$1.txt"
  echo "$(stamp) control $1: netstats entries: ${n:-0} | uid 2000 (the shell, which just fetched from the runner): rx $crx tx $ctx"
  if [ "${n:-0}" -eq 0 ]; then
    echo "$(stamp) STOP: control $1: netstats entries: 0, an empty dump"
    row R1-2 FAIL "control $1: an empty netstats dump: a failed run, not zero"; exit 1
  fi
  if [ "$crx" -eq 0 ] || [ "$ctx" -eq 0 ]; then
    echo "$(stamp) STOP: control $1: uid 2000 shows no bytes after its own fetch"
    row R1-2 FAIL "control $1: the known-talking uid 2000 shows rx $crx tx $ctx: the reader sees nothing, a failed run"; exit 1
  fi
  eval "ctl_rx_$1=$crx"
}

[ -f "$NETB" ] || { row R1-0 FAIL "no ci/tool/emulator/net_bytes.sh at this ref: dispatch with --ref feat/tips-in-release"; exit 1; }
install_verify || exit $?
echo "$(stamp) the build: head $HEAD_SHA, kind $KIND, $APP_ID, APK sha256 $(sha256sum < "$APK" | cut -c1-64), run ${GITHUB_RUN_ID:-?}"
# "Before" is after the install and before the first launch (the Reviewer)

bytes(){ # bytes <file>: "rx X tx Y" from net_bytes.sh's uid line
  sed -n 's/^uid [0-9]*: rx \([0-9]*\) tx \([0-9]*\).*/\1 \2/p' "$1" | head -1
}
netread(){ # netread <before|after>: the reader, its exit checked (8 = no uid: a failed run, never zero)
  local rc=0
  bash "$NETB" "$SERIAL" "$APP_ID" "$OUT/net-$1.txt" > "$OUT/net-$1.line" || rc=$?
  cat "$OUT/net-$1.line"
  if [ "$rc" != 0 ]; then
    row R1-2 FAIL "net_bytes.sh $1 the session exited $rc ($(head -1 "$OUT/net-$1.line")): a failed run, not zero"; exit 1
  fi
}
control before
netread before
read -r rx0 tx0 < <(bytes "$OUT/net-before.line")

if mf flows/pb1/95a_r1_quiet_session.yaml; then
  row R1-1 PASS "flow 95a: cold start; a spend and a save; Timeline, Summary, Me; an export to the share sheet and back; background and resume"
else
  row R1-1 FAIL "flow 95a"
fi

sleep 60   # anything deferred (a job with a network constraint) has its chance
control after
if [ "$ctl_rx_after" -le "$ctl_rx_before" ]; then
  echo "$(stamp) STOP: control after: uid 2000's rx didn't grow ($ctl_rx_before → $ctl_rx_after) after a second fetch"
  row R1-2 FAIL "control after: the reader didn't see the second fetch: a failed run, not zero"; exit 1
fi
netread after
read -r rx1 tx1 < <(bytes "$OUT/net-after.line")
echo "$(stamp) bytes before: rx ${rx0:-?} tx ${tx0:-?}; after: rx ${rx1:-?} tx ${tx1:-?}"
if [ "${rx0:-x}" = 0 ] && [ "${tx0:-x}" = 0 ] && [ "${rx1:-x}" = 0 ] && [ "${tx1:-x}" = 0 ]; then
  row R1-2 PASS "the store build sent and received nothing: rx 0 tx 0 before and after the session, with the control seen both times (net-before.txt, net-after.txt, control-*.fetch)"
else
  row R1-2 FAIL "network bytes: before rx ${rx0:-?} tx ${tx0:-?}, after rx ${rx1:-?} tx ${tx1:-?} (net-*.txt)"
fi
