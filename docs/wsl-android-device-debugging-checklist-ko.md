# WSL2 Android 실기기 디버깅 체크리스트 (One-Page)

상세 설명 문서: `docs/wsl-android-device-debugging-ko.md`

---

## 0) 기본 원칙

- [ ] 한 번에 한 방식만 사용 (`usbipd-win` 권장, 브릿지/무선과 혼용 금지)
- [ ] WSL 셸에서 `ADB_SERVER_SOCKET` 비활성화
- [ ] 폰: 개발자 옵션 + USB 디버깅 ON, 화면 잠금 해제

```bash
unset ADB_SERVER_SOCKET
echo "$ADB_SERVER_SOCKET"  # 빈 값이어야 정상
```

---

## 1) Windows (관리자 PowerShell)

- [ ] `usbipd-win` 설치

```powershell
winget install --interactive --exact dorssel.usbipd-win
```

- [ ] 폰 BUSID 확인

```powershell
usbipd list
```

- [ ] 공유 + WSL attach

```powershell
usbipd bind --busid <PHONE_BUSID>
usbipd attach --wsl --busid <PHONE_BUSID>
```

> 특정 배포판 지정(usbipd 5.x):

```powershell
usbipd attach --wsl Ubuntu --busid <PHONE_BUSID>
```

---

## 2) WSL 연결 확인

- [ ] adb 서버 재시작

```bash
adb kill-server
adb start-server
adb devices -l
```

- [ ] 기대 상태: `device`

```text
R3CR10HFD7R device usb:1-1 ...
```

---

## 3) 권한 이슈 즉시 해결

### A. `no permissions`

- [ ] udev 규칙 패키지 설치

```bash
sudo apt update
sudo apt install -y android-sdk-platform-tools-common
```

- [ ] Samsung(04e8) 규칙 추가

```bash
printf '%s\n' 'SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="plugdev", TAG+="uaccess"' | \
sudo tee /etc/udev/rules.d/51-android-samsung.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

- [ ] Windows에서 재attach 후 adb 재확인

```powershell
usbipd detach --busid <PHONE_BUSID>
usbipd attach --wsl --busid <PHONE_BUSID>
```

```bash
adb kill-server
adb start-server
adb devices -l
```

### B. `unauthorized`

- [ ] 폰 RSA 팝업 `허용` + `항상 허용`
- [ ] 안 뜨면 `USB 디버깅 권한 취소` 후 재연결

### C. `Device in error state`

```powershell
usbipd detach --busid <PHONE_BUSID>
usbipd unbind --busid <PHONE_BUSID>
Restart-Service usbipd
wsl --shutdown
usbipd bind --busid <PHONE_BUSID>
usbipd attach --wsl --busid <PHONE_BUSID>
```

---

## 4) 프로젝트 실행 체크

- [ ] 디바이스 인식

```bash
cd /home/shine/projects/clock_widget/mobile/flutter_app
flutter devices
```

- [ ] 앱 실행

```bash
flutter run -d <DEVICE_ID>
```

- [ ] 빠른 검증

```bash
flutter analyze
flutter test
flutter build apk --debug
```

---

## 5) 완료 기준 (Definition of Done)

- [ ] `adb devices -l`에서 대상 폰이 `device` 상태
- [ ] `flutter run -d <DEVICE_ID>` 성공
- [ ] 앱 실행 후 로그/핫리로드 정상
- [ ] `analyze/test/build` 통과
