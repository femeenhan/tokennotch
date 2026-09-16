# 빌드정령 / Build Spirit

macOS 화면 위의 불꽃 대장장이 동반자. 일반 사용자는 캐릭터와 작은 생활 도구를, 개발자는 AI 작업 상태와 세션별 사용 기록을 사용한다.

## 개발 중 앱 실행

Finder에서 이 프로젝트 폴더의 **`빌드정령 실행.command`를 더블클릭**한다. 최신 코드를 Debug 빌드한 뒤 앱을 실행한다. 이미 실행 중이면 빌드 성공 후 정상 종료하고 다시 연다. 실행 후 터미널 창은 닫아도 된다. 메뉴 막대의 불꽃 아이콘에서 앱 메뉴를 사용할 수 있다.

Xcode 설치와 최초 실행 설정이 필요하다. 빌드 실패 시 오류가 터미널에 표시되며, 전체 로그는 `.build/launcher-build.log`에 저장된다. `.build`는 숨김 폴더이므로 Finder에서 `⌘⇧.`으로 표시를 전환할 수 있다.

터미널에서는 `./빌드정령\ 실행.command`로도 실행할 수 있다. 실행기 회귀 테스트는 `bash Tests/launcher_smoke.sh`로 확인한다.

현재 단계: macOS 로컬 앱, 파츠 기반 정령 동작, Codex 사용량 대시보드에 제공자별 정령과 화면 최대 3개 표시를 추가했다. Codex·Claude·Gemini·Grok의 CLI 훅 설정과 제공자별 상태·기록 분리를 구현했다. Codex 외 제공자의 계정 사용량 조회, 실제 CLI 전체 이벤트 실사용 검증, 서명·공증·배포는 아직 진행하지 않았다. [제공자별 정령 사용법](docs/providers.md), [알파 검증 기록](docs/alpha-results.md), [Codex CLI 호환성](docs/compatibility.md)을 참고한다.

- [상세 설계](docs/superpowers/specs/2026-09-15-build-spirit-design.md)
- [구현 계획](docs/superpowers/plans/2026-09-15-build-spirit.md)
- [개발 준비 점검](docs/readiness.md)
- [기본 동작 확인 방법 및 검증](docs/basic-motion-review.md)
- [픽셀 대시보드 사용법](docs/dashboard.md)

확정된 방향: 최초 A 캐릭터, macOS 직접 다운로드 설치, 구독 없는 1회 구매. 가격과 결제 사업자는 유료 테스트 후 결정한다.
