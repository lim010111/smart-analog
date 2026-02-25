# AGENTS.md (web)

Scope: FastAPI backend + Next.js frontend integration and web runtime workflows.

## Structure

- `web/backend/app/main.py`: FastAPI app entry, web models, API endpoints.
- `web/frontend/src/app/page.tsx`: main client page and API consumption.
- `web/frontend/src/app/settings/color-schema/page.tsx`: color schema editor and apply flow.

## Integration Contract Rules

- Backend request/response shapes are defined in `web/backend/app/main.py` (Pydantic) and mirrored in frontend interfaces.
- When adding/changing endpoint fields, update both sides together in one PR/commit.
- Prefer reusing `src/services/*` for domain logic; keep `main.py` focused on HTTP translation.

## Runtime Commands

- All-in-one local: `./scripts/local-web-dev.sh`
- Backend only: `uv run uvicorn web.backend.app.main:app --reload --host 0.0.0.0 --port 8000`
- Frontend only: `cd web/frontend && NEXT_PUBLIC_BACKEND_URL=http://localhost:8000 npm run dev`
- Frontend build gate: `cd web/frontend && npm run build`

## Deployment/Preflight

- Fly workflow is script-driven via `scripts/fly-deploy-check.sh`.
- If touching deploy behavior, keep `fly.toml`, `Dockerfile`, and script assumptions aligned.

## Verification Expectations

- Backend change: compile sanity and endpoint smoke test.
- Frontend change: `npm run build` plus interactive browser check.
- Cross-layer change: verify payload compatibility and no frontend parsing regressions.
