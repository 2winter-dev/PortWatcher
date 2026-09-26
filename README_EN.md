# PortWatcher

> 中文说明 / Chinese version: [README.md](README.md)

A tiny menu-bar port monitor for macOS. It lives in your status bar, counts the
listening ports on your machine, and lets you inspect, restart, or stop the
process behind any port — all from a single popover.

Native SwiftUI + AppKit, **zero third-party dependencies**.

---

## Features

- **Live port count in the menu bar** — the status-bar icon shows how many ports
  are currently listening; click it to open the panel.
- **System resource strip** — real-time **memory usage** (Activity Monitor style:
  active + speculative + wired + compressed, excluding reclaimable `inactive`
  cache) and **disk usage** (`used / total` from `df`). Numbers turn orange/red
  when high.
- **Full port list** — every TCP (`LISTEN`) and UDP (bound) port, each with:
  - port, protocol (TCP/UDP), process name, PID, user
  - listen address, tagged `Local` / `Public` / specific
  - **launch source**: the `launchd` label + `.plist` path, or the full launch command
  - **memory footprint** (RSS)
- **Human-readable change feed** — every scan is diffed and summarized in a banner
  (e.g. `:8000 added · :5432 restarted · :9000 closed`), with inline `NEW` /
  `⟳ Restart` / memory `▲▼` tags.
- **Filter & search** — All / Favorites / Local only / Auto-launch, plus free-text
  search across port, process, and command.
- **Details & logs** — expand any row for a full info grid, the launch source, the
  `.plist` contents, and a **one-click fetch of that process's real logs**
  (`log show --predicate processID`). Reveal the executable in Finder, copy the
  command line.
- **Restart / Force-stop** — restart `launchd`-managed processes via
  `launchctl kickstart -k`; relaunch normal processes with their original command
  (after a 1s port-release wait). Force-stop sends `kill -9` (or
  `launchctl kill SIGKILL` for `launchd` jobs), with a confirm dialog. All actions
  are written to a **48-hour history log**.
- **Login item** — register PortWatcher to start at login (recommended: keep the
  app in `/Applications`).
- **macOS 26 Liquid Glass** look — translucent background, glass cards, semantic
  colors that follow light/dark mode.
- **Multilingual** — English / 中文, follows the system, with a manual language
  switch in Settings. Falls back to English.

## Installation

Download the latest `PortWatcher.dmg` from the
[Releases](https://github.com/YOUR_GITHUB_USERNAME/PortWatcher/releases) page,
open it, and drag **PortWatcher.app** to **Applications**.

> Requires **macOS 26** or later.

## Build from source

Prerequisites: **Xcode 26 / Swift 6** (the Command Line Tools are enough).

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/PortWatcher.git
cd PortWatcher
bash build-app.sh
open build/PortWatcher.app
```

`build-app.sh` compiles in release mode, assembles `build/PortWatcher.app`, and
copies in the app icon + menu-bar template.

To produce a signed, notarized, distributable disk image:

```bash
export DEV_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="AC_PASSWORD"   # from `xcrun notarytool store-credentials`
bash notarize.sh      # sign with Developer ID (hardened runtime, no sandbox)
bash make-dmg.sh      # package into PortWatcher.dmg
```

## Usage

- Click the menu-bar icon → panel opens.
- **Auto-refresh** is on by default (every 5s).
- Expand a row → restart / force-stop / load logs / reveal in Finder.
- The **gear** (top-right) opens Settings: login item, quit, version.
- Right-click the menu-bar icon → About / Quit.

## How it works

PortWatcher reads **only local system state**. There is **no network access and no
telemetry** — the app never sends anything anywhere. It gathers data by shelling
out to standard macOS utilities:

| Data            | Source                                  |
|-----------------|-----------------------------------------|
| Listening ports | `lsof -iTCP -sTCP:LISTEN`, `lsof -iUDP` |
| Process info    | `ps`                                    |
| Launch source   | `launchctl list` + `.plist` resolution  |
| Process logs    | `log show`                              |
| Memory / disk   | `vm_stat`, `sysctl`, `df`               |

## Privacy

PortWatcher collects **no data** and makes **no network connections** (the only
outbound action is opening `http://127.0.0.1:<port>` in your browser when you
click "Open in browser"). Everything stays on your Mac.

## Project structure

```
Sources/PortWatcher/
  AppDelegate.swift      menu-bar item, popover, right-click menu, About
  ContentView.swift      popover UI: header, filters, list, details, history
  PortMonitor.swift      scan orchestration, favorites, aliases, change diff
  PortScanner.swift      lsof/ps/launchctl parsing, service-name hints
  SystemStats.swift     memory / disk snapshots
  Actions.swift         restart / force-stop / log fetch / launch-at-login
  HistoryStore.swift    48-hour action history (persisted to ~/Library)
  Localization.swift    en/zh string table + language switching
  main.swift            NSApplication entry point
AppStore/               icon + menu-bar SVG sources, render script, store metadata
build-app.sh           assemble the .app
notarize.sh            Developer ID sign + notarize
make-dmg.sh            package into a .dmg
```

## License

[MIT](LICENSE) © 2026 2winter.
