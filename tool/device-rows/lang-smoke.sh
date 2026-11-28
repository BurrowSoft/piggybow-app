#!/usr/bin/env bash
# The 5 languages (decision 97), kind=plus-rows (staging debug: Flutter logs
# every layout overflow; Plus enabled, so the paywall opens, Plus stays off),
# zone UTC. Per language, set by Android's per-app language (UX: no in-app
# picker in 0.2.0), with a guard that it took:
#   flow 97a  onboarding at text x1, a shot per step
#   flow 97b  Home, Add, Summary, Me and the paywall at each font scale, each
#             screen with its anchor string from the language's ARB file
#   LG-<lang>      both flows passed at every scale
#   LG-OVF-<lang>  no Flutter overflow report from the app's own processes
#                  (logcat, tag flutter, the app's uid only; the count and the
#                  matching lines kept: UX's OK, 18:55Z)
# German also runs 97b once more at x2 in dark. The shots are looked at
# afterwards (LG-SHOTS), German first. LG_LANGS and LG_SCALES narrow a run.
. "$(dirname "$0")/lib.sh"
guard_emulator
[ "$KIND" = plus-rows ] || { echo "$(stamp) STOP: dispatch with kind=plus-rows (kind is $KIND)"; exit 7; }
ARB_DIR="${APP_DIR:-$GITHUB_WORKSPACE/app}/lib/l10n"
[ -d "$ARB_DIR" ] || { echo "$(stamp) STOP: no $ARB_DIR (the app's checkout)"; exit 7; }
LANGS=${LG_LANGS:-"en-US de-DE pt-BR es-ES fr-FR"}
SCALES=${LG_SCALES:-"1.0 2.0"}
cleanup(){
  A shell settings put system font_scale 1.0 >/dev/null 2>&1
  A shell cmd uimode night no >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT
install_verify || exit $?
uid=$(A shell cmd package list packages -U "$APP_ID" | tr -d '\r' \
  | awk -v p="package:$APP_ID" '$1 == p { sub(/^uid:/, "", $2); print $2 }')
[[ "$uid" =~ ^[0-9]+$ ]] || { echo "$(stamp) STOP: no uid for $APP_ID"; exit 8; }
uname="u0_a$((uid - 10000))"

arb_for(){ # arb_for <de-DE>: app_de_DE.arb, else app_de.arb
  local f
  for f in "app_${1//-/_}.arb" "app_${1%%-*}.arb"; do
    [ -f "$ARB_DIR/$f" ] && { echo "$ARB_DIR/$f"; return 0; }
  done
  return 1
}
anchor(){ # anchor <arb> <key>: the string, escaped for Maestro's regex
  local v
  v=$(jq -r --arg k "$2" '.[$k] // empty' "$1")
  [ -n "$v" ] || return 1     # a missing key never becomes an empty, match-all anchor
  printf '%s' "$v" | sed 's/[][\.*^$?+(){}|/]/\\&/g'
}
overflows(){ # overflows <file>: the app's own Flutter overflow lines since the last clear
  A logcat -d -v uid -s flutter | tr -d '\r' \
    | grep -E "(^| )($uid|$uname) " | grep -E 'overflowed|RenderFlex' > "$1" || true
  wc -l < "$1" | tr -d ' '
}

for l in $LANGS; do
  arb=$(arb_for "$l") || { row "LG-$l" FAIL "no ARB file for $l in lib/l10n"; continue; }
  envs=(); miss=""
  for kv in A_HOME:tabHome A_ME:tabMe A_WEEK:weekTitle A_IDEA:ideaTitle A_ADD:addSheetLabel             A_CAT:addCategoryLabel A_FEEL:addFeelingLabel A_SUMWEEK:sumWeek A_SUMMONTH:sumMonth             A_MONEY:meSecMoney A_DATA:meSecData A_PLUS:plusTitle; do
    v=$(anchor "$arb" "${kv#*:}") || { miss="$miss ${kv#*:}"; continue; }
    envs+=(-e "${kv%%:*}=$v")
  done
  [ -z "$miss" ] || { row "LG-$l" FAIL "keys missing in ${arb##*/}:$miss"; continue; }
  A shell cmd locale set-app-locales "$APP_ID" --locales "$l"
  got=$(A shell cmd locale get-app-locales "$APP_ID" | tr -d '\r')
  echo "$(stamp) ===== $l: ${arb##*/} | app locales: $got ====="
  A shell settings put system font_scale 1.0; sleep 1
  A logcat -c
  ok=1
  MF_NAME="97a-$l" mf flows/pb1/97a_lang_onboarding.yaml -e "P=$l-x1" || ok=0
  for s in $SCALES; do
    [ "$ok" = 1 ] || break
    A shell settings put system font_scale "$s"; sleep 2
    MF_NAME="97b-$l-x$s" mf flows/pb1/97b_lang_tour.yaml -e "P=$l-x$s" "${envs[@]}" || ok=0
  done
  if [ "$l" = de-DE ] && [ "$ok" = 1 ]; then
    A shell cmd uimode night yes; A shell settings put system font_scale 2.0; sleep 2
    MF_NAME="97b-$l-x2-dark" mf flows/pb1/97b_lang_tour.yaml -e "P=$l-x2-dark" "${envs[@]}" || ok=0
    A shell cmd uimode night no
  fi
  n=$(overflows "$OUT/overflow-$l.txt")
  if [ "$ok" = 1 ]; then
    row "LG-$l" PASS "flows 97a + 97b at $SCALES$([ "$l" = de-DE ] && echo ' + x2 dark'): onboarding, Home, Add, Summary, Me, the paywall, each with its $l anchor"
  else
    row "LG-$l" FAIL "a flow failed in $l (its logs are kept); app locales: $got"
  fi
  if [ "$n" = 0 ]; then
    row "LG-OVF-$l" PASS "no Flutter overflow report from the app ($uname) in $l"
  else
    row "LG-OVF-$l" FAIL "$n Flutter overflow line(s) from the app in $l: overflow-$l.txt"
  fi
done
