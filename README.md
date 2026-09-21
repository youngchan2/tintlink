# TinkLink

macOS, VS Code, Codex, Chrome의 강조색을 함께 바꾸는 Swift 메뉴 막대 앱입니다.

**[최신 버전 다운로드](https://github.com/youngchan2/tintlink/releases/latest)**

## 설치

- Apple Silicon Mac · macOS 13 이상
- Python, Homebrew, Xcode 등 추가 설치 불필요
- Release의 `TinkLink-버전-macos-arm64.zip`을 받아 압축을 풀고, `TinkLink.app`을 응용 프로그램 폴더로 옮겨 실행하세요.
- 상단 메뉴 막대의 팔레트 아이콘을 누르면 앱이 열립니다. Dock에는 상시 표시되지 않습니다.

현재 배포본은 개발 단계의 ad-hoc 서명이며 Apple Developer ID 서명·공증을 받지 않았습니다. 인터넷에서 받은 앱에 대해 macOS가 실행 경고를 표시할 수 있습니다. 업데이트 후 Chrome 연결 권한을 다시 연결해야 할 수 있습니다.

## 사용법

1. 적용할 대상(macOS, VS Code, Codex, Chrome)을 켭니다.
2. Chrome은 적용할 프로필을 선택합니다. 여러 프로필 선택과 모두 선택을 지원합니다.
3. 일곱 개 색상 동그라미 중 하나를 누릅니다.
4. 하단 결과와 Chrome 프로필별 결과를 확인합니다.

`시스템 색상 가져오기`는 현재 macOS 강조색을 선택된 앱에 적용합니다. 시스템 색상을 계속 감시하는 기능은 아닙니다. 새로고침 버튼으로 현재 설정과 프로필 목록을 다시 읽을 수 있습니다.

대상별 아이콘은 설치된 앱에서 가져옵니다. macOS에는 기본 Mac 아이콘을 사용합니다. 설치되지 않은 앱은 일반 앱 아이콘으로 표시됩니다.

### 대상별 준비

| 대상 | 준비 및 지원 범위 |
|---|---|
| macOS | 기본 일곱 강조색. 다색·회색은 가져오기 대상에서 제외합니다. |
| VS Code | **Dark Modern** 테마와 사용자 설정의 `workbench.colorCustomizations` 항목이 필요합니다. 해당 색상 항목 전체를 프리셋으로 교체하며 나머지 설정은 유지합니다. |
| Codex | 설정 파일에 라이트·다크 테마의 `accent`, `accentSource` 항목이 있어야 합니다. 앱에서 두 모드의 강조색을 한 번 설정하세요. 반영에 재시작이 필요할 수 있습니다. |
| Chrome | 표준 Google Chrome 프로필과 TinkLink의 **손쉬운 사용** 권한이 필요합니다. 한국어·영어 Chrome 153의 새 탭 맞춤설정 화면을 기준으로 구현했습니다. |

VS Code에 색상 항목이 없다면 사용자 설정 JSON에 `"workbench.colorCustomizations": {}`를 추가하세요. 기존 항목이 있다면 중복해서 추가하지 마세요.

Chrome 연결은 앱의 `Chrome 연결 허용`을 누른 뒤 **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → TinkLink**에서 허용합니다.

### Chrome 프로필과 계정 동기화

각 Mac의 현재 사용자 Chrome 데이터에서 프로필을 읽습니다. 개인이 지정한 프로필 이름으로 표시하며, 이름을 바꿔도 프로필 선택이 유지됩니다. 새 설치에서는 마지막으로 사용한 프로필 하나를 선택합니다. 이후 새 프로필을 추가하면 직접 선택하세요.

TinkLink는 Chrome의 **새 탭 → Chrome 맞춤설정** 화면을 조작합니다. Chrome 자체가 테마 변경과 계정 동기화를 처리합니다. TinkLink는 동기화를 켜거나 끄지 않으며 Chrome 설정 파일에 직접 쓰지 않습니다. 다른 기기로 테마를 전달하려면 Chrome 계정에서 테마 동기화가 켜져 있어야 합니다.

선택한 프로필마다 설정용 새 창이 열리고 순서대로 처리됩니다. 다른 창으로 이동해도 계속 진행합니다. 설정용 탭 자체를 닫거나 다른 페이지로 이동하면 해당 작업과 남은 프로필 적용을 중단합니다. 이미 완료한 변경은 유지됩니다.

Chrome은 색조 슬라이더로 가장 가까운 색을 선택합니다. 허용 범위는 모든 색에 동일한 ±0.65°이며, 탭·배경의 실제 색상은 Chrome이 기준색으로부터 생성합니다.

| 색상 | VS Code · Codex | Chrome 기준색 |
|---|---|---|
| 파랑 | `#0A84FF` | `#00BDFF` |
| 연보라 | `#B8A1FF` | `#7600FF` |
| 핑크 | `#FF4FA3` | `#FF00C6` |
| 빨강 | `#FF453A` | `#FF0000` |
| 주황 | `#FF9F0A` | `#FFC300` |
| 노랑 | `#FFCC00` | `#FFFA00` |
| 초록 | `#30D158` | `#00FF08` |

macOS의 연보라는 시스템 기본 보라색에 대응합니다. Chrome의 보라·핑크는 슬라이더가 채도와 밝기를 고정하므로 원래 앱 색상과 다를 수 있습니다.

## 설정과 개인정보

- 경로는 실행한 사용자의 홈 폴더를 기준으로 찾습니다. 특정 사용자의 계정이나 프로필은 앱에 포함하지 않습니다.
- Chrome의 `Local State`와 프로필 설정은 목록 표시와 적용 확인을 위해 읽기만 합니다.
- VS Code JSONC와 Codex TOML에서 필요한 부분만 편집하며, 지원하지 않는 구조는 변경 전에 거부합니다.
- 파일은 원래 권한을 유지한 채 교체합니다. 오류 시 같은 작업의 변경만 되돌리고 다른 앱이 동시에 편집한 내용은 보존합니다.
- 선택한 대상과 프로필 ID를 macOS 앱 환경설정에 저장합니다. 색상 이력·백업 파일은 만들지 않습니다.
- 이전 ‘색상 전환기’와의 호환성을 위해 내부 앱 식별자 `local.chan.accentbar`, 설정 잠금 폴더 `AccentBar`는 유지합니다.

## 개발

Apple의 Swift 명령줄 개발 도구가 필요합니다. 저장소 루트에서 실행하세요.

```sh
bash tests/test-native.sh
bash src/AccentBar/build.sh
bash scripts/package-release.sh
```

결과물은 `outputs/TinkLink.app`, `outputs/TinkLink-1.0.0-macos-arm64.zip`, 체크섬 파일입니다. 앱과 빌드에 Python은 사용하지 않습니다. Release에는 앱 ZIP과 체크섬을 올리며, Git에는 소스·프리셋·테스트·문서만 보관합니다.

### 코드 구성

- `src/AccentBar/AccentBar.swift`: SwiftUI 메뉴와 앱 생명주기
- `Models.swift`: 색상 프리셋과 상태 모델
- `NativeSettings.swift`: 사용자별 경로, 프로필 탐색, 시스템 설정과 파일 저장
- `SettingsDocuments.swift`: JSONC/TOML의 필요한 부분 편집
- `ChromeAutomation.swift`: Chrome 화면 조작과 결과 확인
- `Presets/`: 일곱 색상 구성
- `tests/`: 임시 사용자 폴더에서 수행하는 설정·복구·프로필 검사와 Chrome 로직 검사

테스트는 실제 사용자의 설정을 변경하거나 Chrome을 조작하지 않습니다. 배포본에는 네이티브 실행 파일 하나, 앱 아이콘, 일곱 JSON 프리셋만 포함합니다.
