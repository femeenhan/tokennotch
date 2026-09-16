# 빌드정령 상세 설계 v1

작성: 2026-09-15. 구현 기준 초안이며 출시 가격과 대응 도구 버전은 검증 후 확정한다.

## 1. 제품과 범위

확정 사항: 최초 A 불꽃 대장장이 캐릭터, macOS 다운로드 설치, 화면 위 애니메이션, 구독 없는 1회 결제. AI 하나만 사용하는 개발자도 고객이다. 현재 사용자 검증 순서에 맞춰 연동 우선순위는 Codex CLI → Claude Code → Cursor다.

제품 문구: “작업하는 당신 곁의 작은 불꽃 대장장이. AI를 연결하면 작업 상태와 사용 기록도 챙겨줍니다.”

일반 사용자에게는 캐릭터의 즐거움과 방해 없는 작은 편의를, 개발자에게는 쉬운 연결과 작업 상태·사용 기록 탐색을 제공한다. 두 구매 가설은 따로 검증한다. 코드 생존율, ROI 점수, 줄당 비용, 절감액은 제공하지 않는다. 커밋은 관련 기록이며 품질의 증거가 아니다. 코드 없는 조사·리뷰도 정상 활동이다.

로컬 알파: 캐릭터, 드래그·숨김·크기·소리, 타이머·리마인더, Codex 로컬 CLI 상태와 세션별 토큰·추정 비용, Git 관련 커밋 후보. 데모는 항상 명시하며 실제 데이터와 분리한다.
유료 v1: 알파·수요 검증 후 라이선스, 공증 DMG, 업데이트, 기기 해제 추가.
Codex는 검증된 로컬 CLI 훅 범위만 베타로 제공한다. Codex 데스크톱/IDE, Cursor GUI, SSH, 컨테이너, 클라우드 세션은 v1 제외.
계정, 클라우드 분석, 팀, AI 채팅, 결과물 선반, 범용 파일 감시, 브라우저 확장, 마켓, AI 실행·승인 제어, 전역 키 입력 감시는 제외한다.

## 2. 사용자 흐름

첫 실행: 정령 등장 → 조작 안내 → 그냥 함께하기 / AI 연결. 연결·권한을 거절해도 일반 모드는 유지한다.
캐릭터 클릭: 인사와 메뉴. 드래그: 모니터 작업 영역 안에서 이동.
타이머: 기본25분, 1~180분 설정, 한 번 완료 후 종료. 자동 반복 없음.
리마인더: 시각·짧은 문구 등록. 앱 종료 중에는 전달되지 않는다고 안내한다.
개발 연결: 도구 감지 → 접근 안내 → 저장소 선택 → 설정 변경 미리보기 → 승인 → 연결 검사.
홈 전체 스캔은 없으며 미수집 값은 0 대신 기록 없음으로 표시한다.
메뉴: 진행 세션, 확인 필요 세션, 오늘 사용 기록, 타이머, 설정, 숨기기.
복수 세션은 대표 상태와 개수를 표시하고 프로젝트별 목록을 연다.

판매 흐름 설계안: 다운로드·7일 체험 → 1회 구매 → 이메일 키 → 활성화. 구매 후 다운로드도 제공한다. 종료 후 기존 기록 읽기·내보내기는 유지하고 신규 기록·캐릭터 실행을 잠근다. 무료 영구판·복수 상품 등급은 v1에 없다.

## 3. 캐릭터 제작과 상태

기준 원본: /Users/cheolminhan/.codex/generated_images/01a0a432-5a66-7a03-bb7f-5c21f0f1f78a/exec-0cadc50d-1a47-4e9e-9e21-594b8b0ef58b.png

주황 불꽃, 짙은 망치·모루, 밝은 큐브, 최초 얼굴 비율 유지. 귀여운 버전 제외. 현재 PNG는 정적 콘셉트이며 애니메이션 자산이 아니다. 배경 제거와 몸·망치·모루·큐브 제작용 레이어가 필요하다.

| 상태 | 행동 | 프레임 목표 |
|---|---|---|
| idle | 불꽃 살랑임·눈 깜빡임 | 12프레임,12fps 반복 |
| working | 망치질 | 12프레임,12fps 반복 |
| attention | 망치 들고 바라봄 | 8프레임,8fps 반복 |
| completed | 큐브 들어 올림 | 12프레임,12fps 1회 |
| error | 고개 갸웃 | 8프레임,8fps 1회 |
| greeting | 손 흔들기 | 8프레임,8fps 1회 |
| sleeping | 모루에 기대 쉬기 | 8프레임,8fps 반복 |

스프라이트 셀256×256 RGBA PNG, 바닥 중앙 피벗, 동일 크기. manifest는 clip/frameCount/fps/loop를 기록한다. 표시 기본128pt,80~192pt. 초기 기술 검증은 정적 원본과 프로그램적 호흡을 사용할 수 있으나 완성 애니메이션으로 홍보하지 않는다.

우선순위: 숨김·수면 > 입력 필요 > 오류 > 작업 > 완료1회 > 대기. 리마인더는 별도 알림. 다른 세션이 작업 중이면 일부 완료로 전체 idle 전환 금지. Stop은 턴 종료이며 세션 종료·성공의 증거가 아니다.
소리 기본 끔, 시작 인사1회, 망치마다 소리 없음. 동작 줄이기 준수. 잠금·숨김은 렌더링 중단. 모니터 분리 시 주 모니터로 위치 보정. 전체 화면 앱에서는 기본 숨김. 다른 앱 포커스를 빼앗지 않는다.
토큰 사용량으로 성장 보상을 주지 않는다. 코드 삭제·변경 폐기를 실패로 표현하지 않는다.

## 4. 기술 구성

설계 선택: macOS14+, Swift6 언어 모드, AppKit NSPanel, SwiftUI 설정·기록, SpriteKit, SQLite3.
Universal arm64/x86_64 DMG 목표. 양쪽 빌드·실기 확인 후 지원 표기.
앱 프로세스 하나가 렌더링·수집·DB를 소유하며 관리자 데몬은 없다.
SpiritBridge 실행 파일이 원본 훅을 필터링해 사용자 전용 Unix socket으로 전달한다. 앱 부재 시 짧게 종료하며 AI를 막지 않는다. 원본 이벤트 디스크 큐 없음.
Core Swift Package는 swift test로 검사하고 AppKit 앱은 Xcode 타깃으로 만든다. DB 쓰기는 단일 actor. 추가 LLM 호출 없음.

흐름: Codex hooks → Bridge → socket → 정규화 → DB → 상태 reducer → 캐릭터·기록.
별도 usage 증분 파서와 GitObserver도 같은 DB에 메타데이터를 기록한다.

## 5. 이벤트 규격

내부 Event 필드: schemaVersion:Int=1, eventID:String, provider:String, sessionID:String, parentSessionID:String?, turnID:String?, kind:String, occurredAt:Date, receivedAt:Date, projectID:UUID?, worktreeID:UUID?, source:String, sourceVersion:String, payload:허용 메타데이터.

kind: sessionStarted,turnStarted,toolStarted,toolFinished,needsInput,turnStopped,sessionEnded,usageObserved,collectionInterrupted.
payload 허용: toolCategory,success,relativePath,modelID,usageCounts.
prompt,command 문자열,tool result,patch 본문은 저장하지 않는다. 원본 훅·로그는 메모리에서 일시 처리될 수 있음을 설명한다. 원문을 전혀 읽지 않는다는 표현은 금지한다.
eventID 중복 제거. 원본ID가 없으면 정규 메타데이터 해시. 세션 세대·turn으로 오래된 이벤트 덮어쓰기 방지.
120초 무관측은 마지막 관측 시각 표시이며 완료 추론 금지. 재시작 후 기존 활성 세션은 unknown. 절전 시간은 활성 시간에서 제외.

## 6. 어댑터와 설정

Codex 로컬 CLI 설치 버전과 공식 훅 스키마를 먼저 검사한다. SessionStart/UserPromptSubmit/PreToolUse/PostToolUse/PermissionRequest/Stop/Interrupt/SessionEnd 중 지원 이벤트만 연결한다. 권한·서브에이전트도 검증된 범위만 표시한다.
사용량은 동의한 세션 로그 usage 메타데이터를 증분 파싱한다. 안정 공식API로 간주하지 않는다. offset,파일 식별자,레코드ID로 중복·파일 교체를 처리한다. 미완성 마지막 행은 다음 읽기를 기다린다. 포맷 변경·미상 모델은 미산출. 원문 복사·연결 전 기록 자동 수집 없음.
기존 statusLine·OTel endpoint는 유지한다. OTel은 후속 대안이며 알파에 서버를 추가하지 않는다.
도구 capability는 status/usage/fileActivity. 미지원 값 null. CLI 지원을 GUI 지원으로 표현하지 않는다.

훅은 기존 JSON에 우리 항목만 추가, 변경 전 사용자 승인·백업, 원자적 기록. 손상 설정은 설치 거부. 제거 시 사용자 변경을 유지하고 우리 항목만 삭제한다. helper는 Application Support 고정 경로. 제거 후 자동 재설치 없음.

## 7. 사용량과 비용

공급자의 input/output/cacheRead/cacheWrite/reasoning 구분과 포함 관계를 보존한다. 누적·증분, 부모·서브에이전트 중복을 fixture로 검사한다.
가격표: provider,modelID,effectiveFrom,통화,단가,출처URL,확인일. 해당 시점 단가 없으면 미산출. 기본USD, 임의 원화 환산 없음.
observedUsage는 관측 토큰, apiEquivalentEstimate는 공개 가격 환산치이며 정액제 청구액이 아니다. reportedBilledAmount는 실제 청구 확인 자료만 가능하고 v1 기본 수집기는 만들지 않는다.
오늘/7일/30일·프로젝트·세션 필터. 사용자가 추정치임을 확인해 비용 경고를 켠다. 토큰으로 구독 잔여 한도·초기화 시각을 추정하지 않는다.

## 8. Git 관련 기록

등록 저장소 canonical path·git common directory로 식별하고 worktree별 HEAD·branch 분리. 등록 HEAD 이후만 관측. 활성10초·비활성60초 간격. 종료 중 변경에는 관측 공백 표시.
같은 worktree·세션 시간·변경 파일 교집합으로 관련 커밋 후보를 만든다. 사용자 확인/해제 가능. 중첩 세션은 복수 후보이며 비용을 중복 배분하지 않는다.
PR 병합 추론 없음. amend/rebase로 SHA가 사라지면 현재 브랜치에서 확인되지 않음 표시. SHA·부모SHA·경로·추가/삭제 수만 저장, 코드 본문 없음.
git은 인자 배열과 읽기 명령만 사용하고 외부 diff/textconv를 끈다.

## 9. 데이터와 보존

SQLite WAL·foreign keys ON·migration version. ~/Library/Application Support/BuildSpirit/ 사용자 전용 권한.

| 테이블 | 주요 필드 |
|---|---|
| projects | id,path,name,registeredAt |
| worktrees | id,projectID,path,branch,head |
| sessions | provider+sessionID,projectID,worktreeID,parentID,state,lastObservedAt |
| events | eventID PK,sessionID,kind,occurredAt,receivedAt,metadataJSON |
| usage_records | sourceRecordID PK,sessionID,modelID,countsJSON,estimateUSD,priceVersion |
| commits | projectID+sha,parentsJSON,committedAt,fileStatsJSON |
| session_commits | sessionID+sha,association(candidate/confirmed/dismissed),reason |
| source_cursors | sourceID PK,fileIdentity,offset,adapterVersion |
| reminders | id,dueAt,message,deliveredAt |
| settings | key PK,valueJSON |

이벤트30일, 세션·사용량·커밋 관련90일 기본 보존. 기간 밖 관련 레코드 함께 정리. 사용자 요청으로 CSV/JSON 내보내기와 프로젝트/전체 삭제. WAL checkpoint 포함, SSD 물리 삭제 보장 없음. 자동 외부 텔레메트리 없음.

## 10. 결제와 배포

가격 후보2,900/5,900/9,900원(KRW), 확정 전. 단일 상품·구매 버전 지속 사용·본인3대·기기 해제를 설계 기본값으로 둔다.
Lemon Squeezy 후보, 통화·세금·수수료·라이선스·환불 샌드박스 검사 후 선택.
비밀키는 앱에 넣지 않는다. 작은 서버가 서명된 라이선스 증명을 발행하고 앱은 공개키 검증. 기존 활성화는 온라인 필수 아님. 신규·추가 기기는 온라인 필요. 환불 실효는 다음 온라인 검증 시 반영, 완전 오프라인 즉시 실효 보장 없음.
Developer ID,Hardened Runtime,helper 포함 서명·공증 DMG. Sparkle2 후보, 업데이트 서명과 사용자 적용 선택. DB migration 전 백업. 구버전이 새 DB를 읽지 못하면 쓰기 차단·안내.
구매 사용권과 미래 모든 OS·도구 영구 호환 보장은 구분한다. 판매 전 호환 범위·업데이트 정책 공개.

## 11. 품질과 시장 검증

AI 미연결에서 표시·드래그·숨김·타이머 작동. 포커스 유지·투명 영역 클릭 통과. 모니터 분리,Retina,Spaces,잠금·복귀 실기 검사.
초기 목표: 아이들CPU 평균1% 이하,애니메이션5% 이하,메모리150MB 이하. 기종·10분 측정 기록, 실측 전 보장 없음.
민감 fixture 내용이 DB·로그에 남지 않음. 이벤트100회 재전달도 한 번 집계. 미상 비용을0으로 표시하지 않음. 앱 부재·로그 오류에서도 AI와 일반 모드 정상.
배포 전 서명·공증·업데이트·환불·오프라인 검사.

일반10명·개발10명 1주 테스트. 작은 표본으로 시장 규모 추정 금지. 동의한 이용 일지로7일차 사용·종료 이유·대체한 작업 확인.
내부 진행 기준 제안: 각군5명 자발 재사용,3명 제시 가격 구매 선택. 업계 기준 아님. 사전 구매는 미완성·납기·환불 명시. 한 군만 반응하면 그 고객에 집중, 양쪽 약하면 기능 확장 중단 후 재검토.

## 12. 근거

- Claude hooks: https://code.claude.com/docs/en/hooks
- Monitoring: https://code.claude.com/docs/en/monitoring-usage
- AppKit: https://developer.apple.com/documentation/appkit/nspanel
- Updates: https://sparkle-project.org/
- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- 비교: https://ccusage.com/ , https://openpets.dev/

공개 문서 확인과 실기 검증은 구분한다. 대응 도구 버전·usage 합산·Intel 실행·결제 통화는 구현 단계 검증 조건이다.
