#!/bin/sh
# Removes MacAwake, restores sleep, and deletes its watchdog and sleep rule.
set -u
pkill -x MacAwake 2>/dev/null && sleep 2
if pmset -g | grep -q "SleepDisabled[[:space:]]*1"; then sudo pmset -a disablesleep 0; fi
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.macawake.watchdog.plist" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/com.macawake.watchdog.plist"
rm -rf "$HOME/Applications/MacAwake.app"
[ -f /etc/sudoers.d/macawake ] && sudo rm -f /etc/sudoers.d/macawake
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/Library/Application Support/MacAwake" "$HOME/Library/Logs/MacAwake"
fi
echo "MacAwake removed."
