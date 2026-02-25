# AGENTS.md

This repository is a hybrid monorepo:
- Desktop app: PySide6 + Python under `src/`
- Web app: FastAPI + Next.js under `web/`
- Deployment/tooling: Fly.io and local orchestration scripts under `scripts/`

## Where To Start

- Read `README.md` for product scope and runtime modes.
- Use `scripts/local-web-dev.sh` for local web development (backend + frontend together).
- Use `scripts/fly-deploy-check.sh` for Fly preflight/deploy validation.

## Code Map

- Desktop runtime entry: `src/main.py`
- Desktop packaging: `ClockWidget.spec`
- Web backend entry: `web/backend/app/main.py`
- Web frontend entry: `web/frontend/src/app/page.tsx`
- Complex frontend hotspot: `web/frontend/src/app/settings/color-schema/page.tsx`

## Canonical Commands

- Desktop run: `uv run src/main.py`
- Web local all-in-one: `./scripts/local-web-dev.sh`
- Backend only: `uv run uvicorn web.backend.app.main:app --reload --host 0.0.0.0 --port 8000`
- Frontend only: `cd web/frontend && NEXT_PUBLIC_BACKEND_URL=http://localhost:8000 npm run dev`
- Frontend build: `cd web/frontend && npm run build`
- Python sanity compile: `uv run python -m compileall -q src web/backend/app`

## Repo-Specific Rules

- Python baseline is `>=3.13` (`pyproject.toml`).
- Frontend/backend contracts are currently duplicated (Pydantic in backend, TypeScript interfaces in frontend). Keep fields in sync when changing API payloads.
- Prefer extending shared business logic in `src/services/` instead of re-implementing logic in `web/backend/app/main.py`.
- Never commit secrets or local credentials files (`.env`, `token.json`, Apple credentials).

## Testing And Verification Expectations

- There is no mature test suite yet; perform focused runtime verification.
- For backend/service changes: run compile sanity and exercise affected endpoints.
- For frontend changes: run `npm run build` and test affected flows in browser.
- For cross-layer changes: verify both `web/backend/app/main.py` payload shapes and frontend interface usage.

## Local AGENTS Hierarchy

- `src/AGENTS.md`: Python desktop/service architecture and provider/AI boundaries.
- `web/AGENTS.md`: Web coupling rules, API boundaries, deployment/local workflows.
- `web/frontend/AGENTS.md`: Frontend architecture, state/rendering conventions, and hotspot guidance.
