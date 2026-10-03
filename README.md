# Deft

**Give your Mac the Windows habits you miss — free, native, and open source.**

[![Download](https://img.shields.io/github/v/release/ninjait07/deft?label=Download&color=2f7de0)](https://github.com/ninjait07/deft/releases/latest)
[![Follow NonDev on Facebook](https://img.shields.io/badge/Facebook-NonDev-1877F2?logo=facebook&logoColor=white)](https://www.facebook.com/nondev07/)

Deft is a lightweight macOS menu-bar app that brings the window-management and keyboard behaviour of Windows to your Mac, without changing anything permanently.

<p align="center"><img src="docs/img/menu.png" width="360" alt="Deft menu"></p>

## Features

- **Windows Snap** — drag windows to edges/corners to snap them; Snap Layouts, Snap Assist, shared resize dividers, and `Win`+arrow keys. A maximized window shrinks to half size the moment you drag it, like Windows.
- **Live Preview** — real, moving window thumbnails in the switcher (`Alt`+`Tab` in Windows mode, `Cmd`+`Tab` in Mac mode), Snap Assist, and when hovering the Dock.
- **Windows keyboard** — `Ctrl` acts as `Cmd`, the `Win` key, F-keys, Home/End, Explorer keys in Finder, a Windows-style language switch key, and auto-detection of Windows vs Mac keyboards.
- **Cut & paste files in Finder** — `Ctrl`+`X` (or `⌘`+`X` on a Mac keyboard) then `Ctrl`/`⌘`+`V` moves files, like Explorer — a short click sound confirms the cut, and `Esc` cancels it.
- **Mouse & scroll** — independent natural-scroll for mouse and trackpad, side-button back/forward, and `Ctrl`+scroll to zoom (sent as `⌘`+scroll to apps that zoom that way, `⌘+`/`⌘−` to the rest).
- **System Monitor** — live CPU, RAM, SSD, and temperature cells in the menu bar with smooth animation; click for all four at once in a tidy grid (user/system CPU, core types, swap, SSD speed and free space, SSD and battery temperatures), whichever cells you show.
- **AI Usage** — a Claude Code cell next to CPU/RAM with the same session and weekly percentages `/usage` shows, read from the file Claude Code keeps on your Mac (no account, nothing leaves your Mac). Click for weekly and per-model limits and reset times.
- **Display controls** — resolution, refresh rate, rotation, set main display, power a display off, and a drag-to-arrange window.
- **Clean Keyboard** — lock every key so you can wipe the keyboard.
- **Glass slider** — choose how see-through the menu and windows are, from clear Liquid Glass to frosted; the menu updates as you drag.
- **Manual** — a built-in guide to every feature, in English and Thai.

## See it move

**Drag to an edge to snap — Snap Assist fills the rest**

![Snap and Snap Assist](docs/img/snap.gif)

**Snap Layouts — drag to the top and pick a layout**

![Snap Layouts](docs/img/layouts.gif)

**Alt+Tab with live window previews**

![Alt+Tab switcher](docs/img/alttab.gif)

## Screenshots

| Menu bar | System Monitor & Claude Code usage |
|---|---|
| ![Menu bar cells](docs/img/menubar.png) | <img src="docs/img/monitor.png" width="340" alt="Monitor details"> |

| Arrange Displays | Manual |
|---|---|
| <img src="docs/img/arrange.png" width="420" alt="Arrange Displays"> | <img src="docs/img/manual.png" width="360" alt="Manual"> |

## Install

1. Download the latest **Deft.dmg** from [Releases](https://github.com/ninjait07/deft/releases/latest).
2. Open it and drag **Deft** to Applications.
3. Launch Deft and grant the permissions it asks for (see below).

The app is signed with a Developer ID and notarized by Apple, so it opens without security warnings.

Or with Homebrew:

```
brew tap ninjait07/deft https://github.com/ninjait07/deft
brew trust ninjait07/deft
brew install --cask deft
```

## Permissions & privacy

Deft works entirely on your Mac and collects nothing. It uses:

- **Accessibility** — move/resize windows and translate shortcuts.
- **Screen Recording** — draw live window previews (nothing is recorded or sent).
- **Input Monitoring** — tell a Windows keyboard from a Mac one.

The only network request Deft makes is checking for updates (a small public file on GitHub). See [PRIVACY.md](PRIVACY.md).

## Build from source

```
./build.sh                 # build + sign + launch (dev)
KNACK_VERSION=1.0 KNACK_BUILD=1 ./release.sh 1.0 1   # notarized release dmg
```

Requires macOS 13+, Xcode command-line tools, and a Developer ID for signing/notarizing. The whole app is a single Swift file: `Deft.swift`.

## Follow

Updates, demos and new projects are posted on the **[NonDev Facebook page](https://www.facebook.com/nondev07/)** — follow along, ask questions, or suggest features there.

## Support

Deft is free. If it makes your Mac feel like home, you can tip via PromptPay (in-app) or [GitHub Sponsors](https://github.com/sponsors/ninjait07). Thank you!

## License

[GPL-3.0](LICENSE) — crafted by Non Bannawat 🇹🇭
