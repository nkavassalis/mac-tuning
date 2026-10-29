#!/usr/bin/env bash
# install_launchd.sh: on the Mac, run Flint (`rec serve`, as scripts/serve.sh launches it) and the LAN relay (flint_relay.py) as
# user LaunchAgents: started at login (the Mac logs in automatically at boot), restarted by launchd if they exit. No root needed.
#   scp scripts/flint_relay.py "$MAC":mac-tuning-svc/      # first (mkdir -p ~/mac-tuning-svc on the Mac)
#   ssh -i "$MAC_KEY" "$MAC" 'bash -s' < scripts/install_launchd.sh             # install / reinstall
#   ssh -i "$MAC_KEY" "$MAC" 'bash -s -- --uninstall' < scripts/install_launchd.sh
# Knobs (env): RELAY_PORT (11502). Logs: ~/mac-tuning-logs/{serve,relay}.log; engine metrics ~/mac-tuning-logs/flint-metrics.jsonl.
set -euo pipefail
LA=~/Library/LaunchAgents; SVC=~/mac-tuning-svc; LOGS=~/mac-tuning-logs; RELAY_PORT=${RELAY_PORT:-11502}
SERVE=local.flint.serve; RELAY=local.flint.relay; U=gui/$(id -u)
unload() { for l in "$SERVE" "$RELAY"; do launchctl bootout "$U/$l" 2>/dev/null || true; done; }
if [ "${1:-}" = --uninstall ]; then
  unload; rm -f "$LA/$SERVE.plist" "$LA/$RELAY.plist"; echo "removed $SERVE and $RELAY (Flint and the relay are stopped)"; exit 0
fi
D=$HOME/.local/share/rec
PY=$(ls -d "$D"/runtimes/*/python/bin/python3.12 | head -1)
MD=$(dirname "$(ls "$D"/models/*/flint-int4.json | head -1)")
[ -x "$PY" ] && [ -f "$MD/flint-int4.json" ] && [ -f "$D/config/api-key" ] || { echo "rec runtime, model or API key not found under $D" >&2; exit 1; }
[ -f "$SVC/flint_relay.py" ] || { echo "copy scripts/flint_relay.py to $SVC/ first" >&2; exit 1; }
mkdir -p "$LA" "$LOGS"
x() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' <<<"$1"; }   # XML-escape a path
cat > "$LA/$SERVE.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>Label</key><string>$SERVE</string>
 <key>ProgramArguments</key><array>
  <string>$(x "$PY")</string><string>-I</string><string>-B</string><string>-m</string><string>rec_mlx.cli</string><string>serve</string><string>flint</string>
  <string>--model-dir</string><string>$(x "$MD")</string><string>--manifest</string><string>$(x "$MD/flint-int4.json")</string>
  <string>--port</string><string>11500</string><string>--context-limit</string><string>262144</string>
  <string>--api-key-file</string><string>$(x "$D/config/api-key")</string><string>--metrics</string><string>$(x "$LOGS/flint-metrics.jsonl")</string>
 </array>
 <key>EnvironmentVariables</key><dict><key>HF_HUB_OFFLINE</key><string>1</string><key>TOKENIZERS_PARALLELISM</key><string>false</string></dict>
 <key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>30</integer>
 <key>StandardOutPath</key><string>$(x "$LOGS/serve.log")</string><key>StandardErrorPath</key><string>$(x "$LOGS/serve.log")</string>
</dict></plist>
EOF
cat > "$LA/$RELAY.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>Label</key><string>$RELAY</string>
 <key>ProgramArguments</key><array><string>/usr/bin/python3</string><string>-I</string><string>-B</string><string>$(x "$SVC/flint_relay.py")</string></array>
 <key>EnvironmentVariables</key><dict><key>RELAY_PORT</key><string>$RELAY_PORT</string></dict>
 <key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>10</integer>
 <key>StandardOutPath</key><string>$(x "$LOGS/relay.log")</string><key>StandardErrorPath</key><string>$(x "$LOGS/relay.log")</string>
</dict></plist>
EOF
plutil -lint "$LA/$SERVE.plist" "$LA/$RELAY.plist" >/dev/null
unload
"$HOME/.local/bin/rec" stop >/dev/null 2>&1 || true            # a server started by serve.sh or `rec serve`
pkill -f "rec_mlx.cli serve" 2>/dev/null || true; sleep 2
launchctl bootstrap "$U" "$LA/$SERVE.plist"; launchctl bootstrap "$U" "$LA/$RELAY.plist"
K=$(cat "$D/config/api-key")
for i in $(seq 1 90); do
  if curl -sf -m 3 -H "Authorization: Bearer $K" "localhost:$RELAY_PORT/health" >/dev/null 2>&1; then
    echo "flint up through the relay on :$RELAY_PORT after $((i*2)) s (launchd: $SERVE, $RELAY)"; exit 0
  fi
  sleep 2
done
echo "flint not reachable through the relay"; tail -5 "$LOGS/serve.log" "$LOGS/relay.log"; exit 1
