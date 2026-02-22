# Clock Widget Web Backend

## Run

```bash
uv pip install -r web/backend/requirements.txt
uv run uvicorn web.backend.app.main:app --reload --host 0.0.0.0 --port 8000
```

## Environment

- `WEB_DEFAULT_PROVIDER` (`google` default)
- `WEB_CORS_ORIGINS` (`http://localhost:3000` default)

## Endpoints

- `GET /health`
- `GET /api/events/today?provider=google&max_results=20`
- `GET /api/briefing/today?provider=google&max_results=20&force=true`
