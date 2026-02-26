# WSL2 Android 실기기 디버깅 가이드 (usbipd-win 중심)

이 문서는 Windows + WSL2 환경에서 Flutter Android **실기기 디버깅**을 안정적으로 수행하는 절차를 정리합니다.

기준 환경:

- Windows 11 + WSL2(Ubuntu)
- Flutter는 WSL에서 실행
- Android 실기기는 USB로 연결

---

## 1) 권장 방식 요약

현재 프로젝트 기준으로 가장 안정적인 방식은 **usbipd-win USB 패스스루**입니다.

- 이유 1: WSL의 `adb`가 기기를 직접 인식해 버전/브릿지 충돌을 줄임
- 이유 2: OAuth/딥링크 같은 E2E 테스트에서 연결 안정성이 좋음
- 이유 3: Windows adb 서버 브릿지(`ADB_SERVER_SOCKET`) 의존성을 제거 가능

> [!NOTE]
> 무선 디버깅/Windows adb 브릿지도 가능하지만, 본 가이드는 재현성이 높은 usbipd-win 흐름을 기본으로 설명합니다.

---

## 2) 사전 조건

### Windows

1. 개발자 옵션/USB 디버깅이 켜진 Android 폰
2. `usbipd-win` 설치
3. PowerShell 관리자 권한 사용 가능

```powershell
winget install --interactive --exact dorssel.usbipd-win
```

### WSL

1. `adb` 사용 가능
2. `plugdev` 그룹 포함
3. Android vendor udev rule 설정 가능

확인 예시:

```bash
adb version
id
getent group plugdev
```

---

## 3) .zshrc/.bashrc 체크 포인트

과거 Windows adb 브릿지를 사용했다면 아래 변수가 남아 있을 수 있습니다.

```bash
# export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
```

실기기 USB 패스스루 방식에서는 **주석 처리**하거나 제거해야 합니다.

적용:

```bash
source ~/.zshrc   # bash 사용 시 source ~/.bashrc
unset ADB_SERVER_SOCKET
echo "$ADB_SERVER_SOCKET"   # 빈 값이어야 정상
```

---

## 4) 연결 절차 (Windows -> WSL)

### Step A. Windows에서 장치 공유/연결

PowerShell(관리자):

```powershell
usbipd list
```

폰의 `BUSID`를 확인한 뒤:

```powershell
usbipd bind --busid <PHONE_BUSID>
usbipd attach --wsl --busid <PHONE_BUSID>
```

`usbipd-win 5.x`에서 특정 배포판을 지정하려면:

```powershell
usbipd attach --wsl Ubuntu --busid <PHONE_BUSID>
```

> [!IMPORTANT]
> `--distribution` 옵션은 지원되지 않습니다. `--wsl <DISTRIBUTION>` 형식을 사용해야 합니다.

### Step B. WSL에서 adb 인식 확인

```bash
unset ADB_SERVER_SOCKET
adb kill-server
adb start-server
adb devices -l
```

정상 예시:

```text
R3CR10HFD7R device usb:1-1 product:... model:... device:...
```

---

## 5) 권한 이슈(no permissions) 해결

증상 예시:

```text
no permissions (missing udev rules? user is in the plugdev group)
```

### Step A. 기본 규칙 패키지 설치

```bash
sudo apt update
sudo apt install -y android-sdk-platform-tools-common
```

### Step B. 제조사 규칙 추가 (예: Samsung, VID=04e8)

```bash
printf '%s\n' 'SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="plugdev", TAG+="uaccess"' | \
sudo tee /etc/udev/rules.d/51-android-samsung.rules
```

### Step C. 규칙 적용

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

그 후 Windows에서 재attach:

```powershell
usbipd detach --busid <PHONE_BUSID>
usbipd attach --wsl --busid <PHONE_BUSID>
```

WSL에서 재확인:

```bash
adb kill-server
adb start-server
adb devices -l
```

---

## 6) unauthorized 상태 해결

증상 예시:

```text
R3CR10HFD7R unauthorized usb:1-1 ...
```

해결:

1. 폰 화면 잠금 해제
2. RSA 팝업에서 `허용` + `항상 허용` 체크
3. 아래 재실행

```bash
adb kill-server
adb start-server
adb devices -l
```

팝업이 안 뜨면:

- 폰 개발자옵션에서 `USB 디버깅 권한 취소`
- `usbipd detach -> attach`
- adb 재시작

---

## 7) 프로젝트 실행

```bash
cd /home/shine/projects/clock_widget/mobile/flutter_app
flutter devices
flutter run -d <DEVICE_ID>
```

현재 브랜치에서 빠른 검증 루틴:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

---

## 8) 트러블슈팅 체크리스트

### A. `adb devices`가 비어 있음

- `usbipd list`에서 폰이 `Attached`인지 확인
- `BUSID`가 맞는지 재확인 (재연결하면 변경될 수 있음)
- `ADB_SERVER_SOCKET`이 비어 있는지 확인
- 케이블/포트 교체 및 폰 USB 모드 `파일 전송(MTP)`로 변경

### B. `Device in error state`

Windows PowerShell(관리자):

```powershell
usbipd detach --busid <PHONE_BUSID>
usbipd unbind --busid <PHONE_BUSID>
Restart-Service usbipd
wsl --shutdown
```

그 다음 재연결:

```powershell
usbipd bind --busid <PHONE_BUSID>
usbipd attach --wsl --busid <PHONE_BUSID>
```

### C. `cannot connect to daemon at tcp:5037`

- 브릿지 모드 환경 변수가 남아있는지 확인 (`ADB_SERVER_SOCKET`)
- WSL에서 `unset ADB_SERVER_SOCKET` 후 adb 재시작

---

## 9) 무선 디버깅/브릿지 방식 비교 (짧게)

- **usbipd-win (권장)**: 안정성 높음, 재현성 좋음
- **무선 디버깅**: 케이블 없이 편리, 네트워크 영향 큼
- **Windows adb 브릿지**: 기존 에뮬레이터 루틴 유지에 유리, 버전 불일치 이슈 주의

프로젝트 개발에서는 **한 번에 한 방식만** 사용하세요. 혼용하면 인식 충돌이 자주 발생합니다.
