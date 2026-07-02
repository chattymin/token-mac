<div align="center">

<img src="assets/icon.png" width="128" alt="PokeTokenBar 아이콘">

# PokeTokenBar

**당신의 AI 코딩 토큰을 포켓몬으로 — 메뉴바에서.**

[![Release](https://img.shields.io/github/v/release/chattymin/PokeTokenBar?color=444d56&label=release)](https://github.com/chattymin/PokeTokenBar/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-0969da)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-f05138)](https://swift.org)
[![Homebrew](https://img.shields.io/badge/Homebrew-cask-8957e5)](#homebrew)
[![License](https://img.shields.io/badge/license-MIT-3fb950)](LICENSE)

[English](README.md) · **한국어** · [日本語](README.ja.md)

</div>

PokeTokenBar는 오늘 사용한 AI 코딩 토큰(Claude Code · Codex)을 macOS 메뉴바에 보여주고, 그 사용량을 자라나는 **포켓몬 companion**으로 바꿔줍니다. 토큰을 쓰면 알이 부화하고, 실제 진화 라인을 따라 진화하며, 최종 진화 후 도감에 졸업하고, 다시 새 알이 시작됩니다.

> 토큰 사용량은 로컬 Claude Code·Codex 로그에서 직접 읽습니다(`totalTokens` = input + output + cache, 로컬 날짜) — 외부 CLI 불필요. 비공식·비상업 포켓몬 팬 프로젝트 — [라이선스 & 면책](#라이선스--면책) 참고.

## 왜

- 오늘의 토큰 사용량과 비용을 한눈에 — 대시보드도, 브라우저 탭도 필요 없이.
- 공식 **5시간 / 주간** 한도를 리셋 카운트다운과 함께 추적하고, 현재 burn rate로 언제 도달할지 예측합니다.
- …그리고 열어보는 게 즐거워집니다: 사용량이 포켓몬을 키우고, 진화시키고, 졸업시켜 도감을 채웁니다.

## 화면

<table>
<tr>
<td width="50%" valign="top">
<img src="assets/screenshot-home.gif" alt="팝오버 홈"><br>
<b>홈</b> — companion·진화 진행, 오늘 토큰(Claude Code + Codex, 비용 포함), 공식 5h/주간 한도 바.
</td>
<td width="50%" valign="top">
<img src="assets/screenshot-collection.png" alt="컬렉션 / 도감"><br>
<b>컬렉션(도감)</b> — 졸업한 포켓몬을 희귀도순으로, 전체 진화 라인과 획득일과 함께.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="assets/screenshot-empty.gif" alt="빈 도감"><br>
<b>빈 도감</b> — 움직이는 마스코트가 시작을 안내합니다.
</td>
<td width="50%" valign="top">
<img src="assets/menubar.gif" width="200" alt="메뉴바"><br>
<b>메뉴바</b> — 움직이는 companion + 오늘 토큰 합계. 설정에서 비용($)·한도 % 추가 가능.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="assets/settings.png" alt="설정"><br>
<b>설정</b> — 메뉴바 표시 항목(토큰/비용/한도 %), 새로고침 간격, 로그인 시 자동 시작, Keychain 끄기, 알림 임계값.
</td>
<td width="50%" valign="top"></td>
</tr>
</table>

## Companion

- **부화 & 진화** — 알은 [PokéAPI](https://pokeapi.co/)에서 실시간으로 받아온 포켓몬으로 부화하고, 설치 이후 사용한 토큰으로 실제 진화 트리(1/2/3단, 분기)를 따라 진화합니다.
- **희귀도 가중** — common은 자주, legendary는 드물게 부화합니다. 희귀할수록 졸업까지 더 많은 토큰이 듭니다(헤비 유저 기준 common ≈3일 → legendary ≈24일).
- **졸업 & 수집** — 최종 진화 + 임계 도달 시 **도감**에 졸업하고, 새 알이 도착합니다.
- **애니메이션** — Gen-V 스프라이트가 메뉴바와 팝오버에서 움직입니다. 이름·UI는 **한국어 / 영어 / 일본어**.

## 기능

- **실시간 토큰 사용량** — 오늘의 Claude Code + Codex 토큰, 1–15분 간격(또는 수동)으로 갱신.
- **메뉴바 커스터마이즈** — 오늘 토큰(compact, 예: `200.7M`)·오늘 비용($)·공식 한도 % 를 원하는 조합으로 companion 옆에 표시 — 전부 끄면 캐릭터만 남습니다.
- **공식 한도** — Claude·Codex 5시간 / 주간 사용률과 리셋 카운트다운.
- **소진 예측** — 현재 5시간 창이 100%에 도달할 시각 예측.
- **성장 companion + 도감** — 매일 열어보고 싶어지는 부분.
- **현지화** — KO / EN / JA UI와 포켓몬 이름 완비.
- **알림** — 한도 경고/임박 임계값(슬라이더 조절) 알림 + companion 이벤트(부화/진화/졸업) 알림 선택.
- **편의 기능** — 로그인 시 자동 시작, 인앱 업데이트 확인(설정에 현재 버전 표시), Keychain 끄기(한도 섹션만 숨김).

## 설치

### 요구사항

macOS 14+ (Apple Silicon 또는 Intel). 끝입니다 — 토큰 사용량은 로컬 Claude Code/Codex 로그에서 직접 읽으며 외부 CLI가 필요 없습니다.

### Homebrew

```bash
brew install --cask chattymin/tap/poke-token-bar
```

ad-hoc/자체 서명 앱이라 Cask 설치 시 격리 속성을 자동 제거합니다.

### 소스 빌드

```bash
swift build                  # 디버그
swift test                   # 단위 테스트
./scripts/build-app.sh       # release → PokeTokenBar.app → /Applications
```

## 데이터 소스

| 소스 | 용도 | 비고 |
|---|---|---|
| `~/.claude/projects/**/*.jsonl` | Claude Code daily/blocks/weekly/monthly | 직접 읽음; 메시지 id 로 중복제거; 증분 캐시 |
| `~/.codex/sessions/**/*.jsonl` | Codex daily/monthly | `token_count` 이벤트; 주간 = daily 합산 |
| Keychain → `oauth/usage` | Claude 공식 5h/주간 % | 비공식 endpoint; Keychain 프롬프트 1회 후 캐시 |
| `codex app-server` | Codex 공식 5h/주간 % | 계정 snapshot만; 모델 turn 없음 |
| [PokéAPI](https://pokeapi.co/) | 포켓몬 종·진화·스프라이트 | 런타임 fetch; 로컬 캐시, 번들 안 함 |

## 프라이버시 & 권한

- **온디바이스.** 토큰 사용량은 로컬 Claude Code/Codex 로그에서 직접 읽으며, 앱은 `claude`/`codex` 모델 turn을 실행하지 않고 사용량만 읽습니다.
- **Keychain(선택).** 공식 한도를 보여주려면 Claude OAuth 자격증명을 **1회**(비밀번호 프롬프트 1번) 읽고, 앱 자체 Keychain 항목에 캐시해 재사용합니다. 설정에서 끄면 한도 섹션만 숨겨집니다.
- **포켓몬 에셋**은 런타임에 PokéAPI에서 받아오며 `~/Library/Application Support/PokeTokenBar/`에만 캐시됩니다. 저작물은 레포나 릴리스에 번들하지 않습니다.

## 라이선스 & 면책

**MIT** — [LICENSE](LICENSE) 참고. MIT는 본 프로젝트의 소스 코드에만 적용됩니다.

비공식·비상업 팬 프로젝트입니다. **Nintendo, Game Freak, The Pokémon Company와 제휴·보증·후원·승인 관계가 없습니다.** Pokémon 및 포켓몬 캐릭터 이름은 Nintendo의 상표이며, 포켓몬 이름·데이터·스프라이트는 © Nintendo / Game Freak / The Pokémon Company로 식별 목적의 런타임 사용입니다.
