#!/bin/sh
# Builds MacAwake and installs it to ~/Applications.
# The lid-proof sleep rule is installed from inside the app (one admin prompt),
# or pass --with-sleep-rule to install it here with sudo.
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh
DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x MacAwake 2>/dev/null && sleep 1 || true
rm -rf "$DEST/MacAwake.app"
cp -R build/MacAwake.app "$DEST/"

if [ "${1:-}" = "--with-sleep-rule" ]; then
  USER_NAME="$(id -un)"
  TMP="$(mktemp)"
  printf '# Installed by MacAwake\n%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0\n' "$USER_NAME" > "$TMP"
  sudo /usr/sbin/visudo -cf "$TMP"
  sudo /usr/bin/install -m 0440 -o root -g wheel "$TMP" /etc/sudoers.d/macawake
  rm -f "$TMP"
  echo "Sleep rule installed at /etc/sudoers.d/macawake"
fi

open "$DEST/MacAwake.app"
echo "Installed $DEST/MacAwake.app"
