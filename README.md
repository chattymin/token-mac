<div align="center">

<img src="assets/icon.png" width="128" alt="PokeTokenBar icon">

# PokeTokenBar

**Your AI coding tokens, hatched into Pokémon — right in your menu bar.**

[![Release](https://img.shields.io/badge/release-v2.0.0-444d56)](https://github.com/chattymin/poke-token-bar/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-0969da)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-f05138)](https://swift.org)
[![Homebrew](https://img.shields.io/badge/Homebrew-cask-8957e5)](#homebrew)
[![License](https://img.shields.io/badge/license-MIT-3fb950)](LICENSE)

**English** · [한국어](README.ko.md) · [日本語](README.ja.md)

</div>

PokeTokenBar shows how many AI coding tokens you've burned today — Claude Code & Codex — in your macOS menu bar, and turns that usage into a growing **Pokémon companion**. Spend tokens, hatch an egg, evolve it through its real evolution line, graduate it into your Pokédex, and start again.

> Token accounting is powered by [ccusage](https://github.com/ryoppippi/ccusage) (`totalTokens` = input + output + cache, local date). Unofficial, non-commercial Pokémon fan project — see [License & disclaimer](#license--disclaimer).

## Why

- See today's token spend & cost at a glance — no dashboard, no browser tab.
- Track official **5-hour / weekly** limits with reset countdowns and a burn-rate forecast for when you'll hit them.
- …and actually enjoy opening it: your usage raises a Pokémon that evolves, graduates, and fills a Pokédex.

## Screenshots

<table>
<tr>
<td width="50%" valign="top">
<img src="assets/screenshot-home.png" alt="Popover home"><br>
<b>Home</b> — companion + evolution progress, today's tokens (Claude Code + Codex with cost), and official 5h/weekly limit bars.
</td>
<td width="50%" valign="top">
<img src="assets/screenshot-collection.png" alt="Collection / Pokédex"><br>
<b>Collection (Pokédex)</b> — graduated Pokémon, sorted by rarity, with full evolution lines and capture dates.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="assets/screenshot-empty.png" alt="Empty Pokédex"><br>
<b>Empty Pokédex</b> — an animated mascot nudges you to start.
</td>
<td width="50%" valign="top">
<img src="assets/menubar.png" width="200" alt="Menu bar"><br>
<b>Menu bar</b> — animated companion + today's total tokens (compact).
</td>
</tr>
</table>

## The companion

- **Hatch & evolve** — eggs hatch into Pokémon fetched live from [PokéAPI](https://pokeapi.co/); tokens spent since install evolve them through their real tree (1/2/3 stages, branching).
- **Rarity-weighted** — common hatch often, legendary rarely; rarer Pokémon take more tokens to graduate (≈3 days common → ≈24 days legendary at heavy use).
- **Graduate & collect** — reach the final evolution + threshold and it graduates to your **Pokédex**; a fresh egg arrives.
- **Animated** — Gen-V sprites animate in the menu bar and popover. Names & UI in **Korean / English / Japanese**.

## Features

- **Live token usage** — today's Claude Code + Codex tokens (compact, e.g. `200.7M`), with optional cost ($) and limit % in the menu bar.
- **Official limits** — Claude & Codex 5-hour / weekly utilization with reset countdowns.
- **Burn-rate forecast** — projects when the current 5h window hits 100%.
- **Growth companion + Pokédex** — the part you actually look forward to.
- **Localized** — full KO / EN / JA UI and Pokémon names.
- **Notifications** — alerts when a limit crosses your warning / critical thresholds.

## Install

### Requirements

macOS 14+ (Apple Silicon or Intel), and [ccusage](https://github.com/ryoppippi/ccusage) on your PATH:

```bash
npm install -g ccusage
```

### Homebrew

```bash
brew install --cask chattymin/tap/poke-token-bar
```

ad-hoc/self-signed; the cask strips the quarantine attribute on install.

### Build from source

```bash
swift build                  # debug
swift test                   # unit tests
./scripts/build-app.sh       # release → PokeTokenBar.app → /Applications
```

## Data sources

| Source | Used for | Notes |
|---|---|---|
| `ccusage` | Claude Code daily/blocks/weekly/monthly | hidden if absent; supports ccusage 18.x & 20.x |
| `ccusage codex` | Codex daily/monthly | weekly = daily sum (no `codex weekly`) |
| Keychain → `oauth/usage` | Claude official 5h/weekly % | unofficial endpoint; single Keychain prompt, then cached |
| `codex app-server` | Codex official 5h/weekly % | account snapshot only; no model turn |
| [PokéAPI](https://pokeapi.co/) | Pokémon species, evolution, sprites | runtime fetch; cached locally, never bundled |

## Privacy & permissions

- **On-device.** Usage is parsed by ccusage; the app never runs `claude`/`codex` model turns, only reads usage.
- **Keychain (optional).** To show official limits it reads the Claude OAuth credential **once** (a single password prompt), then caches it in the app's own Keychain item for reuse. Turn it off in Settings — the limits section simply hides.
- **Pokémon assets** are fetched at runtime from PokéAPI and cached only under `~/Library/Application Support/PokeTokenBar/`. Nothing copyrighted is bundled in this repository or its releases.

## License & disclaimer

**MIT** — see [LICENSE](LICENSE). The MIT license covers this project's source code only.

This is an unofficial, non-commercial fan project. It is **not affiliated with, endorsed, sponsored, or approved by Nintendo, Game Freak, or The Pokémon Company.** Pokémon and Pokémon character names are trademarks of Nintendo; Pokémon names, data, and sprites are © Nintendo / Game Freak / The Pokémon Company and are fetched at runtime for identification only.
