# Security

## Reporting

Please report vulnerabilities privately through GitHub's
**Security → Report a vulnerability** on this repository, not in a public issue.

## What MacAwake can do with elevated rights

When you enable lid-proof mode, MacAwake installs `/etc/sudoers.d/macawake`:

```
<you> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
```

The rule lets **any process running as your user** turn system sleep off or on without
a password. It allows nothing else. The worst case is a Mac that doesn't sleep when the
lid closes. Review it before you enable it. Remove it with `./scripts/uninstall.sh` or
`sudo rm /etc/sudoers.d/macawake`.

Everything else MacAwake does runs as your user: pausing your own processes, the
LaunchAgent watchdog, the Keychain item and the network changes.

## Data

MacAwake makes no network requests except reachability probes to
`captive.apple.com` and `www.cloudflare.com`, and only during a session. It has no
analytics and no update checks. Logs stay on your Mac and may contain Wi-Fi names.
