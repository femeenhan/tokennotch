# 불꽃정령 편집 원본

`smith-rig.aseprite`는 앱이 사용하는 1254×1254 파츠 시트의 편집 원본이다.
몸통, 불꽃 머리, 망치와 손, 빈손 팔, 왼쪽 눈, 오른쪽 눈, 입을 각각 레이어로 분리했다.
캔버스 크기와 파츠 위치는 `SpiritScene.buildRig()`의 크롭 좌표에 맞춰 고정한다.

`smith-face.aseprite`는 Aseprite MCP로 직접 그린 작은 표정 원본이다.
왼쪽 눈 `(0,0,7,9)`, 오른쪽 눈 `(9,0,7,9)`, 입 `(18,0,9,3)`을 담는다.
리그 원본에는 눈을 13배, 입을 12배로 정수 확대해 배치했다.
일반 수정은 `smith-rig.aseprite`에서 진행하며, 얼굴을 다시 설계할 때 작은 표정 원본을 사용한다.

`hammer-parts.aseprite`는 던지기·소환용 624×396 원본이다.
왼쪽 312×396은 손에 가려져 있던 자루까지 복원한 망치이며, 오른쪽은 손과 팔이다.
각각 `hammer-tool`, `hand-and-arm` 레이어로 편집한다. 앱은 이 파일의 두 파츠를 사용해
망치가 날아갈 때 손을 캐릭터에 남기고, 돌아오면 동일한 손잡이 지점에 붙인다.

## 앱에 반영하기

프로젝트 루트에서 다음 명령으로 **한 프레임의 전체 캔버스**를 내보낸다.
투명 여백을 자르거나 레이어별로 따로 출력하지 않는다.

```sh
aseprite --batch SourceArt/Spirit/smith-rig.aseprite --save-as App/Resources/Spirit/smith-rig-atlas.png
aseprite --batch SourceArt/Spirit/hammer-parts.aseprite --save-as App/Resources/Spirit/hammer-parts.png
```

리그 원본은 한 프레임이다. 호흡·깜빡임·망치질은 `SpiritRigMotion.swift`,
불꽃 흐름·불씨·상태별 색상은 `SpiritScene.swift`에서 처리한다.
머리의 불꽃 셰이더도 원화와 같은 주홍·호박·노랑 팔레트를 사용한다.
기준 캐릭터인 `App/Resources/Spirit/smith-spirit.png`는 보존했다.

## 2026-09-20 정리

- 기존 형태와 파츠 좌표를 유지하면서 잔색을 제한된 팔레트로 정리했다.
- 반투명 가장자리와 고립된 작은 픽셀을 정리했다.
- 작은 계단형 눈 모서리, 눈의 반사광, 얕은 미소를 직접 그렸다.
- 망치질의 팔·몸 압축 연결과 비대칭 깜빡임 타이밍을 개선했다.

MCP의 기본 도구로 얼굴을 그리고 최종 PNG를 내보냈다.
레이어 분리·기존 원화의 일괄 색상 정리·정수 확대는 Aseprite의 Lua 배치 기능을 병행했다.

## 2026-09-21 망치 키 포즈 재작업

`hammer-keyposes.aseprite`는 Aseprite MCP의 create_canvas/draw_pixels/export_sprite로 만든 160×32 시트다.
32×32 셀 5개는 3/4 몸통, 옆으로 돌아선 몸통, 받는 순간의 몸통, 편 손/짧은 팔, 쥔 손/짧은 팔 순이다.
원래 머리·얼굴·망치 원화는 유지한다. 팔 원화는 1:1 크기이며 늘이지 않는다.
몸통 그림 선택과 머리·어깨·중심 이동은 HammerTrickPose 키 포즈로 연결한다.
망치 잔상은 실제 비행 위치의 32/64/96ms 전 샘플을 사용하며 화면 밖 패널에도 같은 샘플을 전달한다.

```sh
aseprite --batch SourceArt/Spirit/hammer-keyposes.aseprite --save-as App/Resources/Spirit/hammer-keyposes.png
```

### Hero hammer

`hero-hammer.aseprite` is the Aseprite MCP-authored 32×48 isolated hammer. Export to `App/Resources/Spirit/hero-hammer.png`. Render at 18×27 rig units with grip anchor `(0.5, 0.3125)` (bottom-left convention). The old `hammer-parts.png` still supplies the unchanged hand; its shoulder-to-palm offset must not scale with the new tool.
