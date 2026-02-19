const API_BASE_URL = process.env.BACKEND_URL ?? "http://localhost:8000";

type BriefingResponse = {
  provider: string;
  generated_at: string;
  briefing: string;
  event_count: number;
};

async function fetchTodayBriefing(): Promise<BriefingResponse> {
  const response = await fetch(`${API_BASE_URL}/api/briefing/today?provider=google`, {
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`Failed to load briefing (${response.status})`);
  }

  return (await response.json()) as BriefingResponse;
}

export default async function Home() {
  let briefing: BriefingResponse | null = null;
  let errorMessage = "";

  try {
    briefing = await fetchTodayBriefing();
  } catch (error) {
    errorMessage = error instanceof Error ? error.message : "Unknown error";
  }

  return (
    <div className="min-h-screen bg-slate-950 px-4 py-12 text-slate-100">
      <main className="mx-auto flex w-full max-w-3xl flex-col gap-6">
        <header className="space-y-2">
          <p className="text-xs font-semibold uppercase tracking-[0.25em] text-sky-300">
            Clock Widget Web
          </p>
          <h1 className="text-3xl font-bold tracking-tight text-white">오늘의 브리핑</h1>
          <p className="text-sm text-slate-300">
            FastAPI가 생성한 실시간 브리핑을 Next.js 화면에서 보여줍니다.
          </p>
        </header>

        <section className="rounded-2xl border border-slate-700 bg-slate-900/80 p-6 shadow-[0_18px_60px_-30px_rgba(15,23,42,0.95)]">
          {briefing ? (
            <div className="space-y-4">
              <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-slate-400">
                <span>provider: {briefing.provider}</span>
                <span>events: {briefing.event_count}</span>
              </div>
              <p className="rounded-xl border border-slate-700 bg-slate-950/60 px-4 py-4 text-base leading-7 text-slate-100">
                {briefing.briefing}
              </p>
              <p className="text-xs text-slate-500">generated: {briefing.generated_at}</p>
            </div>
          ) : (
            <div className="space-y-3">
              <p className="rounded-xl border border-rose-400/40 bg-rose-950/40 px-4 py-3 text-sm text-rose-100">
                브리핑을 불러오지 못했습니다: {errorMessage}
              </p>
              <p className="text-xs text-slate-500">
                백엔드 서버가 실행 중인지 확인하세요 (`uv run uvicorn web.backend.app.main:app --reload`).
              </p>
            </div>
          )}
        </section>
      </main>
    </div>
  );
}
