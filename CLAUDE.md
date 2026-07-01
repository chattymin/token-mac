# PokeTokenBar — Claude 프로젝트 지침

## 릴리스 (자연어 트리거)

사용자가 **버전 배포를 자연어로 요청**하면 — 예: "배포해줘", "릴리스 올려줘", "패치 배포",
"2.1.1 배포", "release", "다음 버전 내줘" — 한 줄 명령을 시키지 말고 아래를 직접 수행한다.

1. **문서 일관성 검토**: `./scripts/release.sh --check-only` 실행. 경고(README/랜딩/cask 의
   stale 버전·제거된 의존성 등)가 있으면 **먼저 문서를 갱신**한다 — README.md/ko/ja, gh-pages
   랜딩 `index.html`(3개 언어 i18n 사전 정합 유지), homebrew-tap cask caveat. (`RELEASE.md` 체크리스트)
2. **버전 결정**: 사용자가 버전을 명시하면 그 값으로 바로 진행. 미명시면 `scripts/build-app.sh` 의
   현재 `VERSION` 기준 다음 패치(기능 추가 릴리스면 마이너)를 제안하고 확인받은 뒤 진행.
3. **릴리스 노트 작성** 후 실행 (반드시 `main` 브랜치에서):
   ```bash
   # 직전 릴리스 이후 변경을 요약해 노트 파일 작성
   PTB_NOTES_FILE=/tmp/ptb-notes.md ./scripts/release.sh <version>
   ```
   스크립트가 test-gate → 문서검토 → 범프 → 빌드검증 → 커밋·push → GitHub Release → cask → Pages 를 순서대로 수행.
4. **검증**: 완료 후 `brew upgrade --cask poke-token-bar` 로 실제 업그레이드 동작 확인.

릴리스는 외부 공개(비가역)이므로 실행 직전 **적용할 버전과 노트 요약을 한 번 보여준 뒤** 진행한다.
세부 절차·체크리스트는 `RELEASE.md` 참고.
