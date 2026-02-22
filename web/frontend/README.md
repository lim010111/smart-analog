# Clock Widget Web Frontend

## Run

```bash
npm install
NEXT_PUBLIC_BACKEND_URL=http://localhost:8000 npm run dev
```

Open `http://localhost:3000`.

The page fetches briefing data from `GET /api/briefing/today` on the FastAPI backend.

## Environment

- `NEXT_PUBLIC_BACKEND_URL` (default: `http://localhost:8000`)
- `BACKEND_URL` (legacy fallback, 일부 페이지에서만 사용)
