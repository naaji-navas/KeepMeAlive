#!/bin/sh
# Installs a downloaded MacAwake release (run from the unzipped folder).
# Pass --with-sleep-rule to install the lid-proof sleep rule now (asks for sudo);
# otherwise the app offers it on first use.
set -eu
cd "$(dirname "$0")"
DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x MacAwake 2>/dev/null && sleep 1 || true
rm -rf "$DEST/MacAwake.app"
cp -R MacAwake.app "$DEST/"
# The release is ad-hoc signed (not notarized), so clear the download quarantine flag.
xattr -dr com.apple.quarantine "$DEST/MacAwake.app" 2>/dev/null || true

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
echo "Installed $DEST/MacAwake.app — look for the moon icon in the menu bar."
