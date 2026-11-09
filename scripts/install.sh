#!/bin/sh
# Builds KeepMeAlive and installs it to ~/Applications.
# The lid-proof sleep rule is installed from inside the app (one admin prompt),
# or pass --with-sleep-rule to install it here with sudo.
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh
DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x KeepMeAlive 2>/dev/null && sleep 1 || true
rm -rf "$DEST/KeepMeAlive.app"
cp -R build/KeepMeAlive.app "$DEST/"

if [ "${1:-}" = "--with-sleep-rule" ]; then
  USER_NAME="$(id -un)"
  TMP="$(mktemp)"
  printf '# Installed by KeepMeAlive\n%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0\n' "$USER_NAME" > "$TMP"
  sudo /usr/sbin/visudo -cf "$TMP"
  sudo /usr/bin/install -m 0440 -o root -g wheel "$TMP" /etc/sudoers.d/keepmealive
  rm -f "$TMP"
  echo "Sleep rule installed at /etc/sudoers.d/keepmealive"
fi

open "$DEST/KeepMeAlive.app"
echo "Installed $DEST/KeepMeAlive.app"
