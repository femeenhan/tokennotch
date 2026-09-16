# 기본 동작 확인

2026-09-16. 확정한 불꽃 대장장이를 파츠 기반 SpriteKit 리그로 교체했다. 전체 PNG를 기울이거나 네 장의 텍스처를 교체하는 방식이 아니다.

## 확인 방법

메뉴 막대 불꽃 아이콘 또는 정령 몸통 중앙 클릭 → **기본 동작 확인…**.

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
swiftc -parse-as-library -swift-version 6 -I Packages/SpiritCore/.build/debug -L Packages/SpiritCore/.build/debug -lSpiritCore App/Companion/SpiritScene.swift Tests/RigSceneSmoke.swift -o .build/rig-smoke/RigSceneSmoke
.build/rig-smoke/RigSceneSmoke /tmp/build-spirit-rig-frames
```

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
