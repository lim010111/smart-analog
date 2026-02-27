# Mobile UI Agent Handoff (Zero-Base)

Last updated: 2026-02-27
Branch: `feature/mobile-flutter-foundation`
Primary goal: fully migrate web analog-clock MVP features to mobile app UI, then release Android first and iOS second.

## 0) Mission and Stop Rule

You are a UI-focused implementer with zero prior context.

Your mission:
1. Build Flutter UI for full MVP feature parity using existing mobile service/repository methods.
2. Do not change backend/mobile contracts unless a hard blocker is proven.
3. Keep widget boundary strict: app handles auth/network; widget reads snapshot artifact only.

Mandatory stop rule:
- Before writing substantial UI code, post a short implementation plan and wait for human confirmation.
- After each major UI milestone (Settings, Event/Natural Input, Briefing/TTS, Colors), post progress.

## 1) Read These First (Order)

1. `mobile/flutter_app/AGENTS.md`
2. `mobile/flutter_app/lib/features/calendar/presentation/mobile_home_screen.dart`
3. `mobile/flutter_app/lib/features/calendar/data/calendar_events_repository.dart`
4. `mobile/flutter_app/lib/integrations/backend_api/api_client.dart`
5. `web/frontend/src/app/page.tsx`
6. `web/frontend/src/app/settings/color-schema/page.tsx`
7. `web/backend/app/main.py`

## 2) Environment Bootstrap (Exact Commands)

From repo root:

```bash
cd /home/shine/projects/clock_widget/mobile/flutter_app
flutter pub get
flutter analyze
flutter test
flutter run
```

If testing with local backend:

```bash
cd /home/shine/projects/clock_widget
uv run uvicorn web.backend.app.main:app --host 0.0.0.0 --port 8000
```

Android real device in this repo often uses adb bridge helper:

```bash
source ~/.zshrc
cw-adb reverse tcp:8000 tcp:8000
cw-flutter-run
```

## 3) Already Implemented (Do Not Redo)

### Auth/callback stability
- Google deep-link callback is wired (`smartanalog://auth/google`).
- Backend mobile callback pending-state is persisted (SQLite), not in-memory only.

### Existing foundation UI (extend this, do not duplicate)
- Current primary UI entry is already implemented at:
  - `mobile/flutter_app/lib/app/app.dart`
  - `mobile/flutter_app/lib/features/calendar/presentation/mobile_home_screen.dart`
- Refactor and extend existing screen/modules instead of creating parallel duplicate auth/provider plumbing.

### Contract hardening
- Existing DTO parsing is strict (FormatException on drift).
- Core regression tests exist.

### Widget storage boundary
- App writes both:
  - `widget_snapshot.json`
  - `widget_snapshot_read_v1.json`
- Widget consumes read artifact only.

## 4) Non-UI Service Groundwork Already Added

Use these directly; do not duplicate service logic in UI.

### API client methods (source of truth)
File: `mobile/flutter_app/lib/integrations/backend_api/api_client.dart`

- `fetchSettings`, `updateSettings`
- `authenticateProvider`, `logoutProvider`
- `createEvent`
- `parseNaturalInput`, `createEventFromNaturalInput`
- `fetchTodayBriefing`, `generateBriefingTtsBase64`, `generateBriefingTtsBinary`
- `fetchColorPalette`, `fetchColorSchema`, `updateColorSchema`, `applyColorsToAll`, `fetchApplyColorsStatus`

### Repository wrappers
File: `mobile/flutter_app/lib/features/calendar/data/calendar_events_repository.dart`

Same capabilities are wrapped there; UI should call repository layer.

### Added DTO contracts
Directory: `mobile/flutter_app/lib/integrations/backend_api/dto/`

- `settings_response_dto.dart`
- `provider_auth_response_dto.dart`
- `create_event_response_dto.dart`
- `natural_input_response_dto.dart`
- `briefing_response_dto.dart`
- `color_rule_dto.dart`
- `colors_response_dto.dart`

### Tests already added
- `mobile/flutter_app/test/backend_mvp_parity_dto_contract_test.dart`

## 5) Feature Mapping (UI -> Endpoint -> Mobile Method)

### A. Settings editor
- Endpoints:
  - `GET /api/settings`
  - `PUT /api/settings`
- Repository:
  - `fetchSettings()`
  - `updateSettings(...)`
- Web reference:
  - `web/frontend/src/app/page.tsx` (`loadSettings`, `saveSettings`)

### B. Provider controls
- Endpoints:
  - `GET /api/providers`
  - `GET /api/providers/status`
  - `POST /api/providers/authenticate`
  - `POST /api/providers/logout`
  - `POST /api/providers/google/auth-url`
  - `POST /api/providers/apple/credentials`
- Repository:
  - existing provider methods + auth/logout methods

Provider-specific flow rules:
- Google must use `fetchGoogleAuthUrl(...)` -> external browser -> deep link callback (`smartanalog://auth/google`) -> refresh status.
- Apple must use `setAppleCredentials(...)` then refresh status.
- Do not use `POST /api/providers/authenticate` for Google (backend guides to auth-url path).

### C. Event creation
- Endpoint:
  - `POST /api/events/create`
- Repository:
  - `createEvent(...)`

### D. Natural input
- Endpoints:
  - `POST /api/events/natural-input/parse`
  - `POST /api/events/natural-input/create`
- Repository:
  - `parseNaturalInput(...)`
  - `createEventFromNaturalInput(...)`

Validation constraints from backend:
- input `text` max length: 500
- parse can return `ready=false` with `reason`; UI must display reason and avoid create call.

### E. Briefing + TTS
- Endpoints:
  - `GET /api/briefing/today`
  - `POST /api/briefing/tts`
  - `POST /api/briefing/tts/base64`
- Repository:
  - `fetchTodayBriefing(...)`
  - `generateBriefingTtsBinary(...)`
  - `generateBriefingTtsBase64(...)`

MVP TTS policy (avoid hidden dependency decisions):
- Required: TTS generation action must work.
- Optional for this phase: in-app waveform/audio player.
- If you add a playback dependency, record it explicitly in your milestone report with reason and platform impact.

### F. Color schema management
- Endpoints:
  - `GET /api/colors/palette`
  - `GET /api/colors/schema`
  - `PUT /api/colors/schema`
  - `POST /api/colors/apply-all`
  - `GET /api/colors/apply-status`
- Repository:
  - `fetchColorPalette(...)`
  - `fetchColorSchema(...)`
  - `updateColorSchema(...)`
  - `applyColorsToAll(...)`
  - `fetchApplyColorsStatus(...)`
- Web reference:
  - `web/frontend/src/app/settings/color-schema/page.tsx`

Known contract issue to handle before/while UI polling:
- `GET /api/colors/apply-status` currently returns numeric timestamps in backend state (`last_started_at`, `last_finished_at`), while mobile DTO expects optional strings.
- Files:
  - backend: `web/backend/app/main.py`
  - mobile DTO: `mobile/flutter_app/lib/integrations/backend_api/dto/colors_response_dto.dart`
- Guard rule for UI implementer: do not block UI work on these fields; poll status using `running`, `queued`, `last_processed`, `last_updated` first. If timestamp parse mismatch appears, report immediately and isolate to contract-alignment patch.

## 5.1) API Error Handling Contract

- Backend non-2xx responses are surfaced by mobile client as `BackendApiException(statusCode, message)`.
- UI must:
  1. show user-facing message from `message`
  2. keep screen usable (no crash)
  3. support retry actions where appropriate
- For provider/auth endpoints, treat `401/400` as actionable state (show auth CTA or credential guidance), not fatal screen errors.

## 6) Do-Not-Touch Boundaries

1. Do not rename backend JSON fields.
2. Do not move contract parsing into presentation widgets.
3. Do not put auth tokens into widget-readable snapshot files.
4. Do not replace repository/api layers with direct HTTP from UI.
5. Do not broaden scope beyond MVP parity features listed here.

## 7) UI Implementation Sequence (Strict)

Execute in this order:

1. Settings + Provider controls
2. Event create form
3. Natural input parse/create flow
4. Briefing display + TTS actions
5. Color schema editor + apply-all + status poll
6. Snapshot refresh hooks after successful actions affecting widget visuals

For each step:
- keep business translation in repository/data layer
- only add UI/state orchestration in presentation
- preserve existing deep-link/auth lifecycle behavior

## 8) Minimal Screen/State Plan

Default plan (unless you propose a better equivalent):
- Keep `mobile_home_screen.dart` as primary integration surface initially.
- Extract sub-widgets per feature to avoid a monolithic file.
- Introduce lightweight UI state objects if needed, but avoid contract duplication.

## 9) Acceptance Gates (Per Milestone)

For each milestone and final pass:

```bash
cd /home/shine/projects/clock_widget/mobile/flutter_app
flutter analyze
flutter test
flutter build apk --debug
```

Behavior checks:
- Settings round-trip persists through backend.
- Provider auth/logout reflects status correctly.
- Event create updates today events.
- Natural parse failure/success states are visible.
- Briefing loads and TTS action executes with clear error handling.
- Color schema updates and apply status are visible/pollable.

Android-first validation:
- complete end-to-end on Android real device first.
- then run equivalent iOS validation.

## 10) Reporting Format to Human Reviewer

After each milestone, report:
1. What was implemented (file paths)
2. What was intentionally not changed
3. Verification commands and outcomes
4. Risks/open questions (if any)

Keep reports concise and evidence-based.
