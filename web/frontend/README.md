# Clock Widget Web Frontend

## Run

```bash
npm install
BACKEND_URL=http://localhost:8000 npm run dev
```

Open `http://localhost:3000`.

The page fetches briefing data from `GET /api/briefing/today` on the FastAPI backend.

## Environment

- `BACKEND_URL` (default: `http://localhost:8000`)
