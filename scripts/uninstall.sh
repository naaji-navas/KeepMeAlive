#!/bin/sh
# Removes KeepMeAlive, restores sleep, and deletes its watchdog and sleep rule.
set -u
pkill -x KeepMeAlive 2>/dev/null && sleep 2
if pmset -g | grep -q "SleepDisabled[[:space:]]*1"; then sudo pmset -a disablesleep 0; fi
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.keepmealive.watchdog.plist" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/com.keepmealive.watchdog.plist"
rm -rf "$HOME/Applications/KeepMeAlive.app"
[ -f /etc/sudoers.d/keepmealive ] && sudo rm -f /etc/sudoers.d/keepmealive
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/Library/Application Support/KeepMeAlive" "$HOME/Library/Logs/KeepMeAlive"
fi
echo "KeepMeAlive removed."
