#!/usr/bin/env bash
# R1's gate (#95, the Reviewer's ruling): the store build (kind=prod-release:
# Plus off, pig tips off) sends NOTHING. The app's own network bytes, read by
# ci/tool/emulator/net_bytes.sh (that uid's netstats lines only), before and
# after a session that touches every screen: expected rx 0 and tx 0 both
# times. Dispatch with --ref feat/tips-in-release (net_bytes.sh lives there).
#   R1-1 flow 95a: cold start, a spend and a save, Timeline, Summary, Me, an
#        export to the share sheet and back, background and resume
#   R1-2 the bytes: 0 before, 0 after (a minute's wait for anything deferred)
. "$(dirname "$0")/lib.sh"
guard_emulator

NETB="$GITHUB_WORKSPACE/ci/tool/emulator/net_bytes.sh"
cleanup(){
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

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
netread before
read -r rx0 tx0 < <(bytes "$OUT/net-before.line")

if mf flows/pb1/95a_r1_quiet_session.yaml; then
  row R1-1 PASS "flow 95a: cold start; a spend and a save; Timeline, Summary, Me; an export to the share sheet and back; background and resume"
else
  row R1-1 FAIL "flow 95a"
fi

sleep 60   # anything deferred (a job with a network constraint) has its chance
netread after
read -r rx1 tx1 < <(bytes "$OUT/net-after.line")
echo "$(stamp) bytes before: rx ${rx0:-?} tx ${tx0:-?}; after: rx ${rx1:-?} tx ${tx1:-?}"
if [ "${rx0:-x}" = 0 ] && [ "${tx0:-x}" = 0 ] && [ "${rx1:-x}" = 0 ] && [ "${tx1:-x}" = 0 ]; then
  row R1-2 PASS "the store build sent and received nothing: rx 0 tx 0 before and after the session (net-before.txt, net-after.txt)"
else
  row R1-2 FAIL "network bytes: before rx ${rx0:-?} tx ${tx0:-?}, after rx ${rx1:-?} tx ${tx1:-?} (net-*.txt)"
fi
