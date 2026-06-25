# TokenMac

오늘 사용한 AI 코딩 토큰량을 macOS 상태바에 표시하는 메뉴바 앱.
집계 기준은 [ccusage](https://github.com/ryoppippi/ccusage) `totalTokens`
(input + output + cache_creation + cache_read, 로컬 날짜)이다.

<p align="center">
  <img src="assets/screenshot.png" width="400" alt="TokenMac 팝오버 — 오늘 토큰량, provider/토큰타입 분해, 주·월 누적, 공식 5h/주간 한도와 소진 예측">
</p>

- Claude Code / Codex 토큰·비용을 상태바에 실시간 표시
- Claude Code / Codex 5시간 세션·주간 한도(%) 및 리셋 카운트다운
- 현재 burn rate 기반 한도 소진 시각 예측
- 임계값 초과 시 알림
- 토큰 사용량으로 성장하는 메뉴바 companion 캐릭터 (포켓몬, 한/영/일)

## 메뉴바 표시

메뉴바에는 companion 캐릭터(부화 전엔 알 🥚)와 **오늘 사용한 토큰 합계**(compact 표기)가 나타난다.

<img src="assets/menubar.png" width="130" alt="메뉴바의 TokenMac — companion 캐릭터 + 오늘 토큰 합계">

- **숫자** — 오늘 모든 provider(Claude Code·Codex) 합산 토큰. `200.7M` = 200,700,000 (`K`/`M`/`B` 단위).
- **캐릭터** — 설치 이후 토큰 사용량으로 진화하는 포켓몬. 가벼운 상하 bob 애니메이션. 자세한 동작은 [Companion](#companion-pokémon) 참조.
- 설정에서 **비용($)**, **한도(%)**도 메뉴바에 함께 표시할 수 있다.

아이콘을 클릭하면 위의 상세 팝오버가 열린다.

## 사전 요구사항

`ccusage`가 PATH(또는 Homebrew 경로)에 설치되어 있어야 한다.

```bash
npm install -g ccusage
```

탐색 경로: `/opt/homebrew/bin` → `/usr/local/bin`. 미설치 시 해당 provider는 UI에서 자동 숨김.

## 설치

### Homebrew

```bash
brew install --cask chattymin/tap/token-mac
```

ad-hoc/자체 서명 앱이라 Cask 설치 시 격리 속성을 자동 제거한다(postflight `xattr -cr`).

### 소스 빌드

```bash
swift build                  # 디버그 빌드
swift test                   # 단위 테스트
./scripts/build-app.sh       # release 빌드 → TokenMac.app 조립 → /Applications 설치
open /Applications/TokenMac.app
```

요구: macOS 14+, Swift 6 toolchain.

## 데이터 소스

| 소스 | 용도 | 비고 |
|---|---|---|
| `ccusage` | Claude Code daily/blocks/weekly/monthly | 미설치 시 숨김. ccusage 18.x·20.x 스키마 모두 지원 |
| `ccusage codex` | Codex daily/monthly | `ccusage codex weekly`가 없어서 주간은 daily 합산 |
| Keychain `Claude Code-credentials` → `api.anthropic.com/api/oauth/usage` | Claude 공식 5h/주간 한도 % | 비공식 endpoint — 실패 시 Claude 한도만 숨김. 최초 실행 시 Keychain 접근 허용 필요 |
| `codex app-server --stdio` → `account/rateLimits/read` | Codex 공식 5h/주간 한도 % | 모델 turn 없이 계정 한도 snapshot만 조회. 실패 시 Codex 한도만 숨김 |

설계 원칙: 사용량 집계는 `claude`/`codex` AI CLI를 직접 실행하지 않고 ccusage 파서만 호출한다. Codex 한도는 `codex app-server`의 account snapshot만 읽으며 모델 turn은 시작하지 않는다. Process 호출 지점은 `Sources/TokenMac/Core/ProcessRunner.swift` 단일.

## 검증

```bash
./scripts/parity-check.sh    # 앱 표시값 == ccusage 재계산값 대조 (오차 0 기대)
```

## provider 확장

`Sources/TokenMac/Core/UsageProvider.swift` protocol 구현체를 추가하고 `UsageStore.init`의 providers 배열에 등록.

## License

MIT — see [LICENSE](LICENSE). The MIT license covers this project's source code only.

## Companion (Pokémon)

The growth companion fetches Pokémon data and sprites at runtime from
[PokéAPI](https://pokeapi.co/); no Pokémon assets or data are bundled in this
repository or its releases. Cached files are stored only on the user's machine
under `~/Library/Application Support/TokenMac/`.

This is an unofficial, non-commercial fan project. It is **not affiliated with,
endorsed, sponsored, or approved by Nintendo, Game Freak, or The Pokémon
Company**. Pokémon and Pokémon character names are trademarks of Nintendo;
Pokémon names, data, and sprites are © Nintendo / Game Freak / The Pokémon
Company and are used at runtime for identification only.
