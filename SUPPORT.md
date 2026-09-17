# Support

Desk Setup Switcher is preparing its first public beta. There is currently no supported public download; local and ordinary CI-generated DMGs are development evidence, not releases. The approved public beta will be a free Developer ID-unsigned GitHub Release and will require a documented one-time **Open Anyway** decision.

## Where to ask

- Use the [support question form](https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=support_question.yml) for installation, Capture → Edit → Review & Apply, permissions, import/export, diagnostics, recovery, or removal questions.
- Use the [bug report form](https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=bug_report.yml) for reproducible incorrect behavior.
- Use the [feature request form](https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=feature_request.yml) only for changes that fit the documented local-only and explicit-apply scope.
- Follow the current [SECURITY.md](SECURITY.md) instructions for vulnerabilities, unsafe mutations, exposed secrets, privacy leaks, or rollback failures. Private vulnerability reporting is currently disabled; request a private channel without including security details in the initial contact, and never use a public issue.

The issue tracker is public. Remove passwords, serial numbers, real SSIDs, exact locations, IP host portions, device UIDs, home-directory paths, and unredacted diagnostics before submitting anything.

## What to include

Provide the application version or commit, macOS version, Mac architecture, where the app came from, the exact step that failed, the expected result, the actual result, and any recovery already attempted. State whether Capture or Apply was confirmed and whether a real system setting changed. Use synthetic profile and device names.

## Planned public-beta support boundary

- The planned initial target is Apple Silicon with a macOS 14 Sonoma deployment target. This is not yet a supported-runtime claim: the exact unsigned release candidate must pass the full clean lifecycle on Apple Silicon/macOS 14 Sonoma before publication.
- Current runtime evidence is Apple Silicon on macOS 26.5.2. The project also cross-builds and packages an `x86_64` slice, but no physical Intel Mac has passed the runtime, install, upgrade, or rollback matrix; Intel is not planned for the initial beta.
- The current profile surface has ten settings across **Display + Sound + Keyboard**: main display, resolution, output device/volume/mute, input device/volume, key repeat speed, repeat delay, and keyboard brightness. Capture queries Display/Audio/Input and does not request Location permission. Repeat values use experimental undocumented preference keys. Brightness is experimental on macOS 15 or later and is available only with already-granted Input Monitoring access when public CoreHID finds exactly one compatible readable/writable backlight element from a built-in HID device. Background Capture checks access without requesting it; unsupported hardware, denial, and ambiguity are nonfatal and omit only brightness. Pointer speed, natural scrolling, standard-function-key behavior, Network, and other historical fields remain dormant compatibility data. No live Keyboard mutation or hardware verification is claimed. Interpret each capability using the [support matrix](docs/SUPPORT-MATRIX.md).
- Accounts, cloud sync, telemetry, automatic profile switching, App Store distribution, paid Developer ID distribution for the initial beta, an in-app updater, shell execution, UI automation, private APIs, and third-party app configuration are outside the product scope.
- Keyboard behavior, accessibility names/values, and non-color state cues are maintained. Comprehensive assistive-technology certification is outside the initial beta scope.

After `v0.1.0` is published, the latest public beta is the primary support target. The preceding beta may receive critical fixes for up to 30 days when a safe backport is practical. Stable support policy is defined in [Compatibility and versioning](docs/COMPATIBILITY.md).

Support and triage are volunteer-maintained and best effort. Response targets, responsibilities, and release authority are documented in [GOVERNANCE.md](GOVERNANCE.md).

## 한국어 안내

설치, 사용, 권한, 가져오기·내보내기, 진단, 복구 관련 질문은 위의 **support question form**을 이용해 주세요. 이슈는 공개됩니다. 비밀번호, 실제 SSID, 정확한 위치, IP 호스트 부분, 기기 UID, 홈 경로, 가리지 않은 진단 정보는 반드시 제거해야 합니다. 현재 비공개 취약점 신고 기능은 비활성 상태입니다. 첫 연락에는 보안 상세를 포함하지 말고 [SECURITY.md](SECURITY.md) 안내에 따라 비공개 채널을 요청하세요.

계획된 첫 public beta 대상은 macOS 14 Sonoma 배포 타깃의 Apple Silicon Mac입니다. 아직 macOS 14 지원 완료를 주장하지 않습니다. 정확한 unsigned 릴리스 후보가 Apple Silicon/macOS 14 Sonoma에서 전체 clean lifecycle을 통과해야 하며, 현재 실기 런타임 증거는 Apple Silicon/macOS 26.5.2에 한정됩니다. Intel은 첫 beta 지원 대상이 아닙니다. 현재 프로필 범위는 **Display + Sound + Keyboard**의 열 가지 설정 종류(주 디스플레이, 해상도, 출력 기기·음량·음소거, 입력 기기·음량, 키 반복 속도, 반복 지연 시간, 키보드 밝기)입니다. Capture는 Display/Audio/Input에서 사용할 수 있는 값만 저장하며 위치 권한을 요청하지 않습니다. 반복 값은 문서화되지 않은 환경설정 키를 사용하므로 실험적입니다. 밝기는 macOS 15 이상에서 입력 모니터링 접근이 미리 허용되어 있고 공개 CoreHID가 내장 HID 기기에서 읽기·쓰기가 가능한 호환 백라이트 요소를 정확히 하나 찾을 때만 사용할 수 있습니다. 백그라운드 Capture는 접근 상태만 확인하고 자동으로 권한을 요청하지 않으며, 미지원·거부·모호한 검색은 치명적이지 않고 밝기만 제외합니다. 포인터 속도, 자연스러운 스크롤, 표준 기능 키 동작, Network와 다른 과거 필드는 비활성 호환 데이터로 남습니다. 실제 키보드 변경은 검증하지 않았습니다. 첫 릴리스는 Developer ID 미서명·미공증이므로 공식 checksum 확인과 macOS의 일회성 **그래도 열기** 절차가 필요합니다.
