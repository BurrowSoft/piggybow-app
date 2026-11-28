# The positive control for net_bytes.sh, sourced by a caller that defines
# A() (adb -s "$SERIAL" ...). Before a reading, the device's shell fetches a
# one-off token from a listener on this runner (from the emulator, 10.0.2.2
# is the runner's 127.0.0.1), so a known uid has just talked, and a reading
# that can't see it stops the run instead of passing for zero bytes.
#   control_start          the listener, on 127.0.0.1:$CONTROL_PORT (8788)
#   control_fetch <label>  the device's fetch; sets CONTROL_UID to the uid
#                          the shell runs as (2000, or 0 under adb root),
#                          for net_bytes.sh's CONTROL_UID
#   control_stop           the listener stopped, its folder deleted
# Each failure prints a STOP line and returns 8. The fetch's answer is
# printed only on a failure, its first characters only.
CONTROL_PORT=${CONTROL_PORT:-8788}
CONTROL_UID=
CONTROL_TOKEN=
CONTROL_PID=
CONTROL_DIR=

control_start() {
  local i
  CONTROL_DIR=$(mktemp -d)
  CONTROL_TOKEN="piggybow-control-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  printf '%s\n' "$CONTROL_TOKEN" > "$CONTROL_DIR/control.txt"
  python3 -m http.server "$CONTROL_PORT" --bind 127.0.0.1 --directory "$CONTROL_DIR" > /dev/null 2>&1 &
  CONTROL_PID=$!
  for i in $(seq 1 40); do
    if curl -fsS "http://127.0.0.1:$CONTROL_PORT/control.txt" 2> /dev/null | grep -qF "$CONTROL_TOKEN"; then
      return 0
    fi
    sleep 0.25
  done
  echo "STOP: the control listener on 127.0.0.1:$CONTROL_PORT never answered"
  return 8
}

control_fetch() {
  local got seen
  CONTROL_UID=$(A shell id -u | tr -d '\r')
  if ! [[ "$CONTROL_UID" =~ ^[0-9]+$ ]]; then
    echo "STOP: control $1: the device's shell uid can't be read ($CONTROL_UID)"
    return 8
  fi
  got=$(A shell "printf 'GET /control.txt HTTP/1.0\r\n\r\n' | nc -w 3 10.0.2.2 $CONTROL_PORT" 2>&1 | tr -d '\r' || true)
  if [ -z "$CONTROL_TOKEN" ] || ! grep -qF "$CONTROL_TOKEN" <<< "$got"; then
    seen=${got:0:120}
    seen=${seen//$'\n'/ }
    echo "STOP: control $1: the device's fetch from the runner didn't arrive (${seen:-no answer})"
    return 8
  fi
  echo "control $1: uid $CONTROL_UID fetched the token from the runner"
}

control_stop() {
  if [ -n "$CONTROL_PID" ]; then kill "$CONTROL_PID" 2> /dev/null || true; fi
  if [ -n "$CONTROL_DIR" ]; then rm -rf "$CONTROL_DIR"; fi
  CONTROL_PID=
  CONTROL_DIR=
}
