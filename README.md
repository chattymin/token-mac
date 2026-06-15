# TokenMac

오늘 사용한 AI 코딩 토큰량을 macOS 상태바에 표시하는 메뉴바 앱.
집계 기준은 [ccusage](https://github.com/ryoppippi/ccusage) `totalTokens`
(input + output + cache_creation + cache_read, 로컬 날짜)이다.

- Claude Code / Codex 토큰·비용을 상태바에 실시간 표시
- 5시간 세션·주간 한도(%) 및 리셋 카운트다운 (Claude 공식 OAuth usage endpoint)
- 현재 burn rate 기반 한도 소진 시각 예측
- 임계값 초과 시 알림
- burn rate에 따라 회전 속도가 변하는 메뉴바 코인 애니메이션

## 사전 요구사항

`ccusage`가 PATH(또는 Homebrew 경로)에 설치되어 있어야 한다.

```bash
npm install -g ccusage
# Codex 사용량도 보려면 ccusage-codex 추가 설치
```

탐색 경로: `/opt/homebrew/bin` → `/usr/local/bin`. 미설치 시 해당 provider는 UI에서 자동 숨김.

## 설치

### Homebrew (예정)

```bash
brew install --cask chattymin/tap/token-mac
```

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
| `ccusage-codex` | Codex daily | 데이터 없으면 UI에서 자동 숨김 |
| Keychain `Claude Code-credentials` → `api.anthropic.com/api/oauth/usage` | 공식 5h/주간 한도 % | 비공식 endpoint — 실패 시 한도 섹션만 숨김. 최초 실행 시 Keychain 접근 허용 필요 |

설계 원칙: `claude`/`codex` 등 AI CLI 바이너리는 절대 스폰하지 않는다 (ccusage 파서만 호출 — CodexBar issue #874 토큰 드레인 사고 교훈). Process 호출 지점은 `Sources/TokenMac/Core/ProcessRunner.swift` 단일.

## 검증

```bash
./scripts/parity-check.sh    # 앱 표시값 == ccusage 재계산값 대조 (오차 0 기대)
```

## provider 확장

`Sources/TokenMac/Core/UsageProvider.swift` protocol 구현체를 추가하고 `UsageStore.init`의 providers 배열에 등록.

## License

MIT — see [LICENSE](LICENSE).
