<div align="center">

<img src="assets/icon.png" width="128" alt="PokeTokenBar アイコン">

# PokeTokenBar

**あなたのAIコーディングトークンを、ポケモンに — メニューバーで。**

[![Release](https://img.shields.io/github/v/release/chattymin/PokeTokenBar?color=444d56&label=release)](https://github.com/chattymin/PokeTokenBar/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-0969da)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-f05138)](https://swift.org)
[![Homebrew](https://img.shields.io/badge/Homebrew-cask-8957e5)](#homebrew)
[![License](https://img.shields.io/badge/license-MIT-3fb950)](LICENSE)

[English](README.md) · [한국어](README.ko.md) · **日本語**

</div>

PokeTokenBar は、今日使ったAIコーディングトークン（Claude Code・Codex）を macOS メニューバーに表示し、その使用量を育っていく **ポケモンのパートナー** に変えます。トークンを使うとタマゴが孵化し、実際の進化ラインに沿って進化し、最終進化後に図鑑へ卒業して、また新しいタマゴが始まります。

> トークン使用量はローカルの Claude Code・Codex ログから直接読み取ります（`totalTokens` = input + output + cache、ローカル日付）— 外部 CLI 不要。非公式・非商用のポケモンファンプロジェクトです — [ライセンス & 免責](#ライセンス--免責) を参照。

## なぜ

- 今日のトークン使用量とコストを一目で — ダッシュボードもブラウザタブも不要。
- 公式の **5時間 / 週間** 上限をリセットのカウントダウンとともに追跡し、現在の burn rate でいつ到達するかを予測します。
- …そして開くのが楽しくなります：使用量がポケモンを育て、進化させ、卒業させて図鑑を埋めます。

## スクリーンショット

<table>
<tr>
<td width="50%" valign="top">
<img src="assets/screenshot-home.gif" alt="ポップオーバー ホーム"><br>
<b>ホーム</b> — パートナー・進化の進捗、今日のトークン（Claude Code + Codex、コスト付き）、公式の5h/週間上限バー。
</td>
<td width="50%" valign="top">
<img src="assets/screenshot-collection.png" alt="コレクション / 図鑑"><br>
<b>コレクション（図鑑）</b> — 卒業したポケモンをレア度順に、進化ライン全体と捕獲日とともに。
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="assets/screenshot-empty.gif" alt="空の図鑑"><br>
<b>空の図鑑</b> — 動くマスコットが始め方を案内します。
</td>
<td width="50%" valign="top">
<img src="assets/menubar.gif" width="200" alt="メニューバー"><br>
<b>メニューバー</b> — 動くパートナー + 今日のトークン合計。設定でコスト($)・上限 % も追加できます。
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="assets/settings.png" alt="設定"><br>
<b>設定</b> — メニューバー表示項目（トークン／コスト／上限 %）、更新間隔、ログイン時に起動、Keychain オフ、通知の閾値。
</td>
<td width="50%" valign="top"></td>
</tr>
</table>

## パートナー

- **孵化 & 進化** — タマゴは [PokéAPI](https://pokeapi.co/) からリアルタイムで取得したポケモンに孵化し、インストール以降に使ったトークンで実際の進化ツリー（1/2/3段階、分岐）に沿って進化します。
- **レア度による重み付け** — common はよく、legendary はまれに孵化します。レアなほど卒業までに多くのトークンが必要です（ヘビーユーザーで common ≈3日 → legendary ≈24日）。
- **卒業 & 収集** — 最終進化 + 閾値に到達すると **図鑑** に卒業し、新しいタマゴが届きます。
- **アニメーション** — Gen-V スプライトがメニューバーとポップオーバーで動きます。名前・UIは **韓国語 / 英語 / 日本語**。

## 機能

- **リアルタイムのトークン使用量** — 今日の Claude Code + Codex トークンを 1–15分間隔（または手動）で更新。
- **メニューバーを自分好みに** — 今日のトークン（compact、例：`200.7M`）・今日のコスト($)・公式上限 % を好きな組み合わせでパートナーの隣に表示 — すべてオフにするとキャラクターだけに。
- **公式の上限** — Claude・Codex の 5時間 / 週間 使用率とリセットのカウントダウン。
- **消費予測** — 現在の5時間ウィンドウが100%に達する時刻を予測。
- **育成パートナー + 図鑑** — 毎日開きたくなる部分。
- **多言語対応** — KO / EN / JA の UI とポケモン名。
- **通知** — 上限の警告／危険の閾値（スライダーで調整）による通知に加え、パートナーのイベント（孵化／進化／卒業）通知も選べます。
- **便利機能** — ログイン時に自動起動、アプリ内アップデート確認（設定に現在のバージョンを表示）、Keychain オフ（上限セクションのみ非表示）。

## インストール

### 必要条件

macOS 14+（Apple Silicon または Intel）。それだけ — トークン使用量はローカルの Claude Code / Codex ログから直接読み取り、外部 CLI は不要です。

### Homebrew

```bash
brew install --cask chattymin/tap/poke-token-bar
```

ad-hoc／自己署名アプリのため、Cask インストール時に隔離属性を自動で除去します。

### ソースからビルド

```bash
swift build                  # デバッグ
swift test                   # ユニットテスト
./scripts/build-app.sh       # release → PokeTokenBar.app → /Applications
```

## データソース

| ソース | 用途 | 備考 |
|---|---|---|
| `~/.claude/projects/**/*.jsonl` | Claude Code daily/blocks/weekly/monthly | 直接読み取り；メッセージ id で重複排除；増分キャッシュ |
| `~/.codex/sessions/**/*.jsonl` | Codex daily/monthly | `token_count` イベント；週間 = daily 合算 |
| Keychain → `oauth/usage` | Claude 公式 5h/週間 % | 非公式 endpoint；Keychain プロンプト1回後にキャッシュ |
| `codex app-server` | Codex 公式 5h/週間 % | アカウント snapshot のみ；モデル turn なし |
| [PokéAPI](https://pokeapi.co/) | ポケモンの種・進化・スプライト | ランタイム取得；ローカルキャッシュ、バンドルしない |

## プライバシー & 権限

- **オンデバイス。** トークン使用量はローカルの Claude Code / Codex ログから直接読み取り、アプリは `claude`/`codex` のモデル turn を実行せず、使用量のみ読み取ります。
- **Keychain（任意）。** 公式の上限を表示するため、Claude OAuth 資格情報を **1回**（パスワードのプロンプト1回）読み取り、アプリ自身の Keychain 項目にキャッシュして再利用します。設定でオフにすると上限セクションが非表示になります。
- **ポケモンのアセット** はランタイムに PokéAPI から取得し、`~/Library/Application Support/PokeTokenBar/` にのみキャッシュされます。著作物はこのリポジトリやリリースにバンドルしません。

## ライセンス & 免責

**MIT** — [LICENSE](LICENSE) を参照。MIT は本プロジェクトのソースコードのみを対象とします。

非公式・非商用のファンプロジェクトです。**任天堂、ゲームフリーク、株式会社ポケモンとの提携・推奨・後援・承認はありません。** ポケモンおよびポケモンのキャラクター名は任天堂の商標であり、ポケモンの名前・データ・スプライトは © Nintendo / Game Freak / The Pokémon Company で、識別目的のランタイム利用です。
