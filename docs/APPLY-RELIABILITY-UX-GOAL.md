# Apply reliability and editor UX goal

`Desk Setup Switcher`에서 프로필을 수정하고 적용하는 핵심 흐름을 사용자가 신뢰할 수 있는 수준으로 복구하라.

이번 작업은 단순한 시각 정리나 문구 변경이 아니다. 현재 확인된 부분 적용 진입점 단절, 적용 불가능한 스냅샷 값의 기본 포함, 미저장 초안 무시, 불충분한 결과 피드백과 편집기 입력 오류를 실제 SwiftUI·도메인·어댑터 경계에서 수정하고 결정론적 테스트, 영문·한국어 현지화, 문서와 패키지 검증까지 완료한다.

계획이나 목업에서 멈추지 말고 아래 완료 기준을 만족하는 설치·빌드·테스트 가능한 구현과 검증된 로컬 커밋을 만든다. 실제 디스플레이·오디오·네트워크·마우스·키보드 설정 변경은 실행하지 않는다.

## 기준선과 작업 시작 당시 확인된 문제

- 기준 브랜치: 현재 로컬 `master`; 작업 시작 전 사용자 변경과 최신 커밋 상태를 다시 확인한다.
- 작업 시작 자동 기준선: 기본 비라이브 테스트 215개가 통과한다. 이 중 6개 라이브/Keychain 테스트는 명시적 옵트인 없이는 건너뛴다.
- 값이 제거된 로컬 관찰에서는 어댑터가 성공을 보고해도 메뉴에서 항목별 결과를 바로 확인할 수 없는 문제가 드러났다. 진단 원문이나 사용자 값은 저장소 증거에 남기지 않는다.
- 회귀 범위는 합성된 지원 디스플레이 operation과 미지원 DNS omission 조합으로 재현한다. 현재 저장된 프로필 값, 이름, 장치·네트워크 식별정보는 문서나 fixture에 복사하지 않는다.
- 네트워크 스냅샷은 IPv4·DNS·프록시 값을 적용 대상으로 포함할 수 있지만 현재 어댑터는 이 변경을 지원하지 않는다.
- 디스플레이 스냅샷은 회전·활성 상태를 적용 대상으로 포함하지만 현재 어댑터는 이 변경을 지원하지 않는다.
- normal apply는 omission이 하나라도 있으면 실행되지 않는다. force/available-items 계획은 내부에 존재하지만 현재 메뉴에는 진입점이 없다.
- 메뉴 Apply는 편집 중인 dirty draft를 확인하지 않고 저장된 `model.profiles` 값을 사용한다.
- 조건 편집 UI는 제거됐지만 legacy conditions는 계속 평가되어 숨은 적용 차단 요인이 될 수 있다.
- 적용 성공은 어댑터가 쓰기를 수락했다는 결과에 의존하며, 특히 experimental input 설정은 실제 반영값을 즉시 재검증하지 않는다.
- 그룹·옵션 포함 여부와 disclosure 상태가 결합되어 캡처 프로필의 편집 화면이 과도하게 길다.
- Save 활성화 전에 값 유효성을 검사하지 않으며 저장 실패는 필드 위치 없이 일반 오류로만 보인다.

## 사용자 결과

완료 후 사용자는 다음을 경험해야 한다.

1. 프로필에 적용 가능한 값과 적용할 수 없는 값이 섞여 있어도 적용 가능한 값은 명시적 미리보기와 확인 뒤 실행할 수 있다.
2. 현재 어댑터가 적용하지 못하는 값은 스냅샷에 보존되더라도 적용 대상으로 오인되지 않는다.
3. 편집 중인 값을 저장하지 않은 채 Apply를 눌러 이전 값이 조용히 적용되는 일이 없다.
4. 캡처가 일부 값이나 권한을 읽지 못했으면 단순 성공 메시지가 아니라 무엇이 제외됐는지 확인할 수 있다.
5. 적용 뒤 성공·부분 성공·실패·건너뜀을 메뉴에서 즉시 확인하고 상세 결과로 이동할 수 있다.
6. 적용 성공 표시는 가능한 범위에서 새 읽기 전용 스냅샷으로 재확인된 결과와 일치한다.
7. 설정 그룹과 옵션은 포함 여부를 유지한 채 접고 펼칠 수 있고, 일반 사용자는 원시 숫자나 식별자를 불필요하게 입력하지 않는다.
8. 잘못된 값은 저장 전에 해당 필드에서 설명되며 키보드와 VoiceOver로도 오류를 찾을 수 있다.

## P0 — 적용 경로 복구

### 하나의 상황별 기본 Apply 행동

- 프로필 행은 하나의 분명한 기본 Apply 버튼을 유지한다. ellipsis와 별도 가용성 검토 버튼은 다시 추가하지 않는다.
- `Ready`이고 실제 operation이 있으면 버튼은 `Apply…`/`적용…`이며 normal preview를 연다.
- `Partial`이고 실행 가능한 operation이 있으면 같은 위치의 버튼이 `Apply Available…`/`가능한 설정 적용…`으로 바뀌고 force preview를 연다.
- force preview는 실행될 값과 건너뛸 값을 분리하고 사용자의 명시적 확인 전에는 아무것도 변경하지 않는다.
- operation이 0개이면 버튼은 비활성화하고 `The Mac already matches this profile` 또는 `No available setting can be applied`를 정확히 구분한다.
- `Unavailable`, transaction lock, display confirmation 대기와 준비 중 상태는 텍스트와 심볼로 이유를 표시한다.
- 준비 중 중복 탭을 막는 per-profile preparing 상태를 둔다. 메뉴를 열 때 readiness를 갱신하더라도 유효한 cached state가 있으면 모든 프로필을 불필요하게 전역 비활성화하지 않는다.

### 미지원 스냅샷 값 정규화

- 디스플레이 회전과 활성 상태 값은 읽기 전용 스냅샷 값으로 보존하되 `isIncluded = false`로 캡처한다.
- IPv4, DNS, web proxy와 secure web proxy 값은 읽기 전용 스냅샷 값으로 보존하되 `isIncluded = false`로 캡처한다.
- 새 캡처뿐 아니라 기존 로컬 프로필과 가져온 이전 문서도 같은 규칙으로 idempotent하게 정규화한다.
- 정규화는 값 자체를 삭제하지 않고 적용 포함 플래그만 끈다. 필요하다면 명시적인 schema migration을 추가하고 backup·validation·import 계약을 유지한다.
- 지원되지 않는 항목을 끈 결과 그룹에 실제 적용 가능한 leaf가 하나도 없으면 그룹도 적용 대상에서 제외한다.
- 지원 범위가 미래에 바뀌기 전까지 UI에서 이 항목의 적용 토글을 제공하지 않는다.
- normal/force 계획과 readiness가 정규화된 적용 대상만 사용하도록 회귀 테스트를 추가한다.

### legacy conditions 정책

- 조건 편집 UI는 다시 추가하지 않는다.
- UI에서 관리할 수 없는 legacy/imported conditions가 normal apply를 조용히 막아서는 안 된다.
- schema round-trip 호환에 필요하면 조건 데이터를 보존할 수 있지만 현재 수동 적용의 readiness와 실행 허용에는 non-blocking으로 취급한다.
- 자동 적용은 추가하지 않는다.
- legacy condition이 있는 가져온 프로필도 다른 유효한 설정이 있으면 정상적으로 계획·미리보기할 수 있음을 테스트한다.
- README, PRODUCT, TECHNICAL-SPEC와 support matrix에서 이 dormant compatibility 정책을 명확히 기록한다.

## P0 — 미저장 초안과 적용의 일관성

- Apply 대상 프로필에 dirty draft가 있으면 저장된 이전 프로필을 바로 적용하지 않는다.
- 같은 프로필의 dirty draft에서는 `Save and Apply`와 `Cancel`을 제공한다. 저장 실패 시 적용하지 않고 초안과 입력값을 유지한다.
- 다른 프로필의 dirty draft가 열려 있으면 기존 save/discard/cancel 보호 흐름을 재사용하되 어떤 프로필을 저장하고 어떤 프로필을 적용할지 문구로 명확히 표시한다.
- `Discard and Apply`가 제공되는 경우 destructive 의미와 대상 프로필을 분명히 표시한다.
- 편집기 하단에는 유효한 dirty draft에서 사용할 수 있는 `Save and Apply` 행동을 제공할 수 있다. 이 행동도 동일한 최신 plan·preview 계약을 사용한다.
- Apply 직전에는 기존 계약대로 현재 프로필, 조건 정책, capabilities와 system snapshots를 다시 읽고 stale plan이면 미리보기로 돌아간다.
- draft 저장과 apply 요청 사이에 프로필 메타데이터가 갱신되어도 사용자가 편집한 값과 최신 lastApplication 메타데이터를 모두 보존한다.

## P1 — 캡처 결과의 신뢰도

- 캡처 성공 결과를 `created` 하나로 축약하지 말고 저장된 항목, 적용 대상에서 제외된 항목, unreadable, permission-required와 unsupported 수를 typed result로 전달한다.
- 완전한 성공과 부분 캡처를 구분한다.
- 부분 캡처이면 메뉴에서 잠깐 사라지는 성공 한 줄만 보여주지 말고 compact result banner를 제공한다.
- Wi-Fi SSID를 권한 때문에 읽지 못했으면 비밀번호·SSID 값을 노출하지 않고 `Wi-Fi network was not captured`와 권한 설정으로 이동하는 선택적 행동을 제공한다. 권한 요청을 자동 실행하지 않는다.
- 캡처가 현재 프로필의 설정을 교체하는 동작이면 `added`가 아니라 `replaced`/`updated` 의미의 정확한 문구를 사용한다.
- 캡처 결과가 적용 가능한 leaf를 하나도 만들지 못하면 프로필을 생성하지 않고 구체적인 비민감 오류를 보여준다.

## P1 — 적용 결과와 read-back 검증

- 적용 요청이 끝나면 메뉴에 compact result card를 표시한다.
- 카드에는 profile, overall status, succeeded/failed/skipped/unsupported count, applied time과 `Details` 행동을 제공한다.
- 실패와 부분 성공은 작은 회색 문구만으로 전달하지 않고 텍스트·심볼·VoiceOver announcement를 함께 사용한다.
- 상세 화면은 설정 그룹과 항목별 결과, 롤백 결과와 사용자에게 필요한 복구 안내를 보여준다. 민감한 원시 값은 노출하지 않는다.
- display safety confirmation이 있는 작업은 Keep/Revert가 끝난 뒤 최종 결과를 확정한다.
- 안전 확인이 없는 작업은 실행 뒤 새로운 읽기 전용 snapshot/plan을 사용해 실행한 operation의 목표 상태가 남아 있는지 확인한다.
- post-apply read-back에서 동일 operation이 여전히 필요하면 단순 `Applied`가 아니라 `Not verified` 또는 실패/부분 성공으로 표시하고 itemized reason을 남긴다.
- force apply에서 의도적으로 건너뛴 omission은 verification failure와 구분한다.
- experimental input은 CFPreferences synchronize 성공만으로 최종 성공을 주장하지 않는다. 즉시 읽은 값이 목표와 일치하는지 확인하고, macOS의 실제 체감 동작은 하드웨어 수동 검증 전까지 `mock/read-back verified`로만 문서화한다.
- readiness refresh 뒤 오래된 `operationalStatusByProfile = .applied/.failed`가 최신 계산 상태를 영구히 가리지 않게 상태 수명과 우선순위를 수정한다.

## P1 — 프로필 편집기 정보 구조

### 포함과 disclosure 분리

- 그룹의 `프로필에 포함` 상태와 펼침 상태를 분리한다.
- 옵션의 `프로필에 포함` 상태와 값 편집 disclosure도 분리한다.
- 포함된 그룹/옵션을 접어도 적용 대상에서 빠지거나 값이 사라지지 않는다.
- 캡처 프로필을 처음 열 때 모든 그룹·옵션이 동시에 펼쳐진 긴 화면을 만들지 않는다. 선택한 그룹 하나 또는 사용자가 펼친 항목만 연다.
- 접힌 행은 현재 목표값의 짧은 요약과 포함/제외 상태를 보여준다.
- 제외했지만 보존된 값은 `Off · 4 saved values`처럼 값이 남아 있음을 정확히 표현한다.

### 직관적인 타입별 컨트롤

- 디스플레이 primary는 여러 개의 독립 Boolean보다 한 개의 `Primary display` picker로 표현한다.
- 디스플레이 mode는 현재 연결된 디스플레이가 제공하는 지원 모드 picker를 우선한다. 선택지는 read-only snapshot 경로의 typed ephemeral catalog로 전달하며 프로필 JSON에 지원 모드 목록을 저장하지 않는다.
- 저장된 모드가 현재 연결 상태에서 보이지 않으면 값을 보존하고 `Saved mode — currently unavailable`로 표시한다.
- 고급 원시 mode 입력이 꼭 필요하면 기본 경로에서 접고 저장 전에 실제 지원 모드와 일치하는지 검증한다.
- 오디오 volume은 0–100 slider와 숫자 값을 함께 제공한다.
- mute, natural scrolling, function keys와 Wi-Fi power는 `include`와 목표 On/Off가 서로 다른 의미임을 레이블과 접근성 값으로 구분한다.
- pointer speed, key repeat와 initial delay는 raw preference 숫자만 요구하지 말고 slow/fast 의미가 있는 slider 또는 단계형 control을 제공한다. 정확한 숫자는 선택적 고급 정보로 둔다.
- 오디오 장치는 가능한 경우 친숙한 이름 picker를 사용하고 UID는 Advanced에서만 보여준다.
- Wi-Fi network는 현재 구현이 macOS에 이미 저장된 네트워크만 안전하게 연결한다는 제한을 입력 옆에 표시한다. 임의 SSID가 바로 연결될 것처럼 보이게 하지 않는다.
- IPv4, DNS, proxy, display rotation과 active state는 `Snapshot only` read-only 영역으로 옮긴다.

### 인라인 검증

- pure draft validator를 추가해 Save 버튼 활성화 전에 필수값, 범위, 빈 값, mode, 포트와 IP/DNS 형식을 검사한다.
- option을 켤 때 현재 snapshot 값이나 안전한 기본값이 있으면 채운다. 안전한 값이 없으면 명확한 `Choose` 상태와 인라인 필수 오류를 보여준다.
- 카테고리만 켜고 leaf가 0개이면 저장은 가능하더라도 메뉴에 가서 처음 알게 하지 말고 편집기에서 `Select at least one setting`을 표시한다.
- 오류는 field identifier와 localized message를 갖고 해당 control에 `accessibilityInvalid`와 설명을 연결한다.
- Save 시 오류가 있으면 첫 오류로 포커스를 옮기거나 오류 요약에서 해당 필드로 이동할 수 있게 한다.
- generic storage 오류와 validation 오류를 구분하고 원시 민감값이나 시스템 오류 문자열을 노출하지 않는다.

## P2 — 메뉴·키보드·접근성 마감

- compact header의 Capture, Settings, Quit 배치는 유지한다.
- 프로필 이름, status, disabled/partial reason과 Apply/Edit가 340pt 기본 폭과 영문·한국어 긴 문자열에서 겹치지 않는다.
- Apply 준비, 실행, 결과와 read-back 상태를 색상에만 의존하지 않는다.
- icon-only actions에는 localized accessibility label과 help가 있다.
- `⌘S`, `⌘,`, `⌘Q`, Return/default, Escape/cancel 계약을 유지하고 새 Save and Apply 대화상자도 키보드로 완료할 수 있다.
- VoiceOver는 include toggle과 목표 On/Off 값을 서로 다른 이름·값으로 읽어야 한다.
- 적용 완료, 부분 성공, 실패와 저장 오류는 포커스를 빼앗지 않는 announcement를 제공한다.
- Increase Contrast, Reduce Transparency와 최소 Settings 크기에서도 주요 행동이 사라지지 않는다.

## 아키텍처와 안전 경계

- SwiftUI/AppKit은 `DeskSetupSwitcher` 앱 레이어에 유지한다.
- action selection, dirty-apply decision, capture summary, field validation, result summary와 status lifetime처럼 결정론적으로 검증해야 하는 로직은 `DeskSetupCore` 또는 `DeskSetupPresentation`의 순수 타입으로 추출한다.
- UI는 concrete system framework mutation을 직접 호출하지 않는다.
- adapter의 `snapshot`, `validate`, `plan`, `apply`, `rollback`, `capability`, `diagnostics` 계약과 transaction ordering을 보존한다.
- 지원되지 않는 mutation을 이번 작업에서 새로 구현하지 않는다.
- display supported-mode 선택지처럼 편집 시점에만 필요한 catalog는 typed ephemeral data로 전달하며 영속 profile identity와 섞지 않는다.
- imported JSON은 계속 untrusted input으로 validation·size·path 방어를 거친다.
- 실제 SSID, IP, 장치 UID, 시리얼, 정확한 위치, 프로필 이름이나 진단 원문을 fixture·스크린샷·커밋에 넣지 않는다.
- telemetry, analytics, cloud, UI automation, arbitrary shell execution, private API와 third-party app configuration 변경을 추가하지 않는다.

## 결정론적 테스트

최소한 다음 회귀 테스트를 추가한다.

### 적용 행동

- Ready + operations는 normal primary action을 만든다.
- Partial + force operations는 같은 위치의 available-items primary action을 만든다.
- Partial + zero operations는 비활성화된다.
- unsupported DNS omission과 supported display operation이 함께 있을 때 force preview는 display operation을 실행 가능하게 유지한다.
- 준비 중 중복 Apply 요청은 하나만 남는다.
- cached readiness와 refresh-in-progress 상태가 안전한 action selection을 만든다.

### 캡처와 migration

- 새 display snapshot은 rotation/active 값을 보존하지만 제외한다.
- 새 network snapshot은 IPv4/DNS/proxy 값을 보존하지만 제외한다.
- 이전 profile/import migration은 같은 플래그를 끄고 사용자 값을 보존하며 두 번 실행해도 결과가 같다.
- 정규화 후 leaf 0개인 group은 applicable payload를 만들지 않는다.
- permission-required SSID는 partial capture summary를 만들고 비밀값을 포함하지 않는다.

### draft와 validation

- 같은 dirty profile에서 Apply는 save decision을 요구하고 저장 전에는 plan을 만들지 않는다.
- 저장 성공 뒤 최신 draft 값으로 preview를 만든다.
- 저장 실패·cancel은 apply하지 않고 draft를 보존한다.
- 다른 dirty profile에서 save/discard/cancel 대상이 정확하다.
- group/option disclosure를 접어도 include와 값은 유지된다.
- nil, 범위 밖 숫자, 빈 device, 잘못된 mode/IP/port는 field-specific error를 만든다.
- 유효하지 않은 draft에서는 Save/Save and Apply가 실행되지 않는다.

### 결과와 검증

- success, partial, failure, rollback과 not-verified 결과 요약을 구분한다.
- post-apply plan에 동일 operation이 남으면 `Applied`로 확정하지 않는다.
- force omission은 read-back failure와 구분한다.
- readiness refresh가 오래된 applied/failed override를 정리한다.
- input write 후 값 불일치는 성공으로 기록되지 않는다.

### 현지화와 접근성 구조

- 모든 새 사용자 문자열의 English/Korean key와 placeholder가 일치한다.
- primary action label, capture summary, validation error와 result status가 두 언어에서 결정론적으로 생성된다.
- icon-only action, include toggle, target value, error와 result announcement에 접근성 이름·값이 존재한다.

## 읽기 전용 UI 검토

가능하면 합성·비식별 profile과 mock adapter로 다음 상태를 렌더링해 확인한다.

1. Ready normal apply
2. Partial available-items apply with one supported operation and one omission
3. Unavailable and no-op
4. dirty draft Save and Apply decision
5. partial capture result with permission-required and snapshot-only values
6. inline validation errors
7. success, partial, failed and not-verified result cards
8. collapsed/expanded display, audio, network and input groups
9. English/Korean and long strings at minimum/default Settings sizes
10. keyboard focus order and accessibility labels

UI 자동화로 실제 앱을 조작하지 않는다. 실제 Apply, Capture, TCC 요청, login-item 변경과 hardware mutation은 수행하지 않는다. 화면 증거가 필요하면 synthetic fixture만 사용하고 저장소에 개인정보가 포함된 캡처를 추가하지 않는다.

## 문서와 증거

동작과 검증 상태에 맞춰 다음을 갱신한다.

- `README.md`
- `CHANGELOG.md`
- `docs/PRODUCT.md`
- `docs/ROADMAP.md`
- `docs/SUPPORT-MATRIX.md`
- `docs/COMPLETION-CRITERIA.md`
- `docs/TECHNICAL-SPEC.md`
- `docs/ARCHITECTURE.md`
- 기존 `docs/UI-REFINEMENT-GOAL.md`에는 이 follow-up 목표가 이전 결정을 대체한 이유와 최종 증거를 짧게 연결한다.

지원하지 않는 mutation, 실행하지 않은 hardware/VoiceOver/TCC 검증과 mock/read-back 검증을 명확히 구분한다.

## 비목표

- DNS, DHCP/static IPv4, proxy, display rotation 또는 activation mutation 신규 구현
- 자동 프로필 전환이나 background condition monitoring
- 조건 편집 UI 재도입
- 로그인 항목·진단·About의 전면 재설계
- arbitrary SSID credential 입력 또는 비밀번호 저장
- third-party device/app 설정 변경
- 실제 hardware mutation·rollback 시험
- Developer ID signing, notarization, release publication
- Figma 보드나 별도 커스텀 디자인 시스템

## 작업 순서

1. 현재 branch, worktree, 설치/테스트 기준선과 사용자 변경을 확인한다.
2. 재현 가능한 순수 action/capture/validation/result 모델과 실패 테스트를 먼저 추가한다.
3. 기존·가져온 profile의 unsupported inclusion normalization을 구현한다.
4. 상황별 primary Apply와 dirty-draft 보호를 구현한다.
5. capture summary와 apply result/read-back verification을 구현한다.
6. editor disclosure 분리, typed controls와 inline validation을 구현한다.
7. English/Korean, keyboard와 accessibility를 마감한다.
8. synthetic read-only UI 검토를 수행하고 수행하지 못한 항목을 기록한다.
9. 관련 문서를 실제 증거에 맞게 갱신한다.
10. `make lint`, `make test`, `make verify`, `git diff --check`를 통과한다.
11. 의도한 파일만 stage하고 간결한 behavior-focused local commit을 만든다. 사용자가 별도로 요청하지 않으면 push하지 않는다.

## 최종 로컬 증거 — 2026-07-14

- 전체 비라이브 `make verify`가 통과했다. 기본 케이스는 XCTest 124개 중 5개 opt-in skip, Swift Testing 166개 중 1개 opt-in skip으로 총 290개이며 실패는 0개다. 두 프레임워크 전체에서 read-only hardware skip은 5개, Keychain-write skip은 1개다.
- English/Korean catalog·source policy lint, Swift Debug/Release, universal Xcode Debug/Release, Xcode Analyze, DMG 생성·체크섬, mounted metadata/resources/architectures와 ad-hoc signature 분류가 통과했다. 별도 `git diff --check`도 통과했다.
- 검증 artifact는 `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg`, SHA-256 `417ffbb20b6a77b9037f42d5acb998574460374675e746715474e17f9f772615`이며 `x86_64 arm64`를 포함한다. 서명은 무결성용 ad-hoc이고 Developer ID·notarization은 없다.
- pure test와 SwiftUI/accessibility 소스 기반 합성 상태 검토는 Ready normal, Partial available-items, unavailable/no-op, dirty decision, partial capture, inline validation, result status, disclosure 보존을 확인했다. localization lint와 정적 소스 검토는 영어·한국어 키와 접근성 이름·값 구조를 확인했다.
- 위 검토는 rendered screenshot, 최소 크기 레이아웃, 실제 키보드 순회, VoiceOver 발화·포커스 또는 UI 자동화 증거가 아니다. 실제 Apply/Capture, TCC, login-item 변경, live read, Keychain write와 hardware mutation/rollback은 실행하지 않았다.
- 개인정보 검사에서는 실제 SSID, IP host, 위치, UID, serial, 사용자 경로 또는 진단 원문을 fixture·문서·화면 증거에 추가하지 않았다.
- 이 증거를 포함하는 behavior-focused local commit과 최종 clean-worktree status는 완료 인계에서 기록한다. Push와 새 CI run은 이번 목표에 포함하지 않았고 수행하지 않았다.

## 완료 기준

다음 항목이 모두 구현·테스트·문서화되고 검증된 커밋에 포함되기 전에는 목표를 완료 처리하지 않는다.

- [x] Partial profile에서 하나의 기본 버튼으로 available-items preview와 실행 경로에 진입할 수 있다.
- [x] ellipsis와 별도 availability-review 버튼은 없다.
- [x] 새 캡처와 기존/imported profile에서 unsupported snapshot-only leaf가 적용 대상에서 제외되고 값은 보존된다.
- [x] legacy conditions가 숨은 normal-apply 차단 요인이 아니다.
- [x] dirty draft가 있는 Apply는 save/discard/cancel 정책을 거치며 이전 저장값을 조용히 적용하지 않는다.
- [x] 캡처 결과가 complete/partial/failure와 제외 이유를 구분한다.
- [x] 메뉴에서 apply 결과와 항목 수를 즉시 확인하고 상세 결과로 이동할 수 있다.
- [x] post-apply read-back 불일치나 read-back unavailable을 `Applied`로 확정하지 않는다.
- [x] 오래된 applied/failed 표시가 최신 readiness를 가리지 않는다.
- [x] 그룹·옵션 include와 disclosure가 분리되고 접어도 값이 보존된다.
- [x] display/audio/network/input의 기본 컨트롤이 원시 값 입력보다 안전한 picker/slider/summary를 우선한다.
- [x] snapshot-only 값을 편집 가능한 적용 옵션처럼 노출하지 않는다.
- [x] Save 전에 field-level validation이 동작하고 오류가 키보드·VoiceOver 구조로 식별된다.
- [x] 새 문자열의 English/Korean 현지화와 접근성 이름·값이 있다.
- [x] 개인정보가 fixture, 로그, 문서 또는 화면 증거에 추가되지 않는다.
- [x] 새 결정론적 회귀 테스트와 기존 기본 테스트가 모두 통과한다.
- [x] `make verify`와 별도 `git diff --check`가 통과한다.
- [x] README, roadmap, support matrix, completion ledger, technical/architecture 문서와 changelog가 실제 증거와 일치한다.
- [x] 의도한 변경만 포함한 검증된 로컬 커밋이 존재하고 worktree가 깨끗하다. 이 문서를 포함하는 최종 커밋과 완료 인계의 clean-worktree 확인을 증거로 삼는다.
- [x] 실행하지 않은 live mutation, full VoiceOver, TCC와 hardware 검증을 완료했다고 주장하지 않는다.
