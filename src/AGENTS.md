# AGENTS.md (src)

Scope: Python desktop runtime and shared domain/services used by both desktop and web backend.

## Primary Responsibilities

- `src/main.py`: desktop entrypoint and Qt app startup.
- `src/models/`: shared domain models (single source for Python-side contracts).
- `src/services/calendar.py`: provider orchestration and calendar-level flows.
- `src/services/providers/`: provider abstractions and implementations (Google, Apple).
- `src/services/ai/`: AI briefing, color schema, natural input, TTS.
- `src/ui/`: widget/menu/dialog wiring for desktop runtime.

## Change Rules

- Keep provider-specific logic inside `src/services/providers/`, not callers.
- Keep shared business logic in `src/services/`; web backend should call these services.
- When changing event/color schema fields, update backend Pydantic and frontend TypeScript in the same change.
- Do not introduce direct web framework concerns (FastAPI models/routes) into `src/services/`.

## Provider/Auth Notes

- Google provider and OAuth flow are implemented in `src/services/providers/google_provider.py` and consumed by web backend endpoints.
- Apple provider uses iCloud CalDAV and app-specific password flow (`src/services/providers/apple_provider.py`).
- Credential files are local state; never commit generated credentials or tokens.

## Verification

- Always run: `uv run python -m compileall -q src web/backend/app` after Python changes.
- For provider changes, exercise login and basic event read flow from backend endpoints.
- For AI service changes, verify degraded behavior without API key remains safe.
