# macOS 일반 모드 알파 검증

검증일: 2026-09-16 KST. macOS 26.6.2 (25G83), Apple Silicon arm64, Xcode 27.0 (27A266a).

현재 최종 구현은 마지막 **Fix round 3** 절의 시각 창·중앙 입력 창 분리 구조를 기준으로 한다. 이전 절은 당시 결과이며 마우스 폴링/모니터 및 픽셀 투명도 의존 입력은 최종 코드에서 제거됐다.

## 실행

```sh
swift test --package-path Packages/SpiritCore
xcodebuild -project BuildSpirit.xcodeproj -scheme BuildSpirit -configuration Debug -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
open .build/xcode/Build/Products/Debug/BuildSpirit.app
```

메뉴 막대 불꽃 아이콘 또는 캐릭터 몸통 중앙 클릭으로 메뉴를 연다. 설정에서 크기, 표시, 전체 화면 숨김, 소리, 집중 타이머와 리마인더를 조작한다. 알림은 앱 자체의 비활성 패널이며 macOS 알림 센터 알림이 아니다. 소리는 기본 꺼짐이다.

진단이 필요하면 실행 파일에 `--diagnostics`를 추가한다. 시작 약 2초 후 패널·메뉴·자산·렌더링 상태를 표준 출력으로 기록한다. 실행 중인 앱을 먼저 종료해 중복 프로세스를 피한다.

## 실제 확인 결과

| 항목 | 결과 |
|---|---|
| SpiritCore 테스트 | 25개 통과. 기존 reducer 19개, 신규 geometry/alerts 6개 |
| Xcode Debug 빌드 | 성공, Swift 6, macOS 14.0 배포 대상, 현재 arm64 아키텍처 |
| 프로젝트 문법 | `plutil -lint BuildSpirit.xcodeproj/project.pbxproj` 통과 |
| 자산 원본 보존 | 지정 A 원본과 복사 PNG의 SHA-256 일치 |
| 앱 생존 | 여러 차례 실제 실행 및 재실행, 실행 중 PID와 프로세스 상태 확인 |
| 패널 진단 | nonactivating, transparent, allSpaces = true; canBecomeKey/Main = false; idle, 128pt, assetLoaded = true |
| 시작 포커스 | 진단 시 appActive = false. 실제 다른 앱 타이핑을 유지하는 실험은 미실시 |
| 메뉴 | 상태 막대 객체와 9항목 생성 진단. 캐릭터 클릭 메뉴의 표시/크기/25분 집중/설정/종료 항목을 접근성 트리로 확인 |
| 설정 UI | 실제 다크 모드 화면 렌더 확인. 기본 25분, 소리 꺼짐, 콘셉트 및 앱 종료 중 미전달 안내 확인 |
| 크기 변경 | 설정 슬라이더 접근성 Increment/Decrement로 128→129→128pt 및 저장 확인 |
| 집중 타이머 | UI에서 1분으로 설정하고 실제 대기 후 완료 패널 표시, 확인 버튼 닫기, 자동 반복 없음 확인 |
| 타이머 재실행 | deliveredAt 저장 확인. 숨김 상태로 재실행 후 완료 패널이 다시 생성되지 않음 |
| 리마인더 | 빈 문구 저장 시 오류 표시 확인. 시각 도달/1회 소비/직렬화는 단위 테스트 통과. UI에서 실제 예약 전달은 미실시 |
| 숨김 및 위치 복원 | UI로 숨김 후 창 없음 확인. 재실행 진단 panelVisible=false, renderPaused=true, 위치 [1367,17] 복원 |
| 표시 복원 | 테스트 종료 전 앱의 UserDefaults 표시값을 true로 복원하고 다시 실행해 표시 확인 |

빌드 중 `Metadata extraction skipped, no AppIntents.framework dependency found` 경고가 발생한다. AppIntents를 사용하지 않는 앱이며 빌드는 성공한다. 별도 lint 설정은 현재 프로젝트에 없고 Swift 타입 검사는 빌드에서 수행했다.

원본 PNG는 정적 콘셉트이며 배경의 어두운 halo가 남아 있다. 제작용 스프라이트·레이어·프레임 애니메이션은 없다. SpriteKit에서 이미지 전체의 세로 스케일을 바꾸는 호흡만 제공한다. manifest와 설정에서 프로토타입임을 표시한다.

## 아직 실기 검증하지 않은 항목과 한계

- 다른 앱에서 연속 타이핑 중 캐릭터 클릭·드래그·알림이 포커스를 유지하는지, 투명 픽셀의 실제 클릭 통과 여부를 실기 확인해야 한다. 코드에는 nonactivating 패널과 이미지 알파 기반 클릭 통과를 구현했다.
- 드래그 자동화는 Computer Use에서 `AXError.notImplemented`를 반환해 이동 실험을 완료하지 못했다. 위치 복원과 보정은 단위 테스트 및 재실행으로 확인했지만 마우스 드래그 실기 확인은 남았다.
- 다중 모니터 분리, Retina 배율 변경, Spaces 전환은 실기 미검증이다. 화면 변화 알림에 연결한 보정 로직은 합성 화면 좌표로 테스트했다.
- 전체 화면 숨김은 공개 `CGWindowListCopyWindowInfo`의 전면 앱 창 경계와 디스플레이 경계를 비교하는 휴리스틱이다. 화면을 덮는 일반 창을 잘못 숨길 수 있고 창 정보가 없거나 특수 전체 화면을 사용하는 앱은 놓칠 수 있다. 모든 앱의 전체 화면 여부를 신뢰성 있게 판정하는 공개 API는 사용하지 못했다. 설정에서 끌 수 있으며, 실제 전체 화면 진입·복귀 실험은 미실시이다.
- 절전/화면 절전/사용자 세션 비활성화는 공개 NSWorkspace 알림에 따라 렌더링을 중단한다. 잠금만의 안정적인 공개 이벤트가 없어 `com.apple.screenIsLocked`/`com.apple.screenIsUnlocked` 시스템 분산 알림을 보완적으로 사용한다. 이름은 공개 안정 계약이 아니며 OS 변경 시 동작이 달라질 수 있다. 실제 잠금·절전·복귀는 미실시이다.
- 동작 줄이기 변경 시 호흡 액션을 제거한다. 실제 macOS 설정을 바꿔 보는 실험은 미실시이다. 라이트 모드와 VoiceOver 전체 탐색도 미검증이다.
- 리마인더는 앱 실행 중의 자체 화면 알림이다. 앱 종료 중 전달되지 않는다. 절전/잠금 중에는 소비를 보류하고 복귀 또는 다음 실행 때 지난 알림을 한 번 소비한다. UserDefaults 저장은 절전 중 중복 소비 방지용이며 프로세스 강제 종료/디스크 오류까지 포함하는 영구 exactly-once 전달을 보장하지 않는다.
- 10분 CPU·메모리 측정, Intel 실기, macOS 14 실기는 아직 하지 않았다. 실행 중 한 번의 표본은 CPU 1.6%, RSS 128720KB였으나 성능 목표 충족의 증거로 사용하지 않는다.
- 서명·공증·배포 검증은 범위 밖이다. 이번 산출물은 로컬 Debug 알파이다.

로컬 확인 로그: `.build/task-2-build.log`, `.build/task-2-tests.log`, `.build/task-2-settings.jpeg`.

## Fix round 1 (2026-09-16)

아래 결과는 최초 검증 이후 I1/I2/M1 수정에 대한 추가 기록이다.

### 미확인 알림의 보존

- 소비한 알림을 FIFO 미확인 큐에 넣는다. 새 tick에서 B가 도착해도 표시 중인 A를 대체하지 않는다. A의 확인 버튼을 누르면 A를 제거하고 B를 표시한다.
- 잠금·절전 중에는 현재 알림 창만 숨긴다. 복귀하면 큐의 맨 앞 미확인 알림을 복원한다. 확인한 알림은 큐에서 제거되어 복원하지 않는다.
- 타이머 소비 상태, 리마인더 및 미확인 큐를 UserDefaults의 `localAlertState` 단일 Codable 값으로 저장한다. 재실행해도 미확인 알림을 복원하며, 소비한 원본에서 다시 큐를 만들지 않는다.
- 리마인더는 확인할 때 큐와 원본 일정에서 함께 제거한다. 완료 리마인더가 매초 검사와 저장 대상에 영구 누적되는 문제를 정리했다. 확인하지 않은 알림은 사용자가 확인할 때까지 유지된다.
- 이전 알파 저장값은 미래/미소비 일정과 타이머 상태를 새 값으로 이전한다. 이전 버전에는 확인 여부가 없어 이미 소비된 과거 리마인더는 재알림하지 않고 정리한다. 이전 중복 저장 키 `focusTimer`와 `reminders`는 이전 후 제거한다. 이미 사라진 과거 미확인 알림까지 복구할 수는 없다.

### 클릭 통과와 이벤트 모니터

- 100ms 포인터 폴링을 제거했다. 표시 중 로컬/글로벌 `mouseMoved`, `leftMouseDragged`, `rightMouseDragged`, `otherMouseDragged` 이벤트에 맞춰 현재 위치와 이미지 알파를 판정한다. 표시 직전과 크기/위치 보정 직후에도 동기로 갱신한다.
- 수신한 좌/우 mouseDown에서 이벤트 좌표의 현재 알파를 다시 검사한다. 투명 지점이면 인사/메뉴/드래그를 시작하지 않는다. 승인한 드래그는 버튼을 놓기 전까지 유지하고, mouseUp 후 현재 위치로 통과 상태를 다시 계산한다.
- 숨김·절전 시 마우스 모니터를 제거하고 복귀 시 설치한다. 종료 시 모니터와 NotificationCenter/NSWorkspace/분산 알림 observer를 모두 해제한다.
- 키 이벤트는 감시하지 않고 접근성/Input Monitoring 권한 요청이나 CGEventTap도 추가하지 않았다. Apple 문서에서 접근성 신뢰 조건은 키 이벤트 감시에 명시돼 있다. 이번 마우스 모니터의 설치는 현재 Mac에서 성공했지만, 여러 OS/보안 설정의 이벤트 전달까지 검증한 것은 아니다. [Apple 이벤트 모니터 문서](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)
- 글로벌 모니터는 다른 앱에 전달되는 이벤트를 비동기로 관찰하며 수정·차단·회수하지 못한다. 따라서 고정 100ms 지연은 제거했지만 빠른 경계 왕복 후 클릭에 대한 OS 수준의 원자적 hit-test를 보장하지 않는다. 이미 우리 패널에 도착한 투명 지점 클릭도 아래 앱에 재전송하지 않는다. 가로채기 권한을 요구하는 이벤트 탭은 사용하지 않는다. [Apple 글로벌 모니터 문서](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))

### 추가 검증

- 새 테스트 5개에서 8개 assertion 실패(RED)를 확인한 후 전체 30개 통과(GREEN). 서로 다른 tick의 A/B 순서, stale 확인 버튼 방어, suspend/resume 표시 선택, 확인 후 미복원, Codable 복원, 타이머 중복 소비 방지, 완료 리마인더 정리, 포인터 이동/drag capture/현재 mouseDown 알파 판정을 검사했다.
- 지정 xcodebuild 명령으로 Debug 빌드 성공. Swift 오류 없음. AppIntents 미사용 메타데이터 경고만 발생했다.
- 수정 앱을 재실행했다. 진단에서 localMouseMonitorInstalled/globalMouseMonitorInstalled=true, pendingAlertCount=0, alertPanelVisible=false, nonactivating/transparent/allSpaces=true, appActive=false, idle/128pt를 확인했다. Computer Use로 캐릭터를 클릭해 메뉴가 열리는 것도 확인했다.
- 실제 OS 잠금/절전 중 알림 복원과 빠른 불투명/투명 경계 왕복·즉시 클릭/드래그·아래 앱 오입력 여부는 아직 실기 미검증이다. 테스트의 suspend 값과 포인터 입력은 순수 모델 입력이며 OS 이벤트 재현을 의미하지 않는다.
- 로그: `.build/task-2-fix1-red.log`, `.build/task-2-fix1-tests.log`, `.build/task-2-fix1-build.log`.

## Fix round 2 (2026-09-16)

### 최종 구조

마우스 폴링, 로컬/글로벌 NSEvent 모니터, PointerInteraction 상태 기계와 두 테스트, 수동 PNG 알파 판정 코드를 제거했다. `ignoresMouseEvents=false`를 고정하고 `NSPanel.isOpaque=false`, clear 배경, `SKView.allowsTransparency=true`, `SKView.isOpaque=false`, clear scene을 사용한다. 입력 라우팅은 WindowServer에 맡긴다. 키/전역 마우스 감시, 권한 요구 이벤트 탭, 클릭 재전송은 없다. 실제 드래그에 필요한 시작 위치와 이동 여부만 유지한다.

[Apple 공식 문서](https://developer.apple.com/documentation/appkit/nswindow/windownumber(at:belowwindowwithwindownumber:))는 `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`가 mouse-down과 같은 규칙으로 조회하고 해당 점에서 투명하거나 마우스를 무시하는 창은 제외한다고 설명한다. 그런데 현재 Mac에서 아래처럼 전체 투명 창까지 반환돼, 이 API를 원자적인 픽셀 클릭 통과 검증 근거로 사용할 수 없었다.

### 실제 진단

최종 실행 창 번호는 19402였다. screen 좌표는 AppKit의 전역 화면 좌표이다.

| 검사 | 결과 |
|---|---|
| 투명 코너 화면 좌표 | [1368,18] |
| 코너의 실제 SpriteKit texture alpha | 0 |
| 코너 windowNumber | 19402, companion과 같음. `transparentCornerPassesThrough=false` |
| 가시 중심 화면 좌표 | [1431,81] |
| 중심의 실제 SpriteKit texture alpha | 약 0.988235 |
| 중심 windowNumber | 19402, companion과 같음. `visibleCenterHitsCompanion=true` |
| 창/뷰 설정 | ignoresMouseEvents=false, spriteViewAllowsTransparency=true, spriteViewOpaque=false, sceneBackgroundAlpha=0 |

같은 companion 창에서 `displayIfNeeded()`와 `flush()` 후 다음 run loop까지 1초 기다려 추가 비교했다. 당시 창 번호 19397에서 (a) alphaValue=0 전체 투명, (b) contentView=nil+clear 배경, (c) 작은 불투명 NSView만 있는 경우 모두 코너/중심에 19397을 반환했다. 별도의 비레이어 NSView 창에서도 코너가 해당 창으로 조회됐다. 따라서 이 조회 결과만으로 실제 픽셀 라우팅 실패 또는 성공을 확정하지 않는다.

SpriteKit RGBA를 비레이어 NSView backing에 그리는 임시 렌더 브리지도 실험했으나 진단 결과를 개선하지 못했다. 이 브리지, 임시 probe 진입점, 전용 호흡 함수·테스트는 최종 제품 코드에서 제거하고 기존 SpriteKit SKAction 호흡으로 복귀했다.

### 실제 입력 자동화 시도: 검증 불가

제품 소스 밖 `.build/BuildSpiritHitProbe.app`에 임시 클릭 카운터 버튼 창을 만들어 companion 아래 위치에 배치했다. Computer Use로 아래 창을 대상으로 투명 코너에 해당하는 좌표를 클릭하니 0→1, 가시 중심에 해당하는 좌표를 클릭하니 1→2가 됐고 companion 메뉴는 확인되지 않았다. 앱을 지정하는 자동화가 교차 앱의 실제 포인터 라우팅을 보존하는지 확인되지 않아 코너 클릭 통과만 성공으로 주장하지 않는다. 가시/투명 입력 분리를 확인하는 실험은 통과하지 못했으며, 실제 마우스로 확인해야 한다. 임시 앱은 확인 후 종료했다. 테스트 코드는 `.build`에만 있고 제품 타깃에는 포함하지 않았다.

### 최종 검증과 한계

- `swift test --package-path Packages/SpiritCore`: 28개 통과. 불필요해진 포인터 상태 테스트 2개를 제거했고 I1 FIFO/영속/확인 회귀 3개는 유지했다.
- 지정 xcodebuild: BUILD SUCCEEDED. AppIntents 미사용 메타데이터 경고 외 소스 오류 없음.
- 수정 바이너리를 다시 실행해 위 두 native hit-test와 실제 SpriteKit 알파를 기록했다. 앱은 idle/128pt, appActive=false, nonactivating/transparent/allSpaces=true로 실행 중이다.
- 현재 환경에서 공개 조회 API로 원자적 per-pixel 입력 shape를 보장하거나 검증할 수 없었다. I2 완전 해결로 판정하지 않는다. 자동화와 별개로 실제 마우스 경계 클릭·드래그 및 아래 앱 오입력 확인이 남았다.
- 최종 로그: `.build/task-2-fix2-tests.log`, `.build/task-2-fix2-build.log`, `.build/task-2-fix2-diagnostics.log`. 비교 실험: `.build/task-2-fix2-probe.log`, `.build/task-2-fix2-click-probe.log`.

## Fix round 3 (2026-09-16)

### 최종 입력 정책

시각용 CompanionPanel은 항상 `ignoresMouseEvents=true`이다. 투명 코너·후광·불꽃·몸통을 포함한 시각 창 전체는 아래 앱의 클릭을 가로채지 않는다. 알파 hit-test나 이전 마우스 위치를 이용해 이 값을 전환하지 않는다. 100ms 폴링, 로컬/글로벌 이벤트 모니터, 이벤트 탭, 권한 요청, 클릭 재전송이 없다.

클릭·우클릭·드래그는 캐릭터 중앙의 작은 별도 nonactivating 입력 패널에서만 받는다. SpiritCore의 순수 geometry로 시각 창 원점에 크기의 40%를 더하고 폭·높이를 각각 20%로 계산한다. 80/128/192pt 캐릭터에서 입력 크기는 16/25.6/38.4pt이다. AppKit이 실제 창 프레임을 반올림하므로 현재 128pt 실행에서는 26×26pt로 나타났다. 중심의 불투명 얼굴/몸통 안에 보수적으로 제한했고 불꽃과 바깥 윤곽은 의도적으로 조작 대상이 아니다. 완전 투명 입력 backing에 의존하지 않도록 몸통 위 입력 패널에 검정 alpha 0.01의 미세한 채움을 사용한다.

위치 이동·화면 복구·크기 변경 때 두 프레임을 동기 갱신한다. 표시/숨김·전체 화면 숨김·잠금/절전·종료는 동일한 setRendering 경로에서 두 창을 함께 처리하며 숨길 때 진행 중 드래그도 취소한다. 두 창 모두 canBecomeKey/Main=false이고 canJoinAllSpaces/fullScreenAuxiliary/stationary 및 floating 레벨을 공유한다.

기술부채: 이 중앙 사각형은 현재 단일 콘셉트 PNG 전용이다. 상세 스프라이트 제작 때 실제 프레임별 알파 마스크에서 보수적인 입력 영역을 산출하는 방식으로 교체해야 한다. 현재 크기와 배치는 `App/Resources/Spirit/manifest.json`에도 기록했다. 전체 캐릭터 실루엣에 대한 per-pixel 입력을 구현했다고 주장하지 않는다.

### RED / GREEN 및 실행 진단

- geometry 신규 테스트 2개에서 4개 assertion 실패(RED)를 실제 확인한 뒤 최소 구현했다. 80/128/192 크기, 음수 화면 원점에서의 이동, 시각 창 내부 포함을 검사한다. 전체 Swift 테스트 30개 통과(GREEN), 기존 FIFO/영속 알림 회귀도 통과했다.
- 지정 xcodebuild Debug 빌드 성공. AppIntents 미사용 메타데이터 경고 외 소스 오류 없음.
- 최종 바이너리 진단: visualIgnoresMouseEvents=true, interactionPanelVisible=true, interactionNonactivating=true, interactionCanBecomeKey=false, interactionCanBecomeMain=false, interactionAllSpaces=true, interactionIgnoresMouseEvents=false, interactionFrameWithinVisual=true.
- 시각 창 번호 19431, 원점 [1367,17], 128pt. 입력 창 번호 19432, 프레임 [1418,68,26,26]. appActive=false, renderPaused=false, idle, assetLoaded=true. 실제 SpriteKit 코너 alpha=0, 중심 alpha≈0.988235.
- 이전 round에서 적합하지 않았던 windowNumber 조회는 최종 진단의 입력 성공 판정에서 제거했다. 시각 창의 고정 ignore와 작은 입력 창의 분리가 안전성을 제공하는 구조이다.

### 실제 입력 자동화: 검증 불가

Computer Use는 새 입력 창 대신 시각 SKView 창을 대상으로 선택했다. 화면 중앙 [64,64] 클릭에서 메뉴가 나타나지 않았고, [64,64]→[54,54] 드래그 호출은 성공 반환했지만 저장 위치 [1367,17]이 바뀌지 않았다. 입력 창의 접근성 라벨/제목과 시각 창의 비인터랙티브 접근성 설정 후에도 도구 선택 창은 같았다. 따라서 새 입력 패널의 실제 클릭·우클릭·드래그 성공은 확인하지 못했다. 도구 호출 성공을 사용자 동작 성공으로 해석하지 않는다.

실제 마우스로 중앙 클릭 메뉴/우클릭/드래그, Space 전환, 잠금·절전 후 두 창 동기 복원을 확인해야 한다. 시각 창은 항상 ignore이므로 투명 영역 클릭을 시각 창이 가로채는 경로는 구조적으로 제거했지만, 교차 앱 실제 입력 자동화 성공을 별도로 주장하지 않는다.

로그: `.build/task-2-fix3-red.log`, `.build/task-2-fix3-tests.log`, `.build/task-2-fix3-build.log`, `.build/task-2-fix3-diagnostics.log`.

## Fix round 4 — 리그 캐릭터의 클릭 누락 (2026-09-16)

사용자가 캐릭터를 클릭해도 말풍선이 한 번에 열리지 않고 바탕화면이 표시되는 현상을 보고했다. 시각 창은 항상 클릭을 통과시키고 별도 입력 창은 과거 단일 PNG 기준 중앙 20%×20%만 받았다. 128pt에서 약 26×26pt이며, 파츠 리그의 몸통 아래·망치·불꽃이 이 영역 밖인 것을 실제 SpriteKit 렌더링 표본으로 확인했다. 따라서 해당 부위 클릭은 아래 앱/바탕화면으로 전달된다. 바탕화면 표시 자체의 macOS 설정과 교차 앱 실제 입력은 자동화로 확정 재현하지 않았다.

입력 프레임을 bottom-left 정규 좌표 [0.10, 0.10, 0.80, 0.85]로 확대했다. 128pt에서는 약 102×109pt이다. 캐릭터와 작은 여유 공간을 하나의 안정적인 사각형으로 받는다. 이 사각형 안의 파츠 사이 투명한 틈도 조작 대상이며 바깥 창 모서리는 계속 클릭 통과한다. 이전 알파 의존 라우팅·마우스 폴링·이벤트 재전송은 추가하지 않았다.

- 기존 영역에서 몸통·망치·불꽃 누락 회귀 10개 assertion 실패(RED), 수정 후 geometry 두 테스트 통과(GREEN).
- 코어 155개/21 suite 통과, Swift 6 Debug 빌드 성공.
- 다중 정령 통합 1개와 앱 훅 통합 3개 통과.
- `CompanionClickSmoke.swift`: 좌클릭·우클릭·취소 라우팅, 이동/크기 변경 후 입력 창 정렬, 80/128/192pt와 일곱 동작의 84개 렌더링 표본에서 실제 가시 픽셀의 입력 영역 포함을 확인했다. 장식 불티는 검사에서 제외했다.

네이티브 smoke 실행:

```sh
mkdir -p .build/click-smoke/Spirit
cp App/Resources/Spirit/smith-rig-atlas.png .build/click-smoke/Spirit/
swiftc -parse-as-library -swift-version 6 -I Packages/SpiritCore/.build/debug -I Packages/SpiritCore/Sources/CSQLite -L Packages/SpiritCore/.build/debug -lSpiritCore App/Companion/SpiritScene.swift App/Companion/CompanionPanel.swift Tests/CompanionClickSmoke.swift -o .build/click-smoke/CompanionClickSmoke
.build/click-smoke/CompanionClickSmoke
```

최종 입력 정책은 이 절과 현재 manifest 기준이며, 초기 round 3의 작은 중앙 입력 사각형은 더 이상 사용하지 않는다.
