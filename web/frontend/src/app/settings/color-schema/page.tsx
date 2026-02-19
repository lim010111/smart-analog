"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_BACKEND_URL ?? process.env.BACKEND_URL ?? "http://localhost:8000";
const REQUEST_TIMEOUT_MS = 15000;

type ColorRule = {
  color_hex: string;
  label: string;
  keywords: string[];
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

export default function ColorSchemaSettingsPage() {
  const [provider, setProvider] = useState("google");
  const [palette, setPalette] = useState<string[]>([]);
  const [schemaRules, setSchemaRules] = useState<ColorRule[]>([]);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [openPaletteIndex, setOpenPaletteIndex] = useState<number | null>(null);

  const hasEventColorSupport = useMemo(() => palette.length > 0, [palette.length]);

  const loadColorState = useCallback(async () => {
    setLoading(true);
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
      setLoading(false);
    }
  }, [provider]);

  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }
    const params = new URLSearchParams(window.location.search);
    const fromQuery = params.get("provider") === "apple" ? "apple" : "google";
    setProvider(fromQuery);
  }, []);

  useEffect(() => {
    void loadColorState();
  }, [loadColorState]);

  useEffect(() => {
    const handleOutsideClick = (event: MouseEvent) => {
      const target = event.target as HTMLElement | null;
      if (!target) {
        return;
      }
      if (!target.closest(".color-picker-cell")) {
        setOpenPaletteIndex(null);
      }
    };

    document.addEventListener("mousedown", handleOutsideClick);
    return () => {
      document.removeEventListener("mousedown", handleOutsideClick);
    };
  }, []);

  const onSaveSchema = async () => {
    setLoading(true);
    setMessage("");
    try {
      await fetchJson(`${API_BASE_URL}/api/colors/schema?provider=${provider}`, {
        method: "PUT",
        body: JSON.stringify({ rules: schemaRules }),
      });
      setMessage("색상 스키마를 저장했습니다.");
    } catch (error) {
      const text = error instanceof Error ? error.message : "Unknown error";
      setMessage(text);
    } finally {
      setLoading(false);
    }
  };

  const onApplyAllColors = async () => {
    setLoading(true);
    setMessage("");
    try {
      const result = await fetchJson<{ processed: number; updated: number }>(
        `${API_BASE_URL}/api/colors/apply-all?provider=${provider}`,
        { method: "POST" },
      );
      setMessage(`AI 색상 적용 완료: 처리 ${result.processed}, 업데이트 ${result.updated}`);
    } catch (error) {
      const text = error instanceof Error ? error.message : "Unknown error";
      setMessage(text);
    } finally {
      setLoading(false);
    }
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
      if (prev === null) {
        return prev;
      }
      if (prev === index) {
        return null;
      }
      if (prev > index) {
        return prev - 1;
      }
      return prev;
    });
  };

  const onProviderChange = (nextProvider: string) => {
    const normalized = nextProvider === "apple" ? "apple" : "google";
    setProvider(normalized);
    if (typeof window !== "undefined") {
      window.history.replaceState(null, "", `/settings/color-schema?provider=${normalized}`);
    }
  };

  return (
    <div className="page-shell theme-dark">
      <div className="page-backdrop" />
      <main className="settings-shell">
        <section className="panel settings-panel">
          <header className="panel-head">
            <h2>AI Color Schema Settings</h2>
            <Link className="button-link" href="/">
              Back to Clock
            </Link>
          </header>

          <div className="settings-toolbar">
            <label>
              Provider
              <select value={provider} onChange={(e) => onProviderChange(e.target.value)}>
                <option value="google">Google</option>
                <option value="apple">Apple</option>
              </select>
            </label>
            <button onClick={() => void loadColorState()} disabled={loading}>
              {loading ? "Loading..." : "Reload"}
            </button>
            <button onClick={addRule} disabled={loading || !hasEventColorSupport}>
              Add Rule
            </button>
            <button onClick={() => void onSaveSchema()} disabled={loading}>
              Save Schema
            </button>
            <button onClick={() => void onApplyAllColors()} disabled={loading || !hasEventColorSupport}>
              Apply to All Events
            </button>
          </div>

          <p className="settings-hint">
            Palette colors: {palette.length} · Rules: {schemaRules.length}
          </p>
          {message ? <p className="notice">{message}</p> : null}

          <div className="schema-list">
            {schemaRules.map((rule, index) => (
              <div className="schema-item" key={`${rule.color_hex}-${index}`}>
                <div className="color-picker-cell">
                  <button
                    type="button"
                    className="color-trigger"
                    onClick={() =>
                      setOpenPaletteIndex((prev) => (prev === index ? null : index))
                    }
                    aria-expanded={openPaletteIndex === index}
                    aria-label="Open color palette"
                  >
                    <span
                      className="color-preview"
                      style={{ backgroundColor: rule.color_hex || "#64748b" }}
                      title={rule.color_hex}
                    />
                  </button>
                  {openPaletteIndex === index ? (
                    <div className="color-choice-grid">
                      {palette.map((color) => {
                        const selected = color === rule.color_hex;
                        return (
                          <button
                            key={`${index}-${color}`}
                            type="button"
                            className={`color-choice ${selected ? "selected" : ""}`}
                            style={{ backgroundColor: color }}
                            aria-label={`Select ${color}`}
                            title={color}
                            onClick={() => {
                              updateRule(index, (prev) => ({ ...prev, color_hex: color }));
                              setOpenPaletteIndex(null);
                            }}
                          />
                        );
                      })}
                    </div>
                  ) : null}
                </div>
                <input
                  className="schema-label-input"
                  value={rule.label}
                  placeholder="Category label"
                  onChange={(e) =>
                    updateRule(index, (prev) => ({ ...prev, label: e.target.value }))
                  }
                />
                <input
                  className="schema-keyword-input"
                  value={rule.keywords.join(", ")}
                  placeholder="keyword1, keyword2"
                  onChange={(e) =>
                    updateRule(index, (prev) => ({
                      ...prev,
                      keywords: e.target.value
                        .split(",")
                        .map((kw) => kw.trim().toLowerCase())
                        .filter(Boolean),
                    }))
                  }
                />
                <button
                  type="button"
                  className="schema-remove-btn"
                  onClick={() => removeRule(index)}
                  aria-label="Remove rule"
                  title="Remove"
                >
                  ×
                </button>
              </div>
            ))}
            {!schemaRules.length ? <p>아직 저장된 색상 규칙이 없습니다.</p> : null}
          </div>
        </section>
      </main>
    </div>
  );
}
