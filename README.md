# 빌드정령 / Build Spirit

macOS 화면 위의 불꽃 대장장이 동반자. 일반 사용자는 캐릭터와 작은 생활 도구를, 개발자는 AI 작업 상태와 세션별 사용 기록을 사용한다.

현재 단계: Task 1-3 구현을 완료했다. 코어, 일반 모드 macOS 로컬 알파, Codex CLI hooks 로컬 베타를 구현하고 사용자 `~/.codex/hooks.json`에 8종 command hook을 설치했다. 실제 CLI `/hooks` 신뢰 승인과 실사용 검증, Claude 연동 및 배포는 아직 진행하지 않았다. 검증 결과와 남은 제한은 [알파 검증 기록](docs/alpha-results.md)과 [Codex CLI 호환성](docs/compatibility.md)에 정리했다.

- [상세 설계](docs/superpowers/specs/2026-09-15-build-spirit-design.md)
- [구현 계획](docs/superpowers/plans/2026-09-15-build-spirit.md)
- [개발 준비 점검](docs/readiness.md)
- [기본 동작 확인 방법 및 검증](docs/basic-motion-review.md)
- [픽셀 대시보드 사용법](docs/dashboard.md)

확정된 방향: 최초 A 캐릭터, macOS 직접 다운로드 설치, 구독 없는 1회 구매. 가격과 결제 사업자는 유료 테스트 후 결정한다.
