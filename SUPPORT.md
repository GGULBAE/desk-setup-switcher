# Support

Desk Setup Switcher is preparing its first public beta. There is currently no supported public download; local and CI-generated ad-hoc-signed DMGs are development evidence, not releases.

## Where to ask

- Use the [support question form](https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=support_question.yml) for installation, Capture → Edit → Review & Apply, permissions, import/export, diagnostics, recovery, or removal questions.
- Use the [bug report form](https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=bug_report.yml) for reproducible incorrect behavior.
- Use the [feature request form](https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=feature_request.yml) only for changes that fit the documented local-only and explicit-apply scope.
- Follow the current [SECURITY.md](SECURITY.md) instructions for vulnerabilities, unsafe mutations, exposed secrets, privacy leaks, or rollback failures. Private vulnerability reporting is currently disabled; request a private channel without including security details in the initial contact, and never use a public issue.

The issue tracker is public. Remove passwords, serial numbers, real SSIDs, exact locations, IP host portions, device UIDs, home-directory paths, and unredacted diagnostics before submitting anything.

## What to include

Provide the application version or commit, macOS version, Mac architecture, where the app came from, the exact step that failed, the expected result, the actual result, and any recovery already attempted. State whether Capture or Apply was confirmed and whether a real system setting changed. Use synthetic profile and device names.

## Planned public-beta support boundary

- The planned initial target is Apple Silicon with a macOS 14 Sonoma deployment target. This is not yet a supported-runtime claim: the exact signed candidate must pass the full clean lifecycle on Apple Silicon/macOS 14 Sonoma before publication.
- Current runtime evidence is Apple Silicon on macOS 26.5.2. The project also cross-builds and packages an `x86_64` slice, but no physical Intel Mac has passed the runtime, install, upgrade, or rollback matrix; Intel is not planned for the initial beta.
- Display, Audio, and Network behavior must be interpreted using the verification levels in the [support matrix](docs/SUPPORT-MATRIX.md). Mock-verified or live-read behavior is not hardware-mutation verification.
- Accounts, cloud sync, telemetry, automatic profile switching, App Store distribution, an in-app updater, shell execution, UI automation, private APIs, and third-party app configuration are outside the product scope.
- Keyboard behavior, accessibility names/values, and non-color state cues are maintained. Comprehensive assistive-technology certification is outside the initial beta scope.

After `v0.1.0` is published, the latest public beta is the primary support target. The preceding beta may receive critical fixes for up to 30 days when a safe backport is practical. Stable support policy is defined in [Compatibility and versioning](docs/COMPATIBILITY.md).

Support and triage are volunteer-maintained and best effort. Response targets, responsibilities, and release authority are documented in [GOVERNANCE.md](GOVERNANCE.md).

## 한국어 안내

설치, 사용, 권한, 가져오기·내보내기, 진단, 복구 관련 질문은 위의 **support question form**을 이용해 주세요. 이슈는 공개됩니다. 비밀번호, 실제 SSID, 정확한 위치, IP 호스트 부분, 기기 UID, 홈 경로, 가리지 않은 진단 정보는 반드시 제거해야 합니다. 현재 비공개 취약점 신고 기능은 비활성 상태입니다. 첫 연락에는 보안 상세를 포함하지 말고 [SECURITY.md](SECURITY.md) 안내에 따라 비공개 채널을 요청하세요.

계획된 첫 public beta 대상은 macOS 14 Sonoma 배포 타깃의 Apple Silicon Mac입니다. 아직 macOS 14 지원 완료를 주장하지 않습니다. 정확한 서명 후보가 Apple Silicon/macOS 14 Sonoma에서 전체 clean lifecycle을 통과해야 하며, 현재 실기 런타임 증거는 Apple Silicon/macOS 26.5.2에 한정됩니다. Intel은 첫 beta 지원 대상이 아닙니다.
