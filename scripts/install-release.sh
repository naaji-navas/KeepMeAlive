#!/bin/sh
# Installs a downloaded KeepMeAlive release (run from the unzipped folder).
# Pass --with-sleep-rule to install the lid-proof sleep rule now (asks for sudo);
# otherwise the app offers it on first use.
set -eu
cd "$(dirname "$0")"
DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x KeepMeAlive 2>/dev/null && sleep 1 || true
rm -rf "$DEST/KeepMeAlive.app"
cp -R KeepMeAlive.app "$DEST/"
# The release is ad-hoc signed (not notarized), so clear the download quarantine flag.
xattr -dr com.apple.quarantine "$DEST/KeepMeAlive.app" 2>/dev/null || true

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
echo "Installed $DEST/KeepMeAlive.app — look for the moon icon in the menu bar."
