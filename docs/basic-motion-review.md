# 기본 동작 확인

2026-09-16. 확정한 불꽃 대장장이를 파츠 기반 SpriteKit 리그로 교체했다. 전체 PNG를 기울이거나 네 장의 텍스처를 교체하는 방식이 아니다.

## 롱탭 번개 충전 (2026-09-22)

롱탭으로 망치를 들면 캐릭터 표시 영역 위쪽에서 번개가 내려와 망치 머리로 모인다.
충전이 강해질수록 가지 번개·망치 주변 전류·흡수되는 빛 입자가 선명해지며,
올려다보는 표정 → 집중하는 눈 → 빛나는 눈과 이를 악문 입으로 이어진다.
약 0.86초 간격의 낙뢰에 작은 몸 반동을 맞추고, 망치를 잡은 손의 접점은 유지한다.
충전 감소 시 모든 전용 효과와 표정이 복구되며, 동작 줄이기를 켜면 진행 중인 번개도 즉시 사라진다.

검증: `ChargeHammerSmoke`의 롱탭·연속 탭, 낙뢰 접점, 손잡이 접점, 표정 복구,
활성 충전 중 동작 줄이기 검사를 80/128/192pt × 밝음/어두움에서 통과했다.
렌더링 PNG와 GIF는 `.build/sky-charge-preview/`에 있다.
`EmotionSceneSmoke`의 기존 감정 동작 회귀 검사, Xcode Debug 빌드와 타입 검사,
`git diff --check`도 통과했다. 별도 lint 설정은 없다.

## 확인 방법

메뉴 막대 불꽃 아이콘 또는 정령 몸통 중앙 클릭 → **기본 동작 확인…**.

### 8개 시나리오 구현 (2026-09-21)

**기본 동작 확인… → 장면 → 다시 재생**에서 시선·쓰다듬기·드래그·작업·완료·불씨·확인/오류·휴식을 개별 확인한다.
재생마다 새 장면을 사용하며, 재생 중 실제 커서와 자동 대기 행동은 잠시 비활성화된다.
중지·다른 장면 선택·동작 줄이기·창 닫기는 진행 중인 입력 작업을 취소한다.

- 시선은 눈이 먼저 움직이고 고개가 뒤따른다. 재진입에는 4초 쿨다운이 있다.
- 쓰다듬기는 첫 인지 이후 만족으로 이어지고, 손길이 멈춘 뒤 0.35초 여운과 0.9초까지 눈 뜨기를 적용한다. 짧은 방향 전환은 반응을 재시작하지 않는다.
- 드래그는 몸만 늘리고 망치는 단단하게 유지한다. 잡고 멈추면 이동 관성만 가라앉으며, 놓기와 숨김/크기 변경에 의한 취소를 구별한다.
- 작업은 0.55초 준비 후 가벼운 두 타격·확인·강한 타격을 반복한다. 작은 받침과 작업물에 불티가 발생하며 실제 진행률을 암시하지 않는다.
- 완료는 마지막 타격 회복 뒤 결과 확인·준비·점프·착지·뿌듯함·정리의 3초 연기다. 낮은 에너지에서는 점프하지 않는다. 중단된 완료를 다시 예약하지 않는다.
- 불씨는 몸과 독립된 좌표로 떠오르고, 손을 피해 올라갔다 내려와 손바닥에 머문 뒤 떠난다. 불씨와 망치 놀이는 하나의 25–45초 대기 스케줄러를 공유한다. 오래 대기하면 휴식한다.
- 확인 요청은 손바닥의 불씨와 기다리는 표정, 오류는 한 번의 놀람 뒤 걱정하는 눈썹과 입으로 구별한다. 새 상태가 쓰다듬기의 잔상을 덮는다.
- 휴식은 하품·느린 눈 감기·망치 내리기 순서로 3초에 걸쳐 진행하고, 깨울 때 눈이 몸보다 먼저 돌아온다.

`Tests/ScenarioSceneSmoke.swift`는 8개 장면 × 80/128/192pt × 밝음/어두움의 48개 GIF와 주요 프레임을 `.build/scenario-preview/`에 생성한다.
망치 축 비율, 독립 불씨, 작업물, 표정 구분, 동작 줄이기를 실제 SpriteKit 노드로 검사한다.

```sh
swiftc -parse-as-library -module-cache-path /tmp/spirit-scenario-modules -swift-version 6 -I Packages/SpiritCore/.build/out/Products/Debug -I Packages/SpiritCore/Sources/CSQLite -L Packages/SpiritCore/.build/out/Products/Debug -lSpiritCore -lsqlite3 App/Companion/SpiritScene.swift Tests/ScenarioSceneSmoke.swift -o .build/rig-smoke/ScenarioSceneSmoke
.build/rig-smoke/ScenarioSceneSmoke .build/scenario-preview
```

최신 검증: 코어 198개 테스트(외부 연동 옵트인 2개 건너뜀), Xcode Debug 빌드,
`EmotionSceneSmoke`, `RigSceneSmoke`, `HammerTrickSmoke`, `CompanionClickSmoke`, `ScenarioSceneSmoke` 통과.
별도 lint 설정은 없으며 Swift 6 컴파일과 `git diff --check`를 사용한다.

### 표정과 감정 동작 (2026-09-21)

콤냥이의 사용자 입력과 전신 포즈 연결을 참고해 기존 불꽃 대장장이 원화를 유지하면서
쓰다듬기·드래그·작업 완료의 감정 연기를 보강했다.

- 쓰다듬기: 만족한 웃는 눈과 미소, 부드러운 몸 압축, 손길 쪽 고개 기울임과 잔잔해지는 불꽃을 함께 적용한다. 피곤한 눈과 구별한다. 반응량은 입력 이벤트 횟수가 아닌 경과 시간 기준이다.
- 드래그: 들어 올리면 몸이 늘어나고 놀란 눈과 작은 입을 보인다. 이동을 멈춰도 잡고 있는 자세를 유지하며 놓으면 짧게 출렁인 뒤 돌아온다. 실제 드래그 시작·해제·취소와 연결된다.
- 완료: 진행 중인 망치질이 끝난 뒤 결과를 내려다보고, 살짝 웅크렸다 폴짝 뛰며, 사용자 쪽으로 시선을 돌려 뿌듯한 표정을 유지한 후 쉰다. 누르기·드래그·새 작업이 시작되면 중단한 연기를 다시 재생하지 않는다.
- 큰 행동은 겹치지 않는다. 쓰다듬기와 드래그는 망치 놀이보다 우선하고, 망치 놀이가 진행되는 동안 하품·불씨 놀이 같은 습관을 시작하지 않는다.
- 동작 줄이기에서는 전신 애니메이션과 파티클을 멈추면서 집중·완료·휴식의 표정은 유지한다.

기본 원화는 그대로 두고 새 표정은 `SpiritScene`의 작은 픽셀 노드로 구성한다.
`SpiritRigMotion`은 표정과 몸의 변형을 하나의 포즈로 전달한다.

실제 렌더러의 비교 이미지는 `Tests/EmotionSceneSmoke.swift`로 생성한다.
128/192pt에서 쓰다듬기·드래그와 놓기·완료·동작 줄이기를 각각 확인하며,
GIF와 정지 프레임은 `.build/emotion-preview/`에 저장한다.

```sh
swiftc -parse-as-library -module-cache-path /tmp/spirit-emotion-modules -swift-version 6 -I Packages/SpiritCore/.build/out/Products/Debug -I Packages/SpiritCore/Sources/CSQLite -L Packages/SpiritCore/.build/out/Products/Debug -lSpiritCore -lsqlite3 App/Companion/SpiritScene.swift Tests/EmotionSceneSmoke.swift -o .build/rig-smoke/EmotionSceneSmoke
.build/rig-smoke/EmotionSceneSmoke .build/emotion-preview
```

먼저 `Packages/SpiritCore`에서 `swift test`로 최신 모듈을 빌드하고,
`App/Resources/Spirit`을 `.build/rig-smoke/Spirit`에 복사해 둔다.

검증: 코어 테스트 실행 통과(총 185개, 옵트인 외부 연동 2개 건너뜀), Xcode Debug 빌드, `EmotionSceneSmoke`,
`CompanionClickSmoke`, `HammerTrickSmoke` 통과. 드래그로 늘어난 불꽃의
상단 잘림을 실제 픽셀 검사로 재현한 뒤 애니메이션 여백을 확보했다.
별도 lint 설정은 없으며 Swift 컴파일과 `git diff --check`로 확인했다.

### 망치 던지기·불러 잡기 (2026-09-21)

정령을 우클릭하거나 메뉴 막대 메뉴에서 **망치 던져 받기**, **망치 불러 잡기**를 선택한다.
**기본 동작 확인…** 창에도 같은 버튼이 있다. 실제 CLI 작업 상태를 바꾸지 않는다.

- 던져 받기: 팔을 준비한 뒤 망치를 위로 던져 한 바퀴 돌리고 받아낸다. 약 2.1초.
- 불러 잡기: 손을 내밀면 화면 여유가 큰 쪽 바깥에서 망치가 날아와 손에 붙는다. 약 2.2초.
- 잡는 순간 몸을 살짝 눌러 충격을 흡수하고 원래 자세로 돌아온다.
- 건강한 대기 상태에서는 25~45초 간격의 공유 스케줄러가 불씨 놀이와 던져 받기를 번갈아 선택한다. 피로·휴식·작업·충전 중에는 자동 실행하지 않는다.
- 작업 중이거나 충전 중에는 메뉴에서 실행할 수 없다. 중복 요청은 무시한다.
- 누르기·드래그·크기 변경·숨김·작업 시작·동작 줄이기에서는 망치를 즉시 손으로 돌려놓고 외부 표시를 정리한다.
- 데스크톱의 비행 망치는 클릭을 가로채지 않는다. 확인 창에서는 창 안으로 들어오는 구간을 볼 수 있다.

편집 원본은 `SourceArt/Spirit/hammer-parts.aseprite`이고, 순수 동작 곡선은 `HammerTrick.swift`에 있다.
`Tests/HammerTrickSmoke.swift`는 실제 렌더러의 손/망치 분리, 재부착, 외부 표시 전달,
취소 및 자동 동작을 검증하고 `.build/hammer-preview/`에 GIF를 생성한다.
`CompanionClickSmoke`는 외부 망치의 화면 좌표·회전 여백·클릭 통과와 이동/크기 변경/숨김 시 정리를 검증한다.

최종 검증: 코어 테스트 177개, Xcode Debug 빌드, `HammerTrickSmoke`, `CompanionClickSmoke` 통과.
망치질의 마지막 회복 구간에는 새 동작을 차단하며, 미리보기는 새 대기 장면에서 시작해 충전·망치질 상태와 겹치지 않는다.
실제 앱에서 충전 후 망치 동작 버튼을 누르면 충전이 해제되는 것도 확인했다.

- **대기**: 호흡, 눈 깜빡임, 독립적인 불꽃 변형.
- **망치질**: 어깨 축 준비 동작 → 빠른 타격 → 몸의 눌림과 반동 → 망치 회수. 타격 시 불티가 발생한다.
- **대기로 전환**: 진행 중인 동작을 마무리하고 쉰다.
- **느리게 보기**: 0.5배 속도로 파츠 동작을 확인한다.
- **동작 줄이기**: 움직임과 불티를 멈춘다. macOS의 동작 줄이기 설정도 존중한다.
- **기본 동작 이어보기**: 대기 3초 → 망치질 6초 → 대기. 느리게 보기에서는 망치질 구간도 늘어난다.

확인 창은 별도의 SpiritScene을 사용한다. 실제 Codex 세션에 가짜 이벤트를 보내거나 실제 정령 상태를 바꾸지 않는다. 창을 닫으면 미리보기 작업도 종료한다. 데스크톱 정령도 같은 리그를 사용한다.

## 이번 범위와 제한

눈, 머리, 몸, 망치를 든 팔, 반대 팔을 분리했다. 불꽃은 머리 상단 메시 변형으로 움직이며, 픽셀 단위로 다시 그린 불꽃 애니메이션은 아니다. 확정 원본 PNG는 보존했다. 독립 파츠 생성 과정에서 일부 비율과 가장자리에 작은 차이가 있다.

이번에는 기본 동작의 질감을 확인한다. 마우스 시선 추적, 타이핑 속도 반응, 드래그 관성, 모루와 타격음은 추가하지 않았다. 기존 확인 요청·완료·오류·인사 제스처는 유지한다.

## 구현

- `Packages/SpiritCore/Sources/SpiritCore/SpiritRigMotion.swift`: 시간 기반 동작 곡선과 전환, 일회성 타격 신호.
- `App/Companion/SpiritScene.swift`: 파츠 피벗, 불꽃 메시, 불티, 상태 라벨.
- `App/Settings/MotionReviewView.swift`: 실시간 독립 미리보기.
- `App/Resources/Spirit/smith-rig-atlas.png`: 투명 파츠 원화. 내장 image_gen 편집 도구로 생성했으며 원본 알파를 유지했다.

## 검증

- `swift test` (Packages/SpiritCore): 63개 통과.
- Xcode Debug 빌드 통과. 별도 lint 설정은 없다.
- `Tests/bridge_integration.py`: 4개 통과.
- `Tests/app_hook_integration.py`: 3개 통과. 격리된 소켓을 사용한다.
- `Tests/RigSceneSmoke.swift`: 실제 SpriteKit에서 독립 노드, 회전 궤적, 불티 생성, 대기 복귀, 동작 줄이기 검증. 타격 주기 중 6개 PNG 캡처 성공을 검사한다.
- macOS 실제 확인 창에서 대기/망치질, 느리게 보기, 동작 줄이기를 조작했다.

렌더러 검증 실행 예:

```sh
mkdir -p .build/rig-smoke/Spirit
cp App/Resources/Spirit/smith-rig-atlas.png .build/rig-smoke/Spirit/
swiftc -parse-as-library -swift-version 6 -I Packages/SpiritCore/.build/debug -I Packages/SpiritCore/Sources/CSQLite -L Packages/SpiritCore/.build/debug -lSpiritCore -lsqlite3 App/Companion/SpiritScene.swift Tests/RigSceneSmoke.swift -o .build/rig-smoke/RigSceneSmoke
.build/rig-smoke/RigSceneSmoke /tmp/build-spirit-rig-frames
```

## 2026-09-20 Aseprite 원화 및 모션 보정

현재 편집 원본과 내보내기 방법은 [SourceArt/Spirit](../SourceArt/Spirit/README.md)에 기록했다.
7개 부위 레이어로 분리한 원화의 크기·배치를 유지하고 색상을 불투명 10색으로 정리했다.
눈 모서리와 반사광, 작은 미소를 MCP로 직접 그렸으며 레이어 구성에는 Aseprite Lua를 병행했다.
불꽃의 얼굴 근처 변형을 줄이고 셰이더 팔레트를 원화와 맞췄다.
깜빡임은 빠르게 닫히고 천천히 열리며, 망치 하강→타격 경계의 팔·몸 압축 불연속을 수정했다.

검증 결과:

- `swift test`: 170개 테스트 통과. 설치된 외부 클라이언트의 옵트인 스모크 1개는 건너뜀.
- Xcode Debug 빌드 통과. 별도 lint 설정은 없으며 Swift 컴파일 및 `git diff --check` 통과.
- Aseprite 원본 재출력과 앱 PNG의 모든 픽셀 일치, 1254×1254 및 알파 0/255 확인.
- `RigSceneSmoke`: 정상·피로·소진·수면의 128/192pt × 3개 배경 비교 24장, 타격·충전 렌더링 통과.
- 실제 불꽃 검사: 윤곽 98셀, 내부 색상 65셀 변화. 동작 줄이기에서는 불꽃 픽셀 고정.
- `CompanionClickSmoke`: 80/128/192pt의 몸통·머리·불꽃 클릭 범위, 좌우 클릭 구분, 말풍선 닫기 및 드래그 검증 통과.

검증 이미지와 GIF는 로컬 `.build/aseprite-polish-after/`에 저장한다.
처음 렌더링 검사기 컴파일은 `CSQLite` 검색 경로 누락으로 실패했고,
위 실행 예에 해당 경로와 링크 플래그를 추가한 뒤 통과했다.

## 2026-09-20 불씨와 이동 잔상 추가 보정

- 일반 불씨는 고정된 11개 좌표 순환 대신 원화 알파 윤곽을 샘플링하고 움직이는 파츠 좌표를 따라 방출한다. 부위 순서를 섞고 부위 안의 위치도 매번 선택한다.
- 3종의 비대칭 불꽃 모양, 작은 불티 위주의 크기 분포, 개별 수명·부력·횡풍·휘어짐·식는 색상으로 차이를 준다. 일반 불씨는 최대 80개로 제한한다.
- 다음 방출 간격은 방출할 때만 갱신한다. 피로·휴식 때는 밀도를 낮추고, 프레임 속도에 따른 방출량 차이를 방지한다.
- 드래그 잔상은 입력 이벤트 횟수가 아닌 누적 이동거리로 방출한다. 캐릭터 뒤쪽 가장자리에서 크기·회전·상승 궤적·수명이 다른 불티를 내보내며, 창이 움직여도 기존 잔상의 화면 좌표를 유지한다. 최대 96개, 수명 0.3~0.85초다.
- 코어 테스트 172개, Debug 빌드, 실제 리그 렌더링, 좌우 클릭·드래그 스모크를 통과했다. 새 검증은 방출 간격 변주/30·120fps 일치, 불씨 크기와 모양 다양성, 미세 이동 이벤트의 과도한 방출 방지, 정지 시 무방출, 잔상 개수 제한·소멸을 포함한다.
- 일반 불씨/망치질 GIF: `.build/embers-after/ember-motion.gif`. 잔상 캡처: `/tmp/build-spirit-drag-trail.png`.

## 파츠 생성 프롬프트

입력: `mockups/assets/pet-v5-smith.png`. 도구: 내장 image_gen. 최종 파일: `App/Resources/Spirit/smith-rig-atlas.png`.

```text
Edit target: the attached approved flame blacksmith. Create production 2D cutout animation asset sheet preserving EXACT character identity, simple chunky square pixels, palette, proportions, left-leaning flame, tiny torso. NOT a redesign. True transparent RGBA background, no checkerboard, no ground, no shadow, no labels. Flat colors, no grain, no new detail. Square canvas divided invisibly into FOUR equal square cells (2 columns x 2 rows), with generous transparent gutters and all parts entirely inside their cell.
TOP LEFT cell: the COMPLETE character base (head with entire red-orange-yellow flame crown, torso with cream belly, both short feet), front view, exactly original silhouette, BUT REMOVE both arms, the hammer, both eyes and mouth entirely, fill face seamlessly yellow. Full base occupies 85% cell height. Keep big head tiny torso ratio EXACTLY reference.
TOP RIGHT cell: ONLY the original gray rectangular hammer with brown vertical handle, PLUS original yellow-orange hand gripping its lower handle and short orange forearm extending right toward where the shoulder would be. No head/body. Isolate this complete hammer+hand+forearm cutout. Upright hammer, hand low, shoulder attachment on RIGHT side of the hand. Match original tool proportions. Large isolated part about 65% cell height.
BOTTOM LEFT cell: ONLY original character's free arm (viewer right), short orange-yellow pixel arm and little fist, extends diagonally downward toward right from shoulder at upper left. No body, no hammer. Around 35% cell height.
BOTTOM RIGHT cell: ONLY the two dark brown rectangular eyes with cream narrow highlights and short brown rectangular mouth between and below them, matching original face feature spacing. No face backing, background transparent. Group about 65% cell width.
Crucial: four discrete assets with no overlap, no duplicated full characters, NO extra assets. Retain the approved reference's simple large pixel steps, cheerful neutral expression once assembled. This is for actual SpriteKit rig animation, each cell independently texture-cropped.
```

### 망치 키 포즈 재작업 (2026-09-21, 이전 연결 팔 방식 폐기)

- Aseprite MCP로 몸통 3종과 고정 길이 손/팔 2종을 그렸다. 정면 원화를 늘이는 연결 도형은 사용하지 않는다.
- 불러잡기 2.7초: 몸 방향·중심 이동 → 짧은 팔로 대기 → 잡으며 뒤로 밀림 → 머리의 지연 반동 → 팔을 접고 복귀.
- 던져잡기 2.1초: 웅크림 → 몸 펴기 → 시선 추적 → 받으며 눌림. 큰 분출 효과는 적용하지 않는다.
- 실제 망치 위치를 시간 기준으로 샘플링해 최대 3개의 짧은 잔상을 만든다. 화면 밖 비행 창에서도 같은 잔상·회전 경계를 사용한다.
- 원래 손에서 새 손으로, 새 손에서 원래 손으로 넘어갈 때 도구가 보이는 동안 끊어지지 않도록 연결했다. 종료·드래그·새 작업·동작 줄이기에서 원래 원화와 도구 상태를 복원한다.
- 코어 201개 테스트, Xcode Debug, HammerPoseSmoke/HammerTrickSmoke/CompanionClickSmoke/EmotionSceneSmoke 통과.
- HammerPoseSmoke는 80/128/192pt·좌우 비행, 팔 배율 고정, 잡은 뒤 프레임 간 위치 연속성, 잔상과 중단 정리를 검사한다. 시각적 품질 판단과 기능 검사는 별개다.
- 결과: `.build/hammer-keypose-preview/recall-192-right.gif`, `toss-192-right.gif`. 원본: `SourceArt/Spirit/hammer-keyposes.aseprite`.

### 망치 왼쪽 당기기

망치에서 시작한 드래그는 캐릭터 이동과 분리됩니다. 왼쪽으로 캐릭터 크기의 18%(최소18pt) 이상 당겨 놓으면 놓치기 → 놀람 → 빈손으로 기다림 → 가속 귀환 → 불티9개와 충격 반동 → 작업 복귀를 재생합니다. 짧은 당김은 복귀하며 더블클릭 묘기는 유지됩니다. 네이티브 입력 회귀 검사와 좌우/크기별 손잡이 정렬 검사를 수행했습니다.

### 바닥에 기대는 대기 망치

대기·타이핑에서는 망치 머리를 발 옆 바닥에 수평으로 두고, 두 팔을 배 앞에 모읍니다. 팔은 손잡이나 얼굴 쪽으로 올라가지 않습니다. 숨쉬기와 타이핑 중 접지점은 고정됩니다. 작업 시작은 0.4초 전환 초반에 팔을 풀고 손잡이를 잡은 뒤 망치를 들어 올리고 손의 잡는 위치를 바꾸며, 마지막 타격 회복 뒤 내려놓습니다. 사용자 묘기도 바닥에서 0.42초 준비 후 연결합니다. `GroundedHammerSmoke`에서 실제 크기별 접지·손잡이·팔 길이와 전환 이미지를 검증합니다.
