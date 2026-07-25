import React, { useMemo, useState } from "react";
import {
  buildSymptomTrendPoints,
  type SymptomTrendRange,
} from "../lib/careconnect-core";

const SERIES_COLORS = ["#0D9488", "#7C3AED", "#0284C7", "#B45309", "#DC2626"];

export default function SymptomTrendChart({
  entries,
  accent = "#0D9488",
}: {
  entries: { name: string; severity: number; date?: string; time?: string }[];
  accent?: string;
}) {
  const [range, setRange] = useState<SymptomTrendRange>("week");
  const points = useMemo(
    () => buildSymptomTrendPoints(entries, range),
    [entries, range],
  );
  const seriesNames = useMemo(() => {
    const first = points[0];
    return first ? Object.keys(first.series) : [];
  }, [points]);

  const width = 320;
  const height = 180;
  const pad = { top: 16, right: 12, bottom: 28, left: 28 };
  const innerW = width - pad.left - pad.right;
  const innerH = height - pad.top - pad.bottom;

  const xAt = (i: number) =>
    pad.left + (points.length <= 1 ? innerW / 2 : (i / (points.length - 1)) * innerW);
  const yAt = (v: number) => pad.top + innerH - ((v - 0) / 5) * innerH;

  return (
    <div
      className="rounded-2xl bg-white border border-[#E5E7EB] p-4 flex flex-col gap-3"
      aria-label="Symptom severity trend chart"
    >
      <div className="flex items-center justify-between gap-2">
        <div>
          <p className="text-[14px] font-bold text-[#0F172A]">Symptom trends</p>
          <p className="text-[11px] text-[#9CA3AF]">Severity over time (1–5)</p>
        </div>
        <div className="flex rounded-xl p-1 gap-1" style={{ background: "#F3F4F6" }}>
          {([
            { key: "week" as const, label: "Week" },
            { key: "month" as const, label: "Month" },
            { key: "year" as const, label: "Year" },
          ]).map(r => (
            <button
              key={r.key}
              type="button"
              onClick={() => setRange(r.key)}
              className="px-2.5 py-1 rounded-lg text-[11px] font-bold transition-all"
              style={{
                background: range === r.key ? "white" : "transparent",
                color: range === r.key ? accent : "#6B7280",
                boxShadow: range === r.key ? "0 1px 3px rgba(0,0,0,0.08)" : "none",
              }}
              aria-pressed={range === r.key}
            >
              {r.label}
            </button>
          ))}
        </div>
      </div>

      {entries.length === 0 || seriesNames.length === 0 ? (
        <p className="text-[12px] text-[#9CA3AF] text-center py-6">
          Log symptoms to see Week / Month / Year trends.
        </p>
      ) : (
        <>
          <svg
            viewBox={`0 0 ${width} ${height}`}
            className="w-full h-auto"
            role="img"
            aria-label={`Symptom trend ${range} chart`}
          >
            {[1, 2, 3, 4, 5].map(v => (
              <g key={v}>
                <line
                  x1={pad.left}
                  x2={width - pad.right}
                  y1={yAt(v)}
                  y2={yAt(v)}
                  stroke="#E5E7EB"
                  strokeDasharray="3 3"
                />
                <text x={pad.left - 6} y={yAt(v) + 3} textAnchor="end" fontSize="10" fill="#9CA3AF">
                  {v}
                </text>
              </g>
            ))}
            {points.map((p, i) => (
              <text
                key={p.dateKey}
                x={xAt(i)}
                y={height - 8}
                textAnchor="middle"
                fontSize="9"
                fill="#6B7280"
              >
                {p.label}
              </text>
            ))}
            {seriesNames.map((name, sIdx) => {
              const color = SERIES_COLORS[sIdx % SERIES_COLORS.length];
              const coords = points
                .map((p, i) => {
                  const val = p.series[name];
                  if (val == null) return null;
                  return { x: xAt(i), y: yAt(val), val };
                })
                .filter(Boolean) as { x: number; y: number; val: number }[];
              if (!coords.length) return null;
              const d = coords
                .map((c, i) => `${i === 0 ? "M" : "L"}${c.x},${c.y}`)
                .join(" ");
              return (
                <g key={name}>
                  <path d={d} fill="none" stroke={color} strokeWidth="2.5" />
                  {coords.map((c, i) => (
                    <circle key={i} cx={c.x} cy={c.y} r="3.5" fill={color} />
                  ))}
                </g>
              );
            })}
          </svg>
          <div className="flex flex-wrap gap-2">
            {seriesNames.map((name, i) => (
              <span
                key={name}
                className="inline-flex items-center gap-1.5 text-[10px] font-semibold text-[#374151]"
              >
                <span
                  className="w-2.5 h-2.5 rounded-full"
                  style={{ background: SERIES_COLORS[i % SERIES_COLORS.length] }}
                />
                {name.length > 32 ? `${name.slice(0, 30)}…` : name}
              </span>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
