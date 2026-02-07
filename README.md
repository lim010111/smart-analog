# Google Calendar Analog Clock Widget

**Google Calendar와 연동하여 오늘의 일정을 시각적으로 보여주는 데스크톱 아날로그 시계 위젯입니다.**

아날로그 시계를 바탕화면에 띄워 일정을 직관적으로 확인할 수 있습니다. 예정된 오늘의 일정을 시계 위에 그려주며, 일정이 완료되면 시계 위에서 자연스럽게 사라집니다.

---

## 주요 기능

- **아날로그 시계**: 시, 분, 초침이 있는 깔끔한 디자인의 아날로그 시계입니다.
- **Google Calendar 연동**: 사용자의 구글 계정과 연동하여 '주(Primary)' 캘린더의 일정을 자동으로 가져옵니다.
- **일정 시각화**:
  - 일정의 시작/종료 시간을 각도로 변환하여 시계 위에 표시합니다.
  - **진행 중인 일정**: 시간이 흐름에 따라 영역이 줄어들며 '지워지는' 효과를 제공합니다.
  - **지난 일정**: 지난 일정은 자동으로 숨김 처리됩니다.
- **테마 지원**: 다크 모드(Dark Mode)와 라이트 모드(Light Mode)를 지원합니다.
- **항상 위(Always on Top)**: 다른 창보다 항상 위에 표시되도록 설정하여 언제든 시간을 확인할 수 있습니다.
- **트레이 메뉴**: 우클릭 메뉴를 통해 동기화, 테마 변경, 포커스 모드 등을 제어할 수 있습니다.

---

## 설치 및 실행 방법

**Python 3.13+** 환경과 **[uv](https://github.com/astral-sh/uv)** 패키지 매니저를 권장합니다.

### 1. 사전 준비 (Google Cloud Console)

1.  [Google Cloud Console](https://console.cloud.google.com/)에서 새 프로젝트를 생성합니다.
2.  **Google Calendar API**를 활성화합니다.
3.  **OAuth 동의 화면**을 구성합니다. (테스트 사용자 등록 필요)
4.  **사용자 인증 정보(Credentials)** > **OAuth 2.0 클라이언트 ID**를 생성하고 `credentials.json` 파일을 다운로드합니다.
5.  다운로드한 `credentials.json` 파일을 프로젝트 최상위 디렉토리에 위치시킵니다.

### 2. 프로젝트 설정

```bash
# 저장소 복제 (예시)
git clone <repository-url>
cd clock_widget

# 의존성 설치 (uv 사용 시)
uv sync
```

### 3. 실행

```bash
uv run src/main.py
```

> 최초 실행 시 브라우저가 열리며 Google 계정 로그인이 필요합니다. 로그인 후 `token.json` 파일이 생성되며 이후에는 자동 로그인됩니다.

---

## 프로젝트 구조

```plaintext
clock_widget/
├── src/
│   ├── core/
│   │   └── theme.py        # 다크/라이트 테마 색상 정의
│   ├── models/
│   │   └── event.py        # 캘린더 일정 데이터 모델 (dataclass)
│   ├── services/
│   │   └── calendar.py     # Google Calendar API 연동 및 데이터 처리
│   ├── ui/
│   │   ├── clock.py        # 아날로그 시계 및 일정 렌더링 (핵심 UI)
│   │   └── menu.py         # 우클릭 컨텍스트 메뉴 정의
│   └── main.py             # 앱 진입점 (Entry Point) & 윈도우 설정
├── credentials.json        # Google OAuth2 인증 정보 (사용자가 직접 추가)
├── token.json              # 사용자 인증 토큰 (자동 생성됨)
├── pyproject.toml          # 프로젝트 의존성 관리 설정
└── README.md               # 프로젝트 설명 파일
```

---

## 사용 방법

- **이동**: 시계를 마우스 왼쪽 버튼으로 드래그하여 원하는 위치로 옮길 수 있습니다.
- **메뉴 열기**: 시계 위에서 마우스 오른쪽 버튼을 클릭하면 메뉴가 나타납니다.
  - **Switch Mode**: 다크/라이트 테마를 전환합니다.
  - **Always on Top**: 시계를 항상 최상위에 표시할지 여부를 토글합니다.
  - **Sync Google Calendar**: 구글 캘린더와 수동으로 동기화합니다.
  - **Refresh Events**: 일정을 새로고침합니다.
  - **Exit**: 위젯을 종료합니다.
- **종료**: 시계를 더블 클릭하면 앱이 종료됩니다. (메뉴의 Exit와 동일)
