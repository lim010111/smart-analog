"use client";

import Link from "next/link";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type DragEvent,
} from "react";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_BACKEND_URL ?? process.env.BACKEND_URL ?? "http://localhost:8000";
const REQUEST_TIMEOUT_MS = 15000;

type ColorRule = {
  color_hex: string;
  label: string;
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
      throw new Error("요청 시간이 초과되었습니다. 캘린더 인증 후 다시 시도해주세요.");
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
  const [syncing, setSyncing] = useState(false);
  const [message, setMessage] = useState("");
  const [openPaletteIndex, setOpenPaletteIndex] = useState<number | null>(null);
  const [schemaVisualOrder, setSchemaVisualOrder] = useState<number[]>([]);
  const [draggingSchemaVisualIndex, setDraggingSchemaVisualIndex] = useState<number | null>(null);
  const [dragOverSchemaVisualIndex, setDragOverSchemaVisualIndex] = useState<number | null>(null);
  const [dragOverSchemaDropPosition, setDragOverSchemaDropPosition] = useState<"before" | "after">("before");
  const [recentlyMovedSchemaRuleIndex, setRecentlyMovedSchemaRuleIndex] = useState<number | null>(null);
  const syncTimerRef = useRef<number | null>(null);
  const schemaReorderTimerRef = useRef<number | null>(null);
  const schemaItemRefs = useRef<Map<number, HTMLDivElement>>(new Map());
  const previousSchemaItemTopsRef = useRef<Map<number, number>>(new Map());
  const schemaFlipResetTimersRef = useRef<Map<number, number>>(new Map());
  const lastSyncedRulesRef = useRef<string>("[]");

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
      const rules = schemaData.rules ?? [];
      setSchemaRules(rules);
      setSchemaVisualOrder(Array.from({ length: rules.length }, (_, idx) => idx));
      lastSyncedRulesRef.current = JSON.stringify(rules);
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

  const syncSchemaRules = useCallback(
    async (nextRules: ColorRule[]) => {
      const serialized = JSON.stringify(nextRules);
      if (serialized === lastSyncedRulesRef.current) {
        return;
      }
      setSyncing(true);
      setMessage("");
      try {
        await fetchJson(`${API_BASE_URL}/api/colors/schema?provider=${provider}`, {
          method: "PUT",
          body: JSON.stringify({ rules: nextRules }),
        });
        await fetchJson<{
          processed: number;
          updated: number;
          processed_today?: number;
          updated_today?: number;
          background_started?: boolean;
          background_queued?: boolean;
        }>(
          `${API_BASE_URL}/api/colors/apply-all?provider=${provider}`,
          { method: "POST" },
        );
        lastSyncedRulesRef.current = serialized;
      } catch (error) {
        const text = error instanceof Error ? error.message : "알 수 없는 오류";
        setMessage(text);
      } finally {
        setSyncing(false);
      }
    },
    [provider],
  );

  const queueSchemaSync = useCallback(
    (nextRules: ColorRule[]) => {
      if (syncTimerRef.current !== null) {
        window.clearTimeout(syncTimerRef.current);
      }
      syncTimerRef.current = window.setTimeout(() => {
        syncTimerRef.current = null;
        void syncSchemaRules(nextRules);
      }, 450);
    },
    [syncSchemaRules],
  );

  const addRule = () => {
    const fallbackColor = palette[0] ?? "#a4bdfc";
    setSchemaRules((prev) => {
      const nextIndex = prev.length;
      const next = [...prev, { color_hex: fallbackColor, label: "새 규칙" }];
      setSchemaVisualOrder((prevOrder) => {
        if (prevOrder.length === nextIndex) {
          return [...prevOrder, nextIndex];
        }
        return [...Array.from({ length: nextIndex }, (_, idx) => idx), nextIndex];
      });
      queueSchemaSync(next);
      return next;
    });
  };

  const updateRule = (index: number, updater: (rule: ColorRule) => ColorRule) => {
    setSchemaRules((prev) => {
      const next = prev.map((rule, idx) => (idx === index ? updater(rule) : rule));
      queueSchemaSync(next);
      return next;
    });
  };

  const removeRule = (index: number) => {
    setSchemaRules((prev) => {
      const next = prev.filter((_, idx) => idx !== index);
      queueSchemaSync(next);
      return next;
    });
    setSchemaVisualOrder((prevOrder) =>
      prevOrder
        .filter((idx) => idx !== index)
        .map((idx) => (idx > index ? idx - 1 : idx)),
    );
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

  const orderedSchemaIndexes = useMemo(() => {
    if (schemaVisualOrder.length !== schemaRules.length) {
      return Array.from({ length: schemaRules.length }, (_, idx) => idx);
    }

    const used = new Set<number>();
    const normalized: number[] = [];
    for (const idx of schemaVisualOrder) {
      if (idx >= 0 && idx < schemaRules.length && !used.has(idx)) {
        used.add(idx);
        normalized.push(idx);
      }
    }
    for (let idx = 0; idx < schemaRules.length; idx += 1) {
      if (!used.has(idx)) {
        normalized.push(idx);
      }
    }
    return normalized;
  }, [schemaRules.length, schemaVisualOrder]);

  const moveSchemaVisualItem = (
    fromVisualIndex: number,
    toVisualIndex: number,
    dropPosition: "before" | "after",
  ) => {
    const baseOrder = [...orderedSchemaIndexes];
    if (
      fromVisualIndex < 0 ||
      toVisualIndex < 0 ||
      fromVisualIndex >= baseOrder.length ||
      toVisualIndex >= baseOrder.length
    ) {
      return;
    }

    let targetInsertIndex = dropPosition === "before" ? toVisualIndex : toVisualIndex + 1;
    if (fromVisualIndex < targetInsertIndex) {
      targetInsertIndex -= 1;
    }
    if (targetInsertIndex === fromVisualIndex) {
      return;
    }

    const [movedRuleIndex] = baseOrder.splice(fromVisualIndex, 1);
    baseOrder.splice(targetInsertIndex, 0, movedRuleIndex);
    setSchemaVisualOrder(baseOrder);
    setRecentlyMovedSchemaRuleIndex(movedRuleIndex);

    if (schemaReorderTimerRef.current !== null) {
      window.clearTimeout(schemaReorderTimerRef.current);
    }
    schemaReorderTimerRef.current = window.setTimeout(() => {
      setRecentlyMovedSchemaRuleIndex(null);
      schemaReorderTimerRef.current = null;
    }, 280);
  };

  const onSchemaDragStart = (visualIndex: number, event: DragEvent<HTMLElement>) => {
    setDraggingSchemaVisualIndex(visualIndex);
    setDragOverSchemaVisualIndex(visualIndex);
    setDragOverSchemaDropPosition("before");
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", String(visualIndex));
  };

  const onSchemaDragOver = (visualIndex: number, event: DragEvent<HTMLElement>) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
    const rect = event.currentTarget.getBoundingClientRect();
    const nextPosition = event.clientY < rect.top + rect.height / 2 ? "before" : "after";
    if (dragOverSchemaVisualIndex !== visualIndex) {
      setDragOverSchemaVisualIndex(visualIndex);
    }
    if (dragOverSchemaDropPosition !== nextPosition) {
      setDragOverSchemaDropPosition(nextPosition);
    }
  };

  const onSchemaDrop = (visualIndex: number, event: DragEvent<HTMLElement>) => {
    event.preventDefault();
    const rawIndex = event.dataTransfer.getData("text/plain");
    const parsedIndex = Number(rawIndex);
    const fromVisualIndex = Number.isInteger(parsedIndex)
      ? parsedIndex
      : draggingSchemaVisualIndex;
    if (fromVisualIndex !== null) {
      moveSchemaVisualItem(fromVisualIndex, visualIndex, dragOverSchemaDropPosition);
    }
    setDraggingSchemaVisualIndex(null);
    setDragOverSchemaVisualIndex(null);
    setDragOverSchemaDropPosition("before");
  };

  const onSchemaDragEnd = () => {
    setDraggingSchemaVisualIndex(null);
    setDragOverSchemaVisualIndex(null);
    setDragOverSchemaDropPosition("before");
  };

  const setSchemaItemRef = (ruleIndex: number) => (element: HTMLDivElement | null) => {
    if (element) {
      schemaItemRefs.current.set(ruleIndex, element);
      return;
    }
    schemaItemRefs.current.delete(ruleIndex);
  };

  useLayoutEffect(() => {
    const nextTops = new Map<number, number>();
    const computeFlipDurationMs = (distancePx: number) => {
      const absDistance = Math.abs(distancePx);
      return Math.min(420, Math.max(140, Math.round(130 + absDistance * 0.9)));
    };
    const draggingRuleIndex =
      draggingSchemaVisualIndex !== null
        ? orderedSchemaIndexes[draggingSchemaVisualIndex] ?? null
        : null;

    for (const ruleIndex of orderedSchemaIndexes) {
      const node = schemaItemRefs.current.get(ruleIndex);
      if (!node) {
        continue;
      }

      const rect = node.getBoundingClientRect();
      nextTops.set(ruleIndex, rect.top);

      if (draggingRuleIndex === ruleIndex) {
        continue;
      }

      const prevTop = previousSchemaItemTopsRef.current.get(ruleIndex);
      if (prevTop === undefined) {
        continue;
      }

      const deltaY = prevTop - rect.top;
      if (Math.abs(deltaY) < 1) {
        continue;
      }

      const activeTimer = schemaFlipResetTimersRef.current.get(ruleIndex);
      if (activeTimer !== undefined) {
        window.clearTimeout(activeTimer);
      }

      node.style.transition = "none";
      node.style.transform = `translateY(${deltaY}px)`;
      node.style.willChange = "transform";
      node.getBoundingClientRect();
      const durationMs = computeFlipDurationMs(deltaY);
      node.style.transition = `transform ${durationMs}ms cubic-bezier(0.22, 0.8, 0.2, 1)`;
      node.style.transform = "";

      const resetTimer = window.setTimeout(() => {
        const currentNode = schemaItemRefs.current.get(ruleIndex);
        if (currentNode) {
          currentNode.style.transition = "";
          currentNode.style.willChange = "";
        }
        schemaFlipResetTimersRef.current.delete(ruleIndex);
      }, durationMs + 70);
      schemaFlipResetTimersRef.current.set(ruleIndex, resetTimer);
    }

    previousSchemaItemTopsRef.current = nextTops;
  }, [orderedSchemaIndexes, draggingSchemaVisualIndex]);

  useEffect(() => {
    return () => {
      if (syncTimerRef.current !== null) {
        window.clearTimeout(syncTimerRef.current);
      }
      if (schemaReorderTimerRef.current !== null) {
        window.clearTimeout(schemaReorderTimerRef.current);
      }
      for (const timerId of schemaFlipResetTimersRef.current.values()) {
        window.clearTimeout(timerId);
      }
      schemaFlipResetTimersRef.current.clear();
    };
  }, []);

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
          <h2>일정 색상 설정</h2>
            <Link className="button-link" href="/">
              시계로 돌아가기
            </Link>
          </header>

          <div className="settings-toolbar">
            <label>
              캘린더 제공자
              <select value={provider} onChange={(e) => onProviderChange(e.target.value)}>
                <option value="google">Google</option>
                <option value="apple">Apple</option>
              </select>
            </label>
            <button onClick={() => void loadColorState()} disabled={loading}>
              {loading ? "불러오는 중..." : "다시 불러오기"}
            </button>
            <button onClick={addRule} disabled={loading || !hasEventColorSupport}>
              규칙 추가
            </button>
            <span style={{ fontSize: "0.85rem", color: "var(--muted)" }}>
              {syncing ? "변경사항 자동 저장/적용 중..." : "변경사항은 자동 저장/적용됩니다."}
            </span>
          </div>

          <p className="settings-hint">
            팔레트 색상: {palette.length}개 · 규칙: {schemaRules.length}개
          </p>
          {message ? <p className="notice">{message}</p> : null}

          <div className="schema-list">
            {orderedSchemaIndexes.map((ruleIndex, visualIndex) => {
              const rule = schemaRules[ruleIndex];
              if (!rule) {
                return null;
              }
              return (
              <div
                className={`schema-item${dragOverSchemaVisualIndex === visualIndex ? ` drag-over drag-over-${dragOverSchemaDropPosition}` : ""}${draggingSchemaVisualIndex === visualIndex ? " dragging" : ""}${recentlyMovedSchemaRuleIndex === ruleIndex ? " reordered" : ""}`}
                key={`${rule.color_hex}-${ruleIndex}`}
                ref={setSchemaItemRef(ruleIndex)}
                onDragOver={(event) => onSchemaDragOver(visualIndex, event)}
                onDrop={(event) => onSchemaDrop(visualIndex, event)}
              >
                <span
                  className="schema-drag-handle"
                  draggable
                  onDragStart={(event) => onSchemaDragStart(visualIndex, event)}
                  onDragEnd={onSchemaDragEnd}
                  title="드래그하여 순서 변경"
                  aria-label="드래그하여 순서 변경"
                >
                  ⋮⋮
                </span>
                <div className="color-picker-cell">
                  <button
                    type="button"
                    className="color-trigger"
                    onClick={() =>
                      setOpenPaletteIndex((prev) => (prev === ruleIndex ? null : ruleIndex))
                    }
                    aria-expanded={openPaletteIndex === ruleIndex}
                    aria-label="색상 팔레트 열기"
                  >
                    <span
                      className="color-preview"
                      style={{ backgroundColor: rule.color_hex || "#64748b" }}
                      title={rule.color_hex}
                    />
                  </button>
                  {openPaletteIndex === ruleIndex ? (
                    <div className="color-choice-grid">
                      {palette.map((color) => {
                        const selected = color === rule.color_hex;
                        return (
                          <button
                            key={`${ruleIndex}-${color}`}
                            type="button"
                            className={`color-choice ${selected ? "selected" : ""}`}
                            style={{ backgroundColor: color }}
                            aria-label={`${color} 선택`}
                            title={color}
                            onClick={() => {
                              updateRule(ruleIndex, (prev) => ({ ...prev, color_hex: color }));
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
                  placeholder="카테고리 라벨"
                  onChange={(e) =>
                    updateRule(ruleIndex, (prev) => ({ ...prev, label: e.target.value }))
                  }
                />
                <button
                  type="button"
                  className="schema-remove-btn"
                  onClick={() => removeRule(ruleIndex)}
                  aria-label="규칙 삭제"
                  title="삭제"
                >
                  ×
                </button>
              </div>
              );
            })}
            {!schemaRules.length ? <p>아직 저장된 색상 규칙이 없습니다.</p> : null}
          </div>
        </section>
      </main>
    </div>
  );
}
