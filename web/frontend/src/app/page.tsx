"use client";

import { useState, useEffect, useRef, useMemo, useCallback, type ChangeEvent } from "react";
import Link from "next/link";
import "./globals.css";

const API_BASE_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? "http://localhost:8000";

const CLOCK_SIZE = 800; // Large size for sharpness

// ... Types ...
type ThemeName = "dark" | "light";

interface WebSettings {
  theme: ThemeName;
  event_opacity: number;
  briefing_enabled: boolean;
  briefing_tts_enabled: boolean;
  widget_pinned: boolean; // Add this line
}

interface WebEvent {
  id: string;
  summary: string;
  description: string;
  start_time: string;
  end_time: string;
  all_day: boolean;
  color_hex?: string;
}

interface EventResponse {
  provider: string;
  count: number;
  events: WebEvent[];
}

interface BriefingResponse {
  provider: string;
  generated_at: string;
  briefing: string;
  event_count: number;
  disabled?: boolean;
}

interface ColorRule {
  color_hex: string;
  label: string;
  keywords: string[];
}

interface NaturalParseResult {
  intent: string;
  title?: string;
  start_time?: string;
  end_time?: string;
  all_day: boolean;
  confidence: number;
  note?: string;
}

interface NaturalParseResponse {
  provider: string;
  ready: boolean;
  reason?: string;
  result: NaturalParseResult | null;
}

interface NaturalCreateResponse {
  provider: string;
  parsed: NaturalParseResult;
  created: WebEvent | null;
}

interface GoogleAuthUrlResponse {
  provider: string;
  auth_url: string;
  state: string;
}

interface HoverInfo {
  event: WebEvent;
  x: number;
  y: number;
}

const defaultSettings: WebSettings = {
  theme: "dark",
  event_opacity: 150,
  briefing_enabled: true,
  briefing_tts_enabled: true,
  widget_pinned: false,
};

function asThemeName(val: string | undefined | null): ThemeName {
  return val === "light" ? "light" : "dark";
}

async function fetchJson<T>(url: string, init?: RequestInit): Promise<T> {
  const headers = new Headers(init?.headers);
  if (init?.body && !(init.body instanceof FormData) && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  const res = await fetch(url, {
    ...init,
    headers,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API 오류: ${res.status} ${text}`);
  }
  return res.json() as Promise<T>;
}

function parseEventDate(value: string): Date {
  // If it's effectively an outline date (YYYY-MM-DD), let's parse it as local time
  // to avoid timezone offset issues (where it might shift to the previous day)
  if (value.length === 10) {
    return new Date(`${value}T00:00:00`);
  }
  return new Date(value);
}

function formatEventRange(event: WebEvent): string {
  if (event.all_day) {
    return "종일";
  }
  const s = new Date(event.start_time).toLocaleTimeString("ko-KR", {
    hour: "2-digit",
    minute: "2-digit",
  });
  const e = new Date(event.end_time).toLocaleTimeString("ko-KR", {
    hour: "2-digit",
    minute: "2-digit",
  });
  return `${s} - ${e}`;
}

function formatDateTime(isoStr?: string): string {
  if (!isoStr) return "";
  const d = new Date(isoStr);
  return d.toLocaleString("ko-KR", {
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function minutesBetween(start: Date, end: Date): number {
  return Math.max(0, (end.getTime() - start.getTime()) / 60000);
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

  // Enhance clock colors to match the new dark/light palette
  const palette =
    theme === "dark"
      ? {
          face: "rgba(18, 24, 38, 0.4)", // transparent face matching bg-card
          border: "rgba(143, 166, 214, 0.2)",
          tick: "#cbd5e1",
          hand: "#f8fafc",
          number: "#f8fafc",
          second: "#ef4444",
          backdrop: "transparent",
        }
      : {
          face: "rgba(255, 255, 255, 0.6)",
          border: "rgba(148, 163, 184, 0.3)",
          tick: "#334155",
          hand: "#0f172a",
          number: "#0f172a",
          second: "#dc2626",
          backdrop: "transparent",
        };

  context.clearRect(0, 0, size, size);
  context.fillStyle = palette.backdrop;
  context.fillRect(0, 0, size, size);

  context.save();
  context.translate(center, center);

  context.beginPath();
  context.fillStyle = palette.face;
  context.strokeStyle = palette.border;
  context.lineWidth = 1.5;
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

    const startRad = (-startAngle * Math.PI) / 180;
    const endRad = (-(startAngle + spanAngle) * Math.PI) / 180;
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
  const [, setNaturalResult] = useState<NaturalParseResult | null>(null);
  const [naturalLoading, setNaturalLoading] = useState(false);

  const [providerAuthenticated, setProviderAuthenticated] = useState(false);

  const [appleId, setAppleId] = useState("");
  const [applePassword, setApplePassword] = useState("");

  const [palette, setPalette] = useState<string[]>([]);
  const [schemaRules, setSchemaRules] = useState<ColorRule[]>([]);
  const [schemaLoading, setSchemaLoading] = useState(false);
  const [schemaSaving, setSchemaSaving] = useState(false);
  const [openPaletteIndex, setOpenPaletteIndex] = useState<number | null>(null);
  const [hoverInfo, setHoverInfo] = useState<HoverInfo | null>(null);

  const [expandedPanels, setExpandedPanels] = useState<Record<string, boolean>>({
    theme: true,
  });

  const togglePanel = (panel: string) => {
    setExpandedPanels((prev) => ({ ...prev, [panel]: !prev[panel] }));
  };

  const addRule = () => {
    const fallbackColor = palette[0] ?? "#a4bdfc";
    setSchemaRules((prev) => [...prev, { color_hex: fallbackColor, label: "", keywords: [] }]);
  };

  const updateRule = (index: number, updater: (rule: ColorRule) => ColorRule) => {
    setSchemaRules((prev) => prev.map((rule, idx) => (idx === index ? updater(rule) : rule)));
  };

  const removeRule = (index: number) => {
    setSchemaRules((prev) => prev.filter((_, idx) => idx !== index));
    setOpenPaletteIndex((prev) => {
      if (prev === null) return prev;
      if (prev === index) return null;
      if (prev > index) return prev - 1;
      return prev;
    });
  };

  const onSaveSchema = async () => {
    setSchemaSaving(true);
    setMessage("");
    try {
      await fetchJson(`${API_BASE_URL}/api/colors/schema?provider=${provider}`, {
        method: "PUT",
        body: JSON.stringify({ rules: schemaRules }),
      });
      setMessage("색상 스키마를 저장했습니다.");
    } catch (error) {
      const text = error instanceof Error ? error.message : "알 수 없는 오류";
      setMessage(text);
    } finally {
      setSchemaSaving(false);
    }
  };

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

  const loadAuthStatus = useCallback(async () => {
    try {
      const data = await fetchJson<{ authenticated: boolean }>(
        `${API_BASE_URL}/api/providers/status?provider=${provider}`,
      );
      setProviderAuthenticated(data.authenticated);
    } catch {
      setProviderAuthenticated(false);
    }
  }, [provider]);

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
      setSchemaRules(schemaData.rules ?? []);
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
        await loadSettings();
        await loadAuthStatus();
        await loadColorState();
        await loadEvents();
        await loadBriefing();
      } catch (err: unknown) {
        if (err instanceof Error) {
          setMessage(`초기화 실패: ${err.message}`);
        } else {
          setMessage("초기화 실패");
        }
      }
    };
    void run();
  }, [loadSettings, loadAuthStatus, loadColorState, loadEvents, loadBriefing]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      void loadEvents();
    }, 5 * 60 * 1000);
    return () => window.clearInterval(interval);
  }, [loadEvents]);

  useEffect(() => {
    if (!clockRef.current || !eventsData) return;
    const canvas = clockRef.current;
    let animationFrameId: number;
    const renderLoop = () => {
      drawClock(canvas, eventsData.events, new Date(), settings.theme, settings.event_opacity);
      animationFrameId = requestAnimationFrame(renderLoop);
    };
    renderLoop();
    return () => cancelAnimationFrame(animationFrameId);
  }, [eventsData, settings.theme, settings.event_opacity]);

  useEffect(() => {
    const handleOutsideClick = (event: MouseEvent) => {
      const target = event.target as HTMLElement | null;
      if (!target) return;
      if (!target.closest(".color-picker-cell")) {
        setOpenPaletteIndex(null);
      }
    };
    document.addEventListener("mousedown", handleOutsideClick);
    return () => {
      document.removeEventListener("mousedown", handleOutsideClick);
    };
  }, []);

  const updateSetting = async (key: keyof WebSettings, val: number | string | boolean) => {
    setMessage("");
    try {
      if (key === "theme" || key === "briefing_enabled" || key === "briefing_tts_enabled" || key === "widget_pinned") {
        const nextSettings: WebSettings = {
          ...settings,
          [key]: val,
        };
        await saveSettings(nextSettings);
        return;
      }
      if (key === "event_opacity") {
        setSettings((prev) => ({ ...prev, event_opacity: val as number }));
        await saveSettings({ ...settings, event_opacity: val as number });
      }
    } catch (err: unknown) {
      if (err instanceof Error) {
        setMessage(`설정 변경 실패: ${err.message}`);
      }
    }
  };

  const onAuthenticateProvider = async () => {
    setMessage("");
    try {
      if (provider === "google") {
        const data = await fetchJson<GoogleAuthUrlResponse>(
          `${API_BASE_URL}/api/providers/google/auth-url`,
          { method: "POST" },
        );
        const popup = window.open(
          data.auth_url,
          "google-calendar-auth",
          "width=540,height=720,menubar=no,toolbar=no,location=yes,resizable=yes,scrollbars=yes,status=no",
        );
        if (!popup) {
          setMessage("팝업이 차단되었습니다. 브라우저에서 팝업을 허용한 뒤 다시 시도해주세요.");
          return;
        }

        setMessage("Google 인증 창에서 권한을 승인해주세요...");

        const authSuccess = await new Promise<boolean>((resolve) => {
          let done = false;
          let checks = 0;

          const finish = (value: boolean) => {
            if (done) return;
            done = true;
            window.removeEventListener("message", onMessage);
            window.clearInterval(intervalId);
            resolve(value);
          };

          const onMessage = (event: MessageEvent) => {
            const payload = event.data as { source?: string; status?: string } | null;
            if (!payload || payload.source !== "google-oauth") return;
            finish(payload.status === "success");
          };

          window.addEventListener("message", onMessage);

          const intervalId = window.setInterval(async () => {
            checks += 1;
            if (popup.closed) {
              finish(false);
              return;
            }
            if (checks % 2 === 0) {
              try {
                const status = await fetchJson<{ authenticated: boolean }>(
                  `${API_BASE_URL}/api/providers/status?provider=google`,
                );
                if (status.authenticated) {
                  finish(true);
                }
              } catch (pollError) {
                void pollError;
              }
            }
            if (checks >= 120) {
              finish(false);
            }
          }, 1000);
        });

        if (authSuccess) {
          await loadAuthStatus();
          await loadEvents();
          await loadBriefing();
          setMessage("Google 캘린더 인증을 완료했습니다.");
        } else {
          setMessage("Google 인증이 완료되지 않았습니다. 다시 시도해주세요.");
        }
      } else if (provider === "apple") {
        setMessage("아래 Apple ID/앱 비밀번호를 입력해주세요.");
      }
    } catch (err: unknown) {
      if (err instanceof Error) {
        setMessage(`인증 오류: ${err.message}`);
      }
    }
  };

  const onSaveAppleCredentials = async () => {
    setMessage("Apple 인증 정보를 저장하는 중...");
    try {
      await fetchJson(`${API_BASE_URL}/api/providers/apple/credentials`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ apple_id: appleId, app_password: applePassword }),
      });
      setMessage("Apple 인증 정보를 저장했습니다.");
      setAppleId("");
      setApplePassword("");
      setProviderAuthenticated(true);
      await loadEvents();
      await loadBriefing();
    } catch (err: unknown) {
      if (err instanceof Error) {
        setMessage(`저장 실패: ${err.message}`);
      }
    }
  };

  const onLogoutProvider = async () => {
    setMessage("");
    try {
      await fetchJson(`${API_BASE_URL}/api/providers/logout?provider=${provider}`, {
        method: "POST",
      });
      setMessage(`${provider}에서 로그아웃했습니다.`);
      setProviderAuthenticated(false);
      setEventsData(null);
      setBriefingData(null);
    } catch (err: unknown) {
      if (err instanceof Error) {
        setMessage(`로그아웃 실패: ${err.message}`);
      }
    }
  };

  const onSpeakBriefing = async () => {
    if (!briefingData?.briefing) return;
    setMessage("");
    try {
      const res = await fetch(`${API_BASE_URL}/api/briefing/tts`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: briefingData.briefing, response_format: "wav" }),
      });
      if (!res.ok) {
        const raw = await res.text();
        try {
          const parsed = JSON.parse(raw) as { detail?: string };
          throw new Error(parsed.detail || raw);
        } catch {
          throw new Error(raw);
        }
      }
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      audio.onended = () => URL.revokeObjectURL(url);
      void audio.play();
    } catch (err: unknown) {
      if (err instanceof Error) {
        setMessage(`TTS 오류: ${err.message}`);
      }
    }
  };

  const onCreateFromNatural = async () => {
    if (!naturalText.trim()) {
      setMessage("먼저 자연어 문장을 입력해주세요.");
      return;
    }
    setNaturalLoading(true);
    setNaturalResult(null);
    setMessage("");
    try {
      const parsedData = await fetchJson<NaturalParseResponse>(
        `${API_BASE_URL}/api/events/natural-input/parse?provider=${provider}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ text: naturalText }),
        },
      );
      if (!parsedData.ready) {
        setMessage(parsedData.reason || "자연어 입력 기능을 사용할 수 없습니다.");
        return;
      }
      if (!parsedData.result) {
        setMessage("입력 문장에서 일정 정보를 찾지 못했습니다.");
        return;
      }
      setNaturalResult(parsedData.result);

      const data = await fetchJson<NaturalCreateResponse>(
        `${API_BASE_URL}/api/events/natural-input/create?provider=${provider}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ text: naturalText }),
        },
      );
      setNaturalResult(data.parsed);
      if (data.created) {
        setMessage("일정을 생성했습니다.");
        await loadEvents();
        await loadBriefing();
      } else {
        setMessage("일정 생성 조건이 충족되지 않아 생성되지 않았습니다.");
      }
    } catch (err: unknown) {
      if (err instanceof Error) {
        setMessage(`일정 생성 오류: ${err.message}`);
      }
    } finally {
      setNaturalLoading(false);
    }
  };

  const handleClockMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!clockRef.current || !eventsData?.events) return;
    const canvas = clockRef.current;
    const rect = canvas.getBoundingClientRect();

    // Scale coordinates if displayed size != internal resolution
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;

    // Center coordinates
    const x = (e.clientX - rect.left) * scaleX - canvas.width / 2;
    const y = (e.clientY - rect.top) * scaleY - canvas.height / 2;

    const distance = Math.sqrt(x * x + y * y);

    const scale = (canvas.width - 12) / 200;
    const pieRadius = 88 * scale;
    const arcRadius = 94 * scale;
    const clickTolerance = 15;

    let hovered: WebEvent | null = null;
    let minDiff = Infinity;
    const now = new Date();
    const currentIsAm = now.getHours() < 12;

    for (const event of eventsData.events) {
      if (event.all_day) continue;

      const evStart = parseEventDate(event.start_time);
      const evEnd = parseEventDate(event.end_time);

      if (now > evEnd) continue;

      const isInProgress = evStart <= now && now <= evEnd;
      const isCurrentCycle = isInProgress || currentIsAm === (evStart.getHours() < 12);

      let targetRadius = pieRadius;
      if (!isCurrentCycle) {
        targetRadius = arcRadius;
      }
      if (Math.abs(distance - targetRadius) > clickTolerance && !isInProgress) {
        if (!isCurrentCycle) continue;
      }

      let startAngle = 90 - ((evStart.getHours() % 12) + evStart.getMinutes() / 60) * 30;
      let spanAngle = -(Math.min(12 * 60, minutesBetween(evStart, evEnd)) / (12 * 60)) * 360;

      if (isInProgress) {
        startAngle = 90 - ((now.getHours() % 12) + now.getMinutes() / 60 + now.getSeconds() / 3600) * 30;
        const remainingHours = Math.min(12, Math.max(0, (evEnd.getTime() - now.getTime()) / 3600000));
        spanAngle = -(remainingHours * 30);
      }

      const pointAngle = (Math.atan2(-y, x) * 180) / Math.PI;
      let diff = startAngle - pointAngle;
      while (diff < 0) diff += 360;
      while (diff >= 360) diff -= 360;

      const absSpan = Math.abs(spanAngle);

      if (diff <= absSpan && diff < minDiff) {
        minDiff = diff;
        hovered = event;
      }
    }

    if (!hovered) {
      setHoverInfo(null);
      return;
    }
    setHoverInfo({ event: hovered, x: e.clientX - rect.left, y: e.clientY - rect.top });
  };

  const handleClockMouseLeave = () => {
    setHoverInfo(null);
  };

  const rootClass = settings.theme === "light" ? "theme-light" : "theme-dark";

  return (
    <div className={`page-shell ${rootClass}`}>
      <div className="page-backdrop" />
      <main className="clock-shell">
        <div className="main-content-column" style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          <section className={`panel clock-main-panel ${settings.widget_pinned ? "pinned" : ""}`}>
            <div className="hero-header">
              <p className="eyebrow">Smart Analog</p>
              <h1>하루 일정을 시계 위에서 직관적으로 확인하세요.</h1>
            </div>
            {message && <p className="notice">{message}</p>}

            <header className="panel-head clock-main-head">
              <small>{clockNow.toLocaleTimeString("ko-KR")}</small>
            </header>

            <div className="clock-wrapper" onMouseMove={handleClockMouseMove} onMouseLeave={handleClockMouseLeave}>
              <canvas ref={clockRef} width={CLOCK_SIZE} height={CLOCK_SIZE} className="clock-canvas" />
              {hoverInfo && (
                <div
                  className="event-tooltip"
                  style={{
                    left: `${Math.min(CLOCK_SIZE - 210, hoverInfo.x + 12)}px`,
                    top: `${Math.min(CLOCK_SIZE - 90, hoverInfo.y + 12)}px`,
                  }}
                >
                  <div className="event-tooltip-title-row">
                    <span className="color-dot" style={{ backgroundColor: hoverInfo.event.color_hex || "#64748b" }} />
                    <strong>{hoverInfo.event.summary}</strong>
                  </div>
                  <span>{formatEventRange(hoverInfo.event)}</span>
                </div>
              )}
            </div>
          </section>

          <div className="clock-meta-grid" style={{ marginTop: '0' }}>
            <section className="panel briefing-panel" style={{ flex: 1 }}>
              <header className="panel-head">
                <h2>오늘의 브리핑</h2>
                <button
                  onClick={() => void onSpeakBriefing()}
                  disabled={!settings.briefing_tts_enabled || !briefingData?.briefing}
                >
                  {settings.briefing_tts_enabled ? "읽어주기" : "TTS 꺼짐"}
                </button>
              </header>
              
              <div className="panel-content">
                {briefingData?.disabled ? (
                  <p>브리핑이 비활성화되어 있습니다. 사이드바에서 켜주세요.</p>
                ) : briefingData ? (
                  <>
                    <p>{briefingData.briefing || "표시할 브리핑이 없습니다."}</p>
                    <small style={{ color: "var(--muted)", marginTop: "8px", display: "inline-block" }}>
                      일정: {briefingData.event_count} · 생성: {formatDateTime(briefingData.generated_at)}
                    </small>
                  </>
                ) : (
                  <p>브리핑 데이터를 불러오는 중...</p>
                )}
              </div>
            </section>

          </div>
        </div>

        <aside className="sidebar-column">
          <section className="panel sidebar-panel">
            <header className="panel-head" onClick={() => togglePanel('controls')} style={{ cursor: 'pointer', userSelect: 'none' }}>
              <div>
                <h2>설정</h2>
              </div>
              <span className={`chevron ${expandedPanels['controls'] ? 'expanded' : ''}`} style={{ color: 'var(--muted)', fontSize: '0.9rem' }}>
                ▼
              </span>
            </header>
            <div className={`collapsible-wrapper ${expandedPanels['controls'] ? 'expanded' : ''}`}>
              <div className="collapsible-inner">
                <div className="panel-content-wrapper" style={{ marginTop: '16px' }}>
                <div className="hero-controls side-controls">
              <label>
                캘린더 제공자
                <select value={provider} onChange={(e) => setProvider(e.target.value)}>
                  <option value="google">Google 캘린더</option>
                  <option value="apple">Apple 캘린더</option>
                </select>
              </label>
              <label>
                테마
                <select
                  value={settings.theme}
                  onChange={(e: ChangeEvent<HTMLSelectElement>) => {
                    void updateSetting("theme", asThemeName(e.target.value));
                  }}
                >
                  <option value="dark">다크 모드</option>
                  <option value="light">라이트 모드</option>
                </select>
              </label>
              <label>
                일정 투명도 ({settings.event_opacity})
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

              <button
                onClick={() => void loadBriefing()}
                disabled={briefingLoading || !settings.briefing_enabled}
              >
                {briefingLoading ? "생성 중..." : "브리핑 생성"}
              </button>
              <button onClick={() => void loadColorState()} disabled={schemaLoading}>
                {schemaLoading ? "동기화 중..." : "색상 스키마 동기화"}
              </button>
              {providerAuthenticated ? (
                <button onClick={() => void onLogoutProvider()}>계정 연결 해제</button>
              ) : (
                <button onClick={() => void onAuthenticateProvider()}>캘린더 인증</button>
              )}
            </div>

            {provider === "apple" && !providerAuthenticated ? (
              <div className="apple-auth">
                <label>
                  Apple ID
                  <input
                    type="text"
                    value={appleId}
                    onChange={(e) => setAppleId(e.target.value)}
                    placeholder="이메일(@icloud.com)"
                  />
                </label>
                <label>
                  앱 전용 비밀번호
                  <input
                    type="password"
                    value={applePassword}
                    onChange={(e) => setApplePassword(e.target.value)}
                    placeholder="xxxx-xxxx-xxxx-xxxx"
                  />
                </label>
                <button onClick={() => void onSaveAppleCredentials()}>자격증명 저장</button>
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
                AI 브리핑 사용
              </label>
              <label>
                <input
                  type="checkbox"
                  checked={settings.briefing_tts_enabled}
                  onChange={(e) => {
                    void updateSetting("briefing_tts_enabled", e.target.checked);
                  }}
                />
                음성 읽기(TTS) 사용
              </label>
              <label>
                <input
                  type="checkbox"
                  checked={settings.widget_pinned}
                  onChange={(e) => {
                    void updateSetting("widget_pinned", e.target.checked);
                  }}
                />
                위젯 고정
              </label>
            </div>
                </div>
              </div>
            </div>
          </section>

          <section className="panel sidebar-panel">
            <header className="panel-head" onClick={() => togglePanel('natural')} style={{ cursor: 'pointer', userSelect: 'none' }}>
              <div>
                <h2>일정 추가하기</h2>
              </div>
              <span className={`chevron ${expandedPanels['natural'] ? 'expanded' : ''}`} style={{ color: 'var(--muted)', fontSize: '0.9rem' }}>
                ▼
              </span>
            </header>
            <div className={`collapsible-wrapper ${expandedPanels['natural'] ? 'expanded' : ''}`}>
              <div className="collapsible-inner">
                <div className="panel-content-wrapper" style={{ marginTop: '16px' }}>
                <form
                  onSubmit={(e) => {
                    e.preventDefault();
                    void onCreateFromNatural();
                  }}
                  className="natural-form"
                >
              <textarea
                placeholder="예: 다음 주 화요일 오후 3시에 친구랑 커피 약속 잡아줘"
                value={naturalText}
                onChange={(e) => setNaturalText(e.target.value)}
              />
              <button type="submit" disabled={naturalLoading}>
                {naturalLoading ? "생성 중..." : "일정 생성"}
              </button>
            </form>
                </div>
              </div>
            </div>
          </section>

          <section className="panel sidebar-panel">
            <header className="panel-head" onClick={() => togglePanel('theme')} style={{ cursor: 'pointer', userSelect: 'none' }}>
              <div>
                <h2>일정 색상 설정</h2>
              </div>
              <span className={`chevron ${expandedPanels['theme'] ? 'expanded' : ''}`} style={{ color: 'var(--muted)', fontSize: '0.9rem' }}>
                ▼
              </span>
            </header>
            <div className={`collapsible-wrapper ${expandedPanels['theme'] ? 'expanded' : ''}`}>
              <div className="collapsible-inner">
                <div className="panel-content-wrapper" style={{ marginTop: '16px' }}>
                <div className="schema-entry-card" style={{ padding: '0', border: 'none', background: 'transparent', boxShadow: 'none' }}>
                  <div className="row-actions" style={{ marginBottom: '12px' }}>
                    <button onClick={addRule} disabled={schemaLoading || schemaSaving || !hasEventColorSupport}>
                      규칙 추가
                    </button>
                    <button onClick={() => void onSaveSchema()} disabled={schemaLoading || schemaSaving}>
                      {schemaSaving ? "저장 중..." : "저장"}
                    </button>
                  </div>
                  <div className="schema-list" style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                    {schemaRules.map((rule, index) => (
                      <div className="schema-item" key={`${rule.color_hex}-${index}`} style={{ display: 'grid', gridTemplateColumns: 'auto 1fr auto', gap: '8px', alignItems: 'center', background: 'var(--bg-card)', padding: '8px', borderRadius: '8px', border: '1px solid var(--border)' }}>
                        <div className="color-picker-cell" style={{ position: 'relative' }}>
                          <button
                            type="button"
                            className="color-trigger"
                            style={{ width: '24px', height: '24px', minWidth: '24px' }}
                            onClick={() => setOpenPaletteIndex(prev => prev === index ? null : index)}
                          >
                            <span className="color-preview" style={{ width: '16px', height: '16px', backgroundColor: rule.color_hex || "#64748b" }} />
                          </button>
                          {openPaletteIndex === index && (
                            <div className="color-choice-grid" style={{ zIndex: 100, width: 'max-content', maxWidth: '200px' }}>
                              {palette.map((color) => (
                                <button
                                  key={`${index}-${color}`}
                                  type="button"
                                  className={`color-choice ${color === rule.color_hex ? "selected" : ""}`}
                                  style={{ backgroundColor: color }}
                                  onClick={() => { updateRule(index, (p) => ({ ...p, color_hex: color })); setOpenPaletteIndex(null); }}
                                />
                              ))}
                            </div>
                          )}
                        </div>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                          <input
                            style={{ fontSize: '0.8rem', padding: '4px 8px' }}
                            value={rule.label}
                            placeholder="라벨"
                            onChange={(e) => updateRule(index, (p) => ({ ...p, label: e.target.value }))}
                          />
                          <input
                            style={{ fontSize: '0.8rem', padding: '4px 8px' }}
                            value={rule.keywords.join(", ")}
                            placeholder="키워드1, 키워드2"
                            onChange={(e) => updateRule(index, (p) => ({
                              ...p,
                              keywords: e.target.value.split(",").map(k => k.trim().toLowerCase()).filter(Boolean)
                            }))}
                          />
                        </div>
                        <button
                          type="button"
                          className="schema-remove-btn"
                          style={{ width: '24px', height: '24px', minWidth: '24px', fontSize: '14px' }}
                          onClick={() => removeRule(index)}
                        >
                          ×
                        </button>
                      </div>
                    ))}
                    {!schemaRules.length && <p style={{ fontSize: '0.85rem', color: 'var(--muted)' }}>규칙이 없습니다.</p>}
                  </div>
                </div>
                </div>
              </div>
            </div>
          </section>

        </aside>
      </main>
    </div>
  );
}
