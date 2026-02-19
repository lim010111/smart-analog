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
- **AI 일정 색상 분류 (선택 기능)**: OpenAI API를 사용해 일정 제목을 카테고리로 분류하고 색상을 자동 적용할 수 있습니다.
- **AI 오늘의 브리핑 (선택 기능)**: 앱 시작 시 오늘 일정 요약을 생성하고, 메뉴에서 스타일 다이얼로그로 확인할 수 있습니다.

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

### AI 일정 색상 분류 (선택)

OpenAI API 키와 사용자 정의 색상 스키마를 설정하면 일정 제목을 카테고리로 분류하여 색상을 자동으로 적용합니다.

1. `.env.template`을 `.env`로 복사합니다.
2. 아래 값을 설정합니다.

```bash
ENABLE_AI_EVENT_COLOR=true
OPENAI_API_KEY=your_openai_api_key_here
OPENAI_COLOR_MODEL=gpt-4o-mini
```

3. 우클릭 메뉴 > **Color Schema** 에서 색상-카테고리 규칙을 정의합니다.
   - 선택 가능한 색상은 현재 캘린더 프로바이더가 실제로 저장 가능한 색상만 표시됩니다.
4. **Generate Keywords** 버튼으로 AI가 각 카테고리에 맞는 키워드를 자동 생성합니다.
5. 우클릭 메뉴 > **Apply AI Colors to All Events** 로 전체 일정 범위에 색상을 일괄 적용할 수 있습니다.

> [!NOTE]
> 색상 스키마가 설정되지 않으면 색상 분류가 적용되지 않습니다.
> API 키가 없거나 호출이 실패하면 스키마의 키워드 기반 로컬 분류로 자동 폴백됩니다.
> 색상 적용 후 캘린더 이벤트 색상 write-back은 프로바이더가 지원할 때만 수행됩니다.
> 전체 일정 일괄 적용은 API 호출량이 많을 수 있어 처리 시간이 길어질 수 있습니다.

### AI Natural Input (feature/ai-natural-input)

자연어 문장을 일정 의도로 파싱하고, 프리뷰 확인 후 이벤트를 생성할 수 있습니다.

```bash
ENABLE_AI_NATURAL_INPUT=false
OPENAI_NATURAL_INPUT_MODEL=gpt-4o-mini
OPENAI_NATURAL_INPUT_TIMEOUT=8
OPENAI_NATURAL_INPUT_MAX_CHARS=300
OPENAI_NATURAL_INPUT_DEFAULT_DURATION_MINUTES=60
OPENAI_NATURAL_INPUT_MIN_CONFIDENCE=0.6
```

1. `.env.template`을 `.env`로 복사하고 `ENABLE_AI_NATURAL_INPUT=true`로 변경합니다.
2. 우클릭 메뉴 > **AI Natural Input** 을 선택합니다.
3. 한 문장으로 일정을 입력하면 파싱 결과(의도/시간/신뢰도)를 프리뷰로 확인할 수 있습니다.
4. 프리뷰에서 **Create Event** 를 누르면 활성 프로바이더에 이벤트를 생성합니다.

> [!NOTE]
> 의도(intent)가 `create`가 아니거나 시작/종료 시간이 부족하면 생성 버튼이 비활성화됩니다.
> 프로바이더가 이벤트 생성을 지원하지 않으면 프리뷰만 가능합니다.

### AI Today Briefing (feature/ai-briefing)

앱 시작 시 오늘 일정을 자연어로 요약하고, 메뉴의 **Show Today Briefing**에서 스타일 다이얼로그로 확인할 수 있습니다.

```bash
ENABLE_AI_TODAY_BRIEFING=false
ENABLE_AI_TODAY_BRIEFING_TTS=false
AI_TTS_BACKEND=openai
OPENAI_BRIEFING_MODEL=gpt-4o-mini
OPENAI_BRIEFING_TIMEOUT=8
OPENAI_BRIEFING_MAX_EVENTS=20
OPENAI_BRIEFING_REFRESH_SLOT_MINUTES=15
OPENAI_TTS_MODEL=gpt-4o-mini-tts
OPENAI_TTS_VOICE=marin
OPENAI_TTS_INSTRUCTIONS=
OPENAI_TTS_TIMEOUT=15
OPENAI_TTS_AUDIO_CACHE_DIR=
```

> [!NOTE]
> OpenAI TTS는 `OPENAI_API_KEY`가 필요합니다.
> 미지원 환경에서는 브리핑 텍스트만 표시됩니다.

`AI_TTS_BACKEND`로 TTS 백엔드를 선택할 수 있습니다.

- `openai` (기본): OpenAI Audio Speech API(`gpt-4o-mini-tts`) 사용
- `qt`: 시스템 Qt TTS 백엔드 사용
- `auto`: OpenAI 시도 후 실패하면 Qt로 폴백

OpenAI TTS는 `/v1/audio/speech` 엔드포인트를 사용하며 기본 출력 포맷은 `wav`입니다.
앱은 생성된 음성을 임시 파일로 저장한 뒤 재생합니다.

> [!TIP]
> OpenAI 문서 기준 TTS 음성은 영어에 최적화되어 있지만 한국어 입력도 지원됩니다.

#### Linux TTS 설정 (선택)

Linux에서 `speechd` 백엔드가 없으면 다음과 같은 메시지가 보일 수 있습니다.

```text
Error loading text-to-speech plug-in "speechd"
```

Ubuntu/Debian 계열은 아래 패키지를 설치한 뒤 앱을 재실행하세요.

```bash
sudo apt update
sudo apt install -y speech-dispatcher libspeechd2
```

설치 후 동작 확인:

```bash
spd-say "clock widget tts test"
```

> [!TIP]
> `Today Briefing`은 켠 상태여도 TTS 백엔드가 초기화되지 않으면 자동으로 음성 기능이 비활성화되고 텍스트 브리핑만 유지됩니다.

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
│   │   │   └── briefing.py              # OpenAI 기반 오늘의 브리핑 생성
│   │   │   └── tts.py                   # OpenAI/Qt 선택형 TTS 어댑터
│   │   │   └── event_coloring.py        # OpenAI 기반 일정 색상 분류
│   │   │   └── natural_input.py         # OpenAI 기반 자연어 입력 파싱
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
  - **Today Briefing**: 오늘의 AI 브리핑 기능 on/off를 전환합니다.
  - **Show Today Briefing**: 현재 브리핑을 스타일 다이얼로그로 확인합니다.
  - **Briefing TTS**: 브리핑 음성 읽기 on/off를 전환합니다.
  - **Speak Today Briefing**: 현재 브리핑을 즉시 음성으로 읽습니다.
  - **AI Natural Input**: 자연어 문장을 파싱하고 프리뷰에서 이벤트 생성 여부를 확인합니다.
  - **Sync Calendar**: 캘린더와 수동으로 동기화합니다.
  - **Refresh Events**: 일정을 새로고침합니다.
  - **Logout**: 현재 캘린더 계정에서 로그아웃합니다.
  - **Exit**: 위젯을 종료합니다.
- **종료**: 시계 우측 상단의 닫기(X) 버튼을 클릭하면 앱이 종료됩니다.
