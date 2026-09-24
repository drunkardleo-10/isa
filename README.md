<div align="center">
  <img src="Assets/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" height="128" alt="isa logo" />
  <h1>isa</h1>

  <p><strong>A blazingly fast, minimalist, memory-efficient macOS web browser.</strong></p>

  <p>
    <a href="#features">Features</a>
    ·
    <a href="#install">Install</a>
    ·
    <a href="#build-from-source">Build from Source</a>
    ·
    <a href="#keyboard-shortcuts">Shortcuts</a>
  </p>

  <p>
    <img src="https://img.shields.io/badge/platform-macOS%2014.0%2B-000000?style=flat&logo=apple&logoColor=white" alt="Platform: macOS 14+" />
    <img src="https://img.shields.io/badge/Swift-5.0-FA7343?style=flat&logo=swift&logoColor=white" alt="Swift 5" />
    <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-007AFF?style=flat" alt="SwiftUI + AppKit" />
    <img src="https://img.shields.io/badge/Engine-WebKit-FF6F00?style=flat&logo=safari&logoColor=white" alt="WebKit" />
    <img src="https://img.shields.io/badge/AdBlock-Built--in-34C759?style=flat" alt="Built-in AdBlock" />
    <img src="https://img.shields.io/badge/Memory-~150MB%20Baseline-success?style=flat" alt="Memory Baseline" />
    <img src="https://img.shields.io/badge/Telemetry-Zero-lightgrey?style=flat" alt="No Telemetry" />
  </p>
</div>

---

**isa** is a lightweight, open-source web browser built natively for macOS using Swift, SwiftUI, AppKit, and WebKit (`WKWebView`). Engineered specifically to solve the extreme memory hogging and battery drain of Chromium and Electron browsers, isa combines an intelligent tab-decay engine, shared WebKit process pooling, built-in network and cosmetic ad blocking, YouTube video ad defusal scriptlets, and a distraction-free Zen interface.

No accounts. No telemetry. No background bloat. Just the web, at native speed.

---

## Features

### Intelligent Memory Management & Performance
- **Aggressive Tab Decay**: Inactive tabs automatically enter deep sleep after idle timeouts, releasing their underlying WebContent processes and reclaiming memory.
- **Shared `WKProcessPool`**: All tabs share a unified WebKit process pool, reducing process duplication across multiple open pages.
- **Concurrency Limiting**: Background tabs do not spin up heavy WebContent processes until focused, avoiding memory spikes when opening batches of tabs.
- **Instant Tab Restoration**: Sleeping tabs retain their title, address, favicon, and state, restoring effortlessly when brought to the foreground.
- **Auto-Play Suppression**: Inactive tabs are prevented from decoding video and buffering audio before user interaction.

### Native Ad & Tracker Blocking
- **Network Request Blocking**: Over 145,000 compiled rules from EasyList and EasyPrivacy compiled into native `WKContentRuleList` bytecode, blocking ads, analytics, trackers, and fingerprinting scripts before network transmission.
- **Cosmetic Element Hiding**: Injects domain-targeted CSS rules at `document_start` to collapse empty ad banners, sponsors, and cookie prompts without Flash of Unstyled Content (FOUC).
- **YouTube In-Stream Video Ad Defusal**: Built-in uBlock Origin-compatible scriptlet pipeline hooks `ytInitialPlayerResponse` and fetch/XHR player endpoints to eliminate prerolls and midrolls.
- **Full CSP & Trusted Types Compliance**: Injected scripts avoid `eval()` or dynamic script generation, safely adhering to strict site security policies.
- **One-Time Bytecode Compilation**: Rules compile once to disk; startup requires only ~22 MB of host memory and zero per-tab compilation overhead.

### Zen Mode & Distraction-Free UI
- **Flexible Tab Layout**: Toggle instantly between a modern **Left Sidebar** and classic **Top Bar** tabs (`Cmd+Option+T`).
- **Collapsible Sidebar**: Collapse the tab bar to maximize your viewable webpage area.
- **Animated Theme Switching**: Fluid toggle between Light, Dark, and System appearances with smooth spring physics.
- **Minimalist Chrome**: Hidden titlebar, clean URL overlay, and distraction-free navigation.

### Tab & Window Controls
- **Persistent Pinned Tabs**: Pin critical tabs (`Cmd+Shift+P`); pins automatically persist across app launches.
- **Per-Tab Audio Muting**: Instantly silence noisy background tabs from the tab item or using `Cmd+Shift+M`.
- **Drag-and-Drop Reordering**: Smooth tab drag-and-drop support with animated reordering.
- **Numbered Tab Selection**: Jump directly to any of your first 9 tabs with `Cmd+1` through `Cmd+9`.

### Built-in Essentials
- **In-Page Find Bar (`Cmd+F`)**: Native search overlay with real-time match counts, instant highlights, and keyboard traversal (`Enter` / `Shift+Enter`).
- **Download Manager**: Native floating downloads popover with progress bars, Finder reveals, and cancellation.
- **Searchable History (`Cmd+Y`)**: Fast browsing history with instant search filtering, date grouping, and one-click history clearing.
- **Customizable Shortcuts (`Cmd+/`)**: Comprehensive shortcut manager and HUD for keyboard-first navigation.

### Privacy-First
- Zero analytics, telemetry, or remote crash reporters.
- No mandatory accounts, logins, or cloud syncing.
- Your browsing data stays entirely on your local machine.

---

## Memory Audit & Benchmarks

Audits measured against 25 active tabs:

| Scenario | Live WebContent Procs | WebKit Total RSS | Host App RSS |
|---|---|---|---|
| **1 active tab (idle)** | 1 proc | ~151 MB | ~134 MB |
| **2 active tabs (idle)** | 2 procs | ~178 MB | ~142 MB |
| **25 tabs with tab decay enabled** | 2 procs (23 sleeping) | **~178 MB** | **~156 MB** |
| *Typical Chrome / Arc (25 tabs)* | *20–25 procs* | *2,500–4,500 MB* | *400–800 MB* |

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd + T` | New Tab |
| `Cmd + W` | Close Active Tab |
| `Cmd + 1` .. `Cmd + 9` | Select Tab 1 through 9 |
| `Cmd + L` | Focus Address Bar |
| `Cmd + R` | Reload Page |
| `Cmd + [` / `Cmd + ]` | Navigate Back / Forward |
| `Cmd + F` | Find in Page |
| `Cmd + G` / `Cmd + Shift + G` | Find Next / Previous Match |
| `Cmd + Shift + M` | Mute / Unmute Active Tab |
| `Cmd + Y` | Show Browsing History |
| `Cmd + Option + T` | Toggle Tab Placement (Sidebar / Top) |
| `Cmd + Shift + B` | Run 25-Tab Benchmark Sequence |
| `Cmd + Shift + U` | Open 25 Sample Tabs |

---

## Install

### Download Pre-Built DMG

Download the latest release from the [Releases](https://github.com/drunkardleo/isa/releases) page. Open `isa.dmg` and drag `isa.app` to your Applications folder.

### Requirements
- **macOS Sonoma (14.0)** or later
- Apple Silicon (M1/M2/M3/M4) or Intel Mac

---

## Build from Source

### Prerequisites
- macOS 14.0+
- Xcode 15.0+ or Command Line Tools
- Swift 5.0+
- Rust toolchain (optional, only required if rebuilding the adblock converter)

### 1. Clone the repository
```bash
git clone https://github.com/drunkardleo/isa.git
cd isa
```

### 2. Build Debug Application
```bash
make build
```
Or directly with `xcodebuild`:
```bash
xcodebuild -project isa.xcodeproj -scheme isa -configuration Release build
```

### 3. Package DMG
```bash
make dmg
```
The resulting `isa.dmg` will be created in your root directory.

---

## Developer Tooling

### Updating Adblocker Rules
The adblocker rules and cosmetic scripts are compiled ahead of time into `rules/` using an offline Rust CLI powered by the `adblock` engine.

To fetch the latest EasyList, EasyPrivacy, and uBlock Origin rule lists and compile them:
```bash
./generate_rules.sh
```

This script:
1. Downloads the latest rule sets from upstream repositories.
2. Uses `tools/rule-converter` to transform ABP syntax into WebKit content-blocking JSON rules and domain-specific cosmetic CSS.
3. Validates compilation against WebKit's native `WKContentRuleListStore`.
4. Outputs optimized JSON to `rules/content-blocker.json`, `rules/cosmetic-filters.json`, and `rules/scriptlets.json`.

---

## Tech Stack

| Component | Technology |
|---|---|
| **App Framework** | Swift 5.0, SwiftUI, AppKit |
| **Web Engine** | WebKit (`WKWebView`, `WKProcessPool`, `WKContentRuleListStore`) |
| **Project Management** | XcodeGen (`project.yml`) & Xcode Project |
| **Rule Compiler** | Rust (`tools/rule-converter` using `adblock` crate) |
| **Styling & Assets** | SF Symbols, Custom Vector SVGs, xcassets |

---

## Contributing

Contributions, bug reports, and suggestions are welcome!
1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Test your changes thoroughly
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
