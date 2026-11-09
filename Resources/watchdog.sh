#!/bin/sh
# MacAwake watchdog — runs every minute via launchd.
# If MacAwake has crashed or was force-quit while it had sleep disabled or apps
# paused, this script undoes those changes so the Mac never stays sleepless by accident.

STATE="$HOME/Library/Application Support/MacAwake/state.json"
LOG="$HOME/Library/Logs/MacAwake/watchdog.log"

[ -f "$STATE" ] || exit 0

get() { /usr/bin/plutil -extract "$1" raw -o - "$STATE" 2>/dev/null; }

PID=$(get appPid)
if [ -n "$PID" ] && [ "$PID" != "0" ] && /bin/kill -0 "$PID" 2>/dev/null; then
  if /bin/ps -p "$PID" -o comm= 2>/dev/null | /usr/bin/grep -q "MacAwake"; then
    exit 0  # app alive, it is in charge
  fi
fi

SLEEP=$(get sleepDisabledByUs)
FROZEN=$(get frozenPids)
MUTED=$(get mutedByUs)

if [ "$SLEEP" != "true" ] && [ "$SLEEP" != "1" ] && [ -z "$FROZEN" ] && [ "$MUTED" != "true" ]; then
  exit 0
fi

ts() { /bin/date "+%Y-%m-%dT%H:%M:%S%z"; }
echo "$(ts) MacAwake (pid $PID) is gone; restoring the system" >> "$LOG"

for p in $FROZEN; do /bin/kill -CONT "$p" 2>/dev/null; done
[ -n "$FROZEN" ] && echo "$(ts) resumed pids: $FROZEN" >> "$LOG"

if [ "$MUTED" = "true" ]; then /usr/bin/osascript -e "set volume output muted false" >/dev/null 2>&1; fi

if [ "$SLEEP" = "true" ] || [ "$SLEEP" = "1" ]; then
  if /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 2>>"$LOG"; then
    echo "$(ts) sleep re-enabled" >> "$LOG"
  else
    echo "$(ts) FAILED to re-enable sleep; run: sudo pmset -a disablesleep 0" >> "$LOG"
    exit 1  # keep state so we retry next minute
  fi
fi

/bin/rm -f "$STATE"
exit 0
