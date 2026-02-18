# Calendar Analog Clock Widget

**Google Calendar / Apple Calendar과 연동하여 오늘의 일정을 시각적으로 보여주는 데스크톱 아날로그 시계 위젯입니다.**

아날로그 시계를 바탕화면에 띄워 일정을 직관적으로 확인할 수 있습니다. 예정된 오늘의 일정을 시계 위에 그려주며, 일정이 완료되면 시계 위에서 자연스럽게 사라집니다.

---

## 주요 기능

- **아날로그 시계**: 시, 분, 초침이 있는 깔끔한 디자인의 아날로그 시계입니다.
- **멀티 캘린더 지원**: Google Calendar과 Apple Calendar(iCloud) 중 선택하여 사용할 수 있습니다.
- **일정 시각화**:
  - 일정의 시작/종료 시간을 각도로 변환하여 시계 위에 표시합니다.
  - **진행 중인 일정**: 시간이 흐름에 따라 영역이 줄어들며 '지워지는' 효과를 제공합니다.
  - **지난 일정**: 지난 일정은 자동으로 숨김 처리됩니다.
- **테마 지원**: 다크 모드(Dark Mode)와 라이트 모드(Light Mode)를 지원합니다.
- **항상 위(Always on Top)**: 다른 창보다 항상 위에 표시되도록 설정하여 언제든 시간을 확인할 수 있습니다.
- **로그인/로그아웃**: 우클릭 메뉴에서 캘린더 프로바이더 전환 및 계정 로그아웃이 가능합니다.

---

## 설치 및 실행 방법

**Python 3.13+** 환경과 **[uv](https://github.com/astral-sh/uv)** 패키지 매니저를 권장합니다.

### 1. 실행

```bash
uv run src/main.py
```

---

## 캘린더 설정

### Google Calendar

최초 실행 시 브라우저가 열리며 Google 계정 로그인이 필요합니다. 로그인 후 `token.json` 파일이 생성되며 이후에는 자동 로그인됩니다.

> [!NOTE]
> 본 앱은 배포용 클라이언트 ID가 내장되어 있어 일반 사용자는 별도의 설정 파일이 필요하지 않습니다.
> 개발 시에는 Google Cloud Console에서 Google Calendar API를 활성화하고 `.env`에 클라이언트 정보를 설정합니다.

### Apple Calendar (iCloud)

Apple Calendar은 iCloud CalDAV를 통해 연동됩니다. **앱 전용 비밀번호(App-Specific Password)** 가 필요합니다.

#### 앱 전용 비밀번호 생성 방법

1. [account.apple.com](https://account.apple.com)에 로그인합니다.
2. **로그인 및 보안** > **앱 전용 비밀번호** 로 이동합니다.
3. **+** 버튼을 클릭하여 새 비밀번호를 생성합니다 (이름 예: "Clock Widget").
4. 생성된 `xxxx-xxxx-xxxx-xxxx` 형식의 비밀번호를 복사합니다.

> [!IMPORTANT]
> - Apple 계정에 **2단계 인증(2FA)** 이 활성화되어 있어야 합니다.
> - 일반 Apple ID 비밀번호가 아닌 **앱 전용 비밀번호**를 사용해야 합니다.

#### 연동 방법

1. 우클릭 메뉴 > **Calendar Provider** > **Apple** 을 선택합니다.
2. 로그인 다이얼로그에 Apple ID(이메일)와 앱 전용 비밀번호를 입력합니다.
3. 인증 성공 시 `apple_credentials.json`에 자격 증명이 저장되며 이후 자동 로그인됩니다.

### OpenAI (AI 기능 브랜치 공통)

`feature/ai-coloring`, `feature/ai-briefing`, `feature/ai-natural-input` 브랜치에서 공통으로 사용할 수 있도록 OpenAI 기본 환경 변수를 지원합니다.

```bash
OPENAI_API_KEY=your_openai_api_key_here
OPENAI_MODEL=gpt-4o-mini
OPENAI_TIMEOUT=8
```

### AI Natural Input (feature/ai-natural-input)

자연어 문장을 일정 의도로 파싱하는 초기 서비스 스캐폴딩이 추가되었습니다.

```bash
ENABLE_AI_NATURAL_INPUT=false
OPENAI_NATURAL_INPUT_MODEL=gpt-4o-mini
OPENAI_NATURAL_INPUT_TIMEOUT=8
OPENAI_NATURAL_INPUT_MAX_CHARS=300
```

---

## 프로젝트 구조

```plaintext
clock_widget/
├── src/
│   ├── main.py                          # 앱 진입점
│   ├── core/
│   │   ├── theme.py                     # 테마 정의
│   │   └── startup.py                   # 시작 프로그램 등록
│   ├── models/
│   │   └── event.py                     # CalendarEvent 데이터 모델
│   ├── services/
│   │   ├── calendar.py                  # 프로바이더 매니저
│   │   ├── ai/
│   │   │   └── core/                    # OpenAI 공통 코어(설정/클라이언트/파서)
│   │   └── providers/
│   │       ├── base.py                  # CalendarProvider ABC
│   │       ├── google_provider.py       # Google Calendar 구현
│   │       └── apple_provider.py        # Apple Calendar (iCloud CalDAV) 구현
│   └── ui/
│       ├── clock.py                     # 아날로그 시계 위젯
│       ├── menu.py                      # 우클릭 컨텍스트 메뉴
│       └── dialogs.py                   # Apple 로그인 다이얼로그
├── pyproject.toml                       # 프로젝트 설정 및 의존성
├── ClockWidget.spec                     # PyInstaller 빌드 설정
└── README.md
```

---

## 사용 방법

- **이동**: 시계를 마우스 왼쪽 버튼으로 드래그하여 원하는 위치로 옮길 수 있습니다.
- **메뉴 열기**: 시계 위에서 마우스 오른쪽 버튼을 클릭하면 메뉴가 나타납니다.
  - **Switch Mode**: 다크/라이트 테마를 전환합니다.
  - **Always on Top**: 시계를 항상 최상위에 표시할지 여부를 토글합니다.
  - **Event Opacity**: 일정 영역의 투명도를 조절합니다.
  - **Calendar Provider**: Google / Apple 캘린더를 선택합니다.
  - **Sync Calendar**: 캘린더와 수동으로 동기화합니다.
  - **Refresh Events**: 일정을 새로고침합니다.
  - **Logout**: 현재 캘린더 계정에서 로그아웃합니다.
  - **Exit**: 위젯을 종료합니다.
- **종료**: 시계 우측 상단의 닫기(X) 버튼을 클릭하면 앱이 종료됩니다.
