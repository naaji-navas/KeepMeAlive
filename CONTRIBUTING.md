# Contributing to KeepMeAlive

Thanks for helping. Contributions of any size are welcome.

## Setup

You need macOS 14 or later and the Xcode Command Line Tools. Full Xcode is optional.

```bash
swift build
./scripts/build-app.sh && open build/KeepMeAlive.app
```

> The Command Line Tools don't include SwiftUI's macro plugin, so use
> `@ViewState` in place of `@State` (defined in `UI/MenuPanel.swift`). It is the same
> property wrapper, minus the macro.

## Ground rules

- **Always undo what you change.** Anything KeepMeAlive changes on the system (sleep,
  paused processes, mute, App Nap defaults) must be recorded in `RuntimeState`
  *before* it is applied, and undone by `AwakeEngine.shutdown()`, by
  `recoverFromPreviousRun()` and, where a shell can do it, by `Resources/watchdog.sh`.
- **No new root powers without discussion.** The sudoers rule covers exactly two `pmset`
  commands. Open an issue before proposing anything that widens it.
- **Never block with the lid closed.** Don't show prompts (Keychain, alerts, permissions)
  from code that can run while the user is away. Read what you need when the session starts.
- **Be careful with pausing.** If an app might be unsafe to pause (VPN, meeting, security,
  input), add it to `AppFreezer.protectedBundleIDs`.

## Testing a change

1. Run `KeepMeAlive preview` to check which apps would be paused.
2. Start a short session, close the lid for a few minutes, then open it and check
   `~/Library/Logs/KeepMeAlive/keepmealive.log`.
3. Afterwards, `pmset -g | grep SleepDisabled` should print nothing.
4. To test crash recovery: start a session, run `kill -9` on the app, and wait up to a
   minute. The watchdog should turn sleep back on.

## Pull requests

Keep PRs focused and fill in the template. If you change behavior, update the README too.
