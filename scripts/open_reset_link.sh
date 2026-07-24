#!/bin/sh
# Local-dev helper: password-reset links must open ON THE SIMULATOR (the
# threewood:// redirect means nothing to a Mac browser, and each link is
# one-time-use). After tapping "Forgot password?" in the app, run this —
# it grabs the newest reset email from Mailpit and opens its link in the
# booted simulator, which hands the recovery token to the app.
set -e

MAILPIT=http://127.0.0.1:54324

ID=$(curl -s "$MAILPIT/api/v1/messages" | python3 -c "
import json, sys
msgs = json.load(sys.stdin).get('messages', [])
resets = [m for m in msgs if 'password' in m['Subject'].lower()]
print(resets[0]['ID'] if resets else '')")

if [ -z "$ID" ]; then
  echo "No password-reset email found in Mailpit ($MAILPIT)." >&2
  echo "Tap 'Forgot password?' in the app first." >&2
  exit 1
fi

LINK=$(curl -s "$MAILPIT/api/v1/message/$ID" | python3 -c "
import json, sys, re, html
d = json.load(sys.stdin)
body = d.get('HTML') or d.get('Text', '')
m = re.search(r'href=\"([^\"]*type=recovery[^\"]*)\"', body) or \
    re.search(r'(https?://\S*type=recovery\S*)', body)
print(html.unescape(m.group(1)) if m else '')")

if [ -z "$LINK" ]; then
  echo "Couldn't find a recovery link in message $ID." >&2
  exit 1
fi

echo "Opening in simulator: $LINK"
xcrun simctl openurl booted "$LINK"
