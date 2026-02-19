"use client";

import {
  ChangeEvent,
  FormEvent,
  MouseEvent as ReactMouseEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import Link from "next/link";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_BACKEND_URL ?? process.env.BACKEND_URL ?? "http://localhost:8000";

const CLOCK_SIZE = 460;
const REQUEST_TIMEOUT_MS = 15000;

type ThemeName = "dark" | "light";

type WebEvent = {
  id: string;
  summary: string;
  description: string;
  start_time: string;
  end_time: string;
  all_day: boolean;
  color_hex: string;
  provider_color_id: string | null;
};

type EventResponse = {
  provider: string;
  date: string;
  count: number;
  events: WebEvent[];
};

type BriefingResponse = {
  provider: string;
  generated_at: string;
  briefing: string;
  event_count: number;
  disabled?: boolean;
};

type NaturalParseResult = {
  intent: string;
  title: string;
  start_time: string | null;
  end_time: string | null;
  all_day: boolean;
  confidence: number;
  note: string | null;
};

type ColorRule = {
  color_hex: string;
  label: string;
  keywords: string[];
};

type WebSettings = {
  theme: ThemeName;
  event_opacity: number;
  briefing_enabled: boolean;
  briefing_tts_enabled: boolean;
  widget_pinned: boolean;
};

const defaultSettings: WebSettings = {
  theme: "dark",
  event_opacity: 150,
  briefing_enabled: true,
  briefing_tts_enabled: false,
  widget_pinned: true,
};

function extractErrorDetail(raw: string): string | null {
  if (!raw) {
    return null;
  }
  try {
    const body = JSON.parse(raw) as { detail?: string };
    return typeof body?.detail === "string" ? body.detail : null;
  } catch {
    return null;
  }
}

async function fetchJson<T>(url: string, init?: RequestInit): Promise<T> {
  const controller = new AbortController();
  const timeoutId = window.setTimeout(() => {
    controller.abort();
  }, REQUEST_TIMEOUT_MS);

  let response: Response;
  try {
    response = await fetch(url, {
      ...init,
      signal: controller.signal,
      headers: {
        "Content-Type": "application/json",
        ...(init?.headers ?? {}),
      },
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error("Request timed out. Please authenticate provider and try again.");
    }
    throw error;
  } finally {
    window.clearTimeout(timeoutId);
  }

  if (!response.ok) {
    let message = `Request failed (${response.status})`;
    const raw = await response.text();
    const detail = extractErrorDetail(raw);
    if (detail) {
      message = detail;
    }
    throw new Error(message);
  }

  return (await response.json()) as T;
}

function formatDateTime(value: string): string {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return value;
  }
  return parsed.toLocaleString("ko-KR", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatEventRange(event: WebEvent): string {
  if (event.all_day) {
    return "종일";
  }
  const start = new Date(event.start_time);
  const end = new Date(event.end_time);
  return `${start.toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit", hour12: false })} - ${end.toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit", hour12: false })}`;
}

function asThemeName(value: string): ThemeName {
  return value === "light" ? "light" : "dark";
}

function parseEventDate(value: string): Date {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? new Date() : parsed;
}

function minutesBetween(start: Date, end: Date): number {
  return Math.max(0, Math.round((end.getTime() - start.getTime()) / 60000));
}

function pointToAngleDeg(relX: number, relY: number): number {
  let deg = (Math.atan2(-relY, relX) * 180) / Math.PI;
  if (deg < 0) {
    deg += 360;
  }
  return deg;
}

function withinClockwiseRange(angle: number, start: number, end: number): boolean {
  if (end < start) {
    return angle >= end && angle <= start;
  }
  return angle >= end || angle <= start;
}

type HoverInfo = {
  event: WebEvent;
  x: number;
  y: number;
};

function detectHoveredEvent(
  events: WebEvent[],
  mouseX: number,
  mouseY: number,
  size: number,
  now: Date,
): WebEvent | null {
  if (!events.length) {
    return null;
  }

  const center = size / 2;
  const relX = mouseX - center;
  const relY = mouseY - center;
  const dist = Math.sqrt(relX * relX + relY * relY);
  const scale = (size - 12) / 200;
  const scaledDist = dist / scale;
  const inPieRegion = scaledDist >= 15 && scaledDist <= 88;
  const inArcRegion = scaledDist >= 90 && scaledDist <= 97;
  const angleDeg = pointToAngleDeg(relX, relY);
  const currentIsAm = now.getHours() < 12;

  if (scaledDist >= 95) {
    const scaledX = relX / scale;
    const scaledY = relY / scale;
    const allDayEvents = events.filter((event) => event.all_day);
    const spacing = 10;
    const totalWidth = (allDayEvents.length - 1) * spacing;

    for (let index = 0; index < allDayEvents.length; index += 1) {
      const dotX = -totalWidth / 2 + index * spacing;
      const dotY = -103;
      const dx = scaledX - dotX;
      const dy = scaledY - dotY;
      if (Math.sqrt(dx * dx + dy * dy) <= 5.5) {
        return allDayEvents[index];
      }
    }
  }

  if (!inPieRegion && !inArcRegion) {
    return null;
  }

  for (const event of events) {
    if (event.all_day) {
      continue;
    }
    const evStart = parseEventDate(event.start_time);
    const evEnd = parseEventDate(event.end_time);
    if (now > evEnd) {
      continue;
    }

    const isInProgress = evStart <= now && now <= evEnd;
    const isCurrentCycle = isInProgress || currentIsAm === (evStart.getHours() < 12);
    if (isCurrentCycle && !inPieRegion) {
      continue;
    }
    if (!isCurrentCycle && !inArcRegion) {
      continue;
    }

    const startHour = (evStart.getHours() % 12) + evStart.getMinutes() / 60;
    let startAngle = 90 - startHour * 30;
    let spanAngle = -(Math.min(12 * 60, minutesBetween(evStart, evEnd)) / (12 * 60)) * 360;

    if (isInProgress) {
      const nowHour = (now.getHours() % 12) + now.getMinutes() / 60 + now.getSeconds() / 3600;
      startAngle = 90 - nowHour * 30;
      const remainingHours = Math.min(12, Math.max(0, (evEnd.getTime() - now.getTime()) / 3600000));
      spanAngle = -(remainingHours * 30);
    }

    const s = ((startAngle % 360) + 360) % 360;
    const e = (((startAngle + spanAngle) % 360) + 360) % 360;

    if (withinClockwiseRange(angleDeg, s, e)) {
      return event;
    }
  }

  return null;
}

function drawClock(
  canvas: HTMLCanvasElement,
  events: WebEvent[],
  now: Date,
  theme: ThemeName,
  eventOpacity: number,
) {
  const context = canvas.getContext("2d");
  if (!context) {
    return;
  }

  const size = canvas.width;
  const center = size / 2;
  const scale = (size - 12) / 200;
  const faceRadius = 95 * scale;
  const pieRadius = 88 * scale;
  const arcRadius = 94 * scale;

  const palette =
    theme === "dark"
      ? {
          face: "#131620",
          border: "#4a5267",
          tick: "#d9def0",
          hand: "#f4f7ff",
          number: "#f4f7ff",
          second: "#ff7a7a",
          backdrop: "#0d111c",
        }
      : {
          face: "#f8fafc",
          border: "#7d8aa5",
          tick: "#1f2937",
          hand: "#111827",
          number: "#111827",
          second: "#d7263d",
          backdrop: "#dde3ee",
        };

  context.clearRect(0, 0, size, size);
  context.fillStyle = palette.backdrop;
  context.fillRect(0, 0, size, size);

  context.save();
  context.translate(center, center);

  context.beginPath();
  context.fillStyle = palette.face;
  context.strokeStyle = palette.border;
  context.lineWidth = 2;
  context.arc(0, 0, faceRadius, 0, Math.PI * 2);
  context.fill();
  context.stroke();

  const currentIsAm = now.getHours() < 12;
  let allDayDotIndex = 0;
  const allDayCount = events.filter((event) => event.all_day).length;

  for (const event of events) {
    if (event.all_day) {
      const dotY = -103 * scale;
      const spacing = 10 * scale;
      const totalWidth = (allDayCount - 1) * spacing;
      const dotX = -totalWidth / 2 + allDayDotIndex * spacing;
      allDayDotIndex += 1;
      context.beginPath();
      context.fillStyle = event.color_hex || "#64748b";
      context.globalAlpha = Math.min(1, Math.max(0.1, eventOpacity / 255));
      context.arc(dotX, dotY, 3.5 * scale, 0, Math.PI * 2);
      context.fill();
      context.globalAlpha = 1;
      continue;
    }

    const evStart = parseEventDate(event.start_time);
    const evEnd = parseEventDate(event.end_time);
    if (now > evEnd) {
      continue;
    }

    const isInProgress = evStart <= now && now <= evEnd;
    const isCurrentCycle = isInProgress || currentIsAm === (evStart.getHours() < 12);

    let startHour = (evStart.getHours() % 12) + evStart.getMinutes() / 60;
    let startAngle = 90 - startHour * 30;
    let spanAngle = -(Math.min(12 * 60, minutesBetween(evStart, evEnd)) / (12 * 60)) * 360;

    if (isInProgress) {
      startHour = (now.getHours() % 12) + now.getMinutes() / 60 + now.getSeconds() / 3600;
      startAngle = 90 - startHour * 30;
      const remainingHours = Math.min(12, Math.max(0, (evEnd.getTime() - now.getTime()) / 3600000));
      spanAngle = -(remainingHours * 30);
    }

    const startRad = ((90 - startAngle) * Math.PI) / 180;
    const endRad = ((90 - (startAngle + spanAngle)) * Math.PI) / 180;
    const color = event.color_hex || "#64748b";
    const alphaBase = Math.max(0.15, Math.min(1, eventOpacity / 255));

    if (isCurrentCycle) {
      context.beginPath();
      context.moveTo(0, 0);
      context.fillStyle = color;
      context.globalAlpha = isInProgress ? alphaBase : alphaBase * 0.45;
      context.arc(0, 0, pieRadius, startRad, endRad, spanAngle > 0);
      context.closePath();
      context.fill();
      context.globalAlpha = 1;

      context.beginPath();
      context.strokeStyle = color;
      context.lineWidth = 1.6;
      context.arc(0, 0, pieRadius, startRad, endRad, spanAngle > 0);
      context.stroke();
    } else {
      context.beginPath();
      context.strokeStyle = color;
      context.lineWidth = 4;
      context.lineCap = "round";
      context.globalAlpha = alphaBase * 0.6;
      context.arc(0, 0, arcRadius, startRad, endRad, spanAngle > 0);
      context.stroke();
      context.globalAlpha = 1;
    }
  }

  context.strokeStyle = palette.tick;
  context.lineWidth = 2;
  for (let index = 0; index < 12; index += 1) {
    context.save();
    context.rotate((index * Math.PI) / 6);
    context.beginPath();
    context.moveTo(85 * scale, 0);
    context.lineTo(90 * scale, 0);
    context.stroke();
    context.restore();
  }

  context.strokeStyle = palette.tick;
  context.lineWidth = 1;
  for (let index = 0; index < 48; index += 1) {
    if (index % 4 !== 0) {
      context.save();
      context.rotate((index * Math.PI) / 24);
      context.beginPath();
      context.moveTo(88 * scale, 0);
      context.lineTo(90 * scale, 0);
      context.stroke();
      context.restore();
    }
  }

  const hourValue = now.getHours() % 12 + now.getMinutes() / 60;
  const minuteValue = now.getMinutes() + now.getSeconds() / 60;
  const secondValue = now.getSeconds() + now.getMilliseconds() / 1000;

  context.save();
  context.rotate((hourValue * Math.PI) / 6);
  context.fillStyle = palette.hand;
  context.beginPath();
  context.moveTo(-4 * scale, 8 * scale);
  context.lineTo(4 * scale, 8 * scale);
  context.lineTo(0, -50 * scale);
  context.closePath();
  context.fill();
  context.restore();

  context.save();
  context.rotate((minuteValue * Math.PI) / 30);
  context.fillStyle = palette.hand;
  context.beginPath();
  context.moveTo(-3 * scale, 8 * scale);
  context.lineTo(3 * scale, 8 * scale);
  context.lineTo(0, -75 * scale);
  context.closePath();
  context.fill();
  context.restore();

  context.save();
  context.rotate((secondValue * Math.PI) / 30);
  context.fillStyle = palette.second;
  context.beginPath();
  context.moveTo(-1 * scale, 15 * scale);
  context.lineTo(1 * scale, 15 * scale);
  context.lineTo(0, -85 * scale);
  context.closePath();
  context.fill();
  context.restore();

  context.beginPath();
  context.fillStyle = palette.hand;
  context.arc(0, 0, 3 * scale, 0, Math.PI * 2);
  context.fill();

  context.fillStyle = palette.number;
  context.font = `${Math.round(9 * scale)}px var(--font-display)`;
  context.textAlign = "center";
  context.textBaseline = "middle";
  for (let hour = 1; hour <= 12; hour += 1) {
    const angle = ((hour * 30 + 270) * Math.PI) / 180;
    const x = 72 * scale * Math.cos(angle);
    const y = 72 * scale * Math.sin(angle);
    context.fillText(String(hour), x, y);
  }

  context.restore();
}

export default function Home() {
  const [provider, setProvider] = useState("google");
  const [settings, setSettings] = useState<WebSettings>(defaultSettings);
  const [eventsData, setEventsData] = useState<EventResponse | null>(null);
  const [briefingData, setBriefingData] = useState<BriefingResponse | null>(null);
  const [briefingLoading, setBriefingLoading] = useState(false);
  const [eventsLoading, setEventsLoading] = useState(false);
  const [message, setMessage] = useState<string>("");
  const [clockNow, setClockNow] = useState<Date>(new Date());

  const [naturalText, setNaturalText] = useState("");
  const [naturalResult, setNaturalResult] = useState<NaturalParseResult | null>(null);
  const [naturalLoading, setNaturalLoading] = useState(false);

  const [appleId, setAppleId] = useState("");
  const [applePassword, setApplePassword] = useState("");

  const [palette, setPalette] = useState<string[]>([]);
  const [schemaRuleCount, setSchemaRuleCount] = useState(0);
  const [schemaLoading, setSchemaLoading] = useState(false);
  const [hoverInfo, setHoverInfo] = useState<HoverInfo | null>(null);

  const clockRef = useRef<HTMLCanvasElement | null>(null);

  const hasEventColorSupport = useMemo(() => palette.length > 0, [palette.length]);

  const loadSettings = useCallback(async () => {
    const data = await fetchJson<WebSettings>(`${API_BASE_URL}/api/settings`);
    setSettings({
      theme: asThemeName(data.theme),
      event_opacity: Number(data.event_opacity ?? 150),
      briefing_enabled: Boolean(data.briefing_enabled),
      briefing_tts_enabled: Boolean(data.briefing_tts_enabled),
      widget_pinned: Boolean(data.widget_pinned),
    });
  }, []);

  const saveSettings = useCallback(
    async (next: WebSettings) => {
      const normalized: WebSettings = {
        ...next,
        theme: asThemeName(next.theme),
        event_opacity: Math.min(255, Math.max(0, Math.round(next.event_opacity))),
      };
      const saved = await fetchJson<WebSettings>(`${API_BASE_URL}/api/settings`, {
        method: "PUT",
        body: JSON.stringify(normalized),
      });
      setSettings({
        theme: asThemeName(saved.theme),
        event_opacity: Number(saved.event_opacity ?? 150),
        briefing_enabled: Boolean(saved.briefing_enabled),
        briefing_tts_enabled: Boolean(saved.briefing_tts_enabled),
        widget_pinned: Boolean(saved.widget_pinned),
      });
    },
    [],
  );

  const loadEvents = useCallback(async () => {
    setEventsLoading(true);
    try {
      const data = await fetchJson<EventResponse>(
        `${API_BASE_URL}/api/events/today?provider=${provider}&max_results=50`,
      );
      setEventsData(data);
    } finally {
      setEventsLoading(false);
    }
  }, [provider]);

  const loadBriefing = useCallback(async () => {
    if (!settings.briefing_enabled) {
      setBriefingData({
        provider,
        generated_at: new Date().toISOString(),
        briefing: "",
        event_count: 0,
        disabled: true,
      });
      return;
    }
    setBriefingLoading(true);
    try {
      const data = await fetchJson<BriefingResponse>(
        `${API_BASE_URL}/api/briefing/today?provider=${provider}&max_results=50&force=true`,
      );
      setBriefingData(data);
    } finally {
      setBriefingLoading(false);
    }
  }, [provider, settings.briefing_enabled]);

  const loadColorState = useCallback(async () => {
    setSchemaLoading(true);
    try {
      const paletteData = await fetchJson<{ palette: string[] }>(
        `${API_BASE_URL}/api/colors/palette?provider=${provider}`,
      );
      setPalette(paletteData.palette ?? []);

      const schemaData = await fetchJson<{ rules: ColorRule[] }>(
        `${API_BASE_URL}/api/colors/schema?provider=${provider}`,
      );
      setSchemaRuleCount((schemaData.rules ?? []).length);
    } finally {
      setSchemaLoading(false);
    }
  }, [provider]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      setClockNow(new Date());
    }, 100);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    const run = async () => {
      setMessage("");
      try {
        await Promise.all([loadSettings(), loadEvents(), loadColorState()]);
      } catch (error) {
        const text = error instanceof Error ? error.message : "Unknown error";
        setMessage(text);
      }
    };
    void run();
  }, [loadColorState, loadEvents, loadSettings]);

  useEffect(() => {
    void loadBriefing();
  }, [loadBriefing]);

  useEffect(() => {
    if (!clockRef.current) {
      return;
    }
    drawClock(
      clockRef.current,
      eventsData?.events ?? [],
      clockNow,
      settings.theme,
      settings.event_opacity,
    );
  }, [clockNow, eventsData?.events, settings.event_opacity, settings.theme]);

  const onSpeakBriefing = async () => {
    if (!settings.briefing_tts_enabled) {
      setMessage("Briefing TTS가 비활성화되어 있습니다.");
      return;
    }
    if (!briefingData?.briefing?.trim()) {
      setMessage("브리핑 텍스트가 없습니다.");
      return;
    }

    setMessage("");
    try {
      const response = await fetch(`${API_BASE_URL}/api/briefing/tts`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ text: briefingData.briefing, response_format: "wav" }),
      });
      if (!response.ok) {
        throw new Error(`TTS failed (${response.status})`);
      }

      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      audio.onended = () => URL.revokeObjectURL(url);
      await audio.play();
    } catch (error) {
      const text = error instanceof Error ? error.message : "Unknown error";
      setMessage(text);
    }
  };

  const onParseNatural = async (event: FormEvent) => {
    event.preventDefault();
    if (!naturalText.trim()) {
      setMessage("자연어 입력 문장을 작성해주세요.");
      return;
    }

    setNaturalLoading(true);
    setMessage("");
    try {
      const data = await fetchJson<{ ready: boolean; reason?: string; result: NaturalParseResult | null }>(
        `${API_BASE_URL}/api/events/natural-input/parse?provider=${provider}`,
        {
          method: "POST",
          body: JSON.stringify({ text: naturalText }),
        },
      );

      if (!data.ready) {
        throw new Error(data.reason || "AI natural input is not ready.");
      }
      setNaturalResult(data.result);
    } catch (error) {
      setNaturalResult(null);
      const text = error instanceof Error ? error.message : "Unknown error";
      setMessage(text);
    } finally {
      setNaturalLoading(false);
    }
  };

  const onCreateFromNatural = async () => {
    if (!naturalText.trim()) {
      setMessage("먼저 자연어 문장을 입력하세요.");
      return;
    }

    setNaturalLoading(true);
    setMessage("");
    try {
      const data = await fetchJson<{ created: WebEvent | null; parsed: NaturalParseResult }>(
        `${API_BASE_URL}/api/events/natural-input/create?provider=${provider}`,
        {
          method: "POST",
          body: JSON.stringify({ text: naturalText }),
        },
      );

      setNaturalResult(data.parsed);
      if (data.created) {
        setMessage(`일정이 생성되었습니다: ${data.created.summary}`);
        await Promise.all([loadEvents(), loadBriefing()]);
      } else {
        setMessage("파싱은 되었지만 생성 조건을 만족하지 않아 이벤트를 만들지 못했습니다.");
      }
    } catch (error) {
      const text = error instanceof Error ? error.message : "Unknown error";
      setMessage(text);
    } finally {
      setNaturalLoading(false);
    }
  };

  const onAuthenticateProvider = async () => {
    setMessage("");
    try {
      await fetchJson(`${API_BASE_URL}/api/providers/authenticate?provider=${provider}`, {
        method: "POST",
      });
      await Promise.all([loadEvents(), loadBriefing()]);
      setMessage(`${provider} 인증을 완료했습니다.`);
    } catch (error) {
      const text = error instanceof Error ? error.message : "Unknown error";
      setMessage(text);
    }
  };

  const onLogoutProvider = async () => {
    setMessage("");
    try {
      await fetchJson(`${API_BASE_URL}/api/providers/logout?provider=${provider}`, {
        method: "POST",
      });
      setEventsData(null);
      setBriefingData(null);
      setMessage(`${provider} 로그아웃 완료`);
    } catch (error) {
      const text = error instanceof Error ? error.message : "Unknown error";
      setMessage(text);
    }
  };

  const onSaveAppleCredentials = async () => {
    if (!appleId.trim() || !applePassword.trim()) {
      setMessage("Apple ID와 App Password를 입력해주세요.");
      return;
    }

    setMessage("");
    try {
      await fetchJson(`${API_BASE_URL}/api/providers/apple/credentials`, {
        method: "POST",
        body: JSON.stringify({
          apple_id: appleId,
          app_password: applePassword,
        }),
      });
      setMessage("Apple 인증 정보 저장 및 인증 완료");
      setApplePassword("");
      await Promise.all([loadEvents(), loadBriefing()]);
    } catch (error) {
      const text = error instanceof Error ? error.message : "Unknown error";
      setMessage(text);
    }
  };

  const updateSetting = async <K extends keyof WebSettings>(key: K, value: WebSettings[K]) => {
    const next = { ...settings, [key]: value };
    setSettings(next);
    try {
      await saveSettings(next);
      if (key === "briefing_enabled") {
        await loadBriefing();
      }
    } catch (error) {
      const text = error instanceof Error ? error.message : "Unknown error";
      setMessage(text);
      await loadSettings();
    }
  };

  const handleClockMouseMove = (event: ReactMouseEvent<HTMLDivElement>) => {
    const container = event.currentTarget;
    const rect = container.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    const hovered = detectHoveredEvent(eventsData?.events ?? [], x, y, CLOCK_SIZE, clockNow);
    if (!hovered) {
      setHoverInfo(null);
      return;
    }
    setHoverInfo({ event: hovered, x, y });
  };

  const handleClockMouseLeave = () => {
    setHoverInfo(null);
  };

  const rootClass = settings.theme === "light" ? "theme-light" : "theme-dark";
  const previewEvents = useMemo(() => (eventsData?.events ?? []).slice(0, 4), [eventsData?.events]);

  return (
    <div className={`page-shell ${rootClass}`}>
      <div className="page-backdrop" />
      <main className="clock-shell">
        <section className={`panel clock-main-panel ${settings.widget_pinned ? "pinned" : ""}`}>
          <div className="hero-header">
            <p className="eyebrow">Clock Widget Web Full Service</p>
            <h1>실시간 시계를 중심으로 일정과 AI 기능을 한 화면에서 관리</h1>
          </div>
          {message ? <p className="notice">{message}</p> : null}

          <header className="panel-head clock-main-head">
            <h2>Analog Clock</h2>
            <small>{clockNow.toLocaleTimeString("ko-KR")}</small>
          </header>

          <div className="clock-wrapper" onMouseMove={handleClockMouseMove} onMouseLeave={handleClockMouseLeave}>
            <canvas ref={clockRef} width={CLOCK_SIZE} height={CLOCK_SIZE} className="clock-canvas" />
            {hoverInfo ? (
              <div
                className="event-tooltip"
                style={{
                  left: `${Math.min(CLOCK_SIZE - 210, hoverInfo.x + 12)}px`,
                  top: `${Math.min(CLOCK_SIZE - 90, hoverInfo.y + 12)}px`,
                }}
              >
                <strong>{hoverInfo.event.summary}</strong>
                <span>{formatEventRange(hoverInfo.event)}</span>
              </div>
            ) : null}
          </div>

          <div className="clock-meta-grid">
            <article className="briefing-card">
              <header className="panel-head">
                <h2>Today Briefing</h2>
                <button
                  onClick={() => void onSpeakBriefing()}
                  disabled={!settings.briefing_tts_enabled || !briefingData?.briefing}
                >
                  Speak Briefing
                </button>
              </header>
              {briefingData?.disabled ? (
                <p>브리핑이 비활성화되어 있습니다. 사이드바에서 Today Briefing을 켜주세요.</p>
              ) : briefingData ? (
                <>
                  <p>{briefingData.briefing || "표시할 브리핑이 없습니다."}</p>
                  <small>
                    events: {briefingData.event_count} · generated: {formatDateTime(briefingData.generated_at)}
                  </small>
                </>
              ) : (
                <p>브리핑 데이터를 로딩 중입니다.</p>
              )}
            </article>

            <article className="briefing-card">
              <header className="panel-head">
                <h2>Upcoming Snapshot</h2>
                <small>{eventsData?.count ?? 0} events</small>
              </header>
              <div className="snapshot-list">
                {previewEvents.map((event) => (
                  <div className="snapshot-item" key={event.id}>
                    <span className="color-dot" style={{ backgroundColor: event.color_hex || "#64748b" }} />
                    <div>
                      <strong>{event.summary}</strong>
                      <p>{formatEventRange(event)}</p>
                    </div>
                  </div>
                ))}
                {!previewEvents.length ? <p>표시할 일정이 없습니다.</p> : null}
              </div>
            </article>
          </div>
        </section>

        <aside className="sidebar-column">
          <section className="panel sidebar-panel">
            <header className="panel-head">
              <h2>Widget Menu</h2>
              <small>Core Controls</small>
            </header>
            <div className="hero-controls side-controls">
              <label>
                Provider
                <select value={provider} onChange={(e) => setProvider(e.target.value)}>
                  <option value="google">Google</option>
                  <option value="apple">Apple</option>
                </select>
              </label>
              <label>
                Theme
                <select
                  value={settings.theme}
                  onChange={(e: ChangeEvent<HTMLSelectElement>) => {
                    void updateSetting("theme", asThemeName(e.target.value));
                  }}
                >
                  <option value="dark">Dark</option>
                  <option value="light">Light</option>
                </select>
              </label>
              <label>
                Event Opacity
                <input
                  type="range"
                  min={0}
                  max={255}
                  value={settings.event_opacity}
                  onChange={(e) => {
                    void updateSetting("event_opacity", Number(e.target.value));
                  }}
                />
              </label>
              <button onClick={() => void loadEvents()} disabled={eventsLoading}>
                {eventsLoading ? "Loading..." : "Refresh Events"}
              </button>
              <button
                onClick={() => void loadBriefing()}
                disabled={briefingLoading || !settings.briefing_enabled}
              >
                {briefingLoading ? "Loading..." : "Refresh Briefing"}
              </button>
              <button onClick={() => void loadColorState()} disabled={schemaLoading}>
                {schemaLoading ? "Loading..." : "Reload Color Schema"}
              </button>
              <button onClick={() => void onAuthenticateProvider()}>Sync Calendar</button>
              <button onClick={() => void onLogoutProvider()}>Logout</button>
            </div>

            {provider === "apple" ? (
              <div className="apple-auth">
                <label>
                  Apple ID
                  <input
                    type="text"
                    value={appleId}
                    onChange={(e) => setAppleId(e.target.value)}
                    placeholder="apple id email"
                  />
                </label>
                <label>
                  App Password
                  <input
                    type="password"
                    value={applePassword}
                    onChange={(e) => setApplePassword(e.target.value)}
                    placeholder="app specific password"
                  />
                </label>
                <button onClick={() => void onSaveAppleCredentials()}>Save Apple Credentials</button>
              </div>
            ) : null}

            <div className="toggle-row">
              <label>
                <input
                  type="checkbox"
                  checked={settings.briefing_enabled}
                  onChange={(e) => {
                    void updateSetting("briefing_enabled", e.target.checked);
                  }}
                />
                Today Briefing
              </label>
              <label>
                <input
                  type="checkbox"
                  checked={settings.briefing_tts_enabled}
                  onChange={(e) => {
                    void updateSetting("briefing_tts_enabled", e.target.checked);
                  }}
                />
                Briefing TTS
              </label>
              <label>
                <input
                  type="checkbox"
                  checked={settings.widget_pinned}
                  onChange={(e) => {
                    void updateSetting("widget_pinned", e.target.checked);
                  }}
                />
                Widget Pinned
              </label>
            </div>
          </section>

          <section className="panel sidebar-panel">
            <header className="panel-head">
              <h2>Natural Input</h2>
              <div className="row-actions">
                <button onClick={() => void onCreateFromNatural()} disabled={naturalLoading}>
                  Create Event
                </button>
              </div>
            </header>
            <form onSubmit={onParseNatural} className="natural-form">
              <textarea
                placeholder="예: 다음 주 화요일 오후 3시에 민지랑 카페 미팅 잡아줘"
                value={naturalText}
                onChange={(e) => setNaturalText(e.target.value)}
              />
              <button type="submit" disabled={naturalLoading}>
                {naturalLoading ? "Parsing..." : "Parse"}
              </button>
            </form>
            {naturalResult ? (
              <div className="result-box">
                <p>intent: {naturalResult.intent}</p>
                <p>title: {naturalResult.title}</p>
                <p>
                  time: {naturalResult.start_time ?? "-"} ~ {naturalResult.end_time ?? "-"}
                </p>
                <p>all_day: {String(naturalResult.all_day)}</p>
                <p>confidence: {naturalResult.confidence.toFixed(2)}</p>
                {naturalResult.note ? <p>note: {naturalResult.note}</p> : null}
              </div>
            ) : null}
          </section>

          <section className="panel sidebar-panel">
            <header className="panel-head">
              <h2>AI Color Schema</h2>
              <small>{schemaRuleCount} rules</small>
            </header>
            <div className="schema-entry-card">
              <p>
                상세 스키마 편집, 키워드 생성, 전체 이벤트 적용은 전용 설정 페이지에서 진행합니다.
              </p>
              <div className="schema-entry-meta">
                <span>Available colors: {palette.length}</span>
                <span>{hasEventColorSupport ? "Writable" : "Read-only"}</span>
              </div>
              <div className="row-actions">
                <button onClick={() => void loadColorState()} disabled={schemaLoading}>
                  {schemaLoading ? "Loading..." : "Refresh Summary"}
                </button>
                <Link
                  className="button-link"
                  href={`/settings/color-schema?provider=${encodeURIComponent(provider)}`}
                >
                  Open Detail Page
                </Link>
              </div>
            </div>
          </section>

          <section className="panel sidebar-panel">
            <header className="panel-head">
              <h2>Today Events ({eventsData?.count ?? 0})</h2>
            </header>
            <div className="events-grid compact-events">
              {(eventsData?.events ?? []).map((event) => (
                <article className="event-card" key={event.id}>
                  <div className="event-top">
                    <span
                      className="color-dot"
                      style={{ backgroundColor: event.color_hex || "#64748b" }}
                    />
                    <h3>{event.summary}</h3>
                  </div>
                  <p>
                    {formatDateTime(event.start_time)} ~ {formatDateTime(event.end_time)}
                  </p>
                  {event.description ? <p className="muted">{event.description}</p> : null}
                </article>
              ))}
              {!eventsData?.events?.length ? <p>표시할 일정이 없습니다.</p> : null}
            </div>
          </section>
        </aside>
      </main>
    </div>
  );
}
