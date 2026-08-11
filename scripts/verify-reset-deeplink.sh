#!/bin/bash
#
# End-to-end check of the password-reset deep link, against the LOCAL stack.
#
# Why this needs a script at all: XCUITest cannot open a URL scheme, and the
# PKCE code verifier lives in the app's own keychain — so the reset has to be
# requested by the app, and the link has to be delivered from outside it. This
# drives both halves:
#
#   1. starts 3WoodUITests/ResetDeepLinkProbe, which asks for a reset in-app
#   2. waits for the resulting mail to land in the local catcher (mailpit)
#   3. resolves the GoTrue /verify redirect into a threewood:// URL
#   4. fires simctl openurl while the test is parked on SpringBoard's prompt
#   5. the test taps Open and asserts UpdatePasswordView appeared
#
# The probe skips itself unless RESET_DEEPLINK_PROBE=1, which is set here, so a
# plain `xcodebuild test` never waits on a prompt that will not come.
#
# Requires: local stack running (`supabase start`) and a booted iPhone 17 Pro.
#
set -uo pipefail

MAIL=http://127.0.0.1:54324
REPO=$(cd "$(dirname "$0")/.." && pwd)
LOG=$(mktemp -t reset-deeplink-probe)

cd "$REPO"

if ! xcrun simctl list devices booted | grep -q "iPhone 17 Pro"; then
  echo "Booting iPhone 17 Pro..."
  xcrun simctl boot "iPhone 17 Pro" || true
  sleep 8
fi

echo "Starting the probe (log: $LOG)"
TEST_RUNNER_RESET_DEEPLINK_PROBE=1 \
xcodebuild -project 3Wood.xcodeproj -scheme 3Wood \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:3WoodUITests/ResetDeepLinkProbe test >"$LOG" 2>&1 &
XCB=$!

newest_message_id() {
  curl -s "$MAIL/api/v1/messages?limit=1" 2>/dev/null \
    | python3 -c "import sys,json;d=json.load(sys.stdin);m=(d.get('messages') or d);print(m[0]['ID'] if m else '')" 2>/dev/null \
    || echo ""
}

deliver() {
  local id=$1
  local verify deeplink
  verify=$(curl -s "$MAIL/api/v1/message/$id" | python3 -c "
import sys,json,re
m=json.load(sys.stdin)
b=(m.get('Text') or '')+(m.get('HTML') or '')
print([x for x in re.findall(r'http://[^\s\"<>]+', b) if 'verify' in x][0].replace('&amp;','&'))
")
  deeplink=$(curl -s -o /dev/null -D- "$verify" | awk 'tolower($1)=="location:"{print $2}' | tr -d '\r')

  # The app is on the default PKCE flow, so GoTrue must hand back ?code=… . A
  # fragment here means the request went out without PKCE parameters, and
  # session(from:) would reject it as "Not a valid PKCE flow URL".
  case "$deeplink" in
    threewood://reset-password\?code=*) echo "  deep link OK (PKCE): $deeplink" ;;
    *) echo "  UNEXPECTED deep link: $deeplink"; return 1 ;;
  esac

  sleep 3
  xcrun simctl openurl booted "$deeplink"
  echo "  delivered"
}

# Serve one link per probe method, for as long as the test run lasts. Only mail
# sent during THIS run is usable — an older email carries a verifier the install
# no longer holds, so the exchange would fail.
LAST=$(newest_message_id)
echo "Baseline message: ${LAST:-none}"
SERVED=0

while kill -0 $XCB 2>/dev/null; do
  sleep 5
  ID=$(newest_message_id)
  if [ -n "$ID" ] && [ "$ID" != "$LAST" ]; then
    LAST="$ID"
    SERVED=$((SERVED + 1))
    echo "Reset #$SERVED requested by the app:"
    deliver "$ID"
  fi
done

wait $XCB
echo
echo "Links delivered: $SERVED"

# One probe deliberately changes the password. Put the seed value back so
# seed.sql stays truthful without needing a db reset. This is the well-known
# local service_role key — local stack only, not a secret.
LOCAL_SERVICE_ROLE="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
UID_=$(curl -s "http://127.0.0.1:54321/auth/v1/admin/users?filter=chip_charlie@example.com" \
  -H "apikey: $LOCAL_SERVICE_ROLE" -H "Authorization: Bearer $LOCAL_SERVICE_ROLE" \
  | python3 -c "import sys,json;u=json.load(sys.stdin).get('users',[]);print(u[0]['id'] if u else '')" 2>/dev/null)
if [ -n "$UID_" ]; then
  curl -s -o /dev/null -X PUT "http://127.0.0.1:54321/auth/v1/admin/users/$UID_" \
    -H "apikey: $LOCAL_SERVICE_ROLE" -H "Authorization: Bearer $LOCAL_SERVICE_ROLE" \
    -H "Content-Type: application/json" -d '{"password":"testpass123"}'
  echo "Restored chip_charlie's seed password."
fi

grep -E "Test Case .* (passed|failed)|error:|TEST (SUCCEEDED|FAILED)" "$LOG" | head -30
