# Mobile Agent Kickoff (Codex-Style)

Last updated: 2026-03-14  
Audience: New coding agent starting mobile feature work immediately

## 1) Mission

Ship working mobile code in `mobile/flutter_app/` with end-to-end verification.  
Do not stop at analysis: gather context, implement, validate, and report concrete results.

## 2) Repo Reality Snapshot (Important)

- Current branch: `feature/mobile-flutter-foundation` (ahead of remote by 4 commits).
- Worktree is actively in progress across mobile/backend/web (large dirty state).
- Mobile is currently the most active surface (Flutter UI + Android/iOS widget integration).

## 3) True Source Paths (Use These)

### Mobile app control flow

- App entry: `mobile/flutter_app/lib/main.dart`
- App bootstrap/theme: `mobile/flutter_app/lib/app/app.dart`
- Main orchestration hub: `mobile/flutter_app/lib/features/calendar/presentation/mobile_home_screen.dart`
- Sub-pages shell: `mobile/flutter_app/lib/features/calendar/presentation/mobile_detail_pages.dart`

### Snapshot + widget boundary

- Snapshot builder: `mobile/flutter_app/lib/features/calendar/application/widget_snapshot_builder.dart`
- Snapshot persistence schema: `mobile/flutter_app/lib/core/storage/widget_snapshot_store.dart`
- Flutter-native bridge: `mobile/flutter_app/lib/integrations/widget_host/widget_host_bridge.dart`

### Android native widget surfaces

- Host channel + refresh bridge: `mobile/flutter_app/android/app/src/main/kotlin/com/smartanalog/flutter_app/MainActivity.kt`
- Home widget provider: `mobile/flutter_app/android/app/src/main/kotlin/com/smartanalog/flutter_app/SmartAnalogAppWidgetProvider.kt`
- LockStar widget provider: `mobile/flutter_app/android/app/src/main/kotlin/com/smartanalog/flutter_app/SmartAnalogLockStarWidgetProvider.kt`
- Manifest deep-link/widget registration: `mobile/flutter_app/android/app/src/main/AndroidManifest.xml`

### iOS widget surface

- WidgetKit extension: `mobile/flutter_app/ios/WidgetExtension/SmartAnalogWidget.swift`

### Backend/mobile contract boundary

- Backend contract source: `web/backend/app/main.py`
- Mobile API client: `mobile/flutter_app/lib/integrations/backend_api/api_client.dart`
- Mobile DTOs: `mobile/flutter_app/lib/integrations/backend_api/dto/`
- Contract regression tests: `mobile/flutter_app/test/backend_mvp_parity_dto_contract_test.dart`

## 4) Known Stale References (Ignore/Do Not Depend On)

These are referenced in docs but missing in this worktree:

- `scripts/local-web-dev.sh`
- `scripts/fly-deploy-check.sh`
- `docs/flyio-deploy-ko.md`
- `src/main.py`
- `web/frontend/src/app/settings/color-schema/page.tsx`
- `mobile/AGENTS.md`
- `mobile/flutter_app/AGENTS.md`

Use actual existing files and commands from this document instead.

## 5) Scope and Guardrails

### In scope

- Mobile feature/UI behavior in Flutter.
- Android/iOS widget behavior tied to snapshot payload.
- Mobile-backend contract-safe changes (with matching DTO/backend updates).

### Out of scope unless explicitly requested

- Broad desktop refactors.
- Unrelated web UX overhauls.
- Renaming backend payload fields for convenience.

### Non-negotiable constraints

- Never revert unrelated user changes in dirty worktree.
- Keep backend, mobile DTO, and web interfaces in sync when API fields change.
- Preserve existing architecture style: repository + DTO translation + native widget bridges.
- Prefer portable commands over local shell aliases.

## 6) First 30 Minutes Runbook (Portable)

### A. Mobile sanity checks

```bash
cd /home/shine/projects/clock_widget/mobile/flutter_app
flutter analyze
flutter test
flutter build apk --debug
```

### B. Local backend for mobile testing

```bash
cd /home/shine/projects/clock_widget
uv run uvicorn web.backend.app.main:app --host 0.0.0.0 --port 8000
```

### C. Android physical device bridge (WSL + local backend)

If you are running inside WSL, use `usbipd attach --wsl` only when `adb devices -l` does not show the device:

```bash
powershell.exe -NoProfile -Command "usbipd list"
powershell.exe -NoProfile -Command "usbipd attach --wsl --busid <BUSID>"
```

Once the device is visible in WSL, run adb/flutter commands only from WSL using the single-port flow (`5037`):

```bash
ADB_SERVER_SOCKET=tcp:127.0.0.1:5037 /home/shine/platform-tools/adb devices -l
ADB_SERVER_SOCKET=tcp:127.0.0.1:5037 /home/shine/platform-tools/adb -s <DEVICE_ID> reverse tcp:8000 tcp:8000
cd /home/shine/projects/clock_widget/mobile/flutter_app
PATH=/home/shine/platform-tools:$PATH ADB_SERVER_SOCKET=tcp:127.0.0.1:5037 flutter run -d <DEVICE_ID> --dart-define=BACKEND_BASE_URL=http://127.0.0.1:8000
```

Important (single-port WSL adb on `5037`):

- `adb start-server` without extra env uses the default server port (`5037`). This matches the current WSL setup.
- Keep all WSL adb/flutter commands on `ADB_SERVER_SOCKET=tcp:127.0.0.1:5037` for a single-port flow.
- You can prefix each command with `ADB_SERVER_SOCKET=tcp:127.0.0.1:5037`, or
  export once in the current shell (`export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037`) and then run `adb ...`/`flutter ...`.
- If you hit host/WSL adb conflicts, move the whole session to `5038` consistently (do not mix `5037` and `5038` in one session).
- If you use `cw-adb`/`cw-flutter-run` wrappers from `~/.zshrc`, move `CW_ANDROID_ADB_SOCKET` to the same port as `ADB_SERVER_SOCKET` for that session.

### D. Android real-device final QA (recommended)

```bash
cd /home/shine/projects/clock_widget
CW_QA_BACKEND_URL=https://smart-analog-clock.fly.dev CW_QA_DEVICE_ID=<DEVICE_ID> PATH=/home/shine/platform-tools:$PATH ./scripts/android-final-qa.sh
```

By default, the script writes artifacts to `/tmp/clock_widget_android_final_qa_<timestamp>/`.

Notes:

- Default mobile backend is remote Fly URL in `mobile/flutter_app/lib/core/config/backend_config.dart`.
- If testing locally, always set `BACKEND_BASE_URL` explicitly.
- If `adb start-server` output shows `5037`, that is expected default behavior. Keep WSL adb/flutter commands on `ADB_SERVER_SOCKET=tcp:127.0.0.1:5037`.
- `scripts/android-final-qa.sh` now uses the same `5037` single-port WSL adb flow by default. Set `CW_QA_ADB_SOCKET` only when intentionally moving the whole session to another port.
- `usbipd attach --wsl` is not always required; use it only when USB is connected but WSL adb cannot see the device.
- If `flutter devices` misses Android but `adb devices -l` lists it, use `scripts/android-final-qa.sh` as the primary WSL validation path and keep standalone adb checks for diagnosis.

### E. Fly apply checklist for backend-coupled mobile changes

Use this when mobile behavior depends on backend runtime logic (for example: AI parsing/creation flow, provider auth, DTO contract behavior, or feature flags).

1. Confirm current Fly runtime config before testing against remote backend:

```bash
cd /home/shine/projects/clock_widget
flyctl status -a smart-analog-clock
flyctl secrets list -a smart-analog-clock
```

2. If your change introduced or updated backend env-driven behavior, sync secrets first (example keys):

```bash
flyctl secrets set \
  ENABLE_AI_NATURAL_INPUT=true \
  OPENAI_NATURAL_INPUT_MODEL=gpt-4o-mini \
  OPENAI_NATURAL_INPUT_TIMEOUT=8 \
  OPENAI_NATURAL_INPUT_REASONING_EFFORT=minimal \
  OPENAI_NATURAL_INPUT_MAX_OUTPUT_TOKENS=180 \
  LANGSMITH_TRACING=true \
  LANGSMITH_PROJECT=clock-widget \
  -a smart-analog-clock
```

3. Deploy backend/web container when behavior changed server-side:

```bash
cd /home/shine/projects/clock_widget
flyctl deploy -a smart-analog-clock
flyctl status -a smart-analog-clock
```

4. Validate critical endpoint behavior before device QA (replace payload with task-specific sentence):

```bash
curl -sS -w "\nTOTAL:%{time_total}s HTTP:%{http_code}\n" \
  -X POST "https://smart-analog-clock.fly.dev/api/events/natural-input/create?provider=google" \
  -H "Content-Type: application/json" \
  -d '{"text":"내일 한 시에 민지랑 홍대입구역에서 보기"}'
```

Notes:

- This worktree does not include `scripts/fly-deploy-check.sh`; use direct `flyctl` commands above.
- If task scope is pure local/mobile UI and does not depend on remote backend runtime behavior, Fly deploy is optional.
- For AI features, require LangSmith secrets on Fly (`LANGSMITH_TRACING`, `LANGSMITH_API_KEY`, `LANGSMITH_PROJECT`) before claiming observability validation.

## 7) Prioritized Starting Points

1. `mobile/flutter_app/lib/features/calendar/presentation/mobile_home_screen.dart`  
   Understand auth flow, deep links, refresh timers, snapshot lifecycle.
2. `mobile/flutter_app/lib/features/calendar/application/widget_snapshot_builder.dart` + `mobile/flutter_app/lib/core/storage/widget_snapshot_store.dart`  
   Confirm payload shape before touching native widgets.
3. Android providers (`SmartAnalogAppWidgetProvider.kt`, `SmartAnalogLockStarWidgetProvider.kt`)  
   Validate rendering consistency and duplicated parsing/formatting behavior.
4. `mobile/flutter_app/ios/WidgetExtension/SmartAnalogWidget.swift`  
   Keep schema parity with Flutter snapshot writer.
5. `web/backend/app/main.py` + mobile DTO folder  
   Confirm contract stability before adding/changing fields.

## 8) Contract Sync Checklist

When changing API payloads, update all applicable surfaces in one change set:

1. Backend Pydantic models/endpoints in `web/backend/app/main.py`
2. Mobile DTO parsing in `mobile/flutter_app/lib/integrations/backend_api/dto/`
3. Mobile mapping/repository logic in `mobile/flutter_app/lib/features/calendar/data/calendar_events_repository.dart`
4. Web interface mirror in `web/frontend/src/app/page.tsx` (if field is shared)
5. Contract tests in `mobile/flutter_app/test/backend_mvp_parity_dto_contract_test.dart`

## 9) Known Risk Areas

- Snapshot schema drift between Dart writer and Kotlin/Swift readers.
- Behavior drift between Flutter analog clock rendering and Android widget renderer.
- iOS widget runtime verification still less proven than Android path.
- Settings opacity semantics (`event_opacity`) may drift across surfaces if not carefully normalized.

## 10) Verification Before Handoff

Minimum required verification for mobile tasks:

1. `flutter analyze`
2. `flutter test`
3. Relevant build command (`flutter build apk --debug` for Android-impacting changes)
4. If API contract changed: manually hit affected backend endpoints and validate DTO parsing path
5. If widget changed: verify snapshot write + native render path on target platform
6. If remote Fly backend is used for QA, verify deployed app version and required Fly secrets before final handoff

### Real-device testing requirement for new features (mandatory)

If a task introduces a new mobile feature or changes user-facing behavior, real-device testing is required before handoff.

- Android changes: run and validate on a physical Android device (not emulator-only).
- iOS changes: validate on a physical iOS device or report an explicit blocker if device access is unavailable.
- Do not mark feature work complete with simulator/emulator-only evidence.
- Final handoff must include what was tested on real devices, device type/OS, and observed result.
- For Android real-device evidence, include command(s) run, `adb devices -l` device line, and log/artifact path (for script runs, `/tmp/clock_widget_android_final_qa_<timestamp>/`).

Report any unverified surface explicitly (for example, iOS WidgetKit runtime unavailable on Linux).

## 11) Agent Prompt Template (Codex Prompting Guide Aligned)

Use this block to start a fresh agent session:

```md
# Mobile Task Kickoff

## Mission
You are a coding agent working in `mobile/flutter_app/` of a monorepo. Deliver working code end-to-end (context -> implementation -> verification).

## Objective
- Primary task: <clear deliverable>
- Why: <user/product impact>

## Context
- Main mobile hub: `mobile/flutter_app/lib/features/calendar/presentation/mobile_home_screen.dart`
- Snapshot boundary: `mobile/flutter_app/lib/features/calendar/application/widget_snapshot_builder.dart`, `mobile/flutter_app/lib/core/storage/widget_snapshot_store.dart`
- Native widget hosts: Android providers + iOS WidgetExtension
- Backend contract source: `web/backend/app/main.py`
- Mobile DTO contract: `mobile/flutter_app/lib/integrations/backend_api/dto/`

## Scope
In: <what to change>
Out: <what not to touch>

## Guardrails
- Keep backend/mobile/web contracts synchronized when fields change.
- Do not revert unrelated dirty-worktree changes.
- Prefer existing patterns over introducing new architecture.
- No broad silent fallbacks; surface errors clearly.

## Verification
- `flutter analyze`
- `flutter test`
- platform-specific build/run relevant to touched surfaces
- contract checks across backend + DTO + consumer mapping

## Output Contract
- Explain what changed and why.
- List touched files with paths.
- Report verification results and remaining risks/blockers.
```

This structure follows the Codex prompting guide principles: clear mission/context, explicit guardrails, end-to-end execution bias, and verification-backed completion.
