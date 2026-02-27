# WSL2 Android 실기기 디버깅 가이드 (Windows adb 브릿지 기본)

이 문서는 Windows + WSL2 환경에서 Flutter Android **실기기 디버깅**을 안정적으로 수행하는 절차를 정리합니다.

기준 환경:

- Windows 11 + WSL2(Ubuntu)
- Flutter는 WSL에서 실행
- Android 실기기는 USB로 연결

---

## 1) 권장 방식 요약

현재 프로젝트 기준으로 가장 안정적인 방식은 **Windows adb 서버 브릿지 + `ADB_SERVER_SOCKET` 고정**입니다.

- 이유 1: 실제 검증에서 `flutter devices`가 Android 기기를 안정적으로 인식
- 이유 2: `adb install`이 즉시 성공하고 `flutter run --release`까지 재현됨
- 이유 3: `usbipd`의 `Shared`/`Attached` 상태 변동 이슈를 우회 가능

> [!NOTE]
> `usbipd-win USB 패스스루`는 대안으로 유효합니다. 다만 현재 브랜치 실사용 기준 기본값은 Windows adb 브릿지입니다.

---

## 2) 사전 조건

### Windows

1. 개발자 옵션/USB 디버깅이 켜진 Android 폰
2. Android SDK `platform-tools` 설치 (`adb.exe` 사용 가능)
3. PowerShell에서 `adb` 실행 가능

확인 예시:

```powershell
where adb
adb version
adb devices -l
```

필요 시(대안 경로용) `usbipd-win`도 설치 가능:

```powershell
winget install --interactive --exact dorssel.usbipd-win
```

### WSL

1. `flutter`/`adb` 사용 가능
2. `ANDROID_HOME` 설정
3. 셸 시작 파일(`~/.zshrc` 또는 `~/.bashrc`) 수정 가능

확인 예시:

```bash
flutter --version
adb version
echo "$ANDROID_HOME"
```

---

## 3) 환경변수 고정 (`.zshrc` / `.bashrc`)

Windows adb 서버 포트를 `5038`로 사용한다면 아래를 셸 시작 파일에 추가합니다.

```bash
# WSL -> Windows adb bridge (project default)
export ADB_SERVER_SOCKET=tcp:127.0.0.1:5038

# Optional: 항상 브릿지 모드로 flutter 실행
alias flutter-phone='ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 flutter'
alias adb-phone='ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 adb'
```

적용:

```bash
source ~/.zshrc   # bash 사용 시 source ~/.bashrc
echo "$ADB_SERVER_SOCKET"   # tcp:127.0.0.1:5038 이면 정상
```

> [!IMPORTANT]
> 한 세션에서 로컬 WSL adb 서버(5037)와 Windows adb 서버(5038)를 혼용하지 마세요. 기기 목록 불일치의 가장 흔한 원인입니다.

---

## 4) 연결 절차 (Windows adb 브릿지)

### Step A. Windows에서 adb 서버/기기 상태 확인

PowerShell:

```powershell
adb -P 5038 kill-server
adb -P 5038 start-server
adb -P 5038 devices -l
```

정상 예시:

```text
R3CR10HFD7R device product:t2sksx model:SM_G996N device:t2s
```

`unauthorized`면 6) 섹션을 먼저 수행하세요.

### Step B. WSL에서 동일 서버를 바라보는지 확인

```bash
echo "$ADB_SERVER_SOCKET"
ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 adb devices -l
ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 flutter devices
```

정상 예시:

```text
SM G996N (mobile) • R3CR10HFD7R • android-arm64 • Android 15 (API 35)
```

---

## 5) 프로젝트 실행 (검증된 명령)

```bash
cd /home/shine/projects/clock_widget/mobile/flutter_app

# 기기 인식 확인
ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 flutter devices

# 설치만 확인
flutter build apk --debug
ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 adb -s <DEVICE_ID> install -r -d -t build/app/outputs/flutter-apk/app-debug.apk

# 실행 확인
ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 flutter run -d <DEVICE_ID>
```

현재 브랜치 빠른 검증 루틴:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

---

## 6) `unauthorized` 상태 해결

증상 예시:

```text
R3CR10HFD7R unauthorized ...
```

해결:

1. 폰 화면 잠금 해제
2. RSA 팝업에서 `허용` + `항상 허용` 체크
3. Windows/WSL 양쪽에서 재확인

```powershell
adb -P 5038 devices -l
```

```bash
ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 adb devices -l
```

팝업이 안 뜨면:

- 폰 개발자옵션에서 `USB 디버깅 권한 취소`
- 케이블 재연결
- `adb -P 5038 kill-server && adb -P 5038 start-server` 재실행

---

## 7) 트러블슈팅 체크리스트

### A. `flutter devices`에 Linux만 보임

- `echo "$ADB_SERVER_SOCKET"` 값이 `tcp:127.0.0.1:5038`인지 확인
- Windows에서 `adb -P 5038 devices -l`가 `device`인지 확인
- WSL에서 `ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 adb devices -l` 재확인
- WSL에서 로컬 adb 데몬이 떠 있으면 정리: `adb kill-server`

### B. `adb install` 실패

- APK 존재 확인: `build/app/outputs/flutter-apk/app-debug.apk`
- 디바이스 지정 설치 재시도:

```bash
ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 adb -s <DEVICE_ID> install -r -d -t build/app/outputs/flutter-apk/app-debug.apk
```

### C. `cannot connect to daemon at tcp:5037`

- 현재 모드가 5038 브릿지인지 재확인 (`ADB_SERVER_SOCKET`)
- Windows 서버 재시작:

```powershell
adb -P 5038 kill-server
adb -P 5038 start-server
```

---

## 8) usbipd-win 대안 경로 (필요할 때만)

Windows PowerShell(관리자):

```powershell
usbipd list
usbipd bind --busid <PHONE_BUSID>
usbipd attach --wsl --busid <PHONE_BUSID>
```

`usbipd-win 5.x`에서 배포판 지정 시:

```powershell
usbipd attach --wsl Ubuntu --busid <PHONE_BUSID>
```

WSL에서 usbipd 모드로 전환할 때:

```bash
unset ADB_SERVER_SOCKET
adb kill-server
adb start-server
adb devices -l
```

> [!IMPORTANT]
> `--distribution` 옵션은 지원되지 않습니다. `--wsl <DISTRIBUTION>` 형식을 사용하세요.

---

## 9) 방식 비교 (요약)

- **Windows adb 브릿지 (기본 권장)**: 현재 프로젝트에서 재현/검증 완료
- **usbipd-win**: 직접 USB 패스스루 필요 시 유효
- **무선 디버깅**: 케이블 없이 편리하지만 네트워크 상태 영향 큼

프로젝트 개발에서는 **한 번에 한 방식만** 사용하세요. 혼용하면 인식 충돌이 자주 발생합니다.
