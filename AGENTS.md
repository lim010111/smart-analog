# AGENTS.md

This repository is a multi-surface monorepo:
- Desktop app: PySide6 + Python under `src/`
- Web app: FastAPI + Next.js under `web/`
- Mobile app: Flutter (iOS/Android) under `mobile/flutter_app/`
- Deployment/tooling: Fly.io and local orchestration scripts under `scripts/`

## Where To Start

- Read `README.md` for product scope and runtime modes.
- Use `scripts/local-web-dev.sh` for local web development (backend + frontend together).
- Use `scripts/fly-deploy-check.sh` for Fly preflight/deploy validation.
- For mobile work, start in `mobile/flutter_app/` and run Flutter commands there.

## Code Map

- Desktop runtime entry: `src/main.py`
- Desktop packaging: `ClockWidget.spec`
- Web backend entry: `web/backend/app/main.py`
- Web frontend entry: `web/frontend/src/app/page.tsx`
- Complex frontend hotspot: `web/frontend/src/app/settings/color-schema/page.tsx`
- Mobile app entry: `mobile/flutter_app/lib/main.dart`
- Mobile app bootstrap: `mobile/flutter_app/lib/app/app.dart`

## Canonical Commands

- Desktop run: `uv run src/main.py`
- Web local all-in-one: `./scripts/local-web-dev.sh`
- Backend only: `uv run uvicorn web.backend.app.main:app --reload --host 0.0.0.0 --port 8000`
- Frontend only: `cd web/frontend && NEXT_PUBLIC_BACKEND_URL=http://localhost:8000 npm run dev`
- Frontend build: `cd web/frontend && npm run build`
- Python sanity compile: `uv run python -m compileall -q src web/backend/app`
- Mobile analyze: `cd mobile/flutter_app && flutter analyze`
- Mobile Android debug build: `cd mobile/flutter_app && flutter build apk --debug`

## Repo-Specific Rules

- Python baseline is `>=3.13` (`pyproject.toml`).
- Frontend/backend contracts are currently duplicated (Pydantic in backend, TypeScript interfaces in frontend). Keep fields in sync when changing API payloads.
- Mobile DTOs are now another contract surface; when backend payloads change, update both `web/frontend` interfaces and `mobile/flutter_app` models in the same change.
- Prefer extending shared business logic in `src/services/` instead of re-implementing logic in `web/backend/app/main.py`.
- Never commit secrets or local credentials files (`.env`, `token.json`, Apple credentials).

## Testing And Verification Expectations

- There is no mature test suite yet; perform focused runtime verification.
- For backend/service changes: run compile sanity and exercise affected endpoints.
- For frontend changes: run `npm run build` and test affected flows in browser.
- For mobile changes: run `flutter analyze` and validate snapshot/model flows from `lib/features/calendar`.
- For cross-layer changes: verify `web/backend/app/main.py` payload shapes against both frontend interfaces and mobile models.

## Local AGENTS Hierarchy

- `src/AGENTS.md`: Python desktop/service architecture and provider/AI boundaries.
- `web/AGENTS.md`: Web coupling rules, API boundaries, deployment/local workflows.
- `web/frontend/AGENTS.md`: Frontend architecture, state/rendering conventions, and hotspot guidance.
- `mobile/AGENTS.md`: Mobile platform boundaries and Flutter workspace rules.
- `mobile/flutter_app/AGENTS.md`: Flutter app architecture, contracts, and widget integration boundaries.
