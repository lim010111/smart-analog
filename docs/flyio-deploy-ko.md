# Fly.io 배포 상세 가이드 (Next.js + FastAPI)

이 문서는 현재 리포지토리에 이미 반영된 배포 구조(`Dockerfile`, `fly.toml`, `nginx.conf`, `supervisord.conf`)를 기준으로, 해커톤 제출용 공개 URL을 빠르게 만드는 절차를 정리합니다.

## 1) 배포 구조 요약

현재 구조는 **단일 Fly.io 앱 + 단일 컨테이너**입니다.

- 외부 트래픽: Fly.io `https://<app>.fly.dev`
- 컨테이너 ingress: `8080` (`fly.toml`의 `internal_port`)
- `nginx` 라우팅:
  - `/api/*`, `/health` -> FastAPI(`127.0.0.1:8000`)
  - 그 외 -> Next.js(`127.0.0.1:3000`)
- 프로세스 관리: `supervisord`가 `nginx` + `uvicorn` + `next start` 동시 관리
- 영속 데이터: Fly Volume을 `/data`로 마운트하고, 아래 파일을 심볼릭 링크로 연결
  - `/app/token.json` -> `/data/token.json`
  - `/app/apple_credentials.json` -> `/data/apple_credentials.json`
  - `/app/color_schema.json` -> `/data/color_schema.json`
  - `/app/.env` -> `/data/.env`

관련 파일:

- `fly.toml`
- `Dockerfile`
- `nginx.conf`
- `supervisord.conf`
- `requirements-deploy.txt`

## 2) 사전 준비

### 로컬 도구

1. `git`
2. `flyctl` (Fly CLI)
3. Docker(선택: 로컬 이미지 빌드 검증 시)

### Fly 계정

1. Fly.io 계정 생성
2. 결제/조직 설정 확인 (무료 크레딧/요금제 정책은 시점별로 변경 가능)

## 3) 원클릭 배포 체크 스크립트

리포지토리에는 preflight + (선택) deploy + (선택) health check를 한 번에 수행하는 스크립트가 포함되어 있습니다.

- 스크립트 경로: `scripts/fly-deploy-check.sh`
- 기본 동작: 로컬 빌드 체크 -> Fly 앱/볼륨/시크릿 검사 -> `fly deploy` -> `/health` 검증

```bash
# 도움말
./scripts/fly-deploy-check.sh --help

# 기본 실행 (권장)
./scripts/fly-deploy-check.sh

# 배포 없이 사전 점검만
./scripts/fly-deploy-check.sh --skip-deploy

# 앱명/리전 오버라이드
./scripts/fly-deploy-check.sh --app my-app --region nrt
```

주요 옵션:

- `--fly-bin <cmd>`: Fly CLI 명령 강제 지정 (`fly` 또는 `flyctl`)
- `--org <slug>`: 앱 자동 생성 시 사용할 조직 슬러그 지정
- `--skip-local-checks`: `next build`/`python compile` 생략
- `--skip-deploy`: `fly deploy` 생략
- `--skip-health-check`: `/health` 검증 생략
- `--no-auto-create`: 앱/볼륨 자동 생성 비활성화
- `--allow-missing-secrets`: 필수 시크릿 누락 시에도 계속 진행
- `--volume-size <gb>`: 볼륨 자동 생성 시 크기 지정
- `--health-retries <n>`: 헬스체크 재시도 횟수
- `--health-delay <seconds>`: 헬스체크 재시도 간격

`fly`/`flyctl`이 둘 다 없으면 아래처럼 먼저 설치하세요.

```bash
curl -L https://fly.io/install.sh | sh
export FLYCTL_INSTALL="$HOME/.fly"
export PATH="$FLYCTL_INSTALL/bin:$PATH"
flyctl version
```

## 4) 앱명/리전 결정

기본 설정은 `fly.toml` 기준입니다.

- 앱명: `smart-analog-clock`
- 리전: `nrt`

이미 같은 이름의 앱이 존재하면 `fly.toml`의 `app` 값을 변경한 뒤 진행하세요.

## 5) 1회성 초기 배포 절차

아래 명령은 리포지토리 루트(`clock_widget/`) 기준입니다.

```bash
# 1) 로그인
fly auth login

# 2) 앱 생성 (이미 있으면 생략)
fly apps create smart-analog-clock

# 3) 볼륨 생성 (앱당 최소 1개)
fly volumes create clock_data --app smart-analog-clock --region nrt --size 1

# 4) 시크릿 주입 (예시)
fly secrets set \
  GOOGLE_CLIENT_ID="..." \
  GOOGLE_CLIENT_SECRET="..." \
  GOOGLE_PROJECT_ID="..." \
  OPENAI_API_KEY="..." \
  WEB_DEFAULT_PROVIDER="google" \
  WEB_CORS_ORIGINS="https://smart-analog-clock.fly.dev" \
  ENABLE_AI_EVENT_COLOR="true" \
  ENABLE_AI_NATURAL_INPUT="true" \
  ENABLE_AI_TODAY_BRIEFING="true" \
  OPENAI_REASONING_EFFORT="high" \
  --app smart-analog-clock

# 5) 배포
fly deploy
```

## 6) 환경변수 설계 원칙

`.env.template`을 기준으로 운영 환경에서는 `fly secrets`를 우선 사용하세요.

### 필수에 가까운 값

- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_PROJECT_ID`
- `OPENAI_API_KEY` (AI 기능 사용 시)
- `WEB_DEFAULT_PROVIDER` (`google` 또는 `apple`)
- `WEB_CORS_ORIGINS` (반드시 실제 서비스 도메인 포함)

### GPT-5 추론 강도

- `OPENAI_REASONING_EFFORT=high` 권장

### 프론트-백엔드 URL

프론트 코드 기준:

- `web/frontend/src/app/page.tsx`
  - `NEXT_PUBLIC_BACKEND_URL ?? "http://localhost:8000"`
- `web/frontend/src/app/settings/color-schema/page.tsx`
  - `NEXT_PUBLIC_BACKEND_URL ?? BACKEND_URL ?? "http://localhost:8000"`

운영에서는 아래 중 하나를 권장합니다.

1. **동일 도메인 라우팅(현재 구조 기본값)**: `NEXT_PUBLIC_BACKEND_URL`을 빈 문자열로 유지해 `/api/*` 상대경로 사용
2. 분리 도메인 사용: `NEXT_PUBLIC_BACKEND_URL=https://api.example.com` 명시

## 7) 배포 검증 체크리스트

```bash
# 상태 확인
fly status --app smart-analog-clock

# 로그 확인
fly logs --app smart-analog-clock

# 앱 열기
fly apps open --app smart-analog-clock
```

브라우저에서 확인:

1. `/health` 응답이 `{"status":"ok"}`인지
2. 메인 페이지 로딩 여부
3. 캘린더 인증/해제 동작
4. 일정 조회/생성/자연어 입력
5. 브리핑/색상 기능 (활성화한 경우)

## 8) 운영 명령 모음

```bash
# 배포 히스토리
fly releases --app smart-analog-clock

# 머신 재시작
fly machine restart <machine-id> --app smart-analog-clock

# 머신 목록
fly machine list --app smart-analog-clock

# 시크릿 목록(값은 마스킹)
fly secrets list --app smart-analog-clock

# SSH 접속
fly ssh console --app smart-analog-clock
```

## 9) 자주 발생하는 문제와 해결

### A. 앱명 충돌

- 증상: `fly apps create`에서 이름 충돌
- 해결: `fly.toml`의 `app` 이름 변경 후 재시도

### A-1. 결제 정보 요구로 앱 생성 실패

- 증상: `We need your payment information to continue` 메시지
- 해결:
  1. Fly 대시보드에서 결제수단/크레딧 설정
  2. 이미 결제가 설정된 조직이 있다면 `--org <slug>`로 실행
  3. 수동 앱 생성 후 `--no-auto-create` 옵션으로 재실행

```bash
# 예시: 조직 지정 실행
./scripts/fly-deploy-check.sh --org my-org-slug
```

### B. 볼륨 없음/마운트 오류

- 증상: credential 파일 유지 안 됨, 앱 재시작 시 인증 풀림
- 해결: `clock_data` 볼륨 생성 여부와 리전 일치 여부 확인

### C. CORS 오류

- 증상: 브라우저에서 `/api/*` 호출 실패
- 해결: `WEB_CORS_ORIGINS`에 실제 프론트 도메인 추가

### C-1. 배포 직후 `/health`가 502

- 증상: 배포는 성공했는데 직후 헬스체크가 502
- 원인: 컨테이너 내부 `frontend`/`backend`/`nginx` 기동 타이밍 지연
- 해결: 스크립트 기본 재시도 사용 또는 재시도 옵션 확대

```bash
./scripts/fly-deploy-check.sh --health-retries 40 --health-delay 3
```

### D. OpenAI 호출 실패

- 증상: 브리핑/자연어/색상 기능 비활성 또는 500
- 해결: `OPENAI_API_KEY`, 모델 변수, timeout 변수 확인

### E. Google 인증 문제

- 증상: 인증 후 일정 조회 실패
- 해결: Google OAuth 클라이언트 설정 및 리다이렉트/승인 범위 재검토, 시크릿 재주입

#### E-1. redirect_uri_mismatch 해결 체크리스트

- `curl -sS -X POST https://smart-analog-clock.fly.dev/api/providers/google/auth-url`
  응답의 `auth_url` 파라미터에서 `redirect_uri`가 아래 값과 **완전히 동일**한지 확인:
  `https://smart-analog-clock.fly.dev/api/providers/google/callback`
- Google Cloud Console → **APIs & Services > Credentials > OAuth 2.0 Client IDs**에서
  해당 `client_id`(위 auth-url의 `client_id`)가 속한 **웹 클라이언트(Web application)** 를 열고
  **Authorized redirect URIs**에 위 URI를 1개만 정확히 등록
  (뒤에 `/` 붙이면 안 됨, `http`/`https`/포트가 다르면 안 됨)
- `승인된 도메인(Authorized domains)`은 별도 설정이며, `redirect_uri_mismatch` 해결 대상은 아닙니다.
  (OAuth 화면/버튼용 도메인 허용은 필요할 수 있지만, 리디렉트 URI는 별도 항목입니다.)
- 운영 환경에서 `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`가 위 콘솔 클라이언트 값과 일치하는지 확인.
- 동일한 URI를 로컬 테스트하려면 로컬용 URI를 별도 등록해야 합니다.
- 문제 지속 시 강제 고정값을 사용해 브라우저 프록시 헤더 의존성을 제거:
- `WEB_GOOGLE_REDIRECT_URI="https://smart-analog-clock.fly.dev/api/providers/google/callback"`
  - `fly secrets set ...` 후 재배포

## 10) 보안 주의사항

1. 실제 API 키/클라이언트 시크릿을 깃에 커밋하지 마세요.
2. `.env`는 로컬 전용으로 두고 운영은 `fly secrets`를 사용하세요.
3. 유출 의심 시 즉시 키 회전(rotate) 하세요.

## 11) 롤백 전략(간단)

1. `fly releases --app <app>`로 이전 릴리스 확인
2. 문제 릴리스 직전 커밋으로 `git revert` 또는 재배포
3. 필요 시 머신 재시작으로 프로세스 상태 초기화

## 12) 해커톤 제출 전 최종 점검

1. 공개 URL 접속 가능 (`https://<app>.fly.dev`)
2. `/health` 정상
3. 인증/일정 조회/일정 생성 시나리오 1회 성공
4. AI 기능 ON/OFF 시 정상 동작
5. 로그에서 치명 에러 없음

---

필요하면 다음 단계로, 이 문서에 맞춘 **운영 체크 스크립트**(배포 후 자동 점검 명령 모음)도 추가할 수 있습니다.
