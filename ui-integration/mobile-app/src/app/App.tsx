import React, { useState, useRef, useEffect } from "react";
import {
  ArrowLeft, Brain, BookOpen, Hand, ChevronLeft, ChevronRight, Check,
  Volume2, Bell, Calendar, Pill, MessageCircle, Home,
  Settings, LayoutGrid, Sliders, Sparkles,
  Eye, EyeOff, Ear, Zap, User, ChevronDown, Shield, MousePointer, Wind,
  AlertTriangle, Captions, Phone, Vibrate, Mic,
  HeartPulse, Users, BarChart2, Send, Video,
  SmilePlus, Stethoscope, Activity, FileText, Star,
  X, ChevronUp, TrendingUp, Clock, MapPin, Menu as MenuIcon,
  Link2, QrCode, Copy, Plus, PhoneOff, PhoneCall, Mail,
} from "lucide-react";
import MailDigestContent from "./MailDigest";
import SymptomTrendChart from "./SymptomTrendChart";
import {
  ageFromDob,
  buildCaregiverPatientRoster as buildCaregiverPatientRosterCore,
  buildInviteUrl,
  buildProfileShareUrl,
  caregiverPatientConfirmed,
  createProfileShareToken,
  dobsMatch,
  formatCheckinStamp,
  HEARING_SPEAKER_LABELS,
  inferSpeakerFromText,
  isDemoCaregiverName,
  isProfessionalCaregiverPersona,
  makeInitials,
  namesMatch,
  namesLooselyMatch,
  normalizeDob,
  parseInviteFromUrl,
  patientSnapshotKey,
  qrImageUrl,
  resolvePatientForCaregiver,
  activateInviteInCareCircle,
  approveCaregiverInCircle,
  canAddCaregiver,
  MAX_CAREGIVERS,
  type CaregiverIdentity,
} from "../lib/careconnect-core";

/** Tap header to minimize / enlarge dashboard and tab sections (accessibility-style dropdown). */
function CollapsibleSection({
  id,
  title,
  subtitle = "Tap to expand or minimize",
  icon,
  accent = "#00A7C8",
  defaultOpen = true,
  children,
  openMap,
  setOpenMap,
}: {
  id: string;
  title: string;
  subtitle?: string;
  icon?: React.ReactNode;
  accent?: string;
  defaultOpen?: boolean;
  children: React.ReactNode;
  openMap: Record<string, boolean>;
  setOpenMap: React.Dispatch<React.SetStateAction<Record<string, boolean>>>;
}) {
  const open = openMap[id] ?? defaultOpen;
  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setOpenMap(prev => ({ ...prev, [id]: !open }))}
        aria-expanded={open}
        className="w-full flex items-center justify-between gap-3 px-4 py-3 rounded-xl border-2 bg-white text-left transition-all duration-150"
        style={{ borderColor: open ? accent : "#E5E7EB", minHeight: 56 }}
      >
        <div className="flex items-center gap-2 min-w-0">
          {icon}
          <div className="min-w-0">
            <p className="text-[14px] font-semibold text-[#0F172A] leading-tight truncate">{title}</p>
            <p className="text-[12px] text-[#595959] leading-tight mt-0.5 truncate">{subtitle}</p>
          </div>
        </div>
        <ChevronDown
          size={16}
          className="shrink-0 transition-transform duration-200 text-[#595959]"
          style={{ transform: open ? "rotate(180deg)" : "rotate(0deg)", color: open ? accent : undefined }}
        />
      </button>
      {open && (
        <div
          className="mt-1 rounded-xl border border-[#E5E7EB] bg-white overflow-hidden"
          style={{ boxShadow: "0 8px 24px rgba(0,0,0,0.08)" }}
        >
          <div className="px-3 py-3">{children}</div>
        </div>
      )}
    </div>
  );
}

/** Same interaction pattern as the accessibility ConditionDropdown. */
function OptionDropdown<T extends string>({
  value,
  onChange,
  options,
  color = "#00A7C8",
  lightBg = "#E0F7FA",
  borderColor = "#B2EBF2",
  label,
}: {
  value: T;
  onChange: (v: T) => void;
  options: { value: T; label: string; description: string }[];
  color?: string;
  lightBg?: string;
  borderColor?: string;
  label?: string;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const selected = options.find(o => o.value === value) ?? options[0];

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    if (open) document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  return (
    <div className="flex flex-col gap-1.5" ref={ref}>
      {label && (
        <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">{label}</label>
      )}
      <div className="relative">
        <button
          type="button"
          onClick={() => setOpen(p => !p)}
          aria-haspopup="listbox"
          aria-expanded={open}
          className="w-full flex items-center justify-between gap-3 px-4 py-3 rounded-xl border-2 bg-white text-left transition-all duration-150"
          style={{ borderColor: open ? color : borderColor, minHeight: 56 }}
        >
          <div className="min-w-0">
            <p className="text-[14px] font-semibold text-[#0F172A] leading-tight truncate">{selected?.label}</p>
            <p className="text-[12px] text-[#595959] leading-tight mt-0.5 truncate">{selected?.description}</p>
          </div>
          <ChevronDown
            size={16}
            className="shrink-0 transition-transform duration-200 text-[#595959]"
            style={{ transform: open ? "rotate(180deg)" : "rotate(0deg)" }}
          />
        </button>
        {open && (
          <ul
            role="listbox"
            className="relative z-50 mt-1 rounded-xl border border-[#E5E7EB] bg-white overflow-hidden max-h-64 overflow-y-auto"
            style={{ boxShadow: "0 8px 24px rgba(0,0,0,0.10)" }}
          >
            {options.map(opt => {
              const isSel = opt.value === value;
              return (
                <li
                  key={opt.value}
                  role="option"
                  aria-selected={isSel}
                  onClick={() => { onChange(opt.value); setOpen(false); }}
                  className="flex items-center gap-3 px-4 py-3 cursor-pointer transition-colors duration-100"
                  style={{ background: isSel ? lightBg : "white", minHeight: 52 }}
                >
                  <div className="flex-1 min-w-0">
                    <p className="text-[14px] font-medium text-[#0F172A] leading-tight">{opt.label}</p>
                    <p className="text-[12px] text-[#595959] leading-tight mt-0.5">{opt.description}</p>
                  </div>
                  {isSel && <Check size={15} style={{ color }} className="shrink-0" />}
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
}

// ── Persistence helpers ────────────────────────────────────────────────────────

const PROFILE_KEY = "careconnect_v1";
const IMAGE_KEY   = "careconnect_v1_img";
const PATIENT_SNAPSHOT_KEY = "careconnect_patient_snapshot";
/** Multi-patient registry so caregivers keep seeing *their* linked patient
 *  even if another patient later signed in on the same browser. */
const PATIENT_SNAPSHOT_REGISTRY_KEY = "careconnect_patient_snapshots";

function loadSaved<T>(field: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(PROFILE_KEY);
    if (!raw) return fallback;
    const data = JSON.parse(raw);
    return field in data ? data[field] : fallback;
  } catch { return fallback; }
}

function saveAll(data: Record<string, unknown>) {
  try { localStorage.setItem(PROFILE_KEY, JSON.stringify(data)); } catch {}
}

// ── Mood history ───────────────────────────────────────────────────────────────

interface MoodEntry {
  date: string;      // YYYY-MM-DD
  score: number;     // 1–5
  symptom?: string;  // primary symptom noted for that day (if any)
}

const MOOD_LABELS = ["", "Poor", "Low", "Fair", "Good", "Great"] as const;
const MOOD_EMOJIS = ["", "😞", "😕", "😐", "🙂", "😄"] as const;
const NONE_SYMPTOM = "None / Feeling fine";
const QUICK_SYMPTOMS = [
  "Headache", "Fatigue", "Pain", "Anxiety", "Nausea", "Dizziness", "Insomnia", NONE_SYMPTOM,
];

function moodDateKey(d = new Date()): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function formatMoodDayLabel(dateKey: string): string {
  const [y, m, d] = dateKey.split("-").map(Number);
  const date = new Date(y, m - 1, d, 12);
  return date.toLocaleDateString([], { weekday: "long", month: "short", day: "numeric" });
}

/** Resolve a LoggedSymptom to YYYY-MM-DD when possible. */
function symptomDateKey(s: { date?: string; time?: string }): string | null {
  if (s.date) return s.date;
  const t = (s.time ?? "").toLowerCase();
  if (t.includes("today")) return moodDateKey();
  if (t.includes("yesterday")) {
    const d = new Date();
    d.setHours(12, 0, 0, 0);
    d.setDate(d.getDate() - 1);
    return moodDateKey(d);
  }
  return null;
}

function findSymptomForDate(
  symptoms: { name: string; severity: number; date?: string; time?: string }[],
  date: string,
): string | undefined {
  const matches = symptoms
    .map(s => ({ name: s.name, severity: s.severity, key: symptomDateKey(s) }))
    .filter(s => s.key === date);
  if (!matches.length) return undefined;
  matches.sort((a, b) => b.severity - a.severity);
  return matches[0].name;
}

/** One score per calendar day; keeps ~3 months for monthly history. */
function upsertMoodHistory(
  history: MoodEntry[],
  score: number,
  opts?: { date?: string; symptom?: string | null },
): MoodEntry[] {
  const date = opts?.date ?? moodDateKey();
  const clamped = Math.max(1, Math.min(5, Math.round(score)));
  const existing = history.find(e => e.date === date);
  let symptom: string | undefined;
  if (opts?.symptom === null) symptom = undefined;
  else if (typeof opts?.symptom === "string" && opts.symptom.trim()) symptom = opts.symptom.trim();
  else symptom = existing?.symptom;
  const entry: MoodEntry = { date, score: clamped };
  if (symptom) entry.symptom = symptom;
  return [...history.filter(e => e.date !== date), entry]
    .sort((a, b) => a.date.localeCompare(b.date))
    .slice(-93);
}

function msUntilNextMidnight(from = new Date()): number {
  const next = new Date(from.getFullYear(), from.getMonth(), from.getDate() + 1, 0, 0, 1);
  return Math.max(1000, next.getTime() - from.getTime());
}

/** Hook: keeps "today" in sync across midnight without a full page reload. */
function useLiveTodayKey(): string {
  const [todayKey, setTodayKey] = useState(() => moodDateKey());
  useEffect(() => {
    const sync = () => {
      const next = moodDateKey();
      setTodayKey(prev => (prev === next ? prev : next));
    };
    const interval = window.setInterval(sync, 30_000);
    let midnightTimer = window.setTimeout(function schedule() {
      sync();
      midnightTimer = window.setTimeout(schedule, msUntilNextMidnight());
    }, msUntilNextMidnight());
    const onVisible = () => { if (document.visibilityState === "visible") sync(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      window.clearInterval(interval);
      window.clearTimeout(midnightTimer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, []);
  return todayKey;
}

interface MonthMoodCell {
  day: number;
  date: string;
  weekday: number;
  score: number | null;
  symptom?: string;
  isToday: boolean;
}

/** Calendar cells for a given month (1..daysInMonth). */
function buildMonthMoodGrid(
  history: MoodEntry[],
  year: number,
  monthIndex: number, // 0–11
): MonthMoodCell[] {
  const byDate = new Map(history.map(e => [e.date, e]));
  const today = moodDateKey();
  const daysInMonth = new Date(year, monthIndex + 1, 0).getDate();
  const cells: MonthMoodCell[] = [];
  for (let day = 1; day <= daysInMonth; day++) {
    const d = new Date(year, monthIndex, day, 12);
    const date = moodDateKey(d);
    const entry = byDate.get(date);
    cells.push({
      day,
      date,
      weekday: d.getDay(),
      score: entry?.score ?? null,
      symptom: entry?.symptom,
      isToday: date === today,
    });
  }
  return cells;
}

function monthFeelingStats(cells: MonthMoodCell[]) {
  const logged = cells.filter(c => c.score != null) as (MonthMoodCell & { score: number })[];
  const avg = logged.length
    ? Math.round((logged.reduce((s, c) => s + c.score, 0) / logged.length) * 10) / 10
    : null;
  const worst = logged.length
    ? logged.reduce((a, b) => (b.score < a.score ? b : a))
    : null;
  const best = logged.length
    ? logged.reduce((a, b) => (b.score > a.score ? b : a))
    : null;
  return { loggedCount: logged.length, daysInMonth: cells.length, avg, worst, best };
}

/** Last 7 calendar days (oldest → newest) for trend charts. */
function buildWeekMoodSeries(history: MoodEntry[]): {
  day: string; score: number | null; date: string; isToday: boolean; symptom?: string;
}[] {
  const dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const byDate = new Map(history.map(e => [e.date, e]));
  const today = moodDateKey();
  const series: { day: string; score: number | null; date: string; isToday: boolean; symptom?: string }[] = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date();
    d.setHours(12, 0, 0, 0);
    d.setDate(d.getDate() - i);
    const date = moodDateKey(d);
    const entry = byDate.get(date);
    series.push({
      day: dayNames[d.getDay()],
      score: entry?.score ?? null,
      date,
      isToday: date === today,
      symptom: entry?.symptom,
    });
  }
  return series;
}

function findWorstDayInWeek(history: MoodEntry[]): {
  day: string; date: string; score: number; symptom?: string; label: string;
} | null {
  const logged = buildWeekMoodSeries(history).filter(s => s.score != null) as {
    day: string; date: string; score: number; symptom?: string;
  }[];
  if (!logged.length) return null;
  const worst = logged.reduce((a, b) => (b.score < a.score ? b : a));
  return {
    ...worst,
    label: formatMoodDayLabel(worst.date),
  };
}

interface SymptomPatternStat {
  name: string;
  count: number;
  avgScore: number;
  days: string[];
}

/** Detect recurring symptoms and how they relate to mood this week. */
function analyzeSymptomPatterns(history: MoodEntry[]): {
  patterns: SymptomPatternStat[];
  recurring: SymptomPatternStat[];
  topSymptom: SymptomPatternStat | null;
  worstLinked: SymptomPatternStat | null;
  insight: string;
} {
  const week = buildWeekMoodSeries(history).filter(
    s => s.score != null && s.symptom && s.symptom !== NONE_SYMPTOM
  ) as { day: string; score: number; symptom: string }[];

  const map = new Map<string, { scores: number[]; days: string[] }>();
  for (const e of week) {
    const cur = map.get(e.symptom) ?? { scores: [], days: [] };
    cur.scores.push(e.score);
    cur.days.push(e.day);
    map.set(e.symptom, cur);
  }

  const patterns: SymptomPatternStat[] = [...map.entries()]
    .map(([name, v]) => ({
      name,
      count: v.scores.length,
      avgScore: Math.round((v.scores.reduce((a, b) => a + b, 0) / v.scores.length) * 10) / 10,
      days: v.days,
    }))
    .sort((a, b) => b.count - a.count || a.avgScore - b.avgScore);

  const recurring = patterns.filter(p => p.count >= 2);
  const topSymptom = patterns[0] ?? null;
  const worstLinked = patterns.length
    ? [...patterns].sort((a, b) => a.avgScore - b.avgScore || b.count - a.count)[0]
    : null;

  let insight = "Tell us your symptom each day on Home so we can spot patterns.";
  if (recurring.length > 0 && worstLinked && worstLinked.count >= 2) {
    insight = `${worstLinked.name} showed up ${worstLinked.count} days (${worstLinked.days.join(", ")}) with an average mood of ${worstLinked.avgScore}/5 — a possible pattern.`;
  } else if (recurring[0]) {
    insight = `${recurring[0].name} appeared ${recurring[0].count} times this week (${recurring[0].days.join(", ")}). Watch how it affects your mood.`;
  } else if (worstLinked) {
    insight = `Lowest moods this week were linked to ${worstLinked.name} (avg ${worstLinked.avgScore}/5). Log again to confirm a pattern.`;
  } else if (topSymptom) {
    insight = `Most noted symptom: ${topSymptom.name}. Keep logging daily to detect patterns.`;
  }

  return { patterns, recurring, topSymptom, worstLinked, insight };
}

const LOW_MOOD_STREAK_ALERT_KEY = "careconnect_low_mood_streak_alert";
const LOW_MOOD_STREAK_THRESHOLD = 3;

/** Count consecutive Poor/Low (score ≤ 2) days ending on throughDate. */
function countConsecutiveLowMoodDays(history: MoodEntry[], throughDate = moodDateKey()): number {
  const byDate = new Map(history.map(e => [e.date, e.score]));
  let count = 0;
  const d = new Date(`${throughDate}T12:00:00`);
  if (Number.isNaN(d.getTime())) return 0;
  for (;;) {
    const key = moodDateKey(d);
    const score = byDate.get(key);
    if (score == null || score > 2) break;
    count++;
    d.setDate(d.getDate() - 1);
  }
  return count;
}

function streakStartKey(throughDate: string, streakDays: number): string {
  const d = new Date(`${throughDate}T12:00:00`);
  d.setDate(d.getDate() - (streakDays - 1));
  return moodDateKey(d);
}

interface LowMoodStreakAlert {
  streakStart: string;
  streakDays: number;
  notifiedAt: string;
  patientName: string;
  symptom?: string;
  recipientNames: string[];
}

function loadLowMoodStreakAlert(): LowMoodStreakAlert | null {
  try {
    const raw = localStorage.getItem(LOW_MOOD_STREAK_ALERT_KEY);
    return raw ? JSON.parse(raw) as LowMoodStreakAlert : null;
  } catch {
    return null;
  }
}

function saveLowMoodStreakAlert(alert: LowMoodStreakAlert | null) {
  try {
    if (alert) localStorage.setItem(LOW_MOOD_STREAK_ALERT_KEY, JSON.stringify(alert));
    else localStorage.removeItem(LOW_MOOD_STREAK_ALERT_KEY);
  } catch {}
}

/** Persist a mood-linked symptom into the symptoms log (same-day dedupe). */
function syncSymptomFromMoodLog(name: string, score: number) {
  const cleaned = name.trim();
  if (!cleaned || cleaned === NONE_SYMPTOM) return;
  try {
    const list = loadLoggedSymptoms();
    const today = moodDateKey();
    if (list.some(s => s.name === cleaned && symptomDateKey(s) === today)) return;
    const entry: LoggedSymptom = {
      id: `s-mood-${Date.now()}`,
      name: cleaned,
      category: "other",
      severity: score <= 2 ? 4 : score === 3 ? 3 : 2,
      time: new Date().toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }),
      note: "Logged with daily mood check-in",
      date: today,
    };
    localStorage.setItem("careconnect_logged_symptoms", JSON.stringify([entry, ...list]));
  } catch {}
}

/** Seed a gentle 7-day demo mood trend (no fabricated symptoms/allergies). */
function seedMoodHistory(currentMood: number | null): MoodEntry[] {
  const base = currentMood && currentMood >= 1 && currentMood <= 5 ? currentMood : 4;
  const plan: number[] = [-1, 0, -1, 1, 0, -2, 0];
  return plan.map((off, i) => {
    const d = new Date();
    d.setHours(12, 0, 0, 0);
    d.setDate(d.getDate() - (6 - i));
    const score = Math.max(1, Math.min(5, base + off));
    return { date: moodDateKey(d), score };
  });
}

/** Load mood history; seed a demo week once if the field has never been saved. */
function loadMoodHistory(): MoodEntry[] {
  try {
    const raw = localStorage.getItem(PROFILE_KEY);
    if (!raw) return seedMoodHistory(null);
    const data = JSON.parse(raw);
    let history: MoodEntry[];
    if ("moodHistory" in data && Array.isArray(data.moodHistory)) {
      history = data.moodHistory as MoodEntry[];
    } else {
      history = seedMoodHistory(
        typeof data.patientMood === "number" ? data.patientMood : null
      );
    }
    // Attach symptoms from the symptom log when a mood day is missing one
    try {
      const symptomsRaw = localStorage.getItem("careconnect_logged_symptoms");
      const symptoms = symptomsRaw ? JSON.parse(symptomsRaw) : [];
      return history.map(e => {
        if (e.symptom) return e;
        const found = findSymptomForDate(symptoms, e.date);
        return found ? { ...e, symptom: found } : e;
      });
    } catch {
      return history;
    }
  } catch {
    return seedMoodHistory(null);
  }
}

// ── Types ──────────────────────────────────────────────────────────────────────

type DisabilityKey = "stml" | "dyslexia" | "carpal" | "hearing";
type AppMode = DisabilityKey | "custom";
type Role = "patient" | "caregiver";
type Tab = "home" | "schedule" | "meds" | "settings" | "symptoms" | "checkin" | "messages" | "patients" | "analytics" | "profile" | "hearing" | "mail";
type Phase = "splash" | "signin" | "profile-create" | "role" | "landing" | "builder" | "app";
interface NavState { phase: Phase; tab?: Tab; }
interface NavProps { canGoBack: boolean; canGoForward: boolean; onBack: () => void; onForward: () => void; }

// ── Feature system ──────────────────────────────────────────────────────────────

type FeatureId =
  | "medication_tracker" | "virtual_checkin" | "symptoms_tracker" | "fall_detection"
  | "voice_commands"     | "wearables"        | "smart_devices"    | "social_feed"
  | "gamification"       | "calendar_asst"    | "notetaker"        | "invoice_asst"
  | "file_management"    | "usps_mail"        | "hearing_assist";

type GrantedItem = "mood" | "checkin_summary" | "med_adherence" | "fall_alerts" | "upcoming_visits" | "symptoms";

interface FeatureDef {
  id: FeatureId; label: string; icon: string; category: "health" | "safety" | "ai" | "devices" | "social" | "documents";
  description: string;
  // maps to an app Tab when enabled
  tab?: Tab;
}

interface LinkedCaregiver {
  id: string; name: string; relationship: string; initials: string;
  grants: GrantedItem[]; status: "active" | "pending" | "suspended";
  email?: string; phone?: string; inviteCode?: string;
  /** True when the patient added this person from Care Circle (counts as pre-approval). */
  addedByPatient?: boolean;
  /** Features the caregiver has asked the patient to share. */
  pendingGrantRequests?: GrantedItem[];
}

interface PatientSnippet {
  id: string; name: string; age: number; initials: string;
  grants: GrantedItem[];
  mood?: number; lastCheckin?: string; medAdherence?: number;
  hasFallAlert?: boolean; nextVisit?: string; symptomsSummary?: string;
  /** Access control derived from Care Circle + patient profile status */
  accessState?: "ok" | "inactive_profile" | "suspended" | "pending" | "unauthorized";
  caregiverRelationship?: string;
  caregiverName?: string;
}

type CaregiverPersona = "care_coordinator" | "primary_physician";

const CAREGIVER_PERSONAS: {
  id: string; persona: CaregiverPersona; label: string; name: string; description: string;
}[] = [
  {
    id: "cg1", persona: "care_coordinator", label: "Family / Support Caregiver",
    name: "",
    description: "For family or support caregivers. You enter your real name and relationship to the patient.",
  },
  {
    id: "cg2", persona: "primary_physician", label: "Primary Care Physician",
    name: "",
    description: "For clinical caregivers. You enter your real name; relationship defaults to Primary Care Physician.",
  },
];

/** Prefer the caregiver’s stated relationship to the patient over a generic persona label. */
function caregiverRoleLabel(
  account?: Pick<CaregiverAccountInfo, "relationshipToPatient"> | null,
  personaId?: string | null,
): string {
  const relation = account?.relationshipToPatient?.trim();
  if (relation) return relation;
  return CAREGIVER_PERSONAS.find(p => p.id === personaId)?.label || "Caregiver";
}

interface CaregiverAccountInfo {
  name: string;
  email: string;
  agency: string;
  credentials: string;
  phone: string;
  password?: string;
  pin?: string;
  colorSeq?: string[];
  /** Patient/User this caregiver is linked to (from invite / confirmation) */
  linkedPatientName?: string;
  linkedPatientDob?: string;
  linkedInviteCode?: string;
  /** Caregiver’s relation to the Patient/User (e.g. Daughter, Friend) */
  relationshipToPatient?: string;
}

const CAREGIVER_ACCOUNT_DEFAULTS: Record<string, CaregiverAccountInfo> = {
  cg1: {
    name: "",
    email: "",
    agency: "",
    credentials: "",
    phone: "",
  },
  cg2: {
    name: "",
    email: "",
    agency: "",
    credentials: "",
    phone: "",
    relationshipToPatient: "Primary Care Physician",
  },
};

function caregiverAccountKey(id: string) {
  return `careconnect_caregiver_account_${id}`;
}

function loadCaregiverAccount(id: string): CaregiverAccountInfo {
  const defaults = CAREGIVER_ACCOUNT_DEFAULTS[id] ?? {
    name: "",
    email: "",
    agency: "",
    credentials: "",
    phone: "",
  };
  try {
    const raw = localStorage.getItem(caregiverAccountKey(id));
    if (!raw) return { ...defaults };
    const saved = { ...defaults, ...JSON.parse(raw) } as CaregiverAccountInfo;
    // Strip old demo seed names so the real caregiver identity can show
    if (isDemoCaregiverName(saved.name)) {
      saved.name = "";
    }
    if (saved.relationshipToPatient?.trim() === "Daughter" && !saved.password && !saved.pin) {
      // likely old Maria demo seed — clear unless they set auth (kept relationship if real account)
      if (!saved.email?.trim() && !saved.phone?.trim()) {
        saved.relationshipToPatient = id === "cg2" ? "Primary Care Physician" : undefined;
      }
    }
    return saved;
  } catch {
    return { ...defaults };
  }
}

function saveCaregiverAccount(id: string, info: CaregiverAccountInfo) {
  try {
    localStorage.setItem(caregiverAccountKey(id), JSON.stringify(info));
  } catch {}
}

function caregiverAccountConfigured(info: CaregiverAccountInfo): boolean {
  const hasAuth = !!(
    info.password?.trim() ||
    info.pin?.trim() ||
    (info.colorSeq && info.colorSeq.length >= 3)
  );
  return hasAuth && !isDemoCaregiverName(info.name) && !!info.name.trim();
}

/** Caregiver accounts that have been created (real name + login), for sign-in. */
function listConfiguredCaregiverAccounts(): { id: string; account: CaregiverAccountInfo }[] {
  const ids = new Set<string>(CAREGIVER_PERSONAS.map(p => p.id));
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key?.startsWith("careconnect_caregiver_account_")) {
        ids.add(key.replace("careconnect_caregiver_account_", ""));
      }
    }
  } catch {}
  return [...ids]
    .map(id => ({ id, account: loadCaregiverAccount(id) }))
    .filter(({ account }) => caregiverAccountConfigured(account));
}

function scrubDemoCaregivers(list: LinkedCaregiver[]): LinkedCaregiver[] {
  return list.filter(cg => {
    if (isDemoCaregiverName(cg.name)) return false;
    if (cg.email === "maria.r@careconnect.app" || cg.email === "spatel@citymedical.org") return false;
    return true;
  });
}

/** One-time cleanup of old Maria / Dr. Patel demo caregiver seeds. */
function migrateDemoCaregiverData() {
  try {
    for (const id of CAREGIVER_PERSONAS.map(p => p.id)) {
      const raw = localStorage.getItem(caregiverAccountKey(id));
      if (!raw) continue;
      const parsed = JSON.parse(raw) as CaregiverAccountInfo;
      const hasAuth = !!(
        parsed.password?.trim() ||
        parsed.pin?.trim() ||
        (parsed.colorSeq && parsed.colorSeq.length >= 3)
      );
      if (isDemoCaregiverName(parsed.name) && !hasAuth) {
        localStorage.removeItem(caregiverAccountKey(id));
        continue;
      }
      if (isDemoCaregiverName(parsed.name)) {
        // Keep auth credentials but force user to set a real name on next edit
        parsed.name = "";
        localStorage.setItem(caregiverAccountKey(id), JSON.stringify(parsed));
      }
    }
    const snap = loadPatientSnapshot();
    if (snap?.linkedCaregivers?.length) {
      const cleaned = scrubDemoCaregivers(snap.linkedCaregivers);
      if (cleaned.length !== snap.linkedCaregivers.length) {
        savePatientSnapshot({ ...snap, linkedCaregivers: cleaned });
      }
    }
  } catch {}
}

/** Build the caregiver's patient roster from the patient's Care Circle grants + active profile. */
function buildCaregiverPatientRoster(opts: {
  caregiverId: string;
  linkedCaregivers: LinkedCaregiver[];
  patientActive: boolean;
  profileName: string;
  profileDob: string;
  profileConditions: string;
  profileAllergies: string;
  medAdherence: number;
  nextVisit?: string;
  symptomsSummary?: string;
  mood?: number;
  lastCheckin?: string;
  hasFallAlert?: boolean;
  linkedPatientName?: string;
  linkedInviteCode?: string;
  caregiverName?: string;
}): PatientSnippet[] {
  return buildCaregiverPatientRosterCore({
    ...opts,
    personas: CAREGIVER_PERSONAS.map(p => ({ id: p.id, label: p.label, name: p.name })),
  }) as PatientSnippet[];
}

interface FeatureOption { id: string; label: string; description: string; category: DisabilityKey; }
interface CustomSettings { [id: string]: boolean; }
interface ProfileCard {
  key: DisabilityKey; label: string; abbr: string; tagline: string; description: string;
  adaptations: string[]; icon: React.ReactNode; color: string; lightBg: string; borderColor: string;
}
interface ModeTheme { color: string; lightBg: string; borderColor: string; name: string; }

// makeInitials, namesMatch, buildInviteUrl, parseInviteFromUrl, qrImageUrl imported from careconnect-core

// ── Data ───────────────────────────────────────────────────────────────────────

const PROFILES: ProfileCard[] = [
  {
    key: "stml", label: "Short-Term Memory Loss", abbr: "STML", tagline: "Step-by-step reminders",
    description: "The app carries the memory burden for you — persistent context cues, auto-save, gentle nudges, and an activity history so you never lose your place.",
    adaptations: ["Breadcrumb context bar", "Auto-save everything", "Daily recap screen", "Step-by-step flows", "Persistent reminders", "Activity history"],
    icon: <Brain size={32} />, color: "#7C3AED", lightBg: "#F5F3FF", borderColor: "#DDD6FE",
  },
  {
    key: "dyslexia", label: "Dyslexia", abbr: "Dyslexia", tagline: "Reading-friendly layout",
    description: "Reduces text load and improves legibility — dyslexia-friendly fonts, generous spacing, text-to-speech, voice input, and plain language throughout.",
    adaptations: ["Lexend / OpenDyslexic font", "Cream tint", "Wide letter & line spacing", "Read aloud on tap", "Voice input", "Plain language"],
    icon: <BookOpen size={32} />, color: "#0E7E57", lightBg: "#F0FDF4", borderColor: "#BBF7D0",
  },
  {
    key: "carpal", label: "Carpal Tunnel", abbr: "Carpal Tunnel", tagline: "Low-effort navigation",
    description: "Minimises precise, repetitive hand movement — oversized targets, voice control, autofill, no timed gestures, and undo everywhere for misclicks.",
    adaptations: ["80dp+ touch targets", "Voice control", "Autofill & defaults", "No timed gestures", "Undo everywhere", "Swipe navigation"],
    icon: <Hand size={32} />, color: "#B45309", lightBg: "#FFFBEB", borderColor: "#FDE68A",
  },
  {
    key: "hearing", label: "Hearing Impaired", abbr: "Hearing", tagline: "Visual & tactile alerts",
    description: "Every audio cue has a visual or tactile equivalent — captions, screen flash, vibration patterns, text-first communication, and real-time call captions.",
    adaptations: ["Closed captions", "Screen flash alerts", "Vibration patterns", "Text chat first", "Real-time call captions", "Hearing Conversation Assist"],
    icon: <Ear size={32} />, color: "#0284C7", lightBg: "#E0F2FE", borderColor: "#BAE6FD",
  },
];

const ALL_FEATURES: FeatureOption[] = [
  // ── Short-term memory ──
  { id: "stml_steps",      label: "Step-by-step flows",        description: "Every task is broken into numbered single steps — only one step shown at a time.", category: "stml" },
  { id: "stml_reminders",  label: "Persistent reminders",      description: "Reminder banners stay on screen and re-prompt every 5 min until dismissed.",       category: "stml" },
  { id: "stml_icons",      label: "Large labelled icons",      description: "Every action shows a large icon alongside its text label — no guessing.",           category: "stml" },
  { id: "stml_confirm",    label: "Confirm before acting",     description: "Ask for confirmation before any important or hard-to-reverse action.",              category: "stml" },
  { id: "stml_autosave",   label: "Auto-save everything",      description: "Progress is saved automatically so nothing is lost if the user walks away mid-task.", category: "stml" },
  { id: "stml_breadcrumb", label: "Context breadcrumbs",       description: "A persistent bar always shows where the user is and what they were doing (e.g. 'Adding medication — Step 2 of 3').", category: "stml" },
  { id: "stml_recap",      label: "Daily recap screen",        description: "A 'Here's what you did today' recap is shown on the home screen each morning.",     category: "stml" },
  { id: "stml_history",    label: "Activity history",          description: "Searchable log of completed actions so the user can check 'did I already do this?'.", category: "stml" },

  // ── Dyslexia ──
  { id: "dys_font",        label: "Dyslexia-friendly font",    description: "Switch all text to Lexend — generous spacing, clear letterforms, no crowding.",     category: "dyslexia" },
  { id: "dys_tint",        label: "Cream screen tint",         description: "Warm cream background reduces high-contrast white glare that tires the eyes.",       category: "dyslexia" },
  { id: "dys_spacing",     label: "Extra letter & line spacing", description: "Wider character, word, and line spacing stops letters from running together.",     category: "dyslexia" },
  { id: "dys_readaloud",   label: "Read aloud on tap",         description: "Tap any paragraph or label to hear it spoken aloud.",                                category: "dyslexia" },
  { id: "dys_tts",         label: "Full screen text-to-speech", description: "All on-screen text — navigation, labels, and content — is read aloud automatically.", category: "dyslexia" },
  { id: "dys_plainlang",   label: "Plain language mode",       description: "Complex sentences are simplified; labels use everyday words and icons instead of jargon.", category: "dyslexia" },
  { id: "dys_voice",       label: "Voice input for text fields", description: "A microphone button appears in every text field as an alternative to typing.",     category: "dyslexia" },
  { id: "dys_chunking",    label: "Visual chunking",           description: "Content is broken into short sections with extra whitespace and progressive disclosure — no walls of text.", category: "dyslexia" },

  // ── Carpal tunnel ──
  { id: "ct_targets",      label: "Oversized touch targets",   description: "All buttons and interactive areas are at least 80 dp tall — no precision needed.",  category: "carpal" },
  { id: "ct_swipe",        label: "Swipe navigation",          description: "Swipe between screens — no small back buttons or precise taps required.",            category: "carpal" },
  { id: "ct_voice",        label: "Voice input & navigation",  description: "Dictate text and navigate by voice — reduces typing and tapping to near zero.",      category: "carpal" },
  { id: "ct_minimal",      label: "Minimal scrolling",         description: "Content is paginated so long scroll sessions are never needed.",                     category: "carpal" },
  { id: "ct_undo",         label: "Undo everywhere",           description: "Every action can be undone with a single large button — imprecise taps are forgiven.", category: "carpal" },
  { id: "ct_autofill",     label: "Autofill & smart defaults", description: "Fields pre-fill from history; common answers appear as large one-tap chips.",        category: "carpal" },
  { id: "ct_notimed",      label: "No timed gestures",         description: "No double-taps, long-presses, or actions with a time limit — everything waits for the user.", category: "carpal" },
  { id: "ct_keyboard",     label: "Full keyboard navigation",  description: "Every action is reachable by keyboard alone — no mouse or pointer required.",        category: "carpal" },

  // ── Hearing ──
  { id: "hear_captions",   label: "Closed captions",           description: "Captions for all audio notifications and spoken content.",                           category: "hearing" },
  { id: "hear_flash",      label: "Screen flash alerts",       description: "The screen border flashes visually whenever a sound alert would normally play.",      category: "hearing" },
  { id: "hear_vibration",  label: "Haptic vibration patterns", description: "Distinct vibration patterns for different alert types — meds, appointments, messages.", category: "hearing" },
  { id: "hear_tty",        label: "TTY / text relay",          description: "TTY mode and relay-service compatibility for text-based phone calls.",                category: "hearing" },
  { id: "hear_chat",       label: "Text chat as first option", description: "Chat / SMS is offered as the primary communication channel instead of voice calls.",  category: "hearing" },
  { id: "hear_badges",     label: "Visual notification badges", description: "Prominent visual badges and banners for every alert — never audio-only.",            category: "hearing" },
  { id: "hear_realtime",   label: "Real-time call captions",   description: "Live captions are shown during phone and video calls with relay-service support.",    category: "hearing" },
  { id: "hear_transcripts",label: "Audio transcripts",         description: "Full text transcripts generated for any voicemail-style messages or audio content.",  category: "hearing" },
];

const CAT_META: Record<DisabilityKey, { label: string; color: string; lightBg: string; borderColor: string; icon: React.ReactNode }> = {
  stml:     { label: "STML",          color: "#7C3AED", lightBg: "#F5F3FF", borderColor: "#DDD6FE", icon: <Brain size={14} />    },
  dyslexia: { label: "Dyslexia",      color: "#0E7E57", lightBg: "#F0FDF4", borderColor: "#BBF7D0", icon: <BookOpen size={14} /> },
  carpal:   { label: "Carpal Tunnel", color: "#B45309", lightBg: "#FFFBEB", borderColor: "#FDE68A", icon: <Hand size={14} />    },
  hearing:  { label: "Hearing",       color: "#0284C7", lightBg: "#E0F2FE", borderColor: "#BAE6FD", icon: <Ear size={14} />     },
};

interface DisabilityOption { value: string; label: string; description: string; }

const DISABILITY_OPTIONS: DisabilityOption[] = [
  { value: "none",          label: "No specific condition",      description: "General accessibility settings" },
  { value: "low_vision",    label: "Low vision",                 description: "Difficulty seeing fine details" },
  { value: "blindness",     label: "Blindness",                  description: "No or very limited light perception" },
  { value: "tremor",        label: "Tremor / motor impairment",  description: "Involuntary hand movements" },
  { value: "cognitive",     label: "Cognitive / memory support", description: "Memory or processing challenges" },
  { value: "hearing_loss",  label: "Hearing loss / deafness",    description: "Reduced or no auditory perception" },
  { value: "chronic_fatigue", label: "Chronic fatigue",          description: "Reduced stamina or energy" },
  { value: "dyslexia_cond", label: "Dyslexia",                   description: "Reading and text processing difficulties" },
  { value: "other",         label: "Other / prefer not to say",  description: "Custom settings without disclosure" },
];

// ── Feature catalogue ──────────────────────────────────────────────────────────

const FEATURE_DEFS: FeatureDef[] = [
  { id: "medication_tracker", label: "Medication Tracker",   icon: "💊", category: "health",    description: "Track doses, set reminders, and log adherence.",       tab: "symptoms" },
  { id: "virtual_checkin",    label: "Virtual Check-In",     icon: "🩺", category: "health",    description: "Guided daily health check-in with your care team.",     tab: "checkin"  },
  { id: "symptoms_tracker",   label: "Symptoms & Allergies", icon: "🌡️", category: "health",    description: "Log symptoms and manage your allergy list.",            tab: "symptoms" },
  { id: "hearing_assist",     label: "Hearing Conversation Assist", icon: "👂", category: "ai", description: "Live captions, speaker ID, AI summaries, memory, and conversation coaching.", tab: "hearing" },
  { id: "fall_detection",     label: "Fall Detection",       icon: "🛡️", category: "safety",   description: "Detect and alert caregivers to falls automatically.",   tab: undefined  },
  { id: "voice_commands",     label: "Voice Commands",       icon: "🎙️", category: "ai",       description: "Hands-free navigation and dictation.",                  tab: undefined  },
  { id: "notetaker",          label: "Notetaker Assistant",  icon: "📝", category: "ai",       description: "AI-powered notes with live transcription.",             tab: undefined  },
  { id: "calendar_asst",      label: "Calendar Assistant",   icon: "📅", category: "ai",       description: "AI scheduling and appointment management.",             tab: "schedule" },
  { id: "invoice_asst",       label: "Invoice Assistant",    icon: "🧾", category: "ai",       description: "OCR invoice capture and expense management.",           tab: undefined  },
  { id: "wearables",          label: "Wearables",            icon: "⌚", category: "devices",  description: "Sync health data from Fitbit and other wearables.",    tab: undefined  },
  { id: "smart_devices",      label: "Smart Devices",        icon: "🏠", category: "devices",  description: "Control and monitor smart home devices.",               tab: undefined  },
  { id: "social_feed",        label: "Social Feed",          icon: "👥", category: "social",   description: "Connect with family, friends, and your care community.", tab: undefined },
  { id: "gamification",       label: "Gamification",         icon: "🏆", category: "social",   description: "Earn points and badges for health milestones.",         tab: undefined  },
  { id: "file_management",    label: "File Management",      icon: "📁", category: "documents", description: "Manage care documents and compliance records.",        tab: undefined  },
  { id: "usps_mail",          label: "Mail Digest (USPS)",   icon: "📬", category: "documents", description: "Daily Informed Delivery digest: OCR, search, importance, ADA read-aloud.", tab: "mail" },
];

const DEFAULT_PATIENT_FEATURES: FeatureId[] = [
  "medication_tracker",
  "virtual_checkin",
  "symptoms_tracker",
  "usps_mail",
];

const DEFAULT_CAREGIVERS: LinkedCaregiver[] = [];

const DEFAULT_PATIENT_SNIPPETS: PatientSnippet[] = [
  { id: "ps1", name: "Eleanor Wright", age: 72, initials: "EW", grants: ["mood", "checkin_summary", "med_adherence", "upcoming_visits"], mood: 4, lastCheckin: "Today 9:00 AM", medAdherence: 91, nextVisit: "Thu 2:30 PM", hasFallAlert: false },
  { id: "ps2", name: "Rosa Martinez",  age: 81, initials: "RM", grants: ["mood", "fall_alerts", "med_adherence"], mood: 2, medAdherence: 67, hasFallAlert: true, lastCheckin: "Yesterday" },
  { id: "ps3", name: "James Nguyen",   age: 68, initials: "JN", grants: [], mood: undefined },
];

const GRANTED_LABELS: Record<GrantedItem, string> = {
  mood:            "Current mood",
  checkin_summary: "Latest check-in",
  med_adherence:   "Medication adherence",
  fall_alerts:     "Fall alerts",
  upcoming_visits: "Upcoming visits",
  symptoms:        "Symptoms summary",
};

function getTheme(mode: AppMode | null): ModeTheme {
  if (mode === "stml")     return { color: "#7C3AED", lightBg: "#F5F3FF", borderColor: "#DDD6FE", name: "STML" };
  if (mode === "dyslexia") return { color: "#0E7E57", lightBg: "#F0FDF4", borderColor: "#BBF7D0", name: "Dyslexia" };
  if (mode === "carpal")   return { color: "#B45309", lightBg: "#FFFBEB", borderColor: "#FDE68A", name: "Carpal Tunnel" };
  if (mode === "hearing")  return { color: "#0284C7", lightBg: "#E0F2FE", borderColor: "#BAE6FD", name: "Hearing" };
  return                          { color: "#00A7C8", lightBg: "#E0F7FA", borderColor: "#B2EBF2", name: "Custom" };
}

// ── Shared primitives ──────────────────────────────────────────────────────────

function Switch({
  checked, onChange, id, large = false, color = "#00A7C8",
}: {
  checked: boolean; onChange: (v: boolean) => void; id: string; large?: boolean; color?: string;
}) {
  return (
    <button
      role="switch" aria-checked={checked} id={id}
      onClick={() => onChange(!checked)}
      className={`relative inline-flex shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 ${large ? "h-9 w-16" : "h-7 w-12"}`}
      style={{ background: checked ? color : "#CBD5E1", outlineColor: color }}
    >
      <span
        className={`pointer-events-none inline-block rounded-full bg-white shadow-md transition-transform duration-200 ${large ? "h-8 w-8" : "h-6 w-6"} ${checked ? (large ? "translate-x-7" : "translate-x-5") : "translate-x-0"}`}
      />
    </button>
  );
}

// ── Voice dictation (shared) ───────────────────────────────────────────────────
// One hook powers every "speak or type" input across the app.

function useVoiceDictation(onText: (text: string) => void) {
  const [isListening, setIsListening] = useState(false);
  const [voiceError, setVoiceError] = useState<string | null>(null);
  const recognitionRef = useRef<{ stop: () => void } | null>(null);
  const onTextRef = useRef(onText);
  onTextRef.current = onText;

  useEffect(() => {
    return () => {
      try { recognitionRef.current?.stop(); } catch {}
      recognitionRef.current = null;
    };
  }, []);

  const stop = () => {
    try { recognitionRef.current?.stop(); } catch {}
    recognitionRef.current = null;
    setIsListening(false);
  };

  const toggle = () => {
    setVoiceError(null);
    const win = window as unknown as {
      SpeechRecognition?: new () => any;
      webkitSpeechRecognition?: new () => any;
    };
    const SpeechRecognitionAPI = win.SpeechRecognition || win.webkitSpeechRecognition;

    if (!SpeechRecognitionAPI) {
      setVoiceError("Voice input is not supported in this browser. Try Chrome or Edge.");
      return;
    }
    if (isListening) { stop(); return; }

    const recognition = new SpeechRecognitionAPI();
    recognition.lang = "en-US";
    recognition.interimResults = true;
    recognition.continuous = false;
    recognition.maxAlternatives = 1;

    recognition.onstart = () => setIsListening(true);
    recognition.onend = () => { setIsListening(false); recognitionRef.current = null; };
    recognition.onerror = (event: { error?: string }) => {
      setIsListening(false);
      recognitionRef.current = null;
      if (event.error === "not-allowed") {
        setVoiceError("Microphone permission is blocked. Allow mic access and try again.");
      } else if (event.error !== "aborted" && event.error !== "no-speech") {
        setVoiceError("Could not capture voice. Please try again.");
      }
    };
    recognition.onresult = (event: { resultIndex: number; results: ArrayLike<{ 0: { transcript: string } }> }) => {
      let transcript = "";
      for (let i = event.resultIndex; i < event.results.length; i++) {
        transcript += event.results[i][0].transcript;
      }
      const cleaned = transcript.trim();
      if (cleaned) onTextRef.current(cleaned);
    };

    recognitionRef.current = recognition;
    try { recognition.start(); }
    catch {
      setVoiceError("Could not start voice input. Please try again.");
      setIsListening(false);
    }
  };

  return { isListening, voiceError, toggle, stop, clearError: () => setVoiceError(null) };
}

function MicButton({ isListening, onClick, color = "#00A7C8", size = "sm" }: {
  isListening: boolean; onClick: () => void; color?: string; size?: "sm" | "md";
}) {
  const dim = size === "md" ? "w-10 h-10" : "w-8 h-8";
  return (
    <button
      type="button"
      onClick={onClick}
      className={`${dim} rounded-full flex items-center justify-center shrink-0 transition-all`}
      style={{
        background: isListening ? "#FEE2E2" : color + "1A",
        color: isListening ? "#EF4444" : color,
        border: `1.5px solid ${isListening ? "#FECACA" : color + "40"}`,
      }}
      aria-pressed={isListening}
      aria-label={isListening ? "Stop voice input" : "Start voice input"}
      title={isListening ? "Stop voice input" : "Speak instead of typing"}
    >
      <Mic size={size === "md" ? 17 : 14} className={isListening ? "animate-pulse" : undefined} />
    </button>
  );
}

/** Text field with a built-in "speak or type" mic button. */
function VoiceField({
  label, value, onChange, placeholder, multiline = false, color = "#00A7C8",
}: {
  label: string; value: string; onChange: (v: string) => void;
  placeholder?: string; multiline?: boolean; color?: string;
}) {
  const { isListening, voiceError, toggle } = useVoiceDictation(text =>
    onChange(value.trim() ? `${value.trim()} ${text}` : text)
  );
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between">
        <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">{label}</label>
        <MicButton isListening={isListening} onClick={toggle} color={color} />
      </div>
      {multiline ? (
        <textarea
          value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder} rows={3}
          className="w-full border rounded-xl px-4 py-3 text-[15px] outline-none bg-white resize-none"
          style={{ fontSize: 16, borderColor: isListening ? "#EF4444" : "#E5E7EB", background: isListening ? "#FEF2F2" : "white" }}
        />
      ) : (
        <input
          type="text" value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder}
          className="w-full border rounded-xl px-4 py-3.5 text-[15px] outline-none bg-white"
          style={{ WebkitAppearance: "none", fontSize: 16, borderColor: isListening ? "#EF4444" : "#E5E7EB", background: isListening ? "#FEF2F2" : "white" }}
        />
      )}
      {isListening && (
        <p className="text-[11px] font-semibold text-[#EF4444] flex items-center gap-1.5">
          <span className="w-2 h-2 rounded-full bg-[#EF4444] animate-pulse" /> Listening — speak now…
        </p>
      )}
      {voiceError && <p className="text-[11px] font-semibold text-[#EF4444]">{voiceError}</p>}
    </div>
  );
}

/** Compact input row with a mic — for forms that manage their own labels. */
function VoiceInput({ value, onChange, placeholder, className, color = "#00A7C8" }: {
  value: string; onChange: (v: string) => void;
  placeholder?: string; className?: string; color?: string;
}) {
  const { isListening, voiceError, toggle } = useVoiceDictation(text =>
    onChange(value.trim() ? `${value.trim()} ${text}` : text)
  );
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <input
          type="text" value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder}
          className={`${className ?? "border border-[#E5E7EB] rounded-xl px-4 py-3 text-[15px] outline-none bg-white"} flex-1 min-w-0`}
          style={{ fontSize: 16, borderColor: isListening ? "#EF4444" : undefined, background: isListening ? "#FEF2F2" : undefined }}
        />
        <MicButton isListening={isListening} onClick={toggle} color={color} />
      </div>
      {voiceError && <p className="text-[11px] font-semibold text-[#EF4444]">{voiceError}</p>}
    </div>
  );
}

function StatusBar() {
  return (
    <div className="flex-none flex items-center justify-between px-6 pt-4 pb-1 bg-white">
      <span className="text-[13px] font-semibold text-[#0F172A]">9:41</span>
      <div className="flex items-center gap-1.5">
        <div className="flex gap-0.5 items-end h-3">
          {[2, 3, 4, 5].map(h => <div key={h} className="w-1 bg-[#0F172A] rounded-sm" style={{ height: h * 2.5 }} />)}
        </div>
        <svg width="16" height="12" viewBox="0 0 16 12" fill="none">
          <path d="M8 2.5C10.2 2.5 12.2 3.4 13.7 4.9L15 3.6C13.1 1.7 10.7 0.5 8 0.5C5.3 0.5 2.9 1.7 1 3.6L2.3 4.9C3.8 3.4 5.8 2.5 8 2.5Z" fill="#0F172A" />
          <path d="M8 5.5C9.4 5.5 10.7 6.1 11.6 7L12.9 5.7C11.6 4.4 9.9 3.5 8 3.5C6.1 3.5 4.4 4.4 3.1 5.7L4.4 7C5.3 6.1 6.6 5.5 8 5.5Z" fill="#0F172A" />
          <circle cx="8" cy="10" r="1.5" fill="#0F172A" />
        </svg>
        <div className="w-5 h-2.5 rounded-sm border border-[#0F172A] p-px">
          <div className="w-full h-full bg-[#0F172A] rounded-[1px]" />
        </div>
      </div>
    </div>
  );
}

// ── Phone shell ────────────────────────────────────────────────────────────────

// On real mobile (< 640px wide): fill the viewport, no frame, no chrome.
// On desktop / preview: centered phone frame at 390×720.
function PhoneShell({
  children, topBar, bottomNav, shellBg = "bg-white", overlay, floatingAction, nav,
}: {
  children: React.ReactNode;
  topBar?: React.ReactNode;
  bottomNav?: React.ReactNode;
  shellBg?: string;
  overlay?: React.ReactNode;
  /** Non-blocking UI layered above content (e.g. SOS FAB). Must not cover the full screen. */
  floatingAction?: React.ReactNode;
  nav?: NavProps;
}) {
  return (
    // Desktop wrapper — hidden on small screens, full-viewport on mobile
    <div className="
      min-h-screen
      sm:bg-gradient-to-br sm:from-[#EFF6FF] sm:via-white sm:to-[#E0F7FA]
      sm:flex sm:items-start sm:justify-center sm:py-8 sm:px-4
    ">
      <div
        className={`
          relative flex flex-col ${shellBg}
          w-full h-screen
          sm:w-full sm:max-w-[390px] sm:h-[720px]
          sm:rounded-[2.5rem] sm:overflow-hidden sm:shadow-2xl
        `}
        style={{ boxShadow: undefined }}
      >
        {/* Status bar — only on desktop preview */}
        <div className="hidden sm:block flex-none">
          <StatusBar />
        </div>

        {/* Safe-area top spacer on real mobile (handles notch / dynamic island) */}
        <div className="sm:hidden flex-none" style={{ paddingTop: "env(safe-area-inset-top, 0px)" }} />

        {/* History nav — desktop preview only */}
        {nav && (
          <div className="hidden sm:flex flex-none items-center gap-0.5 px-3 py-1.5 bg-white border-b border-[#F3F4F6]">
            <button
              onClick={nav.onBack} disabled={!nav.canGoBack}
              className="w-8 h-8 flex items-center justify-center rounded-lg"
              style={{ color: nav.canGoBack ? "#0F172A" : "#D1D5DB" }}
              aria-label="Go back">
              <ChevronLeft size={18} />
            </button>
            <button
              onClick={nav.onForward} disabled={!nav.canGoForward}
              className="w-8 h-8 flex items-center justify-center rounded-lg"
              style={{ color: nav.canGoForward ? "#0F172A" : "#D1D5DB" }}
              aria-label="Go forward">
              <ChevronRight size={18} />
            </button>
          </div>
        )}

        {topBar && <div className="flex-none">{topBar}</div>}

        {/* Scrollable content — grows to fill remaining space */}
        <div className="flex-1 overflow-y-auto min-h-0 overscroll-contain">
          {children}
        </div>

        {bottomNav && (
          <div
            className="flex-none border-t border-[#E5E7EB]"
            style={{ paddingBottom: "env(safe-area-inset-bottom, 0px)" }}
          >
            {bottomNav}
          </div>
        )}

        {/* Home indicator — desktop preview only */}
        <div className="hidden sm:flex flex-none justify-center py-2 bg-white">
          <div className="w-28 h-1 bg-[#0F172A] rounded-full opacity-20" />
        </div>

        {/* Floating actions sit above content but do not block the rest of the screen */}
        {floatingAction}

        {overlay && (
          <div className="absolute inset-0 z-50 sm:rounded-[2.5rem] overflow-hidden bg-white flex flex-col min-h-0 h-full">
            {overlay}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Bottom nav ─────────────────────────────────────────────────────────────────

function BottomNav({ tab, onTab, color, large, onOpenProfile, profileImage }: {
  tab: Tab; onTab: (t: Tab) => void; color: string; large: boolean;
  onOpenProfile: () => void; profileImage: string | null;
}) {
  const navItems: { key: Tab; icon: React.ReactNode; label: string }[] = [
    { key: "home",     icon: <Home size={large ? 24 : 20} />,     label: "Home"     },
    { key: "schedule", icon: <Calendar size={large ? 24 : 20} />, label: "Schedule" },
    { key: "symptoms", icon: <HeartPulse size={large ? 24 : 20} />, label: "Health" },
  ];
  return (
    <div className="flex bg-white px-1 py-1">
      {navItems.map(it => (
        <button
          key={it.key}
          onClick={() => onTab(it.key)}
          className="flex-1 flex flex-col items-center justify-center gap-0.5 rounded-xl py-2 transition-all duration-150"
          style={{ minHeight: large ? 68 : 56, color: tab === it.key ? color : "#9CA3AF" }}
        >
          {it.icon}
          <span className="text-[10px] font-semibold">{it.label}</span>
        </button>
      ))}
      {/* CareConnect brand icon — decorative only */}
      <div
        className="flex-1 flex flex-col items-center justify-center gap-0.5 rounded-xl py-2"
        style={{ minHeight: large ? 68 : 56 }}
      >
        {/* CareConnect logo mark */}
        <div className="flex flex-col items-center justify-center rounded-xl"
          style={{
            width: large ? 30 : 26, height: large ? 30 : 26,
            background: color, borderRadius: 7,
          }}>
          <div className="rounded-full bg-white" style={{ width: large ? 12 : 10, height: large ? 12 : 10 }} />
          <div className="flex gap-0.5 mt-0.5">
            {[0,1,2].map(i => <div key={i} className="rounded-full bg-white/70" style={{ width: large ? 4 : 3, height: large ? 4 : 3 }} />)}
          </div>
        </div>
        <span className="text-[10px] font-semibold" style={{ color }}>Care</span>
      </div>
    </div>
  );
}

// ── App top bar ────────────────────────────────────────────────────────────────

function AppTopBar({ tab, theme, onOpenProfile, profileImage }: {
  tab: Tab; theme: ModeTheme; onOpenProfile: () => void; profileImage: string | null;
}) {
  const titles: Record<Tab, string> = {
    home: "Dashboard", schedule: "Schedule", meds: "Medications", settings: "Profile",
    symptoms: "Symptoms & Allergies", checkin: "Virtual Check-In", messages: "Messages",
    patients: "Patient List", analytics: "Analytics", profile: "My Profile",
    hearing: "Hearing Assist",
  };
  return (
    <div className="flex items-center justify-between px-4 py-3 bg-white border-b" style={{ borderColor: theme.borderColor, minHeight: 60 }}>
      <div>
        <div className="flex items-center gap-1.5 mb-0.5">
          <div className="w-2 h-2 rounded-full" style={{ background: theme.color }} />
          <p className="text-[10px] font-bold uppercase tracking-wider" style={{ color: theme.color }}>{theme.name} mode</p>
        </div>
        <h2 className="text-[18px] font-bold text-[#0F172A] leading-tight">{titles[tab]}</h2>
      </div>
      {/* Profile avatar — always visible top-right */}
      <button
        onClick={onOpenProfile}
        className="w-10 h-10 rounded-full overflow-hidden flex items-center justify-center border-2 transition-all hover:opacity-80"
        style={{ borderColor: theme.color, background: theme.lightBg }}
        aria-label="Open profile & settings"
      >
        {profileImage
          ? <img src={profileImage} className="w-full h-full object-cover" />
          : <User size={18} style={{ color: theme.color }} />}
      </button>
    </div>
  );
}

// ── Landing page (onboarding) ──────────────────────────────────────────────────

type LandingOption = {
  key: AppMode; label: string; tagline: string; description: string;
  icon: React.ReactNode; color: string; lightBg: string; borderColor: string;
  adaptations: string[];
};

const LANDING_OPTIONS: LandingOption[] = [
  { key: "stml",    label: "Short-term memory",    tagline: "Context cues & auto-save",      description: "The app carries the memory burden — breadcrumbs always show where you are, auto-save means nothing is ever lost, and a daily recap keeps you oriented throughout the day.", color: "#7C3AED", lightBg: "#F5F3FF", borderColor: "#DDD6FE", icon: <Brain size={20} />,    adaptations: ["Breadcrumb bar", "Auto-save", "Daily recap", "Step-by-step", "Activity history"] },
  { key: "dyslexia",label: "Dyslexia support",     tagline: "Less text, more clarity",       description: "Dyslexia-friendly font, generous spacing, cream tint, full text-to-speech, voice input, and plain language throughout so reading never slows you down.", color: "#0E7E57", lightBg: "#F0FDF4", borderColor: "#BBF7D0", icon: <BookOpen size={20} />, adaptations: ["Lexend font", "Read aloud", "Voice input", "Plain language", "Visual chunking"] },
  { key: "carpal",  label: "Carpal tunnel",         tagline: "Minimal effort, max reach",     description: "Oversized targets, voice control, autofill smart defaults, no timed gestures, and undo everywhere so every interaction is pain-free.", color: "#B45309", lightBg: "#FFFBEB", borderColor: "#FDE68A", icon: <Hand size={20} />,    adaptations: ["80dp+ targets", "Voice control", "Autofill", "No timed gestures", "Undo everywhere"] },
  { key: "hearing", label: "Hearing impaired",      tagline: "Visual & tactile first",        description: "Every audio cue has a visual or tactile equivalent — captions, screen flash, vibration patterns, text-chat priority, and real-time call captions.", color: "#0284C7", lightBg: "#E0F2FE", borderColor: "#BAE6FD", icon: <Ear size={20} />,     adaptations: ["Captions", "Screen flash", "Vibration", "Text chat first", "Call captions"] },
  { key: "custom",  label: "Custom / Build my own", tagline: "Mix 32 features freely",        description: "Pick any combination of features from all four modes to build a UI tailored exactly to your needs — no preset, no compromise.", color: "#00A7C8", lightBg: "#E0F7FA", borderColor: "#B2EBF2", icon: <Sliders size={20} />, adaptations: ["Any combination", "Full control", "32 features to choose"] },
];

function LandingPage({ onSelect, onSignIn, onCustomize, nav }: {
  onSelect:   (k: DisabilityKey) => void;
  onSignIn:   (k: DisabilityKey) => void;
  onCustomize: () => void;
  nav: NavProps;
}) {
  const [selectedKey, setSelectedKey] = useState<AppMode | null>(null);
  const [dropOpen, setDropOpen]       = useState(false);
  const dropRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (dropRef.current && !dropRef.current.contains(e.target as Node)) setDropOpen(false);
    };
    if (dropOpen) document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [dropOpen]);

  const selected = LANDING_OPTIONS.find(o => o.key === selectedKey) ?? null;

  const handleGetStarted = () => {
    if (!selected) return;
    if (selected.key === "custom") { onCustomize(); return; }
    onSelect(selected.key as DisabilityKey);
  };

  const handleSignIn = () => {
    if (!selected || selected.key === "custom") return;
    onSignIn(selected.key as DisabilityKey);
  };

  return (
    <PhoneShell shellBg="bg-white" nav={nav}>
      {/* Hero */}
      <div className="bg-gradient-to-br from-[#00A7C8] to-[#0087A8] px-6 pt-6 pb-7">
        <div className="flex items-center gap-2 mb-4">
          <div className="w-8 h-8 rounded-lg bg-white/20 flex items-center justify-center">
            <div className="w-4 h-4 rounded-full bg-white" />
          </div>
          <span className="text-white font-bold text-[17px] tracking-tight">CareConnect</span>
        </div>
        <h1 className="text-white font-bold leading-tight mb-1.5" style={{ fontSize: 24 }}>Your care, your way.</h1>
        <p className="text-white/80 text-[13px] leading-relaxed">Choose the accessibility profile that best fits your needs.</p>
      </div>

      <div className="px-4 pt-5 pb-6 flex flex-col gap-4">
        {/* Dropdown selector */}
        <div>
          <p className="text-[11px] font-bold uppercase tracking-wider text-[#595959] mb-2">Select your profile</p>
          <div className="relative" ref={dropRef}>
            <button
              onClick={() => setDropOpen(v => !v)}
              className="w-full flex items-center justify-between gap-3 px-4 py-3.5 rounded-2xl border-2 bg-white text-left transition-all duration-150"
              style={{ borderColor: selected ? selected.color : "#E5E7EB", minHeight: 64 }}
            >
              {selected ? (
                <div className="flex items-center gap-3 flex-1 min-w-0">
                  <div className="shrink-0 w-9 h-9 rounded-xl flex items-center justify-center"
                    style={{ background: selected.lightBg, color: selected.color }}>
                    {selected.icon}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="text-[15px] font-bold text-[#0F172A] leading-tight">{selected.label}</p>
                    <p className="text-[12px] leading-tight mt-0.5" style={{ color: selected.color }}>{selected.tagline}</p>
                  </div>
                </div>
              ) : (
                <p className="text-[15px] text-[#9CA3AF] flex-1">Choose a profile...</p>
              )}
              <ChevronDown size={18} className="shrink-0 text-[#9CA3AF] transition-transform duration-200"
                style={{ transform: dropOpen ? "rotate(180deg)" : "rotate(0deg)" }} />
            </button>

            {dropOpen && (
              <div className="absolute left-0 right-0 z-50 mt-2 rounded-2xl border border-[#E5E7EB] bg-white overflow-hidden"
                style={{ boxShadow: "0 12px 32px rgba(0,0,0,0.12)" }}>
                {LANDING_OPTIONS.map((opt, i) => {
                  const isSel = opt.key === selectedKey;
                  return (
                    <button
                      key={opt.key}
                      onClick={() => { setSelectedKey(opt.key); setDropOpen(false); }}
                      className={`w-full flex items-center gap-3 px-4 py-3.5 text-left transition-colors duration-100 ${i > 0 ? "border-t border-[#F3F4F6]" : ""}`}
                      style={{ background: isSel ? opt.lightBg : "white", minHeight: 60 }}
                    >
                      <div className="shrink-0 w-9 h-9 rounded-xl flex items-center justify-center"
                        style={{ background: isSel ? opt.color : opt.lightBg, color: isSel ? "white" : opt.color }}>
                        {isSel ? <Check size={16} /> : opt.icon}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-[14px] font-semibold text-[#0F172A] leading-tight">{opt.label}</p>
                        <p className="text-[11px] leading-tight mt-0.5" style={{ color: opt.color }}>{opt.tagline}</p>
                      </div>
                      {isSel && <Check size={15} style={{ color: opt.color }} className="shrink-0" />}
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        </div>

        {/* Description + adaptations */}
        {selected && (
          <div className="rounded-2xl p-4 border-2 transition-all duration-200"
            style={{ borderColor: selected.borderColor, background: selected.lightBg }}>
            <p className="text-[13px] text-[#374151] leading-relaxed mb-3">{selected.description}</p>
            <div className="flex flex-wrap gap-1.5">
              {selected.adaptations.map(a => (
                <span key={a} className="text-[10px] font-semibold px-2.5 py-1 rounded-full"
                  style={{ background: "white", color: selected.color, border: `1px solid ${selected.borderColor}` }}>
                  {a}
                </span>
              ))}
            </div>
          </div>
        )}

        {/* Action buttons */}
        <div className="flex flex-col gap-2.5">
          <button
            onClick={handleGetStarted}
            disabled={!selected}
            className="w-full flex items-center justify-center gap-2 py-4 rounded-2xl font-bold text-[16px] transition-all duration-150 active:scale-[0.98]"
            style={{
              background: selected ? selected.color : "#E5E7EB",
              color: selected ? "white" : "#9CA3AF",
              minHeight: 56,
            }}>
            {selected?.key === "custom" ? (
              <><Sliders size={18} /> Build my settings</>
            ) : selected ? (
              <><Sparkles size={18} /> Get started · {selected.label}</>
            ) : "Select a profile above"}
          </button>

          {selected && selected.key !== "custom" && (
            <button
              onClick={handleSignIn}
              className="w-full flex items-center justify-center gap-2 py-3.5 rounded-2xl font-semibold text-[14px] border-2 transition-all duration-150 hover:opacity-80"
              style={{ borderColor: selected.color, color: selected.color, background: "white", minHeight: 48 }}>
              <User size={15} /> Sign in to {selected.label} mode
            </button>
          )}
        </div>

        {/* Helper hint */}
        {!selected && (
          <p className="text-center text-[12px] text-[#9CA3AF]">
            Open the dropdown above to choose your profile
          </p>
        )}
      </div>
    </PhoneShell>
  );
}

// ── Feature builder (reusable) ─────────────────────────────────────────────────

function FeatureBuilder({
  settings, onChange, defaultOpenCategory = null,
}: {
  settings: CustomSettings;
  onChange: (s: CustomSettings) => void;
  /** When set, that category starts expanded; others stay collapsed. */
  defaultOpenCategory?: DisabilityKey | null;
}) {
  const toggle = (id: string) => onChange({ ...settings, [id]: !settings[id] });
  const categories = (["stml", "dyslexia", "carpal", "hearing"] as DisabilityKey[]);

  const initialOpen = () => {
    const open: Record<string, boolean> = {};
    for (const cat of categories) {
      const features = ALL_FEATURES.filter(f => f.category === cat);
      const activeN = features.filter(f => settings[f.id]).length;
      // Expand matching mode, or any group that already has features on
      open[cat] = defaultOpenCategory === cat || (defaultOpenCategory == null && activeN > 0);
    }
    // If nothing would be open, leave all collapsed
    return open;
  };

  const [openCats, setOpenCats] = useState<Record<string, boolean>>(initialOpen);

  const toggleCat = (cat: DisabilityKey) => {
    setOpenCats(prev => ({ ...prev, [cat]: !prev[cat] }));
  };

  return (
    <div className="flex flex-col gap-2">
      {categories.map(cat => {
        const meta     = CAT_META[cat];
        const features = ALL_FEATURES.filter(f => f.category === cat);
        const activeN  = features.filter(f => settings[f.id]).length;
        const isOpen   = !!openCats[cat];
        const emoji    = cat === "stml" ? "🧠" : cat === "dyslexia" ? "📖" : cat === "carpal" ? "✋" : "👂";

        return (
          <div key={cat} className="rounded-2xl overflow-hidden border-2" style={{ borderColor: meta.borderColor }}>
            <button
              type="button"
              onClick={() => toggleCat(cat)}
              className="w-full flex items-center gap-2 px-4 py-3 text-left transition-colors"
              style={{ background: meta.lightBg }}
              aria-expanded={isOpen}
            >
              <div className="w-7 h-7 rounded-lg flex items-center justify-center shrink-0" style={{ background: meta.color, color: "white" }}>
                {meta.icon}
              </div>
              <span className="text-[16px] shrink-0" aria-hidden>{emoji}</span>
              <div className="flex-1 min-w-0">
                <span className="text-[13px] font-bold uppercase tracking-wider" style={{ color: meta.color }}>{meta.label}</span>
                <p className="text-[11px] text-[#6B7280] mt-0.5">
                  {activeN > 0 ? `${activeN} feature${activeN === 1 ? "" : "s"} on` : "No features on"}
                  {" · "}
                  {isOpen ? "Tap to collapse" : "Tap to expand"}
                </p>
              </div>
              <span className="text-[11px] font-bold px-2 py-0.5 rounded-full shrink-0"
                style={{ background: "white", color: meta.color, border: `1px solid ${meta.borderColor}` }}>
                {activeN}/{features.length}
              </span>
              <ChevronDown
                size={18}
                className="shrink-0 transition-transform duration-200"
                style={{
                  color: meta.color,
                  transform: isOpen ? "rotate(180deg)" : "rotate(0deg)",
                }}
              />
            </button>

            {isOpen && features.map((feat, idx) => {
              const on = !!settings[feat.id];
              return (
                <div key={feat.id}
                  className={`flex items-center gap-3 px-4 py-3 bg-white ${idx < features.length - 1 ? "border-b" : ""}`}
                  style={{ borderColor: meta.borderColor, minHeight: 64 }}
                >
                  <button type="button" role="checkbox" aria-checked={on}
                    onClick={() => toggle(feat.id)}
                    className="shrink-0 w-6 h-6 rounded-md border-2 flex items-center justify-center transition-all duration-150"
                    style={{ borderColor: on ? meta.color : "#CBD5E1", background: on ? meta.color : "white" }}
                  >
                    {on && <Check size={13} color="white" strokeWidth={3} />}
                  </button>
                  <div className="flex-1 min-w-0 cursor-pointer" onClick={() => toggle(feat.id)}>
                    <p className="text-[14px] font-semibold text-[#0F172A] leading-snug">{feat.label}</p>
                    <p className="text-[12px] text-[#595959] leading-snug mt-0.5">{feat.description}</p>
                  </div>
                  {on && (
                    <span className="shrink-0 text-[10px] font-bold uppercase px-2 py-0.5 rounded-full"
                      style={{ background: meta.lightBg, color: meta.color }}>ON</span>
                  )}
                </div>
              );
            })}
          </div>
        );
      })}
    </div>
  );
}

function settingsForMode(mode: AppMode | null): CustomSettings {
  const settings: CustomSettings = {};
  if (mode && mode !== "custom") {
    ALL_FEATURES
      .filter(feature => feature.category === mode)
      .forEach(feature => { settings[feature.id] = true; });
  }
  return settings;
}

function AccessibilityModeCustomizer({
  mode, setMode, customSettings, setCustomSettings, theme,
}: {
  mode: AppMode | null;
  setMode: (m: AppMode) => void;
  customSettings: CustomSettings;
  setCustomSettings: (s: CustomSettings) => void;
  theme: ModeTheme;
}) {
  const activeSettings = mode === "custom" ? customSettings : settingsForMode(mode);
  const activeCount = Object.values(activeSettings).filter(Boolean).length;
  const [featuresOpen, setFeaturesOpen] = useState(false);

  const activeByCategory = (["stml", "dyslexia", "carpal", "hearing"] as DisabilityKey[])
    .map(cat => {
      const meta = CAT_META[cat];
      const features = ALL_FEATURES.filter(f => f.category === cat && activeSettings[f.id]);
      return { cat, meta, features };
    })
    .filter(g => g.features.length > 0);

  const chooseMode = (nextMode: AppMode) => {
    if (nextMode === "custom") {
      setCustomSettings(activeCount > 0 ? activeSettings : customSettings);
    } else {
      setCustomSettings(settingsForMode(nextMode));
    }
    setMode(nextMode);
  };

  const customize = (nextSettings: CustomSettings) => {
    setCustomSettings(nextSettings);
    setMode("custom");
  };

  const openCategory: DisabilityKey | null =
    mode === "stml" || mode === "dyslexia" || mode === "carpal" || mode === "hearing"
      ? mode
      : null;

  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-2xl bg-white border border-[#E5E7EB] overflow-hidden">
        <div className="px-4 py-3 border-b border-[#F3F4F6]">
          <p className="text-[12px] font-bold text-[#9CA3AF] uppercase tracking-wider">Accessibility mode</p>
          <p className="text-[13px] text-[#6B7280] mt-1">
            Pick a preset or customize individual accessibility features below.
          </p>
        </div>
        <div className="grid grid-cols-2 gap-2 p-3">
          {PROFILES.map(p => (
            <button key={p.key} onClick={() => chooseMode(p.key)}
              className="flex items-center gap-2 px-3 py-2.5 rounded-xl border-2 transition-all text-left"
              style={{ borderColor: mode === p.key ? p.color : "#E5E7EB", background: mode === p.key ? p.lightBg : "white" }}>
              <span className="text-[16px]">{p.key === "stml" ? "🧠" : p.key === "dyslexia" ? "📖" : p.key === "carpal" ? "✋" : "👂"}</span>
              <span className="text-[12px] font-semibold" style={{ color: mode === p.key ? p.color : "#6B7280" }}>{p.abbr}</span>
            </button>
          ))}
          <button onClick={() => chooseMode("custom")}
            className="col-span-2 flex items-center justify-center gap-2 px-3 py-3 rounded-xl border-2 transition-all"
            style={{ borderColor: mode === "custom" ? theme.color : "#E5E7EB", background: mode === "custom" ? theme.lightBg : "white", color: mode === "custom" ? theme.color : "#6B7280" }}>
            <Sliders size={15} />
            <span className="text-[13px] font-bold">Custom mode</span>
            <span className="text-[11px] font-semibold">({activeCount} active)</span>
          </button>
        </div>
      </div>

      {/* Currently in use — collapsed dropdown summary */}
      <div className="rounded-2xl bg-white border border-[#E5E7EB] overflow-hidden">
        <button
          type="button"
          onClick={() => setFeaturesOpen(o => !o)}
          className="w-full flex items-center gap-3 px-4 py-3.5 text-left"
          aria-expanded={featuresOpen}
        >
          <div className="w-9 h-9 rounded-xl flex items-center justify-center shrink-0"
            style={{ background: theme.lightBg, color: theme.color }}>
            <Sliders size={16} />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-[13px] font-bold text-[#0F172A]">Accessibility features in use</p>
            <p className="text-[11px] text-[#6B7280] mt-0.5">
              {activeCount === 0
                ? "None selected — expand to customize"
                : `${activeCount} active across ${activeByCategory.length || 1} mode${activeByCategory.length === 1 ? "" : "s"}`}
            </p>
          </div>
          <ChevronDown
            size={18}
            className="text-[#9CA3AF] shrink-0 transition-transform duration-200"
            style={{ transform: featuresOpen ? "rotate(180deg)" : "rotate(0deg)" }}
          />
        </button>

        {featuresOpen && (
          <div className="px-3 pb-3 flex flex-col gap-3 border-t border-[#F3F4F6] pt-3">
            {activeByCategory.length > 0 && (
              <div className="px-3 py-2.5 rounded-xl bg-[#F9FAFB] border border-[#E5E7EB]">
                <p className="text-[10px] font-bold uppercase tracking-wider text-[#9CA3AF] mb-2">Currently on</p>
                <div className="flex flex-col gap-2">
                  {activeByCategory.map(({ cat, meta, features }) => (
                    <div key={cat}>
                      <p className="text-[11px] font-bold mb-1" style={{ color: meta.color }}>{meta.label}</p>
                      <div className="flex flex-wrap gap-1.5">
                        {features.map(f => (
                          <span key={f.id} className="text-[10px] font-semibold px-2 py-0.5 rounded-full"
                            style={{ background: meta.lightBg, color: meta.color, border: `1px solid ${meta.borderColor}` }}>
                            {f.label}
                          </span>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <p className="text-[11px] text-[#6B7280] px-1">
              Expand a category below to turn features on or off. Changes switch you into Custom mode.
            </p>

            <FeatureBuilder
              settings={activeSettings}
              onChange={customize}
              defaultOpenCategory={openCategory}
            />
          </div>
        )}
      </div>
    </div>
  );
}

// ── Standalone custom builder page (onboarding) ────────────────────────────────

function CustomBuilderPage({ initialSettings, onBack, onApply, nav }: {
  initialSettings: CustomSettings;
  onBack: () => void;
  onApply: (s: CustomSettings) => void;
  nav: NavProps;
}) {
  const [settings, setSettings] = useState<CustomSettings>(initialSettings);
  const activeCount = Object.values(settings).filter(Boolean).length;

  return (
    <PhoneShell shellBg="bg-[#F8FAFC]" nav={nav}
      topBar={
        <div className="flex items-center gap-3 px-4 py-3 bg-white border-b border-[#E5E7EB]" style={{ minHeight: 60 }}>
          <button onClick={onBack} className="w-10 h-10 rounded-full flex items-center justify-center hover:bg-[#F3F4F6] transition-colors">
            <ArrowLeft size={22} className="text-[#0F172A]" />
          </button>
          <div className="flex-1 min-w-0">
            <p className="text-[11px] font-semibold uppercase tracking-wider text-[#00A7C8]">Custom Mode</p>
            <h2 className="text-[18px] font-bold text-[#0F172A] leading-tight">Build your UI</h2>
          </div>
          <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#E0F7FA]">
            <Sliders size={12} className="text-[#00A7C8]" />
            <span className="text-[12px] font-bold text-[#00A7C8]">{activeCount} on</span>
          </div>
        </div>
      }
    >
      <div className="px-4 pt-4 pb-4 flex flex-col gap-3">
        <p className="text-[13px] text-[#595959] leading-relaxed">
          Mix and match individual features from all three accessibility modes. Every combination creates a UI tailored exactly to you.
        </p>

        <FeatureBuilder settings={settings} onChange={setSettings} />

        {/* Active summary */}
        {activeCount > 0 && (
          <div className="p-4 rounded-2xl border border-[#E5E7EB] bg-white">
            <p className="text-[11px] font-bold uppercase tracking-wider text-[#00A7C8] mb-2">Your selection</p>
            <div className="flex flex-wrap gap-1.5">
              {ALL_FEATURES.filter(f => settings[f.id]).map(f => {
                const m = CAT_META[f.category];
                return (
                  <span key={f.id} className="text-[11px] font-medium px-2 py-1 rounded-full"
                    style={{ background: m.lightBg, color: m.color, border: `1px solid ${m.borderColor}` }}>
                    {f.label}
                  </span>
                );
              })}
            </div>
          </div>
        )}

        <button
          onClick={() => onApply(settings)}
          disabled={activeCount === 0}
          className="w-full flex items-center justify-center gap-2 py-4 rounded-2xl font-bold text-[16px] transition-all duration-150"
          style={{ background: activeCount > 0 ? "#00A7C8" : "#E5E7EB", color: activeCount > 0 ? "white" : "#9CA3AF", minHeight: 64 }}
        >
          <Sparkles size={18} />
          {activeCount > 0 ? `Apply ${activeCount} feature${activeCount !== 1 ? "s" : ""}` : "Select at least one feature"}
        </button>
      </div>
    </PhoneShell>
  );
}

// ── Home tab content ───────────────────────────────────────────────────────────

function HomeContent({
  mode, customSettings, tint, setTint, readAloud, setReadAloud,
  voice, setVoice, swipe, setSwipe, medsReminder, setMedsReminder,
  apptReminder, setApptReminder, stepsDone, setStepsDone, onGoSettings,
  captions, setCaptions, visualAlerts, setVisualAlerts, vibration, setVibration,
  medications, medsChecked, setMedsChecked, onMessageProvider, providerName,
  onOpenHearingAssist, appointments, setAppointments, setModal, clearModal, useLargeSchedule,
  onOpenCheckin,
}: {
  mode: AppMode | null; customSettings: CustomSettings;
  tint: boolean; setTint: (v: boolean) => void;
  readAloud: boolean; setReadAloud: (v: boolean) => void;
  voice: boolean; setVoice: (v: boolean) => void;
  swipe: boolean; setSwipe: (v: boolean) => void;
  medsReminder: boolean; setMedsReminder: (v: boolean) => void;
  apptReminder: boolean; setApptReminder: (v: boolean) => void;
  stepsDone: number; setStepsDone: (n: number) => void;
  onGoSettings: () => void;
  captions: boolean; setCaptions: (v: boolean) => void;
  visualAlerts: boolean; setVisualAlerts: (v: boolean) => void;
  vibration: boolean; setVibration: (v: boolean) => void;
  medications: Medication[];
  medsChecked: Record<string, boolean>;
  setMedsChecked: (v: Record<string, boolean>) => void;
  onMessageProvider: () => void;
  providerName: string;
  onOpenHearingAssist?: () => void;
  appointments: Appointment[];
  setAppointments: (v: Appointment[]) => void;
  setModal: (node: React.ReactNode) => void;
  clearModal: () => void;
  useLargeSchedule: boolean;
  onOpenCheckin?: () => void;
}) {
  const has = (id: string) => mode === "custom" ? !!customSettings[id] : false;
  const isStml    = mode === "stml";
  const isDys     = mode === "dyslexia";
  const isCarpal  = mode === "carpal";
  const isHearing = mode === "hearing";

  const useRemind      = isStml || has("stml_reminders");
  const useSteps       = isStml || has("stml_steps");
  const useIcons       = isStml || has("stml_icons");
  const useBreadcrumb  = isStml || has("stml_breadcrumb");
  const useAutosave    = isStml || has("stml_autosave");
  const useRecap       = isStml || has("stml_recap");
  const useHistory     = isStml || has("stml_history");
  const useTint        = (isDys && tint) || (mode === "custom" && !!customSettings["dys_tint"]);
  const useLexend      = isDys || has("dys_font");
  const useVoice       = (isCarpal && voice) || has("ct_voice") || has("dys_voice");
  const useLarge       = isCarpal || has("ct_targets");
  const useUndo        = isCarpal || has("ct_undo");
  const useAutofill    = isCarpal || has("ct_autofill");
  const useNoTimed     = isCarpal || has("ct_notimed");
  const showDysAids    = isDys || has("dys_tint") || has("dys_readaloud") || has("dys_tts") || has("dys_plainlang") || has("dys_voice") || has("dys_chunking");
  const showStmlPanel  = isStml || useRemind || useSteps || useBreadcrumb;
  const showCarpalPanel= isCarpal || useLarge || useVoice || useUndo || useAutofill;
  const showHearing    = isHearing || has("hear_captions") || has("hear_flash") || has("hear_vibration") || has("hear_chat") || has("hear_badges") || has("hear_realtime") || has("hear_transcripts");

  const primaryColor = isStml ? "#7C3AED" : isDys ? "#0E7E57" : isCarpal ? "#B45309" : isHearing ? "#0284C7" : "#00A7C8";
  const cardBg = useTint ? "#FFFBDB" : "#F9FAFB";
  const minH = useLarge ? 80 : 64;

  const noFeatures = mode === "custom" && Object.values(customSettings).every(v => !v);

  const takenCount = medications.filter(m => !!medsChecked[m.id]).length;
  const toggleMedTaken = (id: string) => {
    setMedsChecked({ ...medsChecked, [id]: !medsChecked[id] });
  };

  const [sectionOpen, setSectionOpen] = useState<Record<string, boolean>>({});
  const bpMed = medications.find(m => /lisinopril/i.test(m.name)) ?? medications[0];
  const bpTaken = bpMed ? !!medsChecked[bpMed.id] : false;
  const [bpReminderVisible, setBpReminderVisible] = useState(true);
  const [bpReminderPulse, setBpReminderPulse] = useState(0);
  const [bpNextAlertAt, setBpNextAlertAt] = useState(() => Date.now());

  useEffect(() => {
    if (useRemind && !medsReminder) setMedsReminder(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [useRemind]);

  // Persistent STML med reminder: re-alert every 5 minutes until marked Done / taken
  useEffect(() => {
    if (!useRemind || !medsReminder || bpTaken) return;
    const tick = () => {
      const now = Date.now();
      if (now >= bpNextAlertAt) {
        setBpReminderVisible(true);
        setBpReminderPulse(p => p + 1);
        setBpNextAlertAt(now + 5 * 60 * 1000);
      }
    };
    tick();
    const id = window.setInterval(tick, 15_000);
    return () => window.clearInterval(id);
  }, [useRemind, bpTaken, bpNextAlertAt]);

  useEffect(() => {
    if (bpTaken) setBpReminderVisible(false);
  }, [bpTaken]);

  const completeBpReminder = () => {
    if (bpMed) setMedsChecked({ ...medsChecked, [bpMed.id]: true });
    setBpReminderVisible(false);
  };

  const todaysMedsCard = (
    <div className="rounded-2xl bg-white border border-[#E5E7EB] overflow-hidden">
      <div className="flex items-center justify-between px-4 py-2.5 border-b border-[#F3F4F6]">
        <div className="flex items-center gap-2">
          <Pill size={15} style={{ color: "#00A7C8" }} />
          <p className="text-[12px] font-bold uppercase tracking-wider text-[#6B7280]">Medications today</p>
        </div>
        <span className="text-[11px] font-semibold text-[#00A7C8]">
          {takenCount} of {medications.length} taken
        </span>
      </div>
      {medications.length === 0 ? (
        <p className="px-4 py-4 text-[13px] text-[#9CA3AF]">No medications scheduled for today.</p>
      ) : medications.map(med => {
        const done = !!medsChecked[med.id];
        return (
          <button
            key={med.id}
            type="button"
            onClick={() => toggleMedTaken(med.id)}
            className="w-full flex items-center gap-3 px-4 py-3 border-b border-[#F9FAFB] last:border-0 text-left hover:bg-[#F9FAFB] transition-colors"
            aria-pressed={done}
            aria-label={done ? `Mark ${med.name} as not taken` : `Verify ${med.name} as taken`}
          >
            <div className="w-7 h-7 rounded-full flex items-center justify-center shrink-0 transition-colors"
              style={{ background: done ? "#00A7C8" : "#F3F4F6", border: `2px solid ${done ? "#00A7C8" : "#E5E7EB"}` }}>
              {done && <Check size={13} color="white" strokeWidth={3} />}
            </div>
            <div className="flex-1 min-w-0">
              <p className={`text-[13px] font-semibold ${done ? "text-[#6B7280] line-through" : "text-[#0F172A]"}`}>
                {med.name} {med.dose}
              </p>
              <p className="text-[11px] text-[#9CA3AF]">{med.time} · {med.purpose}</p>
            </div>
            {done ? (
              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#D1FAE5] text-[#059669]">Taken ✓</span>
            ) : (
              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#FEF3C7] text-[#D97706]">Tap to verify</span>
            )}
          </button>
        );
      })}
      <p className="px-4 py-2 text-[11px] text-[#9CA3AF] bg-[#F9FAFB]">
        Tap a medication to mark it as taken or undo.
      </p>
    </div>
  );

  const providerCard = (
    <div className="rounded-2xl bg-white border border-[#E5E7EB] p-4">
      <div className="flex items-center gap-2 mb-3">
        <Stethoscope size={15} style={{ color: "#00A7C8" }} />
        <p className="text-[12px] font-bold uppercase tracking-wider text-[#6B7280]">Primary care provider</p>
      </div>
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-full flex items-center justify-center shrink-0 text-white font-bold text-[14px]" style={{ background: "#00A7C8" }}>SP</div>
        <div className="flex-1 min-w-0">
          <p className="text-[14px] font-bold text-[#0F172A] truncate">{providerName || "Dr. Sarah Patel, MD"}</p>
          <p className="text-[12px] text-[#6B7280]">Internal Medicine</p>
        </div>
        <button
          type="button"
          onClick={onMessageProvider}
          className="px-3 py-2 rounded-xl text-[12px] font-semibold text-white flex items-center gap-1.5 shrink-0"
          style={{ background: "#00A7C8" }}
          aria-label={`Message ${providerName || "primary care provider"}`}
        >
          <MessageCircle size={13} /> Message
        </button>
      </div>
    </div>
  );

  // Default dashboard cards — shown when no accessibility mode is active
  const defaultDashboard = !isStml && !isDys && !isCarpal && !isHearing && mode !== "custom" ? (
    <div className="flex flex-col gap-3 mb-1">
      {/* Greeting */}
      <div className="rounded-2xl p-4 text-white" style={{ background: "linear-gradient(135deg, #00A7C8 0%, #008DA8 100%)" }}>
        <p className="text-[11px] font-bold uppercase tracking-wider opacity-80 mb-0.5">Good morning</p>
        <p className="text-[20px] font-bold leading-tight mb-3">Ready for today?</p>
        <div className="flex gap-2">
          <div className="flex-1 bg-white/20 rounded-xl px-3 py-2 text-center">
            <p className="text-[22px] font-bold">{medications.length}</p>
            <p className="text-[10px] opacity-80">Meds today</p>
          </div>
          <div className="flex-1 bg-white/20 rounded-xl px-3 py-2 text-center">
            <p className="text-[22px] font-bold">1</p>
            <p className="text-[10px] opacity-80">Appointment</p>
          </div>
          <div className="flex-1 bg-white/20 rounded-xl px-3 py-2 text-center">
            <p className="text-[22px] font-bold">{takenCount}</p>
            <p className="text-[10px] opacity-80">Meds taken</p>
          </div>
        </div>
      </div>

      <CollapsibleSection
        id="home-meds"
        title="Medications today"
        subtitle={`${takenCount} of ${medications.length} taken · tap to expand`}
        icon={<Pill size={14} style={{ color: primaryColor }} />}
        accent={primaryColor}
        openMap={sectionOpen}
        setOpenMap={setSectionOpen}
      >
        <div className="-mx-1">{todaysMedsCard}</div>
      </CollapsibleSection>

      {/* Next appointment */}
      <CollapsibleSection
        id="home-next-appt"
        title="Next appointment"
        subtitle="Dr. Sarah Patel · 2:30 PM"
        icon={<Calendar size={14} style={{ color: primaryColor }} />}
        accent={primaryColor}
        openMap={sectionOpen}
        setOpenMap={setSectionOpen}
      >
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-xl flex flex-col items-center justify-center shrink-0" style={{ background: "#E0F7FA" }}>
            <p className="text-[11px] font-bold text-[#00A7C8] leading-tight">JUL</p>
            <p className="text-[18px] font-bold text-[#00A7C8] leading-tight">24</p>
          </div>
          <div className="flex-1">
            <p className="text-[14px] font-bold text-[#0F172A]">Dr. Sarah Patel</p>
            <p className="text-[12px] text-[#6B7280]">Primary Care · 2:30 PM</p>
            <p className="text-[11px] text-[#9CA3AF]">CareConnect Medical Center</p>
          </div>
          <span className="text-[10px] font-bold px-2 py-1 rounded-full bg-[#D1FAE5] text-[#059669]">Confirmed</span>
        </div>
      </CollapsibleSection>

      <CollapsibleSection
        id="home-provider"
        title="Primary care provider"
        subtitle={providerName || "Dr. Sarah Patel, MD"}
        icon={<Stethoscope size={14} style={{ color: primaryColor }} />}
        accent={primaryColor}
        openMap={sectionOpen}
        setOpenMap={setSectionOpen}
      >
        <div className="-mx-1">{providerCard}</div>
      </CollapsibleSection>

      {medsReminder && (
        <div className="rounded-2xl p-3.5 flex items-center gap-3 border" style={{ background: "#E0F7FA", borderColor: "#B2EBF2" }}>
          <Bell size={16} style={{ color: "#00A7C8" }} />
          <p className="text-[13px] font-semibold flex-1" style={{ color: "#007A96" }}>
            Medication reminder: <span className="font-bold">Atorvastatin 20mg</span> at 8:00 PM
          </p>
          <button onClick={() => setMedsReminder(false)} className="text-[11px] font-bold px-2 py-1 rounded-lg" style={{ background: "#00A7C8", color: "white" }}>Dismiss</button>
        </div>
      )}

      <CollapsibleSection
        id="home-schedule"
        title="Schedule"
        subtitle="Upcoming appointments · tap to expand"
        icon={<Calendar size={14} style={{ color: primaryColor }} />}
        accent={primaryColor}
        openMap={sectionOpen}
        setOpenMap={setSectionOpen}
      >
        <div className="-mx-4 -mb-1">
          <ScheduleContent
            theme={{ color: primaryColor, lightBg: "#E0F7FA", borderColor: "#B2EBF2", name: "CareConnect" }}
            useLarge={useLargeSchedule}
            appointments={appointments}
            setAppointments={setAppointments}
            setModal={setModal}
            clearModal={clearModal}
          />
        </div>
      </CollapsibleSection>

      {onOpenCheckin && (
        <button
          type="button"
          onClick={onOpenCheckin}
          className="rounded-2xl p-4 flex items-center gap-3 border border-[#E5E7EB] bg-white text-left"
        >
          <Stethoscope size={18} style={{ color: primaryColor }} />
          <div className="flex-1">
            <p className="text-[14px] font-bold text-[#0F172A]">Virtual Check-In</p>
            <p className="text-[12px] text-[#6B7280]">Tap to open check-in</p>
          </div>
          <ChevronRight size={16} className="text-[#D1D5DB]" />
        </button>
      )}
    </div>
  ) : (
    // Accessibility modes still get meds + provider messaging + schedule on the dashboard
    <div className="flex flex-col gap-3 mb-1">
      <CollapsibleSection
        id="home-meds-a11y"
        title="Medications today"
        subtitle={`${takenCount} of ${medications.length} taken · tap to expand`}
        icon={<Pill size={14} style={{ color: primaryColor }} />}
        accent={primaryColor}
        openMap={sectionOpen}
        setOpenMap={setSectionOpen}
      >
        <div className="-mx-1">{todaysMedsCard}</div>
      </CollapsibleSection>
      <CollapsibleSection
        id="home-provider-a11y"
        title="Primary care provider"
        subtitle={providerName || "Dr. Sarah Patel, MD"}
        icon={<Stethoscope size={14} style={{ color: primaryColor }} />}
        accent={primaryColor}
        openMap={sectionOpen}
        setOpenMap={setSectionOpen}
      >
        <div className="-mx-1">{providerCard}</div>
      </CollapsibleSection>
      <CollapsibleSection
        id="home-schedule-a11y"
        title="Schedule"
        subtitle="Upcoming appointments · tap to expand"
        icon={<Calendar size={14} style={{ color: primaryColor }} />}
        accent={primaryColor}
        openMap={sectionOpen}
        setOpenMap={setSectionOpen}
      >
        <div className="-mx-4 -mb-1">
          <ScheduleContent
            theme={{ color: primaryColor, lightBg: "#E0F7FA", borderColor: "#B2EBF2", name: "CareConnect" }}
            useLarge={useLargeSchedule}
            appointments={appointments}
            setAppointments={setAppointments}
            setModal={setModal}
            clearModal={clearModal}
          />
        </div>
      </CollapsibleSection>
      {onOpenCheckin && (
        <button
          type="button"
          onClick={onOpenCheckin}
          className="rounded-2xl p-4 flex items-center gap-3 border border-[#E5E7EB] bg-white text-left"
        >
          <Stethoscope size={18} style={{ color: primaryColor }} />
          <div className="flex-1">
            <p className="text-[14px] font-bold text-[#0F172A]">Virtual Check-In</p>
            <p className="text-[12px] text-[#6B7280]">Tap to open check-in</p>
          </div>
          <ChevronRight size={16} className="text-[#D1D5DB]" />
        </button>
      )}
    </div>
  );

  if (noFeatures) {
    return (
      <div className="px-4 pt-4 pb-4 flex flex-col gap-3">
        {defaultDashboard}
        <div className="flex flex-col items-center justify-center gap-4 text-center p-6 rounded-2xl bg-white border border-[#E5E7EB]">
          <div className="w-12 h-12 rounded-2xl bg-[#E0F7FA] flex items-center justify-center">
            <Sliders size={22} className="text-[#00A7C8]" />
          </div>
          <div>
            <p className="text-[16px] font-bold text-[#0F172A] mb-1">No accessibility features active</p>
            <p className="text-[13px] text-[#595959] leading-relaxed">Turn on features that help you in Settings.</p>
          </div>
          <button onClick={onGoSettings}
            className="px-5 py-2.5 rounded-xl bg-[#00A7C8] text-white font-semibold text-[14px]">
            Go to Settings
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="px-4 pt-4 pb-4 flex flex-col gap-3">
      {defaultDashboard}

      {/* ── STML: Breadcrumb context bar ── */}
      {useBreadcrumb && (
        <div className="rounded-xl px-4 py-2.5 flex items-center gap-2.5 border border-[#DDD6FE]" style={{ background: "#F5F3FF" }}>
          <div className="w-2 h-2 rounded-full bg-[#7C3AED] shrink-0" />
          <p className="text-[12px] font-semibold text-[#7C3AED] leading-tight flex-1">
            You&apos;re on: <span className="font-bold">Home Dashboard</span>
          </p>
          {useAutosave && (
            <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#7C3AED] text-white shrink-0">Auto-saved</span>
          )}
        </div>
      )}

      {/* ── STML: Persistent reminder banner ── */}
      {useRemind && medsReminder && bpReminderVisible && !bpTaken && (
        <div
          key={bpReminderPulse}
          className="rounded-2xl p-4 flex items-start gap-3 text-white"
          style={{ background: "#7C3AED", boxShadow: bpReminderPulse > 0 ? "0 0 0 3px rgba(124,58,237,0.35)" : undefined }}
        >
          <Bell size={20} className="shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="text-[11px] font-bold uppercase tracking-wide opacity-80">Right now · repeats every 5 min</p>
            <p className="text-[16px] font-bold leading-snug">Take your blood pressure medication</p>
            <p className="text-[12px] opacity-80 mt-1">
              {bpMed ? `${bpMed.name} ${bpMed.dose}` : "Lisinopril 10mg"} · kitchen cabinet
            </p>
          </div>
          <div className="flex flex-col gap-1.5 shrink-0">
            <button
              type="button"
              onClick={completeBpReminder}
              className="px-2.5 py-1.5 rounded-lg bg-white text-[11px] font-bold text-[#7C3AED]"
            >
              Done
            </button>
            <button
              type="button"
              onClick={() => {
                setBpReminderVisible(false);
                setBpNextAlertAt(Date.now() + 5 * 60 * 1000);
              }}
              className="px-2.5 py-1.5 rounded-lg bg-white/20 text-[11px] font-bold"
            >
              Snooze
            </button>
          </div>
        </div>
      )}

      {/* ── STML: Step-by-step checklist ── */}
      {useSteps && (
        <div className="rounded-2xl overflow-hidden border border-[#DDD6FE] bg-white">
          <div className="flex items-center justify-between px-4 pt-4 pb-2">
            <p className="text-[11px] font-bold uppercase tracking-wider text-[#7C3AED]">Today&apos;s steps</p>
            <span className="text-[11px] font-semibold text-[#595959]">{stepsDone}/3 done</span>
          </div>
          <div className="mx-4 mb-3 h-2 rounded-full bg-[#EDE9FE] overflow-hidden">
            <div className="h-full rounded-full bg-[#7C3AED] transition-all duration-500" style={{ width: `${(stepsDone / 3) * 100}%` }} />
          </div>
          {[
            { label: useIcons ? "💊  Morning medication" : "Morning medication", time: "8:00 AM" },
            { label: useIcons ? "🩺  Blood pressure check" : "Blood pressure check", time: "10:00 AM" },
            { label: useIcons ? "📅  Dr. Patel appointment" : "Dr. Patel appointment", time: "2:30 PM" },
          ].map((s, i) => (
            <div key={i} className="flex items-center gap-3 px-4 py-3 border-t border-[#EDE9FE]" style={{ minHeight: minH }}>
              <button
                onClick={() => setStepsDone(Math.max(stepsDone, i + 1))}
                className="shrink-0 w-7 h-7 rounded-full border-2 flex items-center justify-center transition-all"
                style={{ borderColor: i < stepsDone ? "#7C3AED" : "#DDD6FE", background: i < stepsDone ? "#7C3AED" : "white" }}
              >
                {i < stepsDone && <Check size={13} color="white" strokeWidth={3} />}
              </button>
              <div className="flex-1">
                <p className="text-[14px] font-semibold text-[#0F172A]">{s.label}</p>
                <p className="text-[12px] text-[#595959]">{s.time}</p>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* ── STML: Daily recap & activity history ── */}
      {(useRecap || useHistory) && (
        <div className="rounded-2xl overflow-hidden border border-[#DDD6FE] bg-white">
          {useRecap && (
            <div className="px-4 py-3 border-b border-[#EDE9FE]">
              <p className="text-[11px] font-bold uppercase tracking-wider text-[#7C3AED] mb-2">Today&apos;s recap</p>
              {[
                { icon: "✅", text: "Took Lisinopril 10mg at 8:02 AM" },
                { icon: "✅", text: "Blood pressure logged: 120/78" },
                { icon: "⏳", text: "Dr. Patel appointment at 2:30 PM — upcoming" },
              ].map((item, i) => (
                <p key={i} className="text-[13px] text-[#374151] leading-relaxed">{item.icon} {item.text}</p>
              ))}
            </div>
          )}
          {useHistory && (
            <div className="px-4 py-3">
              <p className="text-[11px] font-bold uppercase tracking-wider text-[#7C3AED] mb-2">Activity history</p>
              <div className="flex items-center gap-2 px-3 py-2 rounded-xl border border-[#EDE9FE] bg-[#F5F3FF]">
                <Sliders size={13} className="text-[#7C3AED] shrink-0" />
                <p className="text-[12px] text-[#595959]">Search: "did I already take my meds?"</p>
              </div>
            </div>
          )}
        </div>
      )}

      {/* ── STML: Reminder toggles ── */}
      {showStmlPanel && (useRemind || isStml) && (
        <div className="rounded-2xl overflow-hidden border border-[#DDD6FE] bg-white">
          <p className="text-[11px] font-bold uppercase tracking-wider text-[#7C3AED] px-4 pt-3 pb-2">Reminder alerts</p>
          <div className="flex items-center justify-between px-4 py-3 border-t border-[#EDE9FE]" style={{ minHeight: minH }}>
            <div>
              <p className="text-[15px] font-semibold text-[#0F172A]">Medication reminders</p>
              <p className="text-[12px] text-[#595959]">Every 5 min until dismissed</p>
            </div>
            <Switch checked={medsReminder} onChange={setMedsReminder} id="h-meds-r" color="#7C3AED" />
          </div>
          <div className="flex items-center justify-between px-4 py-3 border-t border-[#EDE9FE]" style={{ minHeight: minH }}>
            <div>
              <p className="text-[15px] font-semibold text-[#0F172A]">Appointment alerts</p>
              <p className="text-[12px] text-[#595959]">2 hrs and 30 min before</p>
            </div>
            <Switch checked={apptReminder} onChange={setApptReminder} id="h-appt-r" color="#7C3AED" />
          </div>
        </div>
      )}

      {/* ── Dyslexia: Reading aids ── */}
      {showDysAids && (
        <div className="rounded-2xl overflow-hidden border border-[#BBF7D0]" style={{ background: cardBg }}>
          <p className="text-[11px] font-bold uppercase tracking-wider text-[#0E7E57] px-4 pt-3 pb-2">Reading aids</p>

          {(isDys || has("dys_tint")) && (
            <div className="flex items-center justify-between px-4 py-3 border-t border-[#D1FAE5]" style={{ minHeight: 60 }}>
              <div>
                <p className="text-[15px] font-semibold text-[#0F172A]">Cream tint</p>
                <p className="text-[12px] text-[#595959]">Reduces white glare</p>
              </div>
              <Switch checked={tint} onChange={setTint} id="h-tint" color="#0E7E57" />
            </div>
          )}

          {(isDys || has("dys_readaloud") || has("dys_tts")) && (
            <div className="flex items-center justify-between px-4 py-3 border-t border-[#D1FAE5]" style={{ minHeight: 60 }}>
              <div className="flex items-center gap-2">
                <Volume2 size={14} className="text-[#0E7E57]" />
                <div>
                  <p className="text-[15px] font-semibold text-[#0F172A]">Read aloud</p>
                  <p className="text-[12px] text-[#595959]">{has("dys_tts") ? "All screen text spoken automatically" : "Tap any text to hear it"}</p>
                </div>
              </div>
              <Switch checked={readAloud} onChange={setReadAloud} id="h-readaloud" color="#0E7E57" />
            </div>
          )}

          {(isDys || has("dys_voice")) && (
            <div className="border-t border-[#D1FAE5]">
              <button className="w-full flex items-center gap-3 px-4 py-3 text-left hover:bg-[#D1FAE5]/40 transition-colors" style={{ minHeight: 56 }}>
                <div className="w-8 h-8 rounded-xl flex items-center justify-center shrink-0" style={{ background: "#0E7E57" }}>
                  <Mic size={14} className="text-white" />
                </div>
                <div>
                  <p className="text-[14px] font-semibold text-[#0F172A]">Voice input active</p>
                  <p className="text-[12px] text-[#595959]">Tap mic in any text field to dictate</p>
                </div>
              </button>
            </div>
          )}

          {(isDys || has("dys_plainlang")) && (
            <div className="px-4 py-3 border-t border-[#D1FAE5]">
              <p className="text-[11px] font-bold uppercase tracking-wider text-[#0E7E57] mb-1.5">Plain language active</p>
              <p className="text-[13px] text-[#374151] leading-relaxed">
                Short sentences. Clear words. Icons beside every label. No jargon.
              </p>
            </div>
          )}

          {(isDys || has("dys_chunking")) && (
            <div className="px-4 py-3 border-t border-[#D1FAE5]">
              <p className="text-[11px] font-bold uppercase tracking-wider text-[#0E7E57] mb-1.5">Visual chunking</p>
              <div className="flex flex-col gap-1.5">
                {["Morning tasks", "Medications", "Appointments"].map(chunk => (
                  <div key={chunk} className="flex items-center gap-2 px-3 py-2 rounded-xl bg-white border border-[#BBF7D0]">
                    <div className="w-1.5 h-4 rounded-full bg-[#0E7E57] shrink-0" />
                    <p className="text-[13px] font-semibold text-[#0F172A]">{chunk}</p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {isDys && (
            <div className="px-4 py-3 border-t border-[#D1FAE5]" style={{ background: cardBg }}>
              <p className="text-[11px] font-bold uppercase tracking-wider text-[#0E7E57] mb-2">Font preview — Lexend</p>
              <p className="text-[14px] text-[#374151] leading-[1.9]" style={{ fontFamily: "'Lexend','Roboto',sans-serif", letterSpacing: "0.03em" }}>
                The quick brown fox · <span className="font-bold">B b D d P p q</span> · 0123456789
              </p>
            </div>
          )}
        </div>
      )}

      {/* ── Health snapshot (all modes) ── */}
      <div className="rounded-2xl p-4 border border-[#E5E7EB]" style={{ background: cardBg }}>
        <div className="flex items-center gap-2 mb-3">
          <div className="w-1.5 h-5 rounded-full" style={{ background: primaryColor }} />
          <p className="text-[12px] font-bold uppercase tracking-wider" style={{ color: primaryColor }}>Health snapshot</p>
        </div>
        <p className="text-[17px] font-medium text-[#0F172A] leading-[1.8] mb-1">
          Blood pressure:{" "}
          <span className="bg-[#E0F7FA] px-2 py-0.5 rounded font-bold text-[#00A7C8]">120 / 78</span>
        </p>
        <p className="text-[14px] text-[#374151] leading-[1.8]">
          Next check-up:{" "}
          <span className="font-semibold underline underline-offset-4" style={{ textDecorationColor: primaryColor }}>Thursday, Jul 17</span>
        </p>
      </div>

      {/* ── Carpal tunnel: Voice + large actions ── */}
      {showCarpalPanel && (
        <div className="rounded-2xl overflow-hidden border-2 bg-white" style={{ borderColor: "#FDE68A" }}>
          <div className="flex items-center gap-2 px-4 py-2.5" style={{ background: "#FFFBEB", borderBottom: "1px solid #FDE68A" }}>
            <Hand size={14} className="text-[#B45309]" />
            <p className="text-[11px] font-bold uppercase tracking-wider text-[#B45309]">Carpal tunnel aids</p>
          </div>

          {/* Voice input */}
          {useVoice && (
            <button className="w-full flex items-center justify-between px-5 py-4 border-b border-[#FEF3C7] hover:bg-[#FFFBEB] transition-colors" style={{ minHeight: useLarge ? 80 : 64 }}>
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0" style={{ background: "#B45309" }}>
                  <Mic size={18} className="text-white" />
                </div>
                <div className="text-left">
                  <p className="text-[15px] font-bold text-[#0F172A]">Tap to speak</p>
                  <p className="text-[12px] text-[#595959]">Voice command or dictate text</p>
                </div>
              </div>
              <div className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "#FDE68A" }}>
                <div className="w-2.5 h-2.5 rounded-full bg-[#B45309] animate-pulse" />
              </div>
            </button>
          )}

          {/* Swipe + voice toggles */}
          <div className="flex items-center justify-between px-4 py-3 border-b border-[#FEF3C7]" style={{ minHeight: 64 }}>
            <div><p className="text-[14px] font-semibold text-[#0F172A]">Voice input</p><p className="text-[12px] text-[#595959]">Speak instead of type</p></div>
            <Switch checked={voice} onChange={setVoice} id="h-voice" large={useLarge} color="#B45309" />
          </div>
          <div className="flex items-center justify-between px-4 py-3 border-b border-[#FEF3C7]" style={{ minHeight: 64 }}>
            <div><p className="text-[14px] font-semibold text-[#0F172A]">Swipe navigation</p><p className="text-[12px] text-[#595959]">Swipe between screens</p></div>
            <Switch checked={swipe} onChange={setSwipe} id="h-swipe" large={useLarge} color="#B45309" />
          </div>

          {/* Autofill indicator */}
          {useAutofill && (
            <div className="flex items-center gap-3 px-4 py-3 border-b border-[#FEF3C7]" style={{ minHeight: 56 }}>
              <div className="w-8 h-8 rounded-xl flex items-center justify-center shrink-0" style={{ background: "#FFFBEB", border: "1.5px solid #FDE68A" }}>
                <Sparkles size={14} className="text-[#B45309]" />
              </div>
              <div className="flex-1">
                <p className="text-[14px] font-semibold text-[#0F172A]">Autofill active</p>
                <p className="text-[12px] text-[#595959]">Fields pre-fill from your history</p>
              </div>
              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full text-[#B45309] border border-[#FDE68A]" style={{ background: "#FFFBEB" }}>ON</span>
            </div>
          )}

          {/* No timed gestures */}
          {useNoTimed && (
            <div className="flex items-center gap-3 px-4 py-3 border-b border-[#FEF3C7]" style={{ minHeight: 56 }}>
              <div className="w-8 h-8 rounded-xl flex items-center justify-center shrink-0" style={{ background: "#FFFBEB", border: "1.5px solid #FDE68A" }}>
                <Shield size={14} className="text-[#B45309]" />
              </div>
              <div>
                <p className="text-[14px] font-semibold text-[#0F172A]">No timed gestures</p>
                <p className="text-[12px] text-[#595959]">No double-taps, long-presses, or time limits</p>
              </div>
            </div>
          )}

          {/* Undo button */}
          {useUndo && (
            <div className="px-4 py-3">
              <button className="w-full flex items-center justify-center gap-2 py-3 rounded-xl font-bold text-[14px] border-2 border-[#FDE68A] text-[#B45309] bg-[#FFFBEB] hover:bg-[#FEF3C7] transition-colors">
                <ArrowLeft size={16} /> Undo last action
              </button>
            </div>
          )}

          {/* Large action grid */}
          {(isCarpal || has("ct_targets")) && (
            <div className="grid grid-cols-2 gap-2 px-4 pb-4 pt-1">
              {[
                { icon: <Pill size={26} />, label: "Mark meds taken", sub: "Morning dose" },
                { icon: <Calendar size={26} />, label: "My appointments", sub: "Next: Thursday" },
                { icon: <Bell size={26} />, label: "My reminders", sub: "3 active today" },
                { icon: <LayoutGrid size={26} />, label: "All features", sub: "Full menu" },
              ].map(btn => (
                <button key={btn.label}
                  className="flex flex-col items-start gap-2 p-4 rounded-2xl bg-white border-2 hover:bg-[#FFFBEB] transition-colors text-left"
                  style={{ borderColor: "#FDE68A", minHeight: 88 }}>
                  <span style={{ color: "#B45309" }}>{btn.icon}</span>
                  <div>
                    <p className="text-[13px] font-semibold text-[#0F172A] leading-tight">{btn.label}</p>
                    <p className="text-[11px] text-[#595959] mt-0.5">{btn.sub}</p>
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Hearing support dashboard */}
      {showHearing && (
        <div className="rounded-2xl overflow-hidden border-2" style={{ borderColor: "#BAE6FD", background: "#F0F9FF" }}>
          <div className="flex items-center gap-2 px-4 py-2.5" style={{ background: "#0284C7" }}>
            <Ear size={14} className="text-white" />
            <p className="text-[11px] font-bold uppercase tracking-wider text-white">Hearing support</p>
          </div>

          {/* Closed captions + real-time captions */}
          {(isHearing || has("hear_captions") || has("hear_realtime")) && (
            <>
              <div className="flex items-center justify-between px-4 py-3 border-b border-[#BAE6FD]" style={{ minHeight: 60 }}>
                <div className="flex items-center gap-2">
                  <Captions size={15} style={{ color: "#0284C7" }} />
                  <div>
                    <p className="text-[14px] font-semibold text-[#0F172A]">{has("hear_realtime") ? "Real-time call captions" : "Closed captions"}</p>
                    <p className="text-[12px] text-[#595959]">{captions ? "Active — captions on screen" : "Off — tap to enable"}</p>
                  </div>
                </div>
                <Switch checked={captions} onChange={setCaptions} id="h-caps" color="#0284C7" />
              </div>
              {captions && (
                <div className="mx-4 mb-2 mt-1 px-3 py-2.5 rounded-xl border border-[#BAE6FD] bg-white">
                  <p className="text-[10px] font-bold uppercase tracking-wider text-[#0284C7] mb-1">Live caption preview</p>
                  <p className="text-[13px] text-[#374151] leading-relaxed italic">"Reminder: blood pressure medication due at 8:00 AM"</p>
                </div>
              )}
            </>
          )}

          {/* Screen flash alerts */}
          {(isHearing || has("hear_flash")) && (
            <div className="flex items-center justify-between px-4 py-3 border-b border-[#BAE6FD]" style={{ minHeight: 60 }}>
              <div className="flex items-center gap-2">
                <Zap size={15} style={{ color: "#0284C7" }} />
                <div>
                  <p className="text-[14px] font-semibold text-[#0F172A]">Screen flash alerts</p>
                  <p className="text-[12px] text-[#595959]">{visualAlerts ? "Flashes on every notification" : "Visual flash off"}</p>
                </div>
              </div>
              <Switch checked={visualAlerts} onChange={setVisualAlerts} id="h-va-home" color="#0284C7" />
            </div>
          )}

          {/* Haptic vibration patterns */}
          {(isHearing || has("hear_vibration")) && (
            <div className="flex items-center justify-between px-4 py-3 border-b border-[#BAE6FD]" style={{ minHeight: 60 }}>
              <div className="flex items-center gap-2">
                <Vibrate size={15} style={{ color: "#0284C7" }} />
                <div>
                  <p className="text-[14px] font-semibold text-[#0F172A]">Haptic vibration patterns</p>
                  <p className="text-[12px] text-[#595959]">{vibration ? "3 pulses = meds · 2 pulses = appt" : "Vibration off"}</p>
                </div>
              </div>
              <Switch checked={vibration} onChange={setVibration} id="h-vib-home" color="#0284C7" />
            </div>
          )}

          {/* Visual notification badges */}
          {(isHearing || has("hear_badges")) && (
            <div className="px-4 py-3 border-b border-[#BAE6FD]">
              <p className="text-[11px] font-bold uppercase tracking-wider text-[#0284C7] mb-2">Visual notification badges</p>
              <div className="flex gap-2">
                {[
                  { icon: <Pill size={15} />, label: "Meds", count: 1 },
                  { icon: <Calendar size={15} />, label: "Appt", count: 2 },
                  { icon: <Bell size={15} />, label: "Alerts", count: 3 },
                  { icon: <MessageCircle size={15} />, label: "Chat", count: 0 },
                ].map(item => (
                  <div key={item.label} className="flex-1 flex flex-col items-center gap-1 py-2 rounded-xl bg-white border border-[#BAE6FD] relative">
                    <span style={{ color: "#0284C7" }}>{item.icon}</span>
                    {item.count > 0 && (
                      <span className="absolute -top-1.5 -right-1.5 w-4 h-4 rounded-full text-white text-[9px] font-bold flex items-center justify-center" style={{ background: "#EF4444" }}>{item.count}</span>
                    )}
                    <p className="text-[10px] text-[#595959] font-semibold">{item.label}</p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* TTY / text relay */}
          {(isHearing || has("hear_tty")) && (
            <div className="flex items-center gap-3 px-4 py-3 border-b border-[#BAE6FD]" style={{ minHeight: 56 }}>
              <div className="w-8 h-8 rounded-xl flex items-center justify-center shrink-0" style={{ background: "#E0F2FE", border: "1.5px solid #BAE6FD" }}>
                <Phone size={14} style={{ color: "#0284C7" }} />
              </div>
              <div className="flex-1">
                <p className="text-[14px] font-semibold text-[#0F172A]">TTY / Text relay</p>
                <p className="text-[12px] text-[#595959]">All calls use text relay — no audio needed</p>
              </div>
              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full text-white shrink-0" style={{ background: "#0284C7" }}>Active</span>
            </div>
          )}

          {/* Text chat as first option */}
          {(isHearing || has("hear_chat")) && (
            <div className="px-4 py-3 border-b border-[#BAE6FD]">
              <p className="text-[11px] font-bold uppercase tracking-wider text-[#0284C7] mb-2">Text-first communication</p>
              <button className="w-full flex items-center gap-3 px-4 py-3 rounded-xl bg-white border-2 border-[#BAE6FD] hover:bg-[#E0F2FE] transition-colors text-left">
                <MessageCircle size={18} style={{ color: "#0284C7" }} />
                <div>
                  <p className="text-[14px] font-bold text-[#0F172A]">Open text chat</p>
                  <p className="text-[12px] text-[#595959]">Message your care team — text always shown first</p>
                </div>
              </button>
            </div>
          )}

          {/* Audio transcripts */}
          {(isHearing || has("hear_transcripts")) && (
            <div className="px-4 py-3 border-b border-[#BAE6FD]">
              <p className="text-[11px] font-bold uppercase tracking-wider text-[#0284C7] mb-2">Audio transcripts</p>
              {[
                { label: "Dr. Patel call — Jul 14", time: "3 min" },
                { label: "Pharmacy callback — Jul 12", time: "1 min" },
              ].map(t => (
                <div key={t.label} className="flex items-center justify-between py-2 border-b border-[#BAE6FD] last:border-0">
                  <div className="flex items-center gap-2">
                    <div className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: "#0284C7" }} />
                    <p className="text-[13px] text-[#374151]">{t.label}</p>
                  </div>
                  <span className="text-[11px] text-[#0284C7] font-semibold">{t.time} · Read</span>
                </div>
              ))}
            </div>
          )}

          {/* Hearing Conversation Assist entry */}
          {isHearing && onOpenHearingAssist && (
            <div className="px-4 py-3">
              <button
                type="button"
                onClick={onOpenHearingAssist}
                className="w-full flex items-center gap-3 px-3 py-3 rounded-xl text-left"
                style={{ background: "#0284C7" }}
              >
                <Captions size={18} className="text-white shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-[14px] font-bold text-white">Open Hearing Conversation Assist</p>
                  <p className="text-[11px] text-white/80">Live captions, speaker ID, summaries, memory & coaching</p>
                </div>
                <ChevronRight size={16} className="text-white/80" />
              </button>
            </div>
          )}
        </div>
      )}

      {/* Custom active features badge row */}
      {mode === "custom" && Object.values(customSettings).some(Boolean) && (
        <div className="rounded-2xl p-3 bg-white border border-[#E5E7EB]">
          <p className="text-[10px] font-bold uppercase tracking-wider text-[#595959] mb-2">Active features</p>
          <div className="flex flex-wrap gap-1.5">
            {ALL_FEATURES.filter(f => customSettings[f.id]).map(f => {
              const m = CAT_META[f.category];
              return (
                <span key={f.id} className="text-[10px] font-semibold px-2 py-0.5 rounded-full"
                  style={{ background: m.lightBg, color: m.color, border: `1px solid ${m.borderColor}` }}>
                  {f.label}
                </span>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

// ── Schedule tab ───────────────────────────────────────────────────────────────

// ── Shared data types ──────────────────────────────────────────────────────────

interface Medication  { id: string; name: string; dose: string; time: string; purpose: string; }
interface Appointment { id: string; date: string; time: string; title: string; type: string; location: string; confirmed: boolean; }

interface PatientAccountSnapshot {
  profileComplete: boolean;
  profileName: string;
  profileDob: string;
  profileConditions: string;
  profileAllergies: string;
  profileMeds: string;
  linkedCaregivers: LinkedCaregiver[];
  medications: Medication[];
  medsChecked: Record<string, boolean>;
  appointments: Appointment[];
  mood?: number | null;
  moodHistory?: MoodEntry[];
  lastCheckin?: string;
  checkinsThisWeek?: number;
  hasFallAlert?: boolean;
  lowMoodStreakAlert?: LowMoodStreakAlert | null;
}

type PatientSnapshotRegistry = Record<string, PatientAccountSnapshot>;

function seedPatientSnapshotRegistryFromActive() {
  try {
    const active = loadPatientSnapshot();
    if (!active?.profileName || active.profileName === "Your Name") return;
    const registry = (() => {
      try {
        const raw = localStorage.getItem(PATIENT_SNAPSHOT_REGISTRY_KEY);
        if (!raw) return {} as PatientSnapshotRegistry;
        const parsed = JSON.parse(raw);
        return parsed && typeof parsed === "object" ? parsed as PatientSnapshotRegistry : {};
      } catch {
        return {} as PatientSnapshotRegistry;
      }
    })();
    const key = patientSnapshotKey(active.profileName, active.profileDob);
    if (registry[key]) return;
    registry[key] = active;
    const nameOnly = patientSnapshotKey(active.profileName);
    if (nameOnly !== key) registry[nameOnly] = active;
    savePatientSnapshotRegistry(registry);
  } catch {}
}

function loadPatientSnapshotRegistry(): PatientSnapshotRegistry {
  try {
    seedPatientSnapshotRegistryFromActive();
    const raw = localStorage.getItem(PATIENT_SNAPSHOT_REGISTRY_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed as PatientSnapshotRegistry : {};
  } catch {
    return {};
  }
}

function savePatientSnapshotRegistry(registry: PatientSnapshotRegistry) {
  try {
    localStorage.setItem(PATIENT_SNAPSHOT_REGISTRY_KEY, JSON.stringify(registry));
  } catch {}
}

function loadPatientSnapshot(): PatientAccountSnapshot | null {
  try {
    const raw = localStorage.getItem(PATIENT_SNAPSHOT_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch { return null; }
}

function uniquePatientSnapshotsFromRegistry(): PatientAccountSnapshot[] {
  return Object.values(loadPatientSnapshotRegistry());
}

/**
 * Resolve which stored patient this caregiver is caring for, so a second patient
 * signing in on the same browser cannot replace who the caregiver sees.
 */
function loadPatientSnapshotForCaregiver(
  linkedPatientName?: string,
  linkedPatientDob?: string,
  caregiver?: CaregiverIdentity,
): PatientAccountSnapshot | null {
  return resolvePatientForCaregiver<PatientAccountSnapshot>({
    snapshots: uniquePatientSnapshotsFromRegistry(),
    activeSnapshot: loadPatientSnapshot(),
    linkedPatientName,
    linkedPatientDob,
    caregiver,
  });
}

function savePatientSnapshot(data: PatientAccountSnapshot) {
  try {
    localStorage.setItem(PATIENT_SNAPSHOT_KEY, JSON.stringify(data));
    if (data.profileName && data.profileName !== "Your Name") {
      const registry = loadPatientSnapshotRegistry();
      const key = patientSnapshotKey(data.profileName, data.profileDob);
      registry[key] = data;
      // Also index by name-only for caregivers who linked without DOB.
      const nameOnly = patientSnapshotKey(data.profileName);
      if (nameOnly !== key) registry[nameOnly] = data;
      savePatientSnapshotRegistry(registry);
    }
  } catch {}
}

// ── Shared bottom sheet ────────────────────────────────────────────────────────

function FormSheet({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  return (
    <div className="absolute inset-0 bg-black/55 flex flex-col justify-end z-50">
      <div className="bg-white rounded-t-3xl flex flex-col" style={{ maxHeight: "88%" }}>
        <div className="flex items-center justify-between px-5 pt-5 pb-4 border-b border-[#F3F4F6] shrink-0">
          <p className="text-[18px] font-bold text-[#0F172A]">{title}</p>
          <button onClick={onClose}
            className="w-8 h-8 flex items-center justify-center rounded-full bg-[#F3F4F6] text-[#595959] font-bold text-[17px] leading-none">
            ×
          </button>
        </div>
        <div className="overflow-y-auto flex-1 px-5 py-5 flex flex-col gap-4">
          {children}
        </div>
      </div>
    </div>
  );
}

function FormField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <p className="text-[12px] font-bold text-[#595959] uppercase tracking-wide">{label}</p>
      {children}
    </div>
  );
}

// font-size: 16px prevents iOS from auto-zooming on focus
const inputCls = "w-full px-4 py-3.5 rounded-xl border-2 border-[#E5E7EB] text-[16px] text-[#0F172A] outline-none focus:border-[#00A7C8] transition-colors bg-white";

// ── Add-appointment form ───────────────────────────────────────────────────────

function AddAppointmentForm({ theme, onSave, onClose }: {
  theme: ModeTheme;
  onSave: (a: Appointment) => void;
  onClose: () => void;
}) {
  const [title,    setTitle]    = useState("");
  const [date,     setDate]     = useState("");
  const [time,     setTime]     = useState("");
  const [apptType, setApptType] = useState("In person");
  const [location, setLocation] = useState("");

  const TYPES = ["In person", "Home check", "Pharmacy", "Video call", "Phone call"];

  const save = () => {
    if (!title.trim()) return;
    onSave({
      id: Date.now().toString(),
      date: date.trim() || "Upcoming",
      time: time.trim() || "TBD",
      title: title.trim(),
      type: apptType,
      location: location.trim(),
      confirmed: false,
    });
  };

  return (
    <FormSheet title="New appointment" onClose={onClose}>
      <FormField label="Title *">
        <VoiceInput className={inputCls} placeholder="e.g. Dr. Patel — Checkup" value={title} onChange={setTitle} />
      </FormField>
      <FormField label="Date">
        <VoiceInput className={inputCls} placeholder="e.g. Today, Tomorrow, Mon Jul 21" value={date} onChange={setDate} />
      </FormField>
      <FormField label="Time">
        <VoiceInput className={inputCls} placeholder="e.g. 2:30 PM" value={time} onChange={setTime} />
      </FormField>
      <FormField label="Type">
        <div className="flex flex-wrap gap-2">
          {TYPES.map(t => (
            <button key={t} onClick={() => setApptType(t)}
              className="px-3 py-2 rounded-xl text-[13px] font-semibold transition-all border-2"
              style={{
                borderColor: apptType === t ? theme.color : "#E5E7EB",
                background:  apptType === t ? theme.lightBg : "white",
                color:       apptType === t ? theme.color   : "#595959",
              }}>
              {t}
            </button>
          ))}
        </div>
      </FormField>
      <FormField label="Location (optional)">
        <VoiceInput className={inputCls} placeholder="e.g. Room 204, City Medical" value={location} onChange={setLocation} />
      </FormField>
      <div className="flex gap-3 pt-1">
        <button onClick={onClose}
          className="flex-1 py-3.5 rounded-xl border-2 border-[#E5E7EB] font-semibold text-[14px] text-[#595959]">
          Cancel
        </button>
        <button onClick={save} disabled={!title.trim()}
          className="flex-1 py-3.5 rounded-xl font-bold text-[15px] text-white transition-all"
          style={{ background: title.trim() ? theme.color : "#CBD5E1" }}>
          Save appointment
        </button>
      </div>
    </FormSheet>
  );
}

// ── Add-medication form ────────────────────────────────────────────────────────

function AddMedForm({ theme, onSave, onClose }: {
  theme: ModeTheme;
  onSave: (m: Medication) => void;
  onClose: () => void;
}) {
  const [name,    setName]    = useState("");
  const [dose,    setDose]    = useState("");
  const [time,    setTime]    = useState("");
  const [purpose, setPurpose] = useState("");

  const save = () => {
    if (!name.trim()) return;
    onSave({ id: Date.now().toString(), name: name.trim(), dose: dose.trim(), time: time.trim() || "As needed", purpose: purpose.trim() });
  };

  return (
    <FormSheet title="Add medication" onClose={onClose}>
      <FormField label="Medication name *">
        <VoiceInput className={inputCls} placeholder="e.g. Lisinopril" value={name} onChange={setName} />
      </FormField>
      <FormField label="Dose">
        <VoiceInput className={inputCls} placeholder="e.g. 10mg" value={dose} onChange={setDose} />
      </FormField>
      <FormField label="Time">
        <VoiceInput className={inputCls} placeholder="e.g. 8:00 AM" value={time} onChange={setTime} />
      </FormField>
      <FormField label="Purpose">
        <VoiceInput className={inputCls} placeholder="e.g. Blood pressure" value={purpose} onChange={setPurpose} />
      </FormField>
      <div className="flex gap-3 pt-1">
        <button onClick={onClose}
          className="flex-1 py-3.5 rounded-xl border-2 border-[#E5E7EB] font-semibold text-[14px] text-[#595959]">
          Cancel
        </button>
        <button onClick={save} disabled={!name.trim()}
          className="flex-1 py-3.5 rounded-xl font-bold text-[15px] text-white transition-all"
          style={{ background: name.trim() ? theme.color : "#CBD5E1" }}>
          Add medication
        </button>
      </div>
    </FormSheet>
  );
}

// ── Schedule tab ───────────────────────────────────────────────────────────────

function ScheduleContent({ theme, useLarge, appointments, setAppointments, setModal, clearModal }: {
  theme: ModeTheme; useLarge: boolean;
  appointments: Appointment[]; setAppointments: (v: Appointment[]) => void;
  setModal: (node: React.ReactNode) => void;
  clearModal: () => void;
}) {
  const openAddForm = () => setModal(
    <AddAppointmentForm
      theme={theme}
      onSave={appt => { setAppointments([...appointments, appt]); clearModal(); }}
      onClose={clearModal}
    />
  );

  const toggleConfirm = (id: string) =>
    setAppointments(appointments.map(a => a.id === id ? { ...a, confirmed: !a.confirmed } : a));

  const removeAppt = (id: string) =>
    setAppointments(appointments.filter(a => a.id !== id));

  return (
    <div className="px-4 pt-4 pb-6 flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <p className="text-[11px] font-bold uppercase tracking-wider" style={{ color: theme.color }}>
          Upcoming · {appointments.length}
        </p>
        <button onClick={openAddForm}
          className="flex items-center gap-1 text-[12px] font-bold px-3 py-1.5 rounded-lg transition-all hover:opacity-80"
          style={{ background: theme.lightBg, color: theme.color, border: `1.5px solid ${theme.borderColor}` }}>
          + Add
        </button>
      </div>

      {appointments.length === 0 && (
        <div className="py-10 flex flex-col items-center gap-3 text-center">
          <Calendar size={36} style={{ color: theme.borderColor }} />
          <p className="text-[14px] font-semibold text-[#595959]">No appointments yet</p>
          <button onClick={openAddForm}
            className="px-5 py-2.5 rounded-xl font-bold text-[13px] text-white"
            style={{ background: theme.color }}>
            + Add your first appointment
          </button>
        </div>
      )}

      {appointments.map((appt, i) => (
        <div key={appt.id}
          className="rounded-2xl bg-white border-2 flex flex-col transition-all"
          style={{
            borderColor: appt.confirmed ? "#10B981" : i === 0 ? theme.color : theme.borderColor,
            minHeight: useLarge ? 88 : 72,
          }}>
          <div className="flex gap-3 p-4">
            <div className="flex flex-col items-center shrink-0 w-14">
              <p className="text-[10px] font-bold uppercase tracking-wider text-[#595959] leading-tight">{appt.date.split(",")[0]}</p>
              <p className="text-[12px] font-bold text-[#0F172A] leading-tight mt-0.5">{appt.time}</p>
            </div>
            <div className="w-px bg-[#E5E7EB] self-stretch mx-1 shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="text-[15px] font-semibold leading-snug"
                style={{ color: appt.confirmed ? "#10B981" : "#0F172A",
                  textDecoration: appt.confirmed ? "line-through" : "none",
                  textDecorationColor: "#10B981" }}>
                {appt.title}
              </p>
              <p className="text-[12px] mt-0.5" style={{ color: appt.confirmed ? "#10B981" : theme.color }}>{appt.type}</p>
              {appt.location && <p className="text-[11px] text-[#595959] mt-0.5 truncate">{appt.location}</p>}
            </div>
            {i === 0 && !appt.confirmed && (
              <span className="shrink-0 self-start text-[10px] font-bold uppercase px-2 py-0.5 rounded-full text-white" style={{ background: theme.color }}>
                Next
              </span>
            )}
            {appt.confirmed && (
              <div className="shrink-0 self-start w-6 h-6 rounded-full bg-[#10B981] flex items-center justify-center">
                <Check size={13} color="white" strokeWidth={3} />
              </div>
            )}
          </div>
          {/* Action row */}
          <div className="flex gap-2 px-4 pb-3">
            <button onClick={() => toggleConfirm(appt.id)}
              className="flex-1 flex items-center justify-center gap-1.5 py-2 rounded-xl font-semibold text-[12px] transition-all"
              style={{
                background: appt.confirmed ? "#DCFCE7" : theme.lightBg,
                color:      appt.confirmed ? "#10B981" : theme.color,
                border: `1.5px solid ${appt.confirmed ? "#10B981" : theme.borderColor}`,
              }}>
              <Check size={13} /> {appt.confirmed ? "Done" : "Confirm"}
            </button>
            <button onClick={() => removeAppt(appt.id)}
              className="px-3 py-2 rounded-xl font-semibold text-[12px] text-[#EF4444] bg-[#FEF2F2] border border-[#FECACA] transition-all hover:bg-[#FEE2E2]">
              Remove
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}

// ── Meds tab ───────────────────────────────────────────────────────────────────

function MedsContent({ theme, useLarge, medications, setMedications, medsChecked, setMedsChecked, setModal, clearModal }: {
  theme: ModeTheme; useLarge: boolean;
  medications: Medication[]; setMedications: (v: Medication[]) => void;
  medsChecked: Record<string, boolean>; setMedsChecked: (v: Record<string, boolean>) => void;
  setModal: (node: React.ReactNode) => void; clearModal: () => void;
}) {
  const toggleTake = (id: string) => setMedsChecked({ ...medsChecked, [id]: !medsChecked[id] });
  const removeMed  = (id: string) => {
    setMedications(medications.filter(m => m.id !== id));
    const next = { ...medsChecked }; delete next[id]; setMedsChecked(next);
  };

  const openAddForm = () => setModal(
    <AddMedForm
      theme={theme}
      onSave={med => { setMedications([...medications, med]); clearModal(); }}
      onClose={clearModal}
    />
  );

  return (
    <div className="px-4 pt-4 pb-2 flex flex-col gap-3">
      <div className="flex items-center gap-2">
        <Pill size={18} style={{ color: theme.color }} />
        <h2 className="text-[18px] font-bold text-[#0F172A]">Medications</h2>
      </div>
      <div className="flex items-center justify-between">
        <p className="text-[11px] font-bold uppercase tracking-wider" style={{ color: theme.color }}>
          Today&apos;s medications · {medications.length}
        </p>
        <button onClick={openAddForm}
          className="flex items-center gap-1 text-[12px] font-bold px-3 py-1.5 rounded-lg transition-all hover:opacity-80"
          style={{ background: theme.lightBg, color: theme.color, border: `1.5px solid ${theme.borderColor}` }}>
          + Add
        </button>
      </div>

      {medications.length === 0 && (
        <div className="py-10 flex flex-col items-center gap-3 text-center">
          <Pill size={36} style={{ color: theme.borderColor }} />
          <p className="text-[14px] font-semibold text-[#595959]">No medications added</p>
          <button onClick={openAddForm}
            className="px-5 py-2.5 rounded-xl font-bold text-[13px] text-white"
            style={{ background: theme.color }}>
            + Add your first medication
          </button>
        </div>
      )}

      {medications.map(med => {
        const done = !!medsChecked[med.id];
        return (
          <div key={med.id} className="rounded-2xl bg-white border-2 transition-all"
            style={{ borderColor: done ? "#10B981" : theme.borderColor, minHeight: useLarge ? 84 : 68 }}>
            <div className="flex items-center gap-4 px-4 pt-3 pb-2">
              <div className="flex-1 min-w-0">
                <p className="text-[15px] font-semibold"
                  style={{ color: done ? "#10B981" : "#0F172A",
                    textDecoration: done ? "line-through" : "none",
                    textDecorationColor: "#10B981" }}>
                  {med.name}{med.dose ? <span className="font-normal text-[13px] text-[#595959]"> {med.dose}</span> : null}
                </p>
                <p className="text-[12px] mt-0.5 font-medium" style={{ color: done ? "#10B981" : theme.color }}>{med.time}</p>
                {med.purpose && <p className="text-[11px] text-[#595959]">{med.purpose}</p>}
              </div>
              <button onClick={() => toggleTake(med.id)}
                className="shrink-0 flex items-center justify-center rounded-xl font-bold text-[13px] transition-all duration-150"
                style={{
                  width: useLarge ? 80 : 68, height: useLarge ? 48 : 40,
                  background: done ? "#10B981" : theme.lightBg,
                  color:      done ? "white"   : theme.color,
                  border: `2px solid ${done ? "#10B981" : theme.borderColor}`,
                }}>
                {done ? <Check size={18} /> : "Take"}
              </button>
            </div>
            <div className="flex gap-2 px-4 pb-3">
              <button onClick={() => removeMed(med.id)}
                className="text-[11px] font-semibold px-3 py-1.5 rounded-lg text-[#EF4444] bg-[#FEF2F2] border border-[#FECACA] hover:bg-[#FEE2E2] transition-all">
                Remove
              </button>
            </div>
          </div>
        );
      })}

      {/* Refills */}
      <div className="rounded-2xl bg-white border border-[#E5E7EB] overflow-hidden">
        <p className="text-[11px] font-bold uppercase tracking-wider text-[#595959] px-4 pt-3 pb-2">Upcoming refills</p>
        {[
          { name: "Lisinopril 10mg",   due: "Fri Jul 18", pharmacy: "CVS Oak Street" },
          { name: "Atorvastatin 20mg", due: "Mon Jul 28", pharmacy: "Walgreens Main" },
        ].map((r, i) => (
          <div key={i} className="flex items-center gap-3 px-4 py-3 border-t border-[#E5E7EB]" style={{ minHeight: 56 }}>
            <div className="w-2 h-2 rounded-full shrink-0" style={{ background: theme.color }} />
            <div className="flex-1 min-w-0">
              <p className="text-[14px] font-semibold text-[#0F172A]">{r.name}</p>
              <p className="text-[12px] text-[#595959]">Due {r.due} · {r.pharmacy}</p>
            </div>
            <button className="text-[12px] font-semibold px-3 py-1 rounded-lg transition-colors"
              style={{ background: theme.lightBg, color: theme.color }}>Refill</button>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Settings tab ───────────────────────────────────────────────────────────────

function ConditionDropdown({ value, onChange, color, lightBg, borderColor }: {
  value: string; onChange: (v: string) => void;
  color: string; lightBg: string; borderColor: string;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const selected = DISABILITY_OPTIONS.find(o => o.value === value) ?? DISABILITY_OPTIONS[0];

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    if (open) document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen(p => !p)}
        aria-haspopup="listbox" aria-expanded={open}
        className="w-full flex items-center justify-between gap-3 px-4 py-3 rounded-xl border-2 bg-white text-left transition-all duration-150"
        style={{ borderColor: open ? color : borderColor, minHeight: 56 }}
      >
        <div className="min-w-0">
          <p className="text-[14px] font-semibold text-[#0F172A] leading-tight truncate">{selected.label}</p>
          <p className="text-[12px] text-[#595959] leading-tight mt-0.5 truncate">{selected.description}</p>
        </div>
        <ChevronDown size={16} className="shrink-0 transition-transform duration-200 text-[#595959]"
          style={{ transform: open ? "rotate(180deg)" : "rotate(0deg)" }} />
      </button>
      {open && (
        <ul role="listbox"
          className="relative z-50 mt-1 rounded-xl border border-[#E5E7EB] bg-white overflow-hidden max-h-64 overflow-y-auto"
          style={{ boxShadow: "0 8px 24px rgba(0,0,0,0.10)" }}
        >
          {DISABILITY_OPTIONS.map(opt => {
            const isSel = opt.value === value;
            return (
              <li key={opt.value} role="option" aria-selected={isSel}
                onClick={() => { onChange(opt.value); setOpen(false); }}
                className="flex items-center gap-3 px-4 py-3 cursor-pointer transition-colors duration-100"
                style={{ background: isSel ? lightBg : "white", minHeight: 52 }}
              >
                <div className="flex-1 min-w-0">
                  <p className="text-[14px] font-medium text-[#0F172A] leading-tight">{opt.label}</p>
                  <p className="text-[12px] text-[#595959] leading-tight mt-0.5">{opt.description}</p>
                </div>
                {isSel && <Check size={15} style={{ color }} className="shrink-0" />}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function SectionCard({ icon, title, color, lightBg, borderColor, children }: {
  icon: React.ReactNode; title: string;
  color: string; lightBg: string; borderColor: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl overflow-hidden border bg-white" style={{ borderColor }}>
      <div className="flex items-center gap-2 px-4 py-2.5" style={{ background: lightBg, borderBottom: `1px solid ${borderColor}` }}>
        <span style={{ color }}>{icon}</span>
        <p className="text-[11px] font-bold uppercase tracking-wider" style={{ color }}>{title}</p>
      </div>
      {children}
    </div>
  );
}

function SettingRow({ label, subtitle, id, checked, onChange, color, large, last = false }: {
  label: string; subtitle?: string; id: string;
  checked: boolean; onChange: (v: boolean) => void;
  color: string; large?: boolean; last?: boolean;
}) {
  return (
    <div className={`flex items-center justify-between px-4 py-3 transition-colors duration-150 ${!last ? "border-b border-[#F3F4F6]" : ""}`}
      style={{ minHeight: large ? 72 : 56 }}>
      <div className="flex-1 min-w-0 pr-4">
        <p className="text-[14px] font-semibold text-[#0F172A] leading-snug">{label}</p>
        {subtitle && <p className="text-[11px] text-[#595959] leading-snug mt-0.5">{subtitle}</p>}
      </div>
      <Switch checked={checked} onChange={onChange} id={id} color={color} large={large} />
    </div>
  );
}

function SettingsContent({ mode, setMode, customSettings, setCustomSettings, theme,
  disability, setDisability,
  textSize, setTextSize,
  highContrast, setHighContrast,
  boldText, setBoldText,
  colorFilter, setColorFilter,
  reduceMotion, setReduceMotion,
  autoPlay, setAutoPlay,
  readAloudGlobal, setReadAloudGlobal,
  focusIndicators, setFocusIndicators,
  tremorMode, setTremorMode,
  confirmActions, setConfirmActions,
  vibration, setVibration,
  visualAlerts, setVisualAlerts,
  simplifiedNav, setSimplifiedNav,
  captions, setCaptions,
  soundAmplify, setSoundAmplify,
  ttySupport, setTtySupport,
  hearingAidMode, setHearingAidMode,
  onSignOut,
}: {
  mode: AppMode | null; setMode: (m: AppMode) => void;
  customSettings: CustomSettings; setCustomSettings: (s: CustomSettings) => void;
  theme: ModeTheme;
  disability: string; setDisability: (v: string) => void;
  textSize: 0 | 1 | 2; setTextSize: (v: 0 | 1 | 2) => void;
  highContrast: boolean; setHighContrast: (v: boolean) => void;
  boldText: boolean; setBoldText: (v: boolean) => void;
  colorFilter: boolean; setColorFilter: (v: boolean) => void;
  reduceMotion: boolean; setReduceMotion: (v: boolean) => void;
  autoPlay: boolean; setAutoPlay: (v: boolean) => void;
  readAloudGlobal: boolean; setReadAloudGlobal: (v: boolean) => void;
  focusIndicators: boolean; setFocusIndicators: (v: boolean) => void;
  tremorMode: boolean; setTremorMode: (v: boolean) => void;
  confirmActions: boolean; setConfirmActions: (v: boolean) => void;
  vibration: boolean; setVibration: (v: boolean) => void;
  visualAlerts: boolean; setVisualAlerts: (v: boolean) => void;
  simplifiedNav: boolean; setSimplifiedNav: (v: boolean) => void;
  captions: boolean; setCaptions: (v: boolean) => void;
  soundAmplify: boolean; setSoundAmplify: (v: boolean) => void;
  ttySupport: boolean; setTtySupport: (v: boolean) => void;
  hearingAidMode: boolean; setHearingAidMode: (v: boolean) => void;
  onSignOut: () => void;
}) {
  const c = theme.color;
  const lb = theme.lightBg;
  const bc = theme.borderColor;

  return (
    <div className="px-4 pt-4 pb-6 flex flex-col gap-3">

      {/* ── Your condition ── */}
      <SectionCard icon={<User size={14} />} title="Your condition" color={c} lightBg={lb} borderColor={bc}>
        <div className="p-3">
          <p className="text-[12px] text-[#595959] leading-relaxed mb-3">
            Selecting your condition helps CareConnect suggest the most relevant settings.
          </p>
          <ConditionDropdown value={disability} onChange={setDisability} color={c} lightBg={lb} borderColor={bc} />
        </div>
      </SectionCard>

      <AccessibilityModeCustomizer
        mode={mode}
        setMode={setMode}
        customSettings={customSettings}
        setCustomSettings={setCustomSettings}
        theme={theme}
      />

      {/* ── Vision ── */}
      <SectionCard icon={<Eye size={14} />} title="Vision" color={c} lightBg={lb} borderColor={bc}>
        {/* Text size */}
        <div className="px-4 py-3 border-b border-[#F3F4F6]">
          <div className="flex items-center justify-between mb-2">
            <p className="text-[14px] font-semibold text-[#0F172A]">Text size</p>
            <span className="text-[11px] font-bold" style={{ color: c }}>{["100%", "125%", "150%"][textSize]}</span>
          </div>
          <div className="flex rounded-xl overflow-hidden border border-[#E5E7EB] bg-[#F3F4F6]">
            {(["Standard", "Large", "Largest"] as const).map((label, i) => (
              <button key={label} onClick={() => setTextSize(i as 0 | 1 | 2)}
                className="flex-1 py-2.5 text-[12px] font-semibold transition-all duration-150"
                style={{ background: textSize === i ? c : "transparent", color: textSize === i ? "white" : "#595959" }}>
                {label}
              </button>
            ))}
          </div>
          <div className="mt-2.5 px-3 py-2.5 rounded-xl border border-[#E5E7EB] bg-[#F8FAFC]">
            <p className="text-[#0F172A] leading-[1.45] transition-all duration-300" style={{ fontSize: [14, 17.5, 21][textSize] }}>
              Preview text at {["100%", "125%", "150%"][textSize]}
            </p>
            <p className="text-[10px] text-[#9CA3AF] mt-0.5">{[14, 17.5, 21][textSize]}sp · {["Standard", "Large", "Largest"][textSize]}</p>
          </div>
        </div>

        <SettingRow id="s-hc" label="High contrast" subtitle="Maximise text and background contrast" checked={highContrast} onChange={setHighContrast} color={c} />
        {highContrast && (
          <div className="mx-4 mb-2 -mt-1 px-3 py-1.5 rounded-lg flex items-center gap-2 transition-all"
            style={{ background: lb, border: `1px solid ${bc}` }}>
            <div className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: c }} />
            <p className="text-[11px] font-medium" style={{ color: c }}>Maximum contrast active across all screens</p>
          </div>
        )}

        <SettingRow id="s-bt" label="Bold text" subtitle="Increase font weight for easier reading" checked={boldText} onChange={setBoldText} color={c} />

        <SettingRow id="s-cf" label="Colour filter" subtitle="Applies a tint to reduce colour fatigue" checked={colorFilter} onChange={setColorFilter} color={c} />
        {colorFilter && (
          <div className="mx-4 mb-2 -mt-1 px-3 py-1.5 rounded-lg flex items-center gap-1.5 transition-all"
            style={{ background: lb, border: `1px solid ${bc}` }}>
            <div className="w-3 h-3 rounded-sm shrink-0" style={{ background: "linear-gradient(135deg,#FFF9C4,#FFECB3)" }} />
            <p className="text-[11px] font-medium" style={{ color: c }}>Warm amber tint applied</p>
          </div>
        )}

        <div className="flex items-center justify-between px-4 py-3 border-t border-[#F3F4F6]" style={{ minHeight: 56 }}>
          <div className="flex items-center gap-1.5 flex-1 min-w-0 pr-4">
            <Volume2 size={13} style={{ color: readAloudGlobal ? c : "#595959", flexShrink: 0 }} />
            <div className="min-w-0">
              <p className="text-[14px] font-semibold text-[#0F172A] leading-snug">
                Read aloud{" "}
                <span className="text-[10px] font-bold bg-[#E0F7FA] text-[#00A7C8] px-1.5 py-0.5 rounded">beta</span>
              </p>
              <p className="text-[11px] text-[#595959]">{readAloudGlobal ? "Tap any text to hear it spoken" : "Screen-reader TTS preference"}</p>
            </div>
          </div>
          <Switch checked={readAloudGlobal} onChange={setReadAloudGlobal} id="s-ra" color={c} />
        </div>
        {readAloudGlobal && (
          <div className="mx-4 mb-3 px-3 py-1.5 rounded-lg flex items-center gap-2"
            style={{ background: lb, border: `1px solid ${bc}` }}>
            <Volume2 size={11} style={{ color: c }} />
            <p className="text-[11px] font-medium" style={{ color: c }}>Active — tap any text block to hear it</p>
          </div>
        )}

        <SettingRow id="s-fi" label="Focus indicators" subtitle="Show a bold ring around the focused element" checked={focusIndicators} onChange={setFocusIndicators} color={c} last />
      </SectionCard>

      {/* ── Motion & animation ── */}
      <SectionCard icon={<Wind size={14} />} title="Motion & animation" color={c} lightBg={lb} borderColor={bc}>
        <SettingRow id="s-rm" label="Reduce motion" subtitle="Use simple fade transitions instead of animations" checked={reduceMotion} onChange={setReduceMotion} color={c} />
        {reduceMotion && (
          <div className="mx-4 mb-2 -mt-1 px-3 py-1.5 rounded-lg flex items-center gap-2"
            style={{ background: lb, border: `1px solid ${bc}` }}>
            <div className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: c }} />
            <p className="text-[11px] font-medium" style={{ color: c }}>Animations paused — fade transitions only</p>
          </div>
        )}
        <SettingRow id="s-ap" label="Auto-play media" subtitle="Allow videos and animations to start automatically" checked={autoPlay} onChange={setAutoPlay} color={c} last />
      </SectionCard>

      {/* ── Motor & touch ── */}
      <SectionCard icon={<MousePointer size={14} />} title="Motor &amp; touch" color={c} lightBg={lb} borderColor={bc}>
        <SettingRow id="s-tm" label="Tremor mode" subtitle="Enlarge buttons and touch targets to 60“80 dp" checked={tremorMode} onChange={setTremorMode} color={c} large />
        {tremorMode && (
          <div className="mx-4 mb-2 -mt-1 px-3 py-1.5 rounded-lg flex items-center gap-2"
            style={{ background: lb, border: `1px solid ${bc}` }}>
            <Zap size={11} style={{ color: c }} />
            <p className="text-[11px] font-medium" style={{ color: c }}>All touch targets enlarged across the app</p>
          </div>
        )}
        <SettingRow id="s-ca" label="Confirm actions" subtitle="Ask before important or hard-to-reverse actions" checked={confirmActions} onChange={setConfirmActions} color={c} last />
      </SectionCard>

      {/* ── Hearing ── */}
      <SectionCard icon={<Ear size={14} />} title="Hearing accessibility" color={c} lightBg={lb} borderColor={bc}>
        <SettingRow id="s-vib" label="Vibration alerts" subtitle="Vibrate when reminders and notifications fire" checked={vibration} onChange={setVibration} color={c} />
        <SettingRow id="s-va" label="Screen flash alerts" subtitle="Flash the screen border when an alert plays" checked={visualAlerts} onChange={setVisualAlerts} color={c} />
        {visualAlerts && (
          <div className="mx-4 mb-2 -mt-1 px-3 py-1.5 rounded-lg flex items-center gap-2"
            style={{ background: lb, border: `1px solid ${bc}` }}>
            <div className="w-2.5 h-2.5 rounded-sm shrink-0 animate-pulse" style={{ background: c }} />
            <p className="text-[11px] font-medium" style={{ color: c }}>Screen-edge flash active on alerts</p>
          </div>
        )}
        <SettingRow id="s-caps" label="Closed captions" subtitle="Show captions for all audio notifications and content" checked={captions} onChange={setCaptions} color={c} />
        {captions && (
          <div className="mx-4 mb-2 -mt-1 px-3 py-2 rounded-lg"
            style={{ background: lb, border: `1px solid ${bc}` }}>
            <p className="text-[10px] font-bold uppercase tracking-wider mb-1" style={{ color: c }}>Caption preview</p>
            <p className="text-[12px] italic text-[#374151]">"Medication reminder: Lisinopril 10mg at 8:00 AM"</p>
          </div>
        )}
        <SettingRow id="s-amp" label="Sound amplification" subtitle="Boost alert and notification volume to maximum" checked={soundAmplify} onChange={setSoundAmplify} color={c} />
        <SettingRow id="s-tty" label="TTY / text relay" subtitle="Enable TTY mode for text-based phone calls" checked={ttySupport} onChange={setTtySupport} color={c} />
        {ttySupport && (
          <div className="mx-4 mb-2 -mt-1 px-3 py-1.5 rounded-lg flex items-center gap-2"
            style={{ background: lb, border: `1px solid ${bc}` }}>
            <Phone size={11} style={{ color: c }} />
            <p className="text-[11px] font-medium" style={{ color: c }}>TTY relay enabled — text-based calling ready</p>
          </div>
        )}
        <SettingRow id="s-ham" label="Hearing aid compatibility" subtitle="Optimize audio output for hearing aids (M3/T3)" checked={hearingAidMode} onChange={setHearingAidMode} color={c} last />
        {hearingAidMode && (
          <div className="mx-4 mb-3 px-3 py-1.5 rounded-lg flex items-center gap-2"
            style={{ background: lb, border: `1px solid ${bc}` }}>
            <Ear size={11} style={{ color: c }} />
            <p className="text-[11px] font-medium" style={{ color: c }}>M3/T3 hearing aid mode active</p>
          </div>
        )}
      </SectionCard>

      {/* ── Cognitive support ── */}
      <SectionCard icon={<Brain size={14} />} title="Cognitive support" color={c} lightBg={lb} borderColor={bc}>
        <SettingRow id="s-sn" label="Simplified navigation" subtitle="Show only the most essential menu items" checked={simplifiedNav} onChange={setSimplifiedNav} color={c} />
        {simplifiedNav && (
          <div className="mx-4 mb-2 -mt-1 px-3 py-1.5 rounded-lg flex items-center gap-2"
            style={{ background: lb, border: `1px solid ${bc}` }}>
            <Shield size={11} style={{ color: c }} />
            <p className="text-[11px] font-medium" style={{ color: c }}>Non-essential items hidden from navigation</p>
          </div>
        )}
        <div className="px-4 py-3 border-t border-[#F3F4F6]" style={{ minHeight: 56 }}>
          <p className="text-[14px] font-semibold text-[#0F172A]">Session timeout</p>
          <p className="text-[11px] text-[#595959] mb-2">Auto-lock after inactivity</p>
          <div className="flex rounded-xl overflow-hidden border border-[#E5E7EB] bg-[#F3F4F6]">
            {(["5 min", "15 min", "30 min"] as const).map((label, i) => (
              <button key={label}
                className="flex-1 py-2 text-[11px] font-semibold transition-all duration-150"
                style={{ background: i === 1 ? c : "transparent", color: i === 1 ? "white" : "#595959" }}>
                {label}
              </button>
            ))}
          </div>
        </div>
      </SectionCard>

      {/* ── About ── */}
      <div className="rounded-2xl overflow-hidden border border-[#E5E7EB] bg-white">
        <div className="flex items-center gap-3 px-4 py-3 border-b border-[#F3F4F6]">
          <div className="w-10 h-10 rounded-xl bg-[#00A7C8] flex items-center justify-center shrink-0">
            <div className="w-5 h-5 rounded-full bg-white" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-[15px] font-bold text-[#0F172A]">CareConnect</p>
            <p className="text-[11px] text-[#595959]">Accessibility Settings · v2.4.1</p>
          </div>
          <span className="shrink-0 text-[10px] font-bold px-2 py-1 rounded-full"
            style={{ background: lb, color: c }}>{theme.name}</span>
        </div>
        {[
          { label: "Privacy policy",       sub: "How we use your data" },
          { label: "Accessibility help",   sub: "Guides and support resources" },
          { label: "Send feedback",        sub: "Report an issue or suggestion" },
        ].map((row, i, arr) => (
          <div key={row.label} className={`flex items-center justify-between px-4 py-3 ${i < arr.length - 1 ? "border-b border-[#F3F4F6]" : ""}`}
            style={{ minHeight: 52 }}>
            <div>
              <p className="text-[14px] font-semibold text-[#0F172A]">{row.label}</p>
              <p className="text-[11px] text-[#595959]">{row.sub}</p>
            </div>
            <ChevronRight size={15} className="text-[#CBD5E1] shrink-0" />
          </div>
        ))}
      </div>

      {/* ── Sign out ── */}
      <button
        onClick={onSignOut}
        className="w-full flex items-center justify-center gap-2 py-4 rounded-2xl font-bold text-[15px] transition-all hover:opacity-90 active:scale-[0.98]"
        style={{ background: "#FEF2F2", color: "#EF4444", border: "2px solid #FECACA", minHeight: 56 }}>
        <ArrowLeft size={18} /> Sign out of CareConnect
      </button>
      <p className="text-center text-[11px] text-[#9CA3AF] pb-2">
        Your profile, settings, and changes are saved on this device. Log back in anytime to continue where you left off.
      </p>

    </div>
  );
}

// ── Splash screen ──────────────────────────────────────────────────────────────

const SPLASH_MODES = [
  { label: "Short-term memory",  mode: "stml"    as AppMode, icon: <Brain size={16} />,    accent: "#A78BFA" },
  { label: "Dyslexia support",   mode: "dyslexia" as AppMode, icon: <BookOpen size={16} />, accent: "#34D399" },
  { label: "Carpal tunnel",mode: "carpal"  as AppMode, icon: <Hand size={16} />,     accent: "#FCD34D" },
  { label: "Hearing impaired",   mode: "hearing" as AppMode, icon: <Ear size={16} />,      accent: "#7DD3FC" },
  { label: "Custom / build my own", mode: "custom" as AppMode, icon: <Sliders size={16} />, accent: "#E2E8F0" },
];

function SplashScreen({ onGetStarted, onSignIn, onFeatureSignIn }: {
  onGetStarted: () => void;
  onSignIn: () => void;
  onFeatureSignIn: (mode: AppMode) => void;
}) {
  const [selectedMode, setSelectedMode] = useState<AppMode | null>(null);
  const [dropOpen, setDropOpen]         = useState(false);
  const dropRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (dropRef.current && !dropRef.current.contains(e.target as Node)) setDropOpen(false);
    };
    if (dropOpen) document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [dropOpen]);

  const selected = SPLASH_MODES.find(m => m.mode === selectedMode) ?? null;

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#EFF6FF] via-white to-[#E0F7FA] flex items-start justify-center py-8 px-4">
      <div
        className="relative w-full max-w-[390px] rounded-[2.5rem] overflow-hidden shadow-2xl flex flex-col"
        style={{ boxShadow: "0 20px 60px rgba(0,0,0,0.16)", height: 720, background: "#00A7C8" }}
      >
        {/* Status bar */}
        <div className="flex-none flex items-center justify-between px-6 pt-4 pb-1">
          <span className="text-[13px] font-semibold text-white/90">9:41</span>
          <div className="flex items-center gap-1.5">
            <div className="flex gap-0.5 items-end h-3">
              {[2, 3, 4, 5].map(h => <div key={h} className="w-1 bg-white/80 rounded-sm" style={{ height: h * 2.5 }} />)}
            </div>
            <div className="w-5 h-2.5 rounded-sm border border-white/70 p-px">
              <div className="w-full h-full bg-white/80 rounded-[1px]" />
            </div>
          </div>
        </div>

        {/* Hero area */}
        <div className="flex-1 flex flex-col items-center justify-center px-7 text-center gap-5">
          {/* Logo mark */}
          <div className="flex flex-col items-center gap-3">
            <div className="w-20 h-20 rounded-3xl bg-white/20 border-2 border-white/40 flex items-center justify-center shadow-lg">
              <div className="flex flex-col items-center gap-1">
                <div className="w-9 h-9 rounded-full bg-white flex items-center justify-center">
                  <div className="w-4.5 h-4.5 rounded-full bg-[#00A7C8]" style={{ width: 18, height: 18 }} />
                </div>
                <div className="flex gap-1">
                  {[0,1,2].map(i => <div key={i} className="w-2.5 h-2.5 rounded-full bg-white/70" />)}
                </div>
              </div>
            </div>
            <div>
              <p className="text-[30px] font-bold text-white leading-none tracking-tight">CareConnect</p>
              <div className="flex items-center justify-center gap-2 mt-2">
                <div className="h-px w-8 bg-white/40" />
                <p className="text-[12px] font-semibold text-white/80 uppercase tracking-[0.18em]">Your Care, Your Way</p>
                <div className="h-px w-8 bg-white/40" />
              </div>
            </div>
          </div>

          {/* Mode dropdown */}
          <div className="w-full flex flex-col gap-3">
            <p className="text-[11px] font-semibold text-white/60 uppercase tracking-wider">
              Select your accessibility mode
            </p>

            <div className="relative" ref={dropRef}>
              {/* Trigger */}
              <button
                onClick={() => setDropOpen(v => !v)}
                className="w-full flex items-center justify-between gap-3 px-4 py-3.5 rounded-2xl transition-all duration-150 active:scale-[0.98]"
                style={{
                  background: selected ? "rgba(255,255,255,0.22)" : "rgba(255,255,255,0.15)",
                  border: `1.5px solid ${selected ? "rgba(255,255,255,0.55)" : "rgba(255,255,255,0.30)"}`,
                  minHeight: 58,
                }}
              >
                {selected ? (
                  <div className="flex items-center gap-3 flex-1 min-w-0">
                    <div className="w-8 h-8 rounded-xl flex items-center justify-center bg-white/20 text-white shrink-0">
                      {selected.icon}
                    </div>
                    <span className="text-[15px] font-semibold text-white truncate">{selected.label}</span>
                  </div>
                ) : (
                  <span className="text-[15px] text-white/60 flex-1 text-left">Choose a mode…</span>
                )}
                <ChevronDown size={18} className="shrink-0 text-white/70 transition-transform duration-200"
                  style={{ transform: dropOpen ? "rotate(180deg)" : "rotate(0deg)" }} />
              </button>

              {/* Dropdown list */}
              {dropOpen && (
                <div className="absolute left-0 right-0 z-50 mt-2 rounded-2xl overflow-hidden"
                  style={{ background: "rgba(0,55,80,0.97)", border: "1.5px solid rgba(255,255,255,0.18)", boxShadow: "0 16px 40px rgba(0,0,0,0.35)" }}>
                  {SPLASH_MODES.map((m, i) => (
                    <button
                      key={m.mode}
                      onClick={() => { setSelectedMode(m.mode); setDropOpen(false); }}
                      className={`w-full flex items-center gap-3 px-4 py-3.5 text-left transition-all duration-100 ${i > 0 ? "border-t border-white/10" : ""}`}
                      style={{
                        background: selectedMode === m.mode ? "rgba(255,255,255,0.12)" : "transparent",
                        minHeight: 54,
                      }}
                    >
                      <div className="w-8 h-8 rounded-xl flex items-center justify-center shrink-0"
                        style={{ background: m.accent + "33", color: m.accent, border: `1px solid ${m.accent}55` }}>
                        {m.icon}
                      </div>
                      <span className="text-[14px] font-semibold text-white flex-1">{m.label}</span>
                      {selectedMode === m.mode && <Check size={15} className="shrink-0" style={{ color: m.accent }} />}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Sign-in CTA for selected mode */}
            {selected && (
              <button
                onClick={() => onFeatureSignIn(selected.mode)}
                className="w-full flex items-center justify-center gap-2 py-3.5 rounded-2xl font-bold text-[15px] transition-all duration-150 active:scale-[0.98] hover:opacity-90"
                style={{ background: "rgba(255,255,255,0.22)", border: "1.5px solid rgba(255,255,255,0.45)", color: "white", minHeight: 52 }}>
                <User size={16} /> Sign in to {selected.label}
              </button>
            )}
          </div>

          {/* Tagline */}
          <p className="text-[13px] text-white/65 leading-relaxed max-w-[260px] text-center">
            Personalised tools built around the way <em className="not-italic font-bold text-white">you</em> experience the world.
          </p>
        </div>

        {/* CTA */}
        <div className="flex-none px-6 pb-8 flex flex-col gap-3">
          <button
            onClick={onGetStarted}
            className="w-full py-4 rounded-2xl font-bold text-[17px] transition-all duration-150 active:scale-[0.98] hover:opacity-90"
            style={{ background: "white", color: "#00A7C8", minHeight: 60 }}>
            Get started
          </button>
          <button
            onClick={onSignIn}
            className="w-full py-3.5 rounded-2xl font-bold text-[15px] transition-all duration-150 active:scale-[0.98] hover:bg-white/20 border-2 border-white/50 text-white"
            style={{ minHeight: 52 }}>
            Sign in
          </button>
        </div>

        {/* Home indicator */}
        <div className="flex-none flex justify-center py-2">
          <div className="w-28 h-1 bg-white/30 rounded-full" />
        </div>
      </div>
    </div>
  );
}

// ── Sign-in screen ──────────────────────────────────────────────────────────────

const AUTH_COLORS = [
  { hex: "#3B82F6", label: "Blue"   },
  { hex: "#EF4444", label: "Red"    },
  { hex: "#F59E0B", label: "Amber"  },
  { hex: "#10B981", label: "Green"  },
  { hex: "#8B5CF6", label: "Purple" },
  { hex: "#F97316", label: "Orange" },
];

type SignInMethod = "pin" | "password" | "color";

function SignInScreen({
  onSuccess, nav, savedEmail, savedPassword, savedPin, savedColorSeq, savedName, initialRole = "patient",
}: {
  onSuccess: (loginRole: Role, caregiverId?: string) => void;
  nav: NavProps;
  savedEmail?: string;
  savedPassword?: string;
  savedPin?: string;
  savedColorSeq?: string[];
  savedName?: string;
  initialRole?: Role;
}) {
  const [loginRole, setLoginRole]           = useState<Role>(initialRole);
  const configuredCaregivers = listConfiguredCaregiverAccounts();
  const [caregiverId, setCaregiverId]       = useState<string>(
    () => configuredCaregivers[0]?.id || "cg1"
  );
  const [method, setMethod]             = useState<SignInMethod>("password");
  const [pin, setPin]                   = useState("");
  const [pinStatus, setPinStatus]       = useState<"idle" | "error" | "success">("idle");
  const [emailInput, setEmailInput]     = useState("");
  const [password, setPassword]         = useState("");
  const [showPw, setShowPw]             = useState(false);
  const [pwError, setPwError]           = useState(false);
  const [emailError, setEmailError]     = useState(false);
  const [colorSeq, setColorSeq]         = useState<string[]>([]);
  const [colorStatus, setColorStatus]   = useState<"idle" | "error" | "success">("idle");
  const [showEmergency, setShowEmergency] = useState(false);

  useEffect(() => {
    setLoginRole(initialRole);
  }, [initialRole]);

  const cgAccount = loginRole === "caregiver" ? loadCaregiverAccount(caregiverId) : null;
  const CORRECT_PIN = (loginRole === "caregiver" ? cgAccount?.pin : savedPin)?.trim() || "";
  const CORRECT_PW  = (loginRole === "caregiver" ? cgAccount?.password : savedPassword)?.trim() || "";
  const CORRECT_SEQ = (loginRole === "caregiver" ? cgAccount?.colorSeq : savedColorSeq) ?? [];
  const expectedEmail = (
    loginRole === "caregiver"
      ? (cgAccount?.email?.trim() || "")
      : (savedEmail?.trim() || "")
  ).toLowerCase();
  const expectedName = (
    loginRole === "caregiver"
      ? (cgAccount?.name?.trim() || "")
      : (savedName?.trim() || "")
  ).toLowerCase();

  // Prefill email when role / caregiver account changes, but keep it editable
  useEffect(() => {
    const prefill = loginRole === "caregiver"
      ? (cgAccount?.email?.trim() || "")
      : (savedEmail?.trim() || "");
    setEmailInput(prefill);
    setEmailError(false);
  }, [loginRole, caregiverId, savedEmail, cgAccount?.email]);

  const finish = () => {
    if (loginRole === "caregiver") {
      const acct = loadCaregiverAccount(caregiverId);
      if (!caregiverAccountConfigured(acct)) return;
    }
    onSuccess(loginRole, loginRole === "caregiver" ? caregiverId : undefined);
  };

  const switchMethod = (m: SignInMethod) => {
    setMethod(m); setPin(""); setPinStatus("idle");
    setPassword(""); setPwError(false); setEmailError(false);
    setColorSeq([]); setColorStatus("idle");
  };

  const emailMatchesAccount = (raw: string) => {
    const entered = raw.trim().toLowerCase();
    if (!entered) return false;
    if (expectedEmail && entered === expectedEmail) return true;
    if (expectedName && entered === expectedName) return true;
    // If no email was saved on the profile yet, accept any non-empty entry with the correct password
    if (!expectedEmail && !expectedName) return true;
    return false;
  };

  const pressPin = (d: string) => {
    if (pinStatus !== "idle") return;
    if (!CORRECT_PIN) return;
    const next = pin + d;
    setPin(next);
    if (next.length === 4) {
      if (next === CORRECT_PIN) {
        setPinStatus("success");
        setTimeout(finish, 700);
      } else {
        setPinStatus("error");
        setTimeout(() => { setPin(""); setPinStatus("idle"); }, 900);
      }
    }
  };
  const deletePin = () => { if (pinStatus === "idle") setPin(p => p.slice(0, -1)); };

  const submitPw = () => {
    if (!CORRECT_PW) { setPwError(true); setTimeout(() => setPwError(false), 1500); return; }
    if (!emailMatchesAccount(emailInput)) {
      setEmailError(true);
      setTimeout(() => setEmailError(false), 2000);
      return;
    }
    if (password === CORRECT_PW) { finish(); }
    else { setPwError(true); setTimeout(() => setPwError(false), 1500); }
  };

  const tapColor = (hex: string) => {
    if (colorStatus !== "idle" || colorSeq.length >= 3) return;
    if (CORRECT_SEQ.length !== 3) return;
    const next = [...colorSeq, hex];
    setColorSeq(next);
    if (next.length === 3) {
      if (next.join() === CORRECT_SEQ.join()) {
        setColorStatus("success");
        setTimeout(finish, 600);
      } else {
        setColorStatus("error");
        setTimeout(() => { setColorSeq([]); setColorStatus("idle"); }, 900);
      }
    }
  };

  const notSetHint = (label: string) => (
    <div className="rounded-2xl px-4 py-3 text-center" style={{ background: "#FFFBEB", border: "1px solid #FDE68A" }}>
      <p className="text-[13px] font-semibold text-[#92400E]">
        No {label} set yet. Create a profile to set up PIN, password, and colour sequence.
      </p>
    </div>
  );

  const emergencyOverlay = showEmergency ? (
    <div className="absolute inset-0 bg-black/60 flex flex-col justify-end" style={{ borderRadius: "2.5rem" }}>
      <div className="bg-white rounded-t-3xl p-6 flex flex-col gap-4">
        <div className="w-10 h-1 rounded-full bg-[#E5E7EB] mx-auto mb-1" />
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-full bg-[#FEF2F2] flex items-center justify-center shrink-0">
            <AlertTriangle size={22} className="text-[#EF4444]" />
          </div>
          <div>
            <p className="text-[17px] font-bold text-[#0F172A]">Emergency access</p>
            <p className="text-[12px] text-[#595959]">Urgent entry only — not a normal sign-in</p>
          </div>
        </div>
        <p className="text-[13px] text-[#595959] leading-relaxed">
          This bypasses authentication and opens CareConnect immediately. Use in urgent situations only.
        </p>
        <button onClick={finish}
          className="w-full py-4 rounded-2xl font-bold text-white text-[15px] flex items-center justify-center gap-2"
          style={{ background: "#EF4444", minHeight: 56 }}>
          <AlertTriangle size={17} /> Enter CareConnect now
        </button>
        <button onClick={() => setShowEmergency(false)}
          className="w-full py-3 rounded-2xl font-semibold text-[14px] text-[#595959]"
          style={{ border: "2px solid #E5E7EB" }}>
          Cancel — try sign-in again
        </button>
      </div>
    </div>
  ) : undefined;

  return (
    <PhoneShell shellBg="bg-white" overlay={emergencyOverlay} nav={nav}>
      <div className="px-5 pt-5 pb-8 flex flex-col gap-5">

        <div className="flex items-center gap-3">
          <div className="w-11 h-11 rounded-2xl flex items-center justify-center shrink-0"
            style={{ background: "#00A7C8" }}>
            <div className="w-5 h-5 rounded-full bg-white" />
          </div>
          <div>
            <p className="text-[19px] font-bold text-[#0F172A]">CareConnect</p>
            <p className="text-[12px] text-[#595959]">
              Sign in as {loginRole === "caregiver" ? "Caregiver" : "Patient / User"}
            </p>
          </div>
        </div>

        <div className="flex flex-col gap-2">
          <p className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">I am signing in as…</p>
          <div className="grid grid-cols-2 gap-2">
            {([
              { key: "patient" as Role, icon: "👤", label: "Patient / User", hint: "Your health profile" },
              { key: "caregiver" as Role, icon: "🏥", label: "Caregiver", hint: "Shared patient data only" },
            ]).map(opt => (
              <button key={opt.key} type="button" onClick={() => { setLoginRole(opt.key); switchMethod(method); }}
                className="text-left px-3 py-3 rounded-xl border-2 transition-all"
                style={{
                  borderColor: loginRole === opt.key ? "#00A7C8" : "#E5E7EB",
                  background: loginRole === opt.key ? "#E0F7FA" : "white",
                }}>
                <p className="text-[14px] font-bold" style={{ color: loginRole === opt.key ? "#007A94" : "#0F172A" }}>
                  {opt.icon} {opt.label}
                </p>
                <p className="text-[11px] text-[#9CA3AF] mt-0.5">{opt.hint}</p>
              </button>
            ))}
          </div>
        </div>

        {loginRole === "caregiver" && (
          <div className="flex flex-col gap-2 p-3 rounded-2xl" style={{ background: "#F8FAFC", border: "1px solid #E5E7EB" }}>
            <p className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">Which caregiver are you?</p>
            {configuredCaregivers.length === 0 ? (
              <div className="rounded-xl px-3 py-3" style={{ background: "#FFFBEB", border: "1px solid #FDE68A" }}>
                <p className="text-[13px] font-semibold text-[#92400E]">No caregiver profile yet</p>
                <p className="text-[12px] text-[#B45309] mt-1">
                  Create a caregiver account with your name and relationship first. Demo names like Maria Rodriguez are no longer used.
                </p>
              </div>
            ) : (
              <>
                <p className="text-[11px] text-[#6B7280] mb-1">
                  Select your account — shown as your name and relationship to the patient.
                </p>
                {configuredCaregivers.map(({ id, account }) => {
                  const relation = caregiverRoleLabel(account, id);
                  return (
                    <button key={id} type="button" onClick={() => { setCaregiverId(id); switchMethod(method); }}
                      className="text-left px-3 py-2.5 rounded-xl border-2 transition-all"
                      style={{
                        borderColor: caregiverId === id ? "#00A7C8" : "#E5E7EB",
                        background: caregiverId === id ? "white" : "#F9FAFB",
                      }}>
                      <p className="text-[13px] font-bold text-[#0F172A]">{account.name}</p>
                      <p className="text-[12px] font-semibold" style={{ color: "#007A94" }}>
                        {relation}
                      </p>
                    </button>
                  );
                })}
              </>
            )}
          </div>
        )}

        <div className="flex gap-1 p-1 rounded-xl bg-[#F3F4F6]">
          {(["pin", "password", "color"] as SignInMethod[]).map(m => (
            <button key={m} type="button" onClick={() => switchMethod(m)}
              className="flex-1 py-2 rounded-lg text-[12px] font-bold transition-all duration-150"
              style={{
                background: method === m ? "white" : "transparent",
                color: method === m ? "#0F172A" : "#9CA3AF",
                boxShadow: method === m ? "0 1px 3px rgba(0,0,0,0.08)" : "none",
              }}>
              {m === "pin" ? "PIN" : m === "password" ? "Password" : "Colour"}
            </button>
          ))}
        </div>

        {method === "pin" && (
          <div className="flex flex-col items-center gap-5">
            {!CORRECT_PIN ? notSetHint("PIN") : (
              <>
                <div className="text-center">
                  <p className="text-[13px] text-[#595959] mb-4">Enter your 4-digit PIN</p>
                  <div className="flex gap-4 justify-center">
                    {[0, 1, 2, 3].map(i => (
                      <div key={i} className="w-4 h-4 rounded-full border-2 transition-all duration-150"
                        style={{
                          borderColor: pinStatus === "error" ? "#EF4444" : pinStatus === "success" ? "#10B981" : "#00A7C8",
                          background: i < pin.length
                            ? (pinStatus === "error" ? "#EF4444" : pinStatus === "success" ? "#10B981" : "#00A7C8")
                            : "transparent",
                        }} />
                    ))}
                  </div>
                  {pinStatus === "error"   && <p className="text-[12px] text-[#EF4444] mt-2 font-semibold">Incorrect PIN — try again</p>}
                  {pinStatus === "success" && <p className="text-[12px] text-[#10B981] mt-2 font-semibold">✓ Correct — welcome back!</p>}
                </div>

                <div className="grid grid-cols-3 gap-2.5 w-full">
                  {["1","2","3","4","5","6","7","8","9"].map(d => (
                    <button key={d} type="button" onClick={() => pressPin(d)}
                      className="flex items-center justify-center rounded-2xl bg-white text-[22px] font-semibold text-[#0F172A] transition-all duration-100 active:scale-95"
                      style={{ minHeight: 64, border: "2px solid #E5E7EB" }}>
                      {d}
                    </button>
                  ))}
                  <button type="button" onClick={deletePin}
                    className="flex items-center justify-center rounded-2xl bg-white text-[20px] text-[#595959] transition-all"
                    style={{ minHeight: 64, border: "2px solid #E5E7EB" }}>
                    ⌫
                  </button>
                  <button type="button" onClick={() => pressPin("0")}
                    className="flex items-center justify-center rounded-2xl bg-white text-[22px] font-semibold text-[#0F172A] transition-all active:scale-95"
                    style={{ minHeight: 64, border: "2px solid #E5E7EB" }}>
                    0
                  </button>
                  <div className="flex items-center justify-center rounded-2xl text-white"
                    style={{ minHeight: 64, background: "#00A7C8", border: "2px solid #00A7C8" }}>
                    <Check size={22} />
                  </div>
                </div>
              </>
            )}
          </div>
        )}

        {method === "password" && (
          <div className="flex flex-col gap-4">
            {!CORRECT_PW ? notSetHint("password") : (
              <>
                <p className="text-[13px] text-[#595959] text-center">Enter your credentials</p>
                <div className="flex flex-col gap-1.5">
                  <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">Email</label>
                  <input
                    type="email"
                    inputMode="email"
                    autoComplete="username"
                    autoCapitalize="none"
                    autoCorrect="off"
                    spellCheck={false}
                    value={emailInput}
                    onChange={e => { setEmailInput(e.target.value); setEmailError(false); }}
                    onKeyDown={e => e.key === "Enter" && submitPw()}
                    placeholder="you@email.com"
                    className="w-full px-4 py-3.5 rounded-xl text-[#0F172A] outline-none transition-all"
                    style={{
                      border: `2px solid ${emailError ? "#EF4444" : "#E5E7EB"}`,
                      background: "white",
                      fontSize: 16,
                      WebkitAppearance: "none",
                    }}
                  />
                  {emailError && (
                    <p className="text-[12px] text-[#EF4444] font-semibold">
                      Email doesn&apos;t match this account — check and try again
                    </p>
                  )}
                </div>
                <div className="relative">
                  <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider block mb-1.5">Password</label>
                  <input
                    type={showPw ? "text" : "password"}
                    value={password}
                    autoComplete="current-password"
                    onChange={e => { setPassword(e.target.value); setPwError(false); }}
                    onKeyDown={e => e.key === "Enter" && submitPw()}
                    placeholder="Password"
                    className="w-full px-4 py-3.5 rounded-xl text-[#0F172A] outline-none transition-all"
                    style={{ border: `2px solid ${pwError ? "#EF4444" : "#E5E7EB"}`, paddingRight: 48, fontSize: 16 }}
                  />
                  <button
                    type="button"
                    onMouseDown={e => e.preventDefault()}
                    onClick={() => setShowPw(v => !v)}
                    className="absolute right-4 bottom-3.5 text-[#9CA3AF] hover:text-[#595959] transition-colors">
                    {showPw ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
                {pwError && <p className="text-[12px] text-[#EF4444] text-center -mt-2 font-semibold">Incorrect password — try again</p>}
                <button type="button" onClick={submitPw}
                  className="w-full py-4 rounded-xl font-bold text-white text-[15px] transition-all hover:opacity-90"
                  style={{ background: "#00A7C8", minHeight: 56 }}>
                  Sign in
                </button>
              </>
            )}
          </div>
        )}

        {method === "color" && (
          <div className="flex flex-col items-center gap-4">
            {CORRECT_SEQ.length !== 3 ? notSetHint("colour sequence") : (
              <>
                <div className="text-center">
                  <p className="text-[13px] font-semibold text-[#595959] mb-0.5">Tap your colour sequence</p>
                  <p className="text-[11px] text-[#9CA3AF]">Select 3 colours in the correct order</p>
                </div>

                <div className="flex gap-3">
                  {[0, 1, 2].map(i => (
                    <div key={i} className="w-12 h-12 rounded-full border-2 transition-all duration-200 flex items-center justify-center"
                      style={{
                        borderStyle: colorSeq[i] ? "solid" : "dashed",
                        borderColor: colorStatus === "error" ? "#EF4444" : colorStatus === "success" ? "#10B981" : colorSeq[i] ?? "#CBD5E1",
                        background: colorSeq[i] ?? "transparent",
                      }}>
                      {!colorSeq[i] && <span className="text-[15px] font-bold text-[#CBD5E1]">{i + 1}</span>}
                    </div>
                  ))}
                </div>

                {colorStatus === "error"   && <p className="text-[12px] text-[#EF4444] font-semibold">Wrong sequence — try again</p>}
                {colorStatus === "success" && <p className="text-[12px] text-[#10B981] font-semibold">✓ Correct — welcome back!</p>}

                <div className="grid grid-cols-3 gap-2.5 w-full">
                  {AUTH_COLORS.map(col => {
                    const isPicked = colorSeq.includes(col.hex);
                    return (
                      <button key={col.hex} type="button" onClick={() => tapColor(col.hex)}
                        disabled={isPicked || colorSeq.length >= 3}
                        className="flex flex-col items-center justify-center gap-2 p-3 rounded-2xl transition-all duration-150"
                        style={{
                          border: `2px solid ${isPicked ? col.hex : "#E5E7EB"}`,
                          background: isPicked ? col.hex + "22" : "white",
                          opacity: isPicked ? 0.5 : 1,
                          minHeight: 78,
                        }}>
                        <div className="w-10 h-10 rounded-full shadow-sm" style={{ background: col.hex }} />
                        <p className="text-[10px] font-bold text-[#595959] uppercase tracking-wide">{col.label}</p>
                      </button>
                    );
                  })}
                </div>

                {colorSeq.length > 0 && colorStatus === "idle" && (
                  <button type="button" onClick={() => setColorSeq([])}
                    className="text-[12px] font-semibold text-[#595959] underline underline-offset-2">
                    Clear &amp; start over
                  </button>
                )}
              </>
            )}

            <button type="button" onClick={() => setShowEmergency(true)}
              className="w-full flex items-center justify-center gap-2 py-3.5 rounded-2xl font-bold text-[14px] text-white transition-all hover:opacity-90"
              style={{ background: "#EF4444", minHeight: 52 }}>
              <AlertTriangle size={16} /> Emergency access
            </button>
          </div>
        )}

        <div className="flex items-center justify-between pt-1">
          <button
            type="button"
            onClick={nav.onBack}
            disabled={!nav.canGoBack}
            className="flex items-center gap-1.5 text-[12px] font-semibold transition-colors"
            style={{ color: nav.canGoBack ? "#00A7C8" : "#CBD5E1" }}>
            <ChevronLeft size={14} /> Back to CareConnect
          </button>
        </div>
      </div>
    </PhoneShell>
  );
}

// ── Profile panel (full overlay — contains avatar + all settings) ──────────────

interface ProfilePanelProps {
  profileImage: string | null; setProfileImage: (v: string | null) => void;
  profileName: string; setProfileName: (v: string) => void;
  theme: ModeTheme;
  onClose: () => void;
  // forwarded settings props
  mode: AppMode | null; setMode: (m: AppMode) => void;
  customSettings: CustomSettings; setCustomSettings: (s: CustomSettings) => void;
  disability: string; setDisability: (v: string) => void;
  textSize: 0|1|2; setTextSize: (v: 0|1|2) => void;
  highContrast: boolean; setHighContrast: (v: boolean) => void;
  boldText: boolean; setBoldText: (v: boolean) => void;
  colorFilter: boolean; setColorFilter: (v: boolean) => void;
  reduceMotion: boolean; setReduceMotion: (v: boolean) => void;
  autoPlay: boolean; setAutoPlay: (v: boolean) => void;
  readAloudGlobal: boolean; setReadAloudGlobal: (v: boolean) => void;
  focusIndicators: boolean; setFocusIndicators: (v: boolean) => void;
  tremorMode: boolean; setTremorMode: (v: boolean) => void;
  confirmActions: boolean; setConfirmActions: (v: boolean) => void;
  vibration: boolean; setVibration: (v: boolean) => void;
  visualAlerts: boolean; setVisualAlerts: (v: boolean) => void;
  simplifiedNav: boolean; setSimplifiedNav: (v: boolean) => void;
  captions: boolean; setCaptions: (v: boolean) => void;
  soundAmplify: boolean; setSoundAmplify: (v: boolean) => void;
  ttySupport: boolean; setTtySupport: (v: boolean) => void;
  hearingAidMode: boolean; setHearingAidMode: (v: boolean) => void;
  onSignOut: () => void;
}

function ProfilePanel(props: ProfilePanelProps) {
  const { profileImage, setProfileImage, profileName, setProfileName, theme, onClose } = props;
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [editingName, setEditingName] = useState(false);
  const [nameInput, setNameInput]     = useState(profileName);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = ev => { if (ev.target?.result) setProfileImage(ev.target.result as string); };
    reader.readAsDataURL(file);
  };

  const saveName = () => { setProfileName(nameInput.trim() || profileName); setEditingName(false); };

  return (
    <div className="absolute inset-0 bg-white z-50 flex flex-col overflow-hidden rounded-[2.5rem]">
      {/* Panel header */}
      <div className="flex-none flex items-center justify-between px-5 pt-5 pb-3 border-b border-[#F3F4F6]">
        <p className="text-[18px] font-bold text-[#0F172A]">Profile &amp; Settings</p>
        <button onClick={onClose}
          className="w-9 h-9 flex items-center justify-center rounded-full bg-[#F3F4F6] text-[#595959] font-bold text-[18px] leading-none hover:bg-[#E5E7EB] transition-colors">
          ×
        </button>
      </div>

      <div className="flex-1 overflow-y-auto">
        {/* ── Avatar section ── */}
        <div className="flex flex-col items-center px-5 py-6 gap-3 border-b border-[#F3F4F6]">
          {/* Avatar circle */}
          <div className="relative">
            <div className="w-24 h-24 rounded-full overflow-hidden border-4 flex items-center justify-center"
              style={{ borderColor: theme.color, background: theme.lightBg }}>
              {profileImage
                ? <img src={profileImage} className="w-full h-full object-cover" />
                : <User size={40} style={{ color: theme.color }} />}
            </div>
            {/* Camera badge */}
            <button
              onClick={() => fileInputRef.current?.click()}
              className="absolute bottom-0 right-0 w-8 h-8 rounded-full flex items-center justify-center border-2 border-white shadow-md transition-all hover:opacity-80"
              style={{ background: theme.color }}
              aria-label="Change profile photo">
              <Settings size={13} color="white" />
            </button>
          </div>

          {/* Hidden file input */}
          <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={handleFileChange} />

          {/* Name */}
          {editingName ? (
            <div className="flex items-center gap-2 w-full max-w-[220px]">
              <input
                autoFocus
                value={nameInput}
                onChange={e => setNameInput(e.target.value)}
                onKeyDown={e => e.key === "Enter" && saveName()}
                className="flex-1 px-3 py-2 rounded-xl border-2 text-[15px] font-bold text-center text-[#0F172A] outline-none"
                style={{ borderColor: theme.color }}
              />
              <button onClick={saveName}
                className="w-8 h-8 rounded-xl flex items-center justify-center text-white"
                style={{ background: theme.color }}>
                <Check size={15} />
              </button>
            </div>
          ) : (
            <button onClick={() => { setNameInput(profileName); setEditingName(true); }}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl hover:opacity-80 transition-opacity">
              <p className="text-[17px] font-bold text-[#0F172A]">{profileName}</p>
              <div className="w-5 h-5 rounded-full flex items-center justify-center" style={{ background: theme.lightBg }}>
                <Settings size={10} style={{ color: theme.color }} />
              </div>
            </button>
          )}

          <button
            onClick={() => fileInputRef.current?.click()}
            className="text-[12px] font-semibold px-4 py-2 rounded-xl transition-all hover:opacity-80"
            style={{ background: theme.lightBg, color: theme.color, border: `1.5px solid ${theme.borderColor}` }}>
            Change profile photo
          </button>
        </div>

        {/* ── All settings (reuse SettingsContent) ── */}
        <SettingsContent
          mode={props.mode} setMode={props.setMode}
          customSettings={props.customSettings} setCustomSettings={props.setCustomSettings}
          theme={theme}
          disability={props.disability} setDisability={props.setDisability}
          textSize={props.textSize} setTextSize={props.setTextSize}
          highContrast={props.highContrast} setHighContrast={props.setHighContrast}
          boldText={props.boldText} setBoldText={props.setBoldText}
          colorFilter={props.colorFilter} setColorFilter={props.setColorFilter}
          reduceMotion={props.reduceMotion} setReduceMotion={props.setReduceMotion}
          autoPlay={props.autoPlay} setAutoPlay={props.setAutoPlay}
          readAloudGlobal={props.readAloudGlobal} setReadAloudGlobal={props.setReadAloudGlobal}
          focusIndicators={props.focusIndicators} setFocusIndicators={props.setFocusIndicators}
          tremorMode={props.tremorMode} setTremorMode={props.setTremorMode}
          confirmActions={props.confirmActions} setConfirmActions={props.setConfirmActions}
          vibration={props.vibration} setVibration={props.setVibration}
          visualAlerts={props.visualAlerts} setVisualAlerts={props.setVisualAlerts}
          simplifiedNav={props.simplifiedNav} setSimplifiedNav={props.setSimplifiedNav}
          captions={props.captions} setCaptions={props.setCaptions}
          soundAmplify={props.soundAmplify} setSoundAmplify={props.setSoundAmplify}
          ttySupport={props.ttySupport} setTtySupport={props.setTtySupport}
          hearingAidMode={props.hearingAidMode} setHearingAidMode={props.setHearingAidMode}
          onSignOut={props.onSignOut}
        />
      </div>
    </div>
  );
}

// ── Root App ───────────────────────────────────────────────────────────────────

const DEFAULT_MEDICATIONS: Medication[] = [
  { id: "m1", name: "Lisinopril",   dose: "10mg",  time: "8:00 AM",  purpose: "Blood pressure" },
  { id: "m2", name: "Metformin",    dose: "500mg", time: "12:00 PM", purpose: "Blood sugar"    },
  { id: "m3", name: "Atorvastatin", dose: "20mg",  time: "9:00 PM",  purpose: "Cholesterol"    },
];

const DEFAULT_APPOINTMENTS: Appointment[] = [
  { id: "1", date: "Today",       time: "2:30 PM",    title: "Dr. Patel — General checkup",    type: "In person",  location: "Room 204, City Medical Center", confirmed: false },
  { id: "2", date: "Tomorrow",    time: "10:00 AM",   title: "Blood pressure check",           type: "Home check", location: "",                             confirmed: false },
  { id: "3", date: "Fri, Jul 18", time: "by 5:00 PM", title: "Refill Lisinopril prescription", type: "Pharmacy",   location: "CVS — Oak Street",             confirmed: false },
  { id: "4", date: "Sat, Jul 19", time: "3:00 PM",    title: "Video call with family",         type: "Video call", location: "",                             confirmed: false },
  { id: "5", date: "Thu, Jul 24", time: "9:00 AM",    title: "Dr. Singh — Cardiology",         type: "In person",  location: "St. Mary's Hospital",          confirmed: false },
];

// ── Role picker ───────────────────────────────────────────────────────────────

function RolePickerScreen({ nav, onSelect }: { nav: NavProps; onSelect: (r: Role) => void }) {
  return (
    <PhoneShell nav={nav} shellBg="bg-white">
      <div className="flex flex-col min-h-full px-6 py-8 gap-6">
        <div className="text-center">
          <div className="w-14 h-14 rounded-2xl flex items-center justify-center mx-auto mb-4" style={{ background: "#00A7C8" }}>
            <HeartPulse size={28} className="text-white" />
          </div>
          <h1 className="text-[22px] font-bold text-[#0F172A]">Welcome to CareConnect</h1>
          <p className="text-[14px] text-[#6B7280] mt-1.5">How will you be using the app?</p>
        </div>

        {[
          {
            role: "patient" as Role,
            icon: <User size={28} />,
            title: "Patient",
            subtitle: "Manage your health, medications, and care",
            color: "#00A7C8",
            bg: "#E0F7FA",
            features: ["Medication reminders", "Symptom tracking", "Virtual check-ins", "Appointment schedule"],
          },
          {
            role: "caregiver" as Role,
            icon: <Users size={28} />,
            title: "Caregiver",
            subtitle: "Coordinate and monitor patient care",
            color: "#0E7E57",
            bg: "#F0FDF4",
            features: ["Patient roster & status", "Visit verification (EVV)", "Care analytics", "Scheduling & tasks"],
          },
        ].map(opt => (
          <button
            key={opt.role}
            onClick={() => onSelect(opt.role)}
            className="w-full text-left p-5 rounded-2xl border-2 hover:scale-[1.01] transition-all"
            style={{ borderColor: opt.color + "40", background: opt.bg }}
          >
            <div className="flex items-center gap-4 mb-3">
              <div className="w-12 h-12 rounded-xl flex items-center justify-center shrink-0" style={{ background: opt.color }}>
                <span className="text-white">{opt.icon}</span>
              </div>
              <div>
                <p className="text-[18px] font-bold text-[#0F172A]">{opt.title}</p>
                <p className="text-[13px] text-[#6B7280]">{opt.subtitle}</p>
              </div>
              <ChevronRight size={20} className="ml-auto shrink-0 text-[#9CA3AF]" />
            </div>
            <div className="flex flex-wrap gap-2 mt-1">
              {opt.features.map(f => (
                <span key={f} className="text-[11px] font-semibold px-2.5 py-1 rounded-full"
                  style={{ background: opt.color + "20", color: opt.color }}>
                  {f}
                </span>
              ))}
            </div>
          </button>
        ))}
      </div>
    </PhoneShell>
  );
}

// ── Symptoms & Allergies (Patient) ─────────────────────────────────────────────

type SymptomCategory = DisabilityKey | "other";

interface LoggedSymptom {
  id: string;
  name: string;
  category: SymptomCategory;
  severity: number;
  time: string;
  note: string;
  date?: string; // YYYY-MM-DD for trend matching
}

interface LoggedAllergy {
  id: string;
  name: string;
  reaction: string;
  severity: "Mild" | "Moderate" | "Severe";
}

const SYMPTOM_CATALOG: { key: SymptomCategory; label: string; color: string; symptoms: string[] }[] = [
  {
    key: "stml", label: "Short-Term Memory Loss", color: "#7C3AED",
    symptoms: [
      "Forgetting recently learned information or recent events (e.g., whether medication was already taken)",
      "Losing track of what they were doing mid-task",
      "Repeating questions or actions without realizing it",
      "Misplacing items or forgetting appointments and dates",
      "Difficulty following multi-step instructions",
      "Trouble recalling names, words, or passwords on demand",
      "Increased anxiety or frustration from awareness of memory gaps",
    ],
  },
  {
    key: "dyslexia", label: "Dyslexia", color: "#0E7E57",
    symptoms: [
      "Slow, effortful reading that requires re-reading",
      "Letters appearing to move, blur, or run together on the page",
      "Confusing visually similar letters (b/d, p/q) or transposing them",
      "Difficulty spelling, even common words",
      "Trouble sounding out unfamiliar words",
      "Skipping words or losing their place in dense text",
      "Reading fatigue and headaches, especially with high-contrast white screens",
    ],
  },
  {
    key: "carpal", label: "Carpal Tunnel Syndrome", color: "#B45309",
    symptoms: [
      "Numbness or tingling in the thumb, index, and middle fingers",
      "Pain in the wrist or hand that worsens with repetitive motion (typing, tapping, scrolling)",
      "Weakened grip strength and dropping objects",
      "Difficulty with fine motor precision (small buttons, pinch gestures)",
      "Pain radiating up the forearm",
      "Symptoms worsening at night or after prolonged device use",
      "Hand fatigue after short periods of typing or swiping",
    ],
  },
  {
    key: "hearing", label: "Hearing Impairment", color: "#0284C7",
    symptoms: [
      "Inability to hear alerts, alarms, ringtones, or notification sounds",
      "Difficulty understanding speech, especially on phone calls or with background noise",
      "Missing spoken information in videos or voice messages",
      "Asking others to repeat themselves frequently",
      "Tinnitus (ringing or buzzing in the ears)",
      "Reliance on lip-reading, captions, or visual cues to follow conversation",
      "Social withdrawal or fatigue from the effort of listening",
    ],
  },
];

const DEFAULT_SYMPTOMS: LoggedSymptom[] = [];

const DEFAULT_ALLERGIES: LoggedAllergy[] = [];

type AllergyCategory = "food" | "medication" | "environmental" | "contact";

const ALLERGY_CATALOG: { key: AllergyCategory; label: string; color: string; allergies: string[] }[] = [
  {
    key: "food", label: "Food allergies (Big 9)", color: "#EF4444",
    allergies: [
      "Peanuts",
      "Tree nuts (almonds, walnuts, cashews, etc.)",
      "Milk / dairy",
      "Eggs",
      "Wheat",
      "Soy",
      "Fish (e.g., cod, salmon, tuna)",
      "Shellfish (shrimp, crab, lobster)",
      "Sesame",
    ],
  },
  {
    key: "medication", label: "Medication allergies", color: "#7C3AED",
    allergies: [
      "Penicillin and related antibiotics (amoxicillin)",
      "Sulfa drugs (sulfonamide antibiotics)",
      "NSAIDs (aspirin, ibuprofen)",
      "Opioids (codeine, morphine)",
      "Anticonvulsants / seizure medications",
    ],
  },
  {
    key: "environmental", label: "Environmental / inhalant", color: "#0284C7",
    allergies: [
      "Pollen (trees, grasses, ragweed — seasonal hay fever)",
      "Dust mites",
      "Mold spores",
      "Pet dander (cats, dogs)",
      "Cockroach droppings",
      "Smoke or strong odors/perfumes (irritant sensitivity)",
    ],
  },
  {
    key: "contact", label: "Contact and other", color: "#B45309",
    allergies: [
      "Latex (gloves, bandages, medical devices)",
      "Insect stings (bees, wasps, hornets, fire ants)",
      "Nickel and metals (jewelry, watch bands, medical hardware)",
      "Adhesives / medical tape",
    ],
  },
];

function allergyCategoryLabel(key: AllergyCategory): string {
  return ALLERGY_CATALOG.find(c => c.key === key)?.label ?? key;
}

const SYMPTOMS_STORAGE_KEY = "careconnect_logged_symptoms";
const ALLERGIES_STORAGE_KEY = "careconnect_logged_allergies";

/** Legacy demo symptom/allergy ids from earlier builds — strip on load. */
const DEMO_SYMPTOM_IDS = new Set(["s1", "s2", "s3", "s4", "s5"]);
const DEMO_ALLERGY_IDS = new Set(["a1", "a2", "a3"]);
const DEMO_SYMPTOM_NAMES = new Set(["Headache", "Fatigue", "Mild dizziness"]);

function loadLoggedSymptoms(): LoggedSymptom[] {
  try {
    const raw = localStorage.getItem(SYMPTOMS_STORAGE_KEY);
    if (!raw) return [];
    const list = JSON.parse(raw) as LoggedSymptom[];
    if (!Array.isArray(list)) return [];
    const cleaned = list.filter(s =>
      s && typeof s.name === "string" && s.name.trim()
      && !DEMO_SYMPTOM_IDS.has(s.id)
      && !(DEMO_SYMPTOM_NAMES.has(s.name) && String(s.id || "").startsWith("s") && String(s.id).length <= 3)
    );
    if (cleaned.length !== list.length) {
      try { localStorage.setItem(SYMPTOMS_STORAGE_KEY, JSON.stringify(cleaned)); } catch {}
    }
    return cleaned;
  } catch { return []; }
}

function loadLoggedAllergies(): LoggedAllergy[] {
  try {
    const raw = localStorage.getItem(ALLERGIES_STORAGE_KEY);
    if (!raw) return [];
    const list = JSON.parse(raw) as LoggedAllergy[];
    if (!Array.isArray(list)) return [];
    const cleaned = list.filter(a =>
      a && typeof a.name === "string" && a.name.trim() && !DEMO_ALLERGY_IDS.has(a.id)
    );
    if (cleaned.length !== list.length) {
      try { localStorage.setItem(ALLERGIES_STORAGE_KEY, JSON.stringify(cleaned)); } catch {}
    }
    return cleaned;
  } catch { return []; }
}

function categoryLabel(key: SymptomCategory): string {
  if (key === "other") return "Custom";
  return SYMPTOM_CATALOG.find(c => c.key === key)?.label ?? key;
}

function SymptomsContent({ theme }: { theme: ModeTheme }) {
  const [activeTab, setActiveTab] = useState<"symptoms" | "allergies">("symptoms");
  const [showAdd, setShowAdd] = useState(false);
  const [symptoms, setSymptoms] = useState<LoggedSymptom[]>(loadLoggedSymptoms);
  const [allergies, setAllergies] = useState<LoggedAllergy[]>(loadLoggedAllergies);

  // Add-symptom form state
  const [entryMode, setEntryMode] = useState<"dropdown" | "custom">("dropdown");
  const [selectedCategory, setSelectedCategory] = useState<SymptomCategory>("stml");
  const [selectedSymptom, setSelectedSymptom] = useState("");
  const [customSymptom, setCustomSymptom] = useState("");
  const [newSeverity, setNewSeverity] = useState(3);
  const [newNote, setNewNote] = useState("");
  const [isListening, setIsListening] = useState(false);
  const [voiceError, setVoiceError] = useState<string | null>(null);
  const recognitionRef = useRef<{ stop: () => void } | null>(null);

  // Add-allergy form state
  const [showAddAllergy, setShowAddAllergy] = useState(false);
  const [allergyEntryMode, setAllergyEntryMode] = useState<"dropdown" | "custom">("dropdown");
  const [selectedAllergyCategory, setSelectedAllergyCategory] = useState<AllergyCategory>("food");
  const [selectedAllergy, setSelectedAllergy] = useState("");
  const [customAllergy, setCustomAllergy] = useState("");
  const [allergyReaction, setAllergyReaction] = useState("");
  const [allergySeverity, setAllergySeverity] = useState<"Mild" | "Moderate" | "Severe">("Moderate");
  const { isListening: allergyListening, voiceError: allergyVoiceError, toggle: allergyMicToggle, stop: stopAllergyMic } =
    useVoiceDictation(text => setCustomAllergy(prev => (prev.trim() ? `${prev.trim()} ${text}` : text)));
  const { isListening: reactionListening, toggle: reactionMicToggle } =
    useVoiceDictation(text => setAllergyReaction(prev => (prev.trim() ? `${prev.trim()} ${text}` : text)));

  useEffect(() => {
    try { localStorage.setItem(SYMPTOMS_STORAGE_KEY, JSON.stringify(symptoms)); } catch {}
  }, [symptoms]);

  useEffect(() => {
    try { localStorage.setItem(ALLERGIES_STORAGE_KEY, JSON.stringify(allergies)); } catch {}
  }, [allergies]);

  useEffect(() => {
    return () => {
      try { recognitionRef.current?.stop(); } catch {}
      recognitionRef.current = null;
    };
  }, []);

  const catalogForCategory = SYMPTOM_CATALOG.find(c => c.key === selectedCategory);
  const symptomOptions = catalogForCategory?.symptoms ?? [];
  const allergyCatalogForCategory = ALLERGY_CATALOG.find(c => c.key === selectedAllergyCategory);
  const allergyOptions = allergyCatalogForCategory?.allergies ?? [];

  const stopListening = () => {
    try { recognitionRef.current?.stop(); } catch {}
    recognitionRef.current = null;
    setIsListening(false);
  };

  const startVoiceInput = () => {
    setVoiceError(null);
    const win = window as unknown as {
      SpeechRecognition?: new () => any;
      webkitSpeechRecognition?: new () => any;
    };
    const SpeechRecognitionAPI = win.SpeechRecognition || win.webkitSpeechRecognition;

    if (!SpeechRecognitionAPI) {
      setVoiceError("Voice input is not supported in this browser. Try Chrome or Edge.");
      return;
    }

    if (isListening) {
      stopListening();
      return;
    }

    const recognition = new SpeechRecognitionAPI();
    recognition.lang = "en-US";
    recognition.interimResults = true;
    recognition.continuous = false;
    recognition.maxAlternatives = 1;

    recognition.onstart = () => setIsListening(true);
    recognition.onend = () => {
      setIsListening(false);
      recognitionRef.current = null;
    };
    recognition.onerror = (event: { error?: string }) => {
      setIsListening(false);
      recognitionRef.current = null;
      if (event.error === "not-allowed") {
        setVoiceError("Microphone permission is blocked. Allow mic access and try again.");
      } else if (event.error !== "aborted" && event.error !== "no-speech") {
        setVoiceError("Could not capture voice. Please try again.");
      }
    };
    recognition.onresult = (event: { resultIndex: number; results: ArrayLike<{ 0: { transcript: string } }> }) => {
      let transcript = "";
      for (let i = event.resultIndex; i < event.results.length; i++) {
        transcript += event.results[i][0].transcript;
      }
      const cleaned = transcript.trim();
      if (!cleaned) return;
      setCustomSymptom(prev => (prev.trim() ? `${prev.trim()} ${cleaned}` : cleaned));
    };

    recognitionRef.current = recognition;
    try {
      recognition.start();
    } catch {
      setVoiceError("Could not start voice input. Please try again.");
      setIsListening(false);
    }
  };

  const resetForm = () => {
    stopListening();
    setShowAdd(false);
    setEntryMode("dropdown");
    setSelectedCategory("stml");
    setSelectedSymptom("");
    setCustomSymptom("");
    setNewSeverity(3);
    setNewNote("");
    setVoiceError(null);
  };

  const saveSymptom = () => {
    const name = entryMode === "custom"
      ? customSymptom.trim()
      : selectedSymptom.trim();
    if (!name) return;

    const entry: LoggedSymptom = {
      id: `s-${Date.now()}`,
      name,
      category: entryMode === "custom" ? "other" : selectedCategory,
      severity: newSeverity,
      time: new Date().toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }),
      note: newNote.trim() || (entryMode === "dropdown" ? categoryLabel(selectedCategory) : "Custom symptom"),
      date: moodDateKey(),
    };
    setSymptoms(prev => [entry, ...prev]);
    resetForm();
  };

  const canSave = entryMode === "custom"
    ? customSymptom.trim().length > 0
    : selectedSymptom.length > 0;

  const resetAllergyForm = () => {
    stopAllergyMic();
    setShowAddAllergy(false);
    setAllergyEntryMode("dropdown");
    setSelectedAllergyCategory("food");
    setSelectedAllergy("");
    setCustomAllergy("");
    setAllergyReaction("");
    setAllergySeverity("Moderate");
  };

  const saveAllergy = () => {
    const name = allergyEntryMode === "custom"
      ? customAllergy.trim()
      : selectedAllergy.trim();
    if (!name) return;
    const entry: LoggedAllergy = {
      id: `a-${Date.now()}`,
      name,
      reaction: allergyReaction.trim()
        || (allergyEntryMode === "dropdown" ? allergyCategoryLabel(selectedAllergyCategory) : "Custom allergy"),
      severity: allergySeverity,
    };
    setAllergies(prev => [entry, ...prev]);
    resetAllergyForm();
  };

  const canSaveAllergy = allergyEntryMode === "custom"
    ? customAllergy.trim().length > 0
    : selectedAllergy.length > 0;

  return (
    <div className="flex flex-col min-h-full">
      <div className="px-4 pt-4 pb-0">
        <div className="flex items-center gap-2 mb-3">
          <HeartPulse size={18} style={{ color: theme.color }} />
          <h2 className="text-[18px] font-bold text-[#0F172A]">Symptoms & Allergies</h2>
        </div>
        <div className="flex rounded-xl p-1 gap-1" style={{ background: "#F3F4F6" }}>
          {(["symptoms", "allergies"] as const).map(t => (
            <button
              key={t}
              onClick={() => setActiveTab(t)}
              className="flex-1 py-2 rounded-lg text-[13px] font-semibold transition-all"
              style={{
                background: activeTab === t ? "white" : "transparent",
                color: activeTab === t ? theme.color : "#6B7280",
                boxShadow: activeTab === t ? "0 1px 3px rgba(0,0,0,0.1)" : "none",
              }}
            >
              {t === "symptoms" ? "Symptoms" : "Allergies"}
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 px-4 py-3 flex flex-col gap-3">
        {activeTab === "symptoms" ? (
          <>
            <SymptomTrendChart entries={symptoms} accent={theme.color} />
            {symptoms.length === 0 && !showAdd && (
              <div className="rounded-2xl p-4 text-center border border-dashed border-[#E5E7EB] bg-[#F9FAFB]">
                <p className="text-[14px] font-semibold text-[#0F172A]">No symptoms logged yet</p>
                <p className="text-[12px] text-[#9CA3AF] mt-1 leading-relaxed">
                  Only symptoms you add appear here.
                </p>
              </div>
            )}
            {symptoms.map(s => (
              <div key={s.id} className="rounded-2xl p-4 bg-white border border-[#E5E7EB]">
                <div className="flex items-start justify-between gap-2 mb-1.5">
                  <div className="min-w-0 flex-1">
                    <p className="text-[14px] font-bold text-[#0F172A] leading-snug">{s.name}</p>
                    <p className="text-[11px] font-semibold mt-1" style={{ color: theme.color }}>
                      {categoryLabel(s.category)}
                    </p>
                  </div>
                  <div className="flex gap-0.5 shrink-0 pt-1">
                    {[1, 2, 3, 4, 5].map(n => (
                      <div key={n} className="w-2.5 h-2.5 rounded-full" style={{ background: n <= s.severity ? "#EF4444" : "#E5E7EB" }} />
                    ))}
                  </div>
                </div>
                <p className="text-[12px] text-[#6B7280] mb-1">{s.time}</p>
                {s.note && <p className="text-[13px] text-[#374151]">{s.note}</p>}
              </div>
            ))}

            {showAdd ? (
              <div className="rounded-2xl p-4 border-2 bg-white" style={{ borderColor: theme.color + "50" }}>
                <p className="text-[14px] font-bold mb-3" style={{ color: theme.color }}>Log new symptom</p>

                {/* Entry mode toggle */}
                <div className="flex rounded-xl p-1 gap-1 mb-3" style={{ background: "#F3F4F6" }}>
                  <button type="button" onClick={() => { stopListening(); setEntryMode("dropdown"); setVoiceError(null); }}
                    className="flex-1 py-2 rounded-lg text-[12px] font-semibold transition-all"
                    style={{
                      background: entryMode === "dropdown" ? "white" : "transparent",
                      color: entryMode === "dropdown" ? theme.color : "#6B7280",
                      boxShadow: entryMode === "dropdown" ? "0 1px 3px rgba(0,0,0,0.08)" : "none",
                    }}>
                    Choose from list
                  </button>
                  <button type="button" onClick={() => setEntryMode("custom")}
                    className="flex-1 py-2 rounded-lg text-[12px] font-semibold transition-all"
                    style={{
                      background: entryMode === "custom" ? "white" : "transparent",
                      color: entryMode === "custom" ? theme.color : "#6B7280",
                      boxShadow: entryMode === "custom" ? "0 1px 3px rgba(0,0,0,0.08)" : "none",
                    }}>
                    Type my own
                  </button>
                </div>

                {entryMode === "dropdown" ? (
                  <div className="flex flex-col gap-3 mb-3">
                    <div>
                      <label className="text-[11px] font-bold text-[#6B7280] uppercase tracking-wider mb-1.5 block">
                        Condition category
                      </label>
                      <select
                        value={selectedCategory}
                        onChange={e => {
                          setSelectedCategory(e.target.value as SymptomCategory);
                          setSelectedSymptom("");
                        }}
                        className="w-full border-2 border-[#E5E7EB] rounded-xl px-3 py-3 bg-white outline-none appearance-none"
                        style={{ fontSize: 15, color: "#0F172A" }}
                      >
                        {SYMPTOM_CATALOG.map(c => (
                          <option key={c.key} value={c.key}>{c.label}</option>
                        ))}
                      </select>
                    </div>
                    <div>
                      <label className="text-[11px] font-bold text-[#6B7280] uppercase tracking-wider mb-1.5 block">
                        Symptom
                      </label>
                      <select
                        value={selectedSymptom}
                        onChange={e => setSelectedSymptom(e.target.value)}
                        className="w-full border-2 border-[#E5E7EB] rounded-xl px-3 py-3 bg-white outline-none appearance-none"
                        style={{ fontSize: 15, color: selectedSymptom ? "#0F172A" : "#9CA3AF" }}
                      >
                        <option value="">Select a symptom…</option>
                        {symptomOptions.map(s => (
                          <option key={s} value={s}>{s}</option>
                        ))}
                      </select>
                    </div>
                  </div>
                ) : (
                  <div className="mb-3">
                    <div className="flex items-center justify-between mb-1.5">
                      <label className="text-[11px] font-bold text-[#6B7280] uppercase tracking-wider">
                        Describe your symptom
                      </label>
                      <button
                        type="button"
                        onClick={startVoiceInput}
                        className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-[12px] font-semibold transition-all"
                        style={{
                          background: isListening ? "#FEE2E2" : theme.lightBg,
                          color: isListening ? "#EF4444" : theme.color,
                          border: `1.5px solid ${isListening ? "#FECACA" : theme.borderColor}`,
                        }}
                        aria-pressed={isListening}
                        aria-label={isListening ? "Stop voice input" : "Start voice input"}
                      >
                        <Mic size={14} className={isListening ? "animate-pulse" : undefined} />
                        {isListening ? "Listening… tap to stop" : "Voice command"}
                      </button>
                    </div>
                    <textarea
                      value={customSymptom}
                      onChange={e => setCustomSymptom(e.target.value)}
                      placeholder={isListening ? "Speak now — your words will appear here…" : "Type or use Voice command to describe your symptom…"}
                      rows={3}
                      className="w-full border-2 rounded-xl px-3 py-3 outline-none resize-none"
                      style={{
                        fontSize: 15,
                        borderColor: isListening ? "#EF4444" : "#E5E7EB",
                        background: isListening ? "#FEF2F2" : "white",
                      }}
                    />
                    {isListening && (
                      <p className="text-[12px] font-semibold text-[#EF4444] mt-1.5 flex items-center gap-1.5">
                        <span className="w-2 h-2 rounded-full bg-[#EF4444] animate-pulse" />
                        Listening for your symptom description…
                      </p>
                    )}
                    {voiceError && (
                      <p className="text-[12px] font-semibold text-[#EF4444] mt-1.5">{voiceError}</p>
                    )}
                    {!isListening && !voiceError && (
                      <p className="text-[11px] text-[#9CA3AF] mt-1.5">
                        Tap Voice command and say your symptom out loud. You can edit the text afterward.
                      </p>
                    )}
                  </div>
                )}

                <p className="text-[12px] font-semibold text-[#6B7280] mb-2">Severity: {newSeverity}/5</p>
                <div className="flex gap-2 mb-3">
                  {[1, 2, 3, 4, 5].map(n => (
                    <button key={n} type="button" onClick={() => setNewSeverity(n)}
                      className="flex-1 h-8 rounded-lg text-[12px] font-bold transition-all"
                      style={{ background: n <= newSeverity ? "#EF4444" : "#E5E7EB", color: n <= newSeverity ? "white" : "#6B7280" }}>
                      {n}
                    </button>
                  ))}
                </div>

                <label className="text-[11px] font-bold text-[#6B7280] uppercase tracking-wider mb-1.5 block">
                  Notes (optional)
                </label>
                <div className="mb-3">
                  <VoiceInput
                    value={newNote}
                    onChange={setNewNote}
                    placeholder="Anything else to note…"
                    className="border-2 border-[#E5E7EB] rounded-xl px-3 py-2.5 outline-none"
                    color={theme.color}
                  />
                </div>

                <div className="flex gap-2">
                  <button type="button" onClick={resetForm}
                    className="flex-1 py-2.5 rounded-xl border border-[#E5E7EB] text-[13px] font-semibold text-[#6B7280]">
                    Cancel
                  </button>
                  <button type="button" onClick={saveSymptom} disabled={!canSave}
                    className="flex-1 py-2.5 rounded-xl text-[13px] font-semibold text-white transition-opacity"
                    style={{ background: theme.color, opacity: canSave ? 1 : 0.4 }}>
                    Save
                  </button>
                </div>
              </div>
            ) : (
              <button type="button" onClick={() => setShowAdd(true)}
                className="w-full py-3 rounded-2xl border-2 border-dashed text-[14px] font-semibold transition-colors"
                style={{ borderColor: theme.color + "60", color: theme.color }}>
                + Log a symptom
              </button>
            )}
          </>
        ) : (
          <>
            {allergies.length === 0 && !showAddAllergy && (
              <div className="rounded-2xl p-4 text-center border border-dashed border-[#E5E7EB] bg-[#F9FAFB]">
                <p className="text-[14px] font-semibold text-[#0F172A]">No allergies logged yet</p>
                <p className="text-[12px] text-[#9CA3AF] mt-1 leading-relaxed">
                  Only allergies you add appear here.
                </p>
              </div>
            )}
            {allergies.map(a => (
              <div key={a.id} className="rounded-2xl p-4 bg-white border border-[#E5E7EB]">
                <div className="flex items-center justify-between mb-1">
                  <p className="text-[15px] font-bold text-[#0F172A]">{a.name}</p>
                  <span className="text-[11px] font-bold px-2 py-0.5 rounded-full"
                    style={{
                      background: a.severity === "Severe" ? "#FEE2E2" : a.severity === "Moderate" ? "#FEF3C7" : "#E0F2FE",
                      color: a.severity === "Severe" ? "#EF4444" : a.severity === "Moderate" ? "#F59E0B" : "#0284C7",
                    }}>
                    {a.severity}
                  </span>
                </div>
                <p className="text-[13px] text-[#6B7280]">Reaction: {a.reaction}</p>
              </div>
            ))}

            {showAddAllergy ? (
              <div className="rounded-2xl p-4 border-2 bg-white" style={{ borderColor: theme.color + "50" }}>
                <p className="text-[14px] font-bold mb-3" style={{ color: theme.color }}>Log new allergy</p>

                <div className="flex rounded-xl p-1 gap-1 mb-3" style={{ background: "#F3F4F6" }}>
                  <button type="button" onClick={() => { stopAllergyMic(); setAllergyEntryMode("dropdown"); }}
                    className="flex-1 py-2 rounded-lg text-[12px] font-semibold transition-all"
                    style={{
                      background: allergyEntryMode === "dropdown" ? "white" : "transparent",
                      color: allergyEntryMode === "dropdown" ? theme.color : "#6B7280",
                      boxShadow: allergyEntryMode === "dropdown" ? "0 1px 3px rgba(0,0,0,0.08)" : "none",
                    }}>
                    Choose from list
                  </button>
                  <button type="button" onClick={() => setAllergyEntryMode("custom")}
                    className="flex-1 py-2 rounded-lg text-[12px] font-semibold transition-all"
                    style={{
                      background: allergyEntryMode === "custom" ? "white" : "transparent",
                      color: allergyEntryMode === "custom" ? theme.color : "#6B7280",
                      boxShadow: allergyEntryMode === "custom" ? "0 1px 3px rgba(0,0,0,0.08)" : "none",
                    }}>
                    Type or say my own
                  </button>
                </div>

                {allergyEntryMode === "dropdown" ? (
                  <div className="flex flex-col gap-3 mb-3">
                    <div>
                      <label className="text-[11px] font-bold text-[#6B7280] uppercase tracking-wider mb-1.5 block">
                        Allergy category
                      </label>
                      <select
                        value={selectedAllergyCategory}
                        onChange={e => {
                          setSelectedAllergyCategory(e.target.value as AllergyCategory);
                          setSelectedAllergy("");
                        }}
                        className="w-full border-2 border-[#E5E7EB] rounded-xl px-3 py-3 bg-white outline-none appearance-none"
                        style={{ fontSize: 15, color: "#0F172A" }}
                      >
                        {ALLERGY_CATALOG.map(c => (
                          <option key={c.key} value={c.key}>{c.label}</option>
                        ))}
                      </select>
                    </div>
                    <div>
                      <label className="text-[11px] font-bold text-[#6B7280] uppercase tracking-wider mb-1.5 block">
                        Allergy
                      </label>
                      <select
                        value={selectedAllergy}
                        onChange={e => setSelectedAllergy(e.target.value)}
                        className="w-full border-2 border-[#E5E7EB] rounded-xl px-3 py-3 bg-white outline-none appearance-none"
                        style={{ fontSize: 15, color: selectedAllergy ? "#0F172A" : "#9CA3AF" }}
                      >
                        <option value="">Select an allergy…</option>
                        {allergyOptions.map(a => (
                          <option key={a} value={a}>{a}</option>
                        ))}
                      </select>
                    </div>
                  </div>
                ) : (
                  <div className="mb-3">
                    <div className="flex items-center justify-between mb-1.5">
                      <label className="text-[11px] font-bold text-[#6B7280] uppercase tracking-wider">
                        Describe your allergy
                      </label>
                      <button
                        type="button"
                        onClick={allergyMicToggle}
                        className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-[12px] font-semibold transition-all"
                        style={{
                          background: allergyListening ? "#FEE2E2" : theme.lightBg,
                          color: allergyListening ? "#EF4444" : theme.color,
                          border: `1.5px solid ${allergyListening ? "#FECACA" : theme.borderColor}`,
                        }}
                        aria-pressed={allergyListening}
                        aria-label={allergyListening ? "Stop voice input" : "Start voice input"}
                      >
                        <Mic size={14} className={allergyListening ? "animate-pulse" : undefined} />
                        {allergyListening ? "Listening… tap to stop" : "Voice command"}
                      </button>
                    </div>
                    <textarea
                      value={customAllergy}
                      onChange={e => setCustomAllergy(e.target.value)}
                      placeholder={allergyListening ? "Speak now — your words will appear here…" : "Type or use Voice command to describe your allergy…"}
                      rows={3}
                      className="w-full border-2 rounded-xl px-3 py-3 outline-none resize-none"
                      style={{
                        fontSize: 15,
                        borderColor: allergyListening ? "#EF4444" : "#E5E7EB",
                        background: allergyListening ? "#FEF2F2" : "white",
                      }}
                    />
                    {allergyListening && (
                      <p className="text-[12px] font-semibold text-[#EF4444] mt-1.5 flex items-center gap-1.5">
                        <span className="w-2 h-2 rounded-full bg-[#EF4444] animate-pulse" />
                        Listening for your allergy…
                      </p>
                    )}
                    {allergyVoiceError && (
                      <p className="text-[12px] font-semibold text-[#EF4444] mt-1.5">{allergyVoiceError}</p>
                    )}
                    {!allergyListening && !allergyVoiceError && (
                      <p className="text-[11px] text-[#9CA3AF] mt-1.5">
                        Tap Voice command and say your allergy out loud. You can edit the text afterward.
                      </p>
                    )}
                  </div>
                )}

                <div className="mb-3">
                  <div className="flex items-center justify-between mb-1.5">
                    <label className="text-[11px] font-bold text-[#6B7280] uppercase tracking-wider">
                      Reaction (optional)
                    </label>
                    <MicButton isListening={reactionListening} onClick={reactionMicToggle} color={theme.color} />
                  </div>
                  <input
                    value={allergyReaction}
                    onChange={e => setAllergyReaction(e.target.value)}
                    placeholder={reactionListening ? "Listening…" : "e.g. Hives, swelling, difficulty breathing"}
                    className="w-full border-2 rounded-xl px-3 py-2.5 outline-none"
                    style={{
                      fontSize: 15,
                      borderColor: reactionListening ? "#EF4444" : "#E5E7EB",
                      background: reactionListening ? "#FEF2F2" : "white",
                    }}
                  />
                </div>

                <p className="text-[11px] font-bold text-[#6B7280] uppercase tracking-wider mb-1.5">Severity</p>
                <div className="flex gap-2 mb-3">
                  {(["Mild", "Moderate", "Severe"] as const).map(level => (
                    <button key={level} type="button" onClick={() => setAllergySeverity(level)}
                      className="flex-1 py-2 rounded-xl text-[12px] font-bold transition-all"
                      style={{
                        background: allergySeverity === level
                          ? (level === "Severe" ? "#FEE2E2" : level === "Moderate" ? "#FEF3C7" : "#E0F2FE")
                          : "#F3F4F6",
                        color: allergySeverity === level
                          ? (level === "Severe" ? "#EF4444" : level === "Moderate" ? "#D97706" : "#0284C7")
                          : "#6B7280",
                        border: allergySeverity === level ? "1.5px solid currentColor" : "1.5px solid transparent",
                      }}>
                      {level}
                    </button>
                  ))}
                </div>

                <div className="flex gap-2">
                  <button type="button" onClick={resetAllergyForm}
                    className="flex-1 py-2.5 rounded-xl border border-[#E5E7EB] text-[13px] font-semibold text-[#6B7280]">
                    Cancel
                  </button>
                  <button type="button" onClick={saveAllergy} disabled={!canSaveAllergy}
                    className="flex-1 py-2.5 rounded-xl text-[13px] font-semibold text-white transition-opacity"
                    style={{ background: theme.color, opacity: canSaveAllergy ? 1 : 0.4 }}>
                    Save
                  </button>
                </div>
              </div>
            ) : (
              <button type="button" onClick={() => setShowAddAllergy(true)}
                className="w-full py-3 rounded-2xl border-2 border-dashed text-[14px] font-semibold transition-colors"
                style={{ borderColor: theme.color + "60", color: theme.color }}>
                + Log new allergy
              </button>
            )}
          </>
        )}
      </div>
    </div>
  );
}

// ── Virtual Check-In (Patient) ─────────────────────────────────────────────────

const CHECKIN_QUESTIONS = [
  { id: "q1", question: "How are you feeling today overall?", type: "scale" as const },
  { id: "q2", question: "Any new symptoms since your last check-in?", type: "yesno" as const },
  { id: "q3", question: "Did you take all your medications today?", type: "yesno" as const },
  { id: "q4", question: "Describe your sleep quality last night", type: "scale" as const },
  { id: "q5", question: "Any notes for your care team?", type: "text" as const },
];

function VirtualCheckinContent({
  theme, lastCheckin, checkinsThisWeek = 0, onCheckinComplete,
}: {
  theme: ModeTheme;
  lastCheckin?: string;
  checkinsThisWeek?: number;
  onCheckinComplete?: (info: {
    lastCheckin: string;
    score: number;
    checkinsThisWeek: number;
    symptomNote?: string;
  }) => void;
}) {
  const [step, setStep] = useState<"history" | "checkin">("history");
  const [qIndex, setQIndex] = useState(0);
  const [answers, setAnswers] = useState<Record<string, string | number>>({});
  const [done, setDone] = useState(false);
  const q = CHECKIN_QUESTIONS[qIndex];
  const { isListening: checkinListening, toggle: checkinMicToggle } = useVoiceDictation(text =>
    setAnswers(prev => {
      const existing = String(prev[q.id] ?? "").trim();
      return { ...prev, [q.id]: existing ? `${existing} ${text}` : text };
    })
  );
  const progress = (qIndex / CHECKIN_QUESTIONS.length) * 100;

  const completeCheckin = () => {
    const scaleAns = Number(answers.q1) || Number(answers.q4) || 3;
    const stamp = formatCheckinStamp();
    const weekCount = Math.min(7, (checkinsThisWeek || 0) + 1);
    const hasNewSymptoms = String(answers.q2).toLowerCase() === "yes";
    const note = String(answers.q5 ?? "").trim();
    const symptomNote = hasNewSymptoms
      ? (note || "New symptoms reported in check-in")
      : undefined;
    onCheckinComplete?.({
      lastCheckin: stamp,
      score: scaleAns,
      checkinsThisWeek: weekCount,
      symptomNote,
    });
    setDone(true);
  };

  const HISTORY = [
    ...(lastCheckin ? [{ date: lastCheckin, score: 4, status: "Latest" }] : []),
    { date: "Yesterday", score: 3, status: "Fair" },
    { date: "Earlier this week", score: 2, status: "Poor" },
  ];

  if (step === "history") {
    return (
      <div className="flex flex-col min-h-full px-4 pt-4 pb-4 gap-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Stethoscope size={18} style={{ color: theme.color }} />
            <h2 className="text-[18px] font-bold text-[#0F172A]">Virtual Check-In</h2>
          </div>
          <button onClick={() => { setStep("checkin"); setQIndex(0); setDone(false); setAnswers({}); }}
            className="px-4 py-2 rounded-xl text-[13px] font-bold text-white"
            style={{ background: theme.color }}>
            Start check-in
          </button>
        </div>

        <div className="rounded-2xl p-4" style={{ background: theme.lightBg, border: `1.5px solid ${theme.borderColor}` }}>
          <p className="text-[12px] font-bold uppercase tracking-wider mb-1" style={{ color: theme.color }}>Last check-in</p>
          <p className="text-[22px] font-bold text-[#0F172A]">{lastCheckin || "Not yet today"}</p>
          <p className="text-[13px] font-semibold text-[#374151] mt-1">
            {checkinsThisWeek}/7 check-ins this week
          </p>
        </div>

        <div className="flex flex-col gap-2">
          <p className="text-[12px] font-bold uppercase tracking-wider text-[#6B7280]">Check-in history</p>
          {HISTORY.map((h, i) => (
            <div key={i} className="flex items-center gap-3 p-3 rounded-xl bg-white border border-[#E5E7EB]">
              <div className="w-2 h-10 rounded-full shrink-0" style={{ background: h.score >= 4 ? "#10B981" : h.score === 3 ? "#F59E0B" : "#EF4444" }} />
              <div className="flex-1">
                <p className="text-[13px] font-semibold text-[#0F172A]">{h.date}</p>
                <p className="text-[12px] text-[#6B7280]">{h.status} · {h.score}/5</p>
              </div>
              <ChevronRight size={16} className="text-[#D1D5DB]" />
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (done) {
    return (
      <div className="flex flex-col items-center justify-center min-h-full px-6 text-center gap-5">
        <div className="w-16 h-16 rounded-full flex items-center justify-center" style={{ background: "#D1FAE5" }}>
          <Check size={32} style={{ color: "#10B981" }} />
        </div>
        <div>
          <p className="text-[20px] font-bold text-[#0F172A]">Check-in complete!</p>
          <p className="text-[14px] text-[#6B7280] mt-1">Your care team has been notified. Great job staying on track.</p>
        </div>
        <button onClick={() => setStep("history")} className="px-6 py-3 rounded-2xl text-white font-bold text-[15px]" style={{ background: theme.color }}>
          Back to history
        </button>
      </div>
    );
  }

  return (
    <div className="flex flex-col min-h-full px-4 pt-4 pb-4">
      <div className="flex items-center justify-between mb-4">
        <button onClick={() => setStep("history")} className="flex items-center gap-1 text-[13px] font-semibold text-[#6B7280]">
          <ChevronLeft size={16} /> Cancel
        </button>
        <span className="text-[12px] font-semibold text-[#6B7280]">{qIndex + 1} / {CHECKIN_QUESTIONS.length}</span>
      </div>
      <div className="h-1.5 rounded-full bg-[#E5E7EB] mb-6 overflow-hidden">
        <div className="h-full rounded-full transition-all duration-500" style={{ width: `${progress}%`, background: theme.color }} />
      </div>

      <p className="text-[18px] font-bold text-[#0F172A] mb-6 leading-snug">{q.question}</p>

      {q.type === "scale" && (
        <div className="flex gap-2 mb-8">
          {[1,2,3,4,5].map(n => (
            <button key={n} onClick={() => setAnswers({ ...answers, [q.id]: n })}
              className="flex-1 aspect-square rounded-2xl text-[18px] font-bold border-2 transition-all"
              style={{
                borderColor: answers[q.id] === n ? theme.color : "#E5E7EB",
                background: answers[q.id] === n ? theme.lightBg : "white",
                color: answers[q.id] === n ? theme.color : "#6B7280",
              }}>
              {n}
            </button>
          ))}
        </div>
      )}
      {q.type === "yesno" && (
        <div className="flex gap-3 mb-8">
          {["Yes", "No"].map(opt => (
            <button key={opt} onClick={() => setAnswers({ ...answers, [q.id]: opt })}
              className="flex-1 py-4 rounded-2xl text-[16px] font-bold border-2 transition-all"
              style={{
                borderColor: answers[q.id] === opt ? theme.color : "#E5E7EB",
                background: answers[q.id] === opt ? theme.lightBg : "white",
                color: answers[q.id] === opt ? theme.color : "#6B7280",
              }}>
              {opt}
            </button>
          ))}
        </div>
      )}
      {q.type === "text" && (
        <div className="mb-8">
          <div className="flex justify-end mb-2">
            <MicButton isListening={checkinListening} onClick={checkinMicToggle} color={theme.color} />
          </div>
          <textarea
            value={(answers[q.id] as string) || ""}
            onChange={e => setAnswers({ ...answers, [q.id]: e.target.value })}
            placeholder={checkinListening ? "Listening — speak your message…" : "Type or tap the mic to speak a message for your care team..."}
            rows={4}
            className="w-full border border-[#E5E7EB] rounded-2xl px-4 py-3 resize-none outline-none"
            style={{ borderColor: checkinListening ? "#EF4444" : theme.color + "40", background: checkinListening ? "#FEF2F2" : "white", fontSize: 16 }}
          />
        </div>
      )}

      <button
        disabled={!answers[q.id] && q.type !== "text"}
        onClick={() => {
          if (qIndex < CHECKIN_QUESTIONS.length - 1) setQIndex(qIndex + 1);
          else completeCheckin();
        }}
        className="w-full py-4 rounded-2xl text-[16px] font-bold text-white transition-opacity"
        style={{ background: theme.color, opacity: !answers[q.id] && q.type !== "text" ? 0.4 : 1 }}>
        {qIndex < CHECKIN_QUESTIONS.length - 1 ? "Next" : "Submit check-in"}
      </button>
    </div>
  );
}

// ── Messages / Chat (Patient & Caregiver) ──────────────────────────────────────

interface ChatConversation {
  id: string;
  name: string;
  role: string;
  lastMsg: string;
  time: string;
  unread: number;
  avatar: string;
  phone?: string;
}

const SAMPLE_CONVERSATIONS: ChatConversation[] = [
  { id: "c1", name: "Dr. Sarah Patel", role: "Primary Care Physician", lastMsg: "Your blood pressure looks good. Keep up the medication.", time: "2:15 PM", unread: 0, avatar: "SP", phone: "(555) 880-1200" },
  { id: "c2", name: "Maria Rodriguez", role: "Daughter", lastMsg: "I've confirmed your Thursday appointment.", time: "Yesterday", unread: 2, avatar: "MR", phone: "(555) 201-4400" },
  { id: "c3", name: "CareConnect Team", role: "Support", lastMsg: "Your weekly health summary is ready to view.", time: "Mon", unread: 0, avatar: "CC", phone: "(555) 100-2000" },
];

const NEW_CHAT_SUGGESTIONS: { name: string; role: string; phone: string }[] = [
  { name: "Dr. Sarah Patel", role: "Primary Care Physician", phone: "(555) 880-1200" },
  { name: "Maria Rodriguez", role: "Daughter", phone: "(555) 201-4400" },
  { name: "Pharmacy Refill Line", role: "Pharmacy", phone: "(555) 330-7788" },
  { name: "Emergency Contact", role: "Family / Emergency", phone: "(555) 444-1212" },
];

interface ChatMessage {
  id: string;
  sender: string;
  text: string;
  time: string;
  mine: boolean;
}

const SAMPLE_MESSAGES: Record<string, ChatMessage[]> = {
  c1: [
  { id: "m1", sender: "Dr. Sarah Patel", text: "Good morning! How are you feeling after starting the new dosage?", time: "9:10 AM", mine: false },
  { id: "m2", sender: "You", text: "A bit tired in the mornings but otherwise okay.", time: "9:22 AM", mine: true },
  { id: "m3", sender: "Dr. Sarah Patel", text: "That's expected for the first week. Please continue and we'll review at Thursday's appointment.", time: "9:31 AM", mine: false },
  { id: "m4", sender: "Dr. Sarah Patel", text: "Your blood pressure looks good. Keep up the medication.", time: "2:15 PM", mine: false },
  ],
  c2: [
    { id: "m5", sender: "Maria Rodriguez", text: "I've confirmed your Thursday appointment.", time: "Yesterday", mine: false },
  ],
  c3: [
    { id: "m6", sender: "CareConnect Team", text: "Your weekly health summary is ready to view.", time: "Monday", mine: false },
  ],
};

const CHAT_STORAGE_KEY = "careconnect_chat_messages";
const CONV_STORAGE_KEY = "careconnect_conversations";

function loadChatMessages(): Record<string, ChatMessage[]> {
  try {
    const saved = localStorage.getItem(CHAT_STORAGE_KEY);
    return saved ? JSON.parse(saved) : SAMPLE_MESSAGES;
  } catch {
    return SAMPLE_MESSAGES;
  }
}

function loadConversations(): ChatConversation[] {
  try {
    const saved = localStorage.getItem(CONV_STORAGE_KEY);
    if (saved) {
      const parsed = JSON.parse(saved) as ChatConversation[];
      if (Array.isArray(parsed) && parsed.length) return parsed;
    }
  } catch {}
  return SAMPLE_CONVERSATIONS;
}

function saveConversations(convs: ChatConversation[]) {
  try { localStorage.setItem(CONV_STORAGE_KEY, JSON.stringify(convs)); } catch {}
}

function digitsOnlyPhone(phone?: string): string {
  return (phone ?? "").replace(/[^\d+]/g, "");
}

function makeChatAvatar(name: string): string {
  return makeInitials(name) || "??";
}

/** Map Care Circle members to existing chat threads (doctor / care coordinator). */
function caregiverChatId(cg: LinkedCaregiver): "c1" | "c2" {
  const blob = `${cg.relationship} ${cg.name}`.toLowerCase();
  if (/physician|doctor|dr\.|patel|md\b/.test(blob)) return "c1";
  return "c2";
}

/**
 * If the patient has logged Poor/Low for 3+ consecutive days, notify active
 * caregivers who can view mood (doctor + care coordinator) via Messages.
 * Dedupes so the same streak only notifies once.
 */
function maybeNotifyCareTeamLowMoodStreak(opts: {
  history: MoodEntry[];
  score: number;
  patientName: string;
  symptom?: string;
  linkedCaregivers: LinkedCaregiver[];
}): LowMoodStreakAlert | null {
  if (opts.score > 2) return null;
  const today = moodDateKey();
  const streakDays = countConsecutiveLowMoodDays(opts.history, today);
  if (streakDays < LOW_MOOD_STREAK_THRESHOLD) return null;

  const streakStart = streakStartKey(today, streakDays);
  const prev = loadLowMoodStreakAlert();
  if (prev?.streakStart === streakStart) return null;

  const recipients = opts.linkedCaregivers.filter(
    cg => cg.status === "active" && cg.grants.includes("mood")
  );
  const chatTargets: { chatId: "c1" | "c2"; name: string }[] = [];
  if (recipients.length === 0) {
    chatTargets.push(
      { chatId: "c1", name: "Dr. Sarah Patel" },
      { chatId: "c2", name: "Maria Rodriguez" },
    );
  } else {
    const seen = new Set<string>();
    for (const cg of recipients) {
      const chatId = caregiverChatId(cg);
      if (seen.has(chatId)) continue;
      seen.add(chatId);
      chatTargets.push({ chatId, name: cg.name });
    }
  }

  const symptomLine = opts.symptom && opts.symptom !== NONE_SYMPTOM
    ? ` Latest noted symptom: ${opts.symptom}.`
    : "";
  const patientLabel = opts.patientName && opts.patientName !== "Your Name"
    ? opts.patientName
    : "Your patient";
  const alertText =
    `⚠️ CareConnect alert: ${patientLabel} has logged feeling Poor or Low for ${streakDays} consecutive days (${formatMoodDayLabel(streakStart)} – ${formatMoodDayLabel(today)}).` +
    symptomLine +
    ` Please check in when you can.`;

  const now = new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  try {
    const chats = loadChatMessages();
    for (const target of chatTargets) {
      const patientCopy: ChatMessage = {
        id: `low-mood-you-${target.chatId}-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
        sender: "You",
        text: `I wanted my care team to know I've been feeling low for ${streakDays} days in a row.${symptomLine}`,
        time: now,
        mine: true,
      };
      const alertMsg: ChatMessage = {
        id: `low-mood-${target.chatId}-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
        sender: "CareConnect Alerts",
        text: alertText,
        time: now,
        mine: false,
      };
      chats[target.chatId] = [...(chats[target.chatId] ?? []), patientCopy, alertMsg];
    }
    localStorage.setItem(CHAT_STORAGE_KEY, JSON.stringify(chats));
  } catch {}

  const alert: LowMoodStreakAlert = {
    streakStart,
    streakDays,
    notifiedAt: new Date().toISOString(),
    patientName: patientLabel,
    symptom: opts.symptom && opts.symptom !== NONE_SYMPTOM ? opts.symptom : undefined,
    recipientNames: chatTargets.map(t => t.name),
  };
  saveLowMoodStreakAlert(alert);
  return alert;
}

// ── Hearing Conversation Assist ────────────────────────────────────────────────

const HEARING_MEMORY_KEY = "careconnect_hearing_memory";

interface HearingCaptionLine {
  id: string;
  speaker: string;
  text: string;
  at: string;
}

interface HearingSessionMemory {
  id: string;
  startedAt: string;
  title: string;
  lines: HearingCaptionLine[];
  summary: string;
  coachingNotes: string[];
  flow: { speaker: string; turns: number; words: number }[];
}

function loadHearingMemory(): HearingSessionMemory[] {
  try {
    const raw = localStorage.getItem(HEARING_MEMORY_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveHearingMemory(sessions: HearingSessionMemory[]) {
  try {
    localStorage.setItem(HEARING_MEMORY_KEY, JSON.stringify(sessions.slice(0, 20)));
  } catch {}
}

const HEARING_SPEAKERS = [...HEARING_SPEAKER_LABELS];

function buildHearingSummary(lines: HearingCaptionLine[]): string {
  if (lines.length === 0) {
    return "No conversation captured yet. Start live captions to generate an AI summary.";
  }
  const speakers = [...new Set(lines.map(l => l.speaker))];
  const topics: string[] = [];
  const blob = lines.map(l => l.text.toLowerCase()).join(" ");
  if (/medicat|dose|pill|prescription/.test(blob)) topics.push("medications");
  if (/appoint|visit|schedule|thursday|monday|follow.?up/.test(blob)) topics.push("appointments");
  if (/pain|symptom|feel|tired|headache|fatigue/.test(blob)) topics.push("symptoms / how you’re feeling");
  if (/blood pressure|bp|heart|glucose/.test(blob)) topics.push("vitals");
  if (topics.length === 0) topics.push("general care discussion");

  const keyLines = lines.slice(-3).map(l => `${l.speaker}: “${l.text}”`).join(" · ");
  return (
    `AI summary · ${lines.length} caption${lines.length === 1 ? "" : "s"} from ${speakers.join(", ")}. ` +
    `Main topics: ${topics.join(", ")}. ` +
    `Recent: ${keyLines}`
  );
}

function buildHearingCoaching(lines: HearingCaptionLine[]): string[] {
  const tips: string[] = [];
  if (lines.length === 0) {
    return [
      "Face the speaker and confirm lighting is on your face for lip-reading support.",
      "Ask people to speak one at a time — captions work best with clear turns.",
      "Tap Start captions before the conversation begins.",
    ];
  }
  const last = lines[lines.length - 1];
  const youTurns = lines.filter(l => l.speaker === "You").length;
  const otherTurns = lines.length - youTurns;
  const longUtterance = lines.some(l => l.text.split(/\s+/).length > 28);

  if (otherTurns >= 3 && youTurns === 0) {
    tips.push("You’ve been mostly listening — consider confirming what you heard: “Just to confirm…”");
  }
  if (youTurns > otherTurns + 2) {
    tips.push("Pause and invite the other person to respond so turns stay balanced.");
  }
  if (longUtterance) {
    tips.push("A long stretch of speech just landed — ask for a short recap if anything was unclear.");
  }
  if (/sorry|what|repeat|again|missed/i.test(last.text)) {
    tips.push("Clarification was requested — good move. Ask them to rephrase, not just repeat louder.");
  }
  if (tips.length === 0) {
    tips.push("Conversation flow looks steady. Keep watching live captions and speaker labels.");
    tips.push("If background noise rises, move closer or switch to text chat.");
  }
  return tips.slice(0, 3);
}

function buildConversationFlow(lines: HearingCaptionLine[]) {
  const map = new Map<string, { turns: number; words: number }>();
  for (const line of lines) {
    const cur = map.get(line.speaker) ?? { turns: 0, words: 0 };
    cur.turns += 1;
    cur.words += line.text.trim().split(/\s+/).filter(Boolean).length;
    map.set(line.speaker, cur);
  }
  return [...map.entries()]
    .map(([speaker, v]) => ({ speaker, ...v }))
    .sort((a, b) => b.turns - a.turns);
}

function HearingAssistContent({
  theme, onOpenMessages,
}: {
  theme: ModeTheme;
  onOpenMessages?: () => void;
}) {
  const [panel, setPanel] = useState<"live" | "summary" | "memory" | "coach" | "flow">("live");
  const [listening, setListening] = useState(false);
  const [partial, setPartial] = useState("");
  const [lines, setLines] = useState<HearingCaptionLine[]>([]);
  const [activeSpeaker, setActiveSpeaker] = useState("Doctor");
  const [autoIdentify, setAutoIdentify] = useState(true);
  const [voiceError, setVoiceError] = useState<string | null>(null);
  const [memory, setMemory] = useState<HearingSessionMemory[]>(loadHearingMemory);
  const [savedFlash, setSavedFlash] = useState(false);
  const [panelOpen, setPanelOpen] = useState<Record<string, boolean>>({
    live: true, summary: true, memory: true, coach: true, flow: true,
  });
  const recognitionRef = useRef<{ stop: () => void; continuous?: boolean; interimResults?: boolean; lang?: string; onresult: ((ev: unknown) => void) | null; onerror: ((ev: unknown) => void) | null; onend: (() => void) | null; start: () => void } | null>(null);
  const speakerRef = useRef(activeSpeaker);
  speakerRef.current = activeSpeaker;
  const autoIdentifyRef = useRef(autoIdentify);
  autoIdentifyRef.current = autoIdentify;
  const lastSpeakerRef = useRef<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  const summary = buildHearingSummary(lines);
  const coaching = buildHearingCoaching(lines);
  const flow = buildConversationFlow(lines);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [lines, partial]);

  useEffect(() => {
    return () => {
      try { recognitionRef.current?.stop(); } catch {}
      recognitionRef.current = null;
    };
  }, []);

  const stopListening = () => {
    try { recognitionRef.current?.stop(); } catch {}
    recognitionRef.current = null;
    setListening(false);
    setPartial("");
  };

  const startListening = () => {
    setVoiceError(null);
    const win = window as unknown as {
      SpeechRecognition?: new () => {
        continuous: boolean; interimResults: boolean; lang: string;
        onresult: ((ev: unknown) => void) | null;
        onerror: ((ev: unknown) => void) | null;
        onend: (() => void) | null;
        start: () => void; stop: () => void;
      };
      webkitSpeechRecognition?: new () => {
        continuous: boolean; interimResults: boolean; lang: string;
        onresult: ((ev: unknown) => void) | null;
        onerror: ((ev: unknown) => void) | null;
        onend: (() => void) | null;
        start: () => void; stop: () => void;
      };
    };
    const SR = win.SpeechRecognition || win.webkitSpeechRecognition;
    if (!SR) {
      setVoiceError("Live captions need a browser with speech recognition (Chrome recommended).");
      return;
    }
    const recognition = new SR();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = "en-US";
    recognition.onresult = (event: unknown) => {
      const ev = event as { resultIndex: number; results: ArrayLike<{ isFinal: boolean; 0: { transcript: string } }> };
      let interim = "";
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        const result = ev.results[i];
        const transcript = result[0].transcript.trim();
        if (!transcript) continue;
        if (result.isFinal) {
          const speaker = autoIdentifyRef.current
            ? inferSpeakerFromText(transcript, lastSpeakerRef.current || speakerRef.current)
            : speakerRef.current;
          lastSpeakerRef.current = speaker;
          if (autoIdentifyRef.current) setActiveSpeaker(speaker);
          setLines(prev => [
            ...prev,
            {
              id: `cap-${Date.now()}-${i}`,
              speaker,
              text: transcript,
              at: new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit", second: "2-digit" }),
            },
          ]);
          setPartial("");
        } else {
          interim += transcript + " ";
        }
      }
      if (interim) setPartial(interim.trim());
    };
    recognition.onerror = (event: unknown) => {
      const err = event as { error?: string };
      if (err.error === "not-allowed") {
        setVoiceError("Microphone permission is required for live captions.");
      } else if (err.error !== "aborted") {
        setVoiceError("Captioning paused — tap Start captions to resume.");
      }
      setListening(false);
    };
    recognition.onend = () => {
      // Keep listening if user hasn't stopped
      if (recognitionRef.current) {
        try { recognition.start(); } catch { setListening(false); }
      }
    };
    recognitionRef.current = recognition;
    try {
      recognition.start();
      setListening(true);
    } catch {
      setVoiceError("Could not start live captions. Try again.");
      setListening(false);
    }
  };

  const toggleListening = () => {
    if (listening) stopListening();
    else startListening();
  };

  const saveToMemory = () => {
    if (lines.length === 0) return;
    const session: HearingSessionMemory = {
      id: `hs-${Date.now()}`,
      startedAt: new Date().toISOString(),
      title: `Conversation · ${new Date().toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}`,
      lines: [...lines],
      summary,
      coachingNotes: coaching,
      flow,
    };
    const next = [session, ...memory];
    setMemory(next);
    saveHearingMemory(next);
    setSavedFlash(true);
    window.setTimeout(() => setSavedFlash(false), 2200);
  };

  const clearLive = () => {
    stopListening();
    setLines([]);
    setPartial("");
  };

  const simulateDemo = () => {
    const texts = [
      { id: "d1", text: "Good morning. How have you been feeling since your last visit?" },
      { id: "d2", text: "A little tired in the mornings, but my blood pressure feels steadier." },
      { id: "d3", text: "That's expected with the new dosage. Please continue your medication and we'll review Thursday." },
      { id: "d4", text: "I'll help set phone reminders for the evening dose." },
      { id: "d5", text: "Could you repeat the appointment time one more time?" },
      { id: "d6", text: "Thursday at 2:30 PM with me in clinic." },
    ];
    const times = ["9:00:02 AM", "9:00:11 AM", "9:00:22 AM", "9:00:31 AM", "9:00:40 AM", "9:00:48 AM"];
    let prev: string | null = null;
    const scripted = texts.map((row, i) => {
      const speaker = inferSpeakerFromText(row.text, prev);
      prev = speaker;
      return { id: row.id, speaker, text: row.text, at: times[i] };
    });
    setLines(scripted);
    lastSpeakerRef.current = scripted[scripted.length - 1]?.speaker ?? null;
    setActiveSpeaker(scripted[scripted.length - 1]?.speaker ?? "Doctor");
    setAutoIdentify(true);
    setPanel("live");
    setPanelOpen(prev => ({ ...prev, live: true }));
  };

  const speakerColor = (name: string) => {
    if (name === "You") return "#00A7C8";
    if (name === "Doctor") return "#0284C7";
    if (name === "Caregiver") return "#7C3AED";
    if (name === "Nurse") return "#0E7E57";
    return "#B45309";
  };

  const panels: { key: typeof panel; label: string; icon: React.ReactNode }[] = [
    { key: "live", label: "Captions", icon: <Captions size={13} /> },
    { key: "summary", label: "Summary", icon: <Sparkles size={13} /> },
    { key: "memory", label: "Memory", icon: <FileText size={13} /> },
    { key: "coach", label: "Coach", icon: <Zap size={13} /> },
    { key: "flow", label: "Flow", icon: <Activity size={13} /> },
  ];

  return (
    <div className="flex flex-col min-h-full px-4 pt-4 pb-28 gap-3">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-2 mb-0.5">
            <Ear size={18} style={{ color: "#0284C7" }} />
            <h2 className="text-[18px] font-bold text-[#0F172A]">Hearing Assist</h2>
          </div>
          <p className="text-[12px] text-[#6B7280]">
            Live captions · speaker ID · AI summaries · memory · coaching · flow
          </p>
        </div>
        <button
          type="button"
          onClick={simulateDemo}
          className="px-3 py-1.5 rounded-xl text-[11px] font-bold border border-[#BAE6FD] text-[#0284C7] bg-[#E0F2FE] shrink-0"
        >
          Demo
        </button>
      </div>

      <div className="flex gap-1 p-1 rounded-2xl overflow-x-auto" style={{ background: "#F3F4F6" }}>
        {panels.map(p => (
          <button
            key={p.key}
            type="button"
            onClick={() => {
              setPanel(p.key);
              setPanelOpen(prev => ({ ...prev, [p.key]: !(prev[p.key] ?? true) && panel === p.key ? false : true }));
            }}
            className="flex-1 min-w-[4.5rem] flex flex-col items-center gap-0.5 py-2 rounded-xl transition-all"
            style={{
              background: panel === p.key ? "white" : "transparent",
              boxShadow: panel === p.key ? "0 1px 3px rgba(0,0,0,0.08)" : "none",
              color: panel === p.key ? "#0284C7" : "#9CA3AF",
              transform: panel === p.key ? "scale(1.06)" : "scale(1)",
            }}
          >
            {p.icon}
            <span className="text-[9px] font-bold uppercase tracking-wide">{p.label}</span>
          </button>
        ))}
      </div>

      {panel === "live" && (panelOpen.live ?? true) && (
        <>
          <div className="rounded-2xl p-3 border border-[#BAE6FD] bg-[#E0F2FE]">
            <div className="flex items-center justify-between mb-2">
              <p className="text-[11px] font-bold uppercase tracking-wide text-[#0284C7]">Speaker identification</p>
              <button
                type="button"
                onClick={() => setAutoIdentify(v => !v)}
                className="text-[11px] font-bold px-2.5 py-1 rounded-full border"
                style={{
                  background: autoIdentify ? "#0284C7" : "white",
                  color: autoIdentify ? "white" : "#0284C7",
                  borderColor: "#0284C7",
                }}
              >
                {autoIdentify ? "Auto on" : "Auto off"}
              </button>
            </div>
            <div className="flex flex-wrap gap-1.5">
              {HEARING_SPEAKERS.map(s => (
                <button
                  key={s}
                  type="button"
                  onClick={() => {
                    setActiveSpeaker(s);
                    setAutoIdentify(false);
                    lastSpeakerRef.current = s;
                  }}
                  className="px-2.5 py-1 rounded-full text-[11px] font-bold border transition-all"
                  style={{
                    background: activeSpeaker === s ? speakerColor(s) : "white",
                    borderColor: activeSpeaker === s ? speakerColor(s) : "#BAE6FD",
                    color: activeSpeaker === s ? "white" : "#374151",
                  }}
                >
                  {s}
                </button>
              ))}
            </div>
            <p className="text-[11px] text-[#0369A1] mt-2">
              {autoIdentify
                ? <>Automatically identifying who is talking. Current: <span className="font-bold">{activeSpeaker}</span></>
                : <>Manual mode — tap a label to override. Current: <span className="font-bold">{activeSpeaker}</span></>}
            </p>
          </div>

          <div className="flex gap-2">
            <button
              type="button"
              onClick={toggleListening}
              className="flex-1 py-3 rounded-xl text-[13px] font-bold text-white flex items-center justify-center gap-2"
              style={{ background: listening ? "#EF4444" : "#0284C7" }}
            >
              <Mic size={16} />
              {listening ? "Stop captions" : "Start live captions"}
            </button>
            <button
              type="button"
              onClick={saveToMemory}
              disabled={lines.length === 0}
              className="px-3 py-3 rounded-xl text-[12px] font-bold border border-[#BAE6FD] text-[#0284C7] bg-white disabled:opacity-40"
            >
              Save
            </button>
            <button
              type="button"
              onClick={clearLive}
              className="px-3 py-3 rounded-xl text-[12px] font-bold border border-[#E5E7EB] text-[#6B7280] bg-white"
            >
              Clear
            </button>
          </div>

          {voiceError && (
            <div className="px-3 py-2 rounded-xl text-[12px] font-semibold" style={{ background: "#FEF2F2", color: "#B91C1C", border: "1px solid #FECACA" }}>
              {voiceError}
            </div>
          )}
          {savedFlash && (
            <div className="px-3 py-2 rounded-xl text-[12px] font-semibold" style={{ background: "#ECFDF5", color: "#047857", border: "1px solid #A7F3D0" }}>
              Saved to conversation memory
            </div>
          )}

          <div ref={scrollRef} className="rounded-2xl bg-[#0F172A] border border-[#1E293B] p-3 min-h-[220px] max-h-[320px] overflow-y-auto flex flex-col gap-2">
            <div className="flex items-center justify-between mb-1">
              <p className="text-[10px] font-bold uppercase tracking-wider text-[#38BDF8]">Live captions</p>
              {listening && (
                <span className="flex items-center gap-1 text-[10px] font-bold text-[#F87171]">
                  <span className="w-1.5 h-1.5 rounded-full bg-[#EF4444] animate-pulse" /> LIVE
                </span>
              )}
            </div>
            {lines.length === 0 && !partial && (
              <p className="text-[13px] text-white/50 leading-relaxed">
                Captions will appear here in real time. Choose a speaker, then tap Start live captions — or try Demo.
              </p>
            )}
            {lines.map(line => (
              <div key={line.id} className="flex flex-col gap-0.5">
                <div className="flex items-center gap-2">
                  <span className="text-[10px] font-bold px-1.5 py-0.5 rounded" style={{ background: speakerColor(line.speaker), color: "white" }}>
                    {line.speaker}
                  </span>
                  <span className="text-[10px] text-white/40">{line.at}</span>
                </div>
                <p className="text-[14px] text-white leading-relaxed pl-0.5">{line.text}</p>
              </div>
            ))}
            {partial && (
              <div className="flex flex-col gap-0.5 opacity-70">
                <span className="text-[10px] font-bold px-1.5 py-0.5 rounded w-fit" style={{ background: speakerColor(activeSpeaker), color: "white" }}>
                  {activeSpeaker}
                </span>
                <p className="text-[14px] text-white/80 italic leading-relaxed">{partial}…</p>
              </div>
            )}
          </div>
        </>
      )}

      {panel === "summary" && (panelOpen.summary ?? true) && (
        <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB] flex flex-col gap-3">
          <div className="flex items-center gap-2">
            <Sparkles size={16} style={{ color: "#0284C7" }} />
            <p className="text-[14px] font-bold text-[#0F172A]">AI conversation summary</p>
          </div>
          <p className="text-[13px] text-[#374151] leading-relaxed">{summary}</p>
          <div className="px-3 py-2 rounded-xl bg-[#E0F2FE] border border-[#BAE6FD]">
            <p className="text-[11px] font-bold text-[#0284C7] uppercase tracking-wide mb-1">Generated from live captions</p>
            <p className="text-[12px] text-[#0369A1]">
              Summaries update as new captions arrive. Save to Memory to keep this session for later review with your care team.
            </p>
          </div>
          <button
            type="button"
            onClick={saveToMemory}
            disabled={lines.length === 0}
            className="w-full py-3 rounded-xl text-[13px] font-bold text-white disabled:opacity-40"
            style={{ background: "#0284C7" }}
          >
            Save summary to memory
          </button>
        </div>
      )}

      {panel === "memory" && (panelOpen.memory ?? true) && (
        <div className="flex flex-col gap-3">
          <p className="text-[13px] text-[#6B7280]">Past captioned conversations saved on this device.</p>
          {memory.length === 0 ? (
            <div className="rounded-2xl p-5 bg-white border border-[#E5E7EB] text-center">
              <p className="text-[14px] font-bold text-[#0F172A] mb-1">No saved conversations yet</p>
              <p className="text-[12px] text-[#9CA3AF]">Run live captions, then tap Save to build conversation memory.</p>
            </div>
          ) : memory.map(session => (
            <div key={session.id} className="rounded-2xl p-4 bg-white border border-[#E5E7EB]">
              <p className="text-[13px] font-bold text-[#0F172A]">{session.title}</p>
              <p className="text-[12px] text-[#6B7280] mt-1 leading-relaxed">{session.summary}</p>
              <p className="text-[11px] text-[#9CA3AF] mt-2">
                {session.lines.length} captions · {session.flow.map(f => `${f.speaker} ${f.turns}×`).join(" · ")}
              </p>
              <button
                type="button"
                onClick={() => { setLines(session.lines); setPanel("live"); }}
                className="mt-2 text-[12px] font-bold text-[#0284C7]"
              >
                Reopen transcript
              </button>
            </div>
          ))}
        </div>
      )}

      {panel === "coach" && (panelOpen.coach ?? true) && (
        <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB] flex flex-col gap-3">
          <div className="flex items-center gap-2">
            <Zap size={16} style={{ color: "#0284C7" }} />
            <p className="text-[14px] font-bold text-[#0F172A]">Real-time conversation coaching</p>
          </div>
          <p className="text-[12px] text-[#6B7280]">
            Tips update from turn-taking, clarification requests, and caption patterns.
          </p>
          {coaching.map((tip, i) => (
            <div key={i} className="flex gap-2 px-3 py-2.5 rounded-xl bg-[#E0F2FE] border border-[#BAE6FD]">
              <span className="text-[13px] font-bold text-[#0284C7]">{i + 1}.</span>
              <p className="text-[13px] text-[#0F172A] leading-snug">{tip}</p>
            </div>
          ))}
          {onOpenMessages && (
            <button
              type="button"
              onClick={onOpenMessages}
              className="w-full py-3 rounded-xl text-[13px] font-bold text-white"
              style={{ background: "#0284C7" }}
            >
              Switch to text chat
            </button>
          )}
        </div>
      )}

      {panel === "flow" && (panelOpen.flow ?? true) && (
        <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB] flex flex-col gap-3">
          <div className="flex items-center gap-2">
            <Activity size={16} style={{ color: "#0284C7" }} />
            <p className="text-[14px] font-bold text-[#0F172A]">Conversation flow</p>
          </div>
          {flow.length === 0 ? (
            <p className="text-[13px] text-[#9CA3AF]">Start captions to track who is speaking and how the conversation moves.</p>
          ) : (
            <>
              <div className="flex flex-col gap-2">
                {flow.map(f => {
                  const maxTurns = Math.max(...flow.map(x => x.turns), 1);
                  const pct = Math.round((f.turns / maxTurns) * 100);
                  return (
                    <div key={f.speaker}>
                      <div className="flex justify-between text-[12px] mb-1">
                        <span className="font-bold" style={{ color: speakerColor(f.speaker) }}>{f.speaker}</span>
                        <span className="text-[#6B7280]">{f.turns} turns · {f.words} words</span>
                      </div>
                      <div className="h-2 rounded-full bg-[#E5E7EB] overflow-hidden">
                        <div className="h-full rounded-full" style={{ width: `${pct}%`, background: speakerColor(f.speaker) }} />
                      </div>
                    </div>
                  );
                })}
              </div>
              <div className="pt-2 border-t border-[#F3F4F6]">
                <p className="text-[11px] font-bold uppercase tracking-wide text-[#9CA3AF] mb-2">Turn timeline</p>
                <div className="flex flex-wrap gap-1">
                  {lines.map(l => (
                    <span
                      key={l.id}
                      className="text-[10px] font-bold px-2 py-1 rounded-full text-white"
                      style={{ background: speakerColor(l.speaker) }}
                      title={l.text}
                    >
                      {l.speaker}
                    </span>
                  ))}
                </div>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}

function CallSessionOverlay({
  theme, contact, mode, onEnd, hearingAssist = false,
}: {
  theme: ModeTheme;
  contact: ChatConversation;
  mode: "voice" | "video";
  onEnd: (durationSec: number) => void;
  hearingAssist?: boolean;
}) {
  const [status, setStatus] = useState<"calling" | "connected" | "ended">("calling");
  const [elapsed, setElapsed] = useState(0);
  const elapsedRef = useRef(0);
  const [callCaptions, setCallCaptions] = useState<{ speaker: string; text: string }[]>([]);
  const [livePartial, setLivePartial] = useState("");
  const recognitionRef = useRef<{ stop: () => void } | null>(null);

  useEffect(() => {
    const connectTimer = window.setTimeout(() => setStatus("connected"), 1800);
    return () => window.clearTimeout(connectTimer);
  }, []);

  useEffect(() => {
    if (status !== "connected") return;
    const tick = window.setInterval(() => {
      elapsedRef.current += 1;
      setElapsed(elapsedRef.current);
    }, 1000);
    return () => window.clearInterval(tick);
  }, [status]);

  // Demo + optional mic captions during connected hearing-assist calls
  useEffect(() => {
    if (!hearingAssist || status !== "connected") return;
    const demoScript = [
      { delay: 1200, speaker: contact.name.split(" ")[0] || "Caller", text: "Can you hear me okay on this call?" },
      { delay: 4200, speaker: "You", text: "Yes — I have live captions on." },
      { delay: 7500, speaker: contact.name.split(" ")[0] || "Caller", text: "Great. Let's review your medication schedule for this week." },
    ];
    const timers = demoScript.map(item =>
      window.setTimeout(() => {
        setCallCaptions(prev => [...prev, { speaker: item.speaker, text: item.text }]);
      }, item.delay)
    );

    const win = window as unknown as {
      SpeechRecognition?: new () => any;
      webkitSpeechRecognition?: new () => any;
    };
    const SR = win.SpeechRecognition || win.webkitSpeechRecognition;
    if (SR) {
      try {
        const recognition = new SR();
        recognition.continuous = true;
        recognition.interimResults = true;
        recognition.lang = "en-US";
        recognition.onresult = (event: any) => {
          let interim = "";
          for (let i = event.resultIndex; i < event.results.length; i++) {
            const t = event.results[i][0].transcript.trim();
            if (!t) continue;
            if (event.results[i].isFinal) {
              setCallCaptions(prev => [...prev, { speaker: "You", text: t }]);
              setLivePartial("");
            } else interim += t + " ";
          }
          if (interim) setLivePartial(interim.trim());
        };
        recognition.onerror = () => {};
        recognitionRef.current = recognition;
        recognition.start();
      } catch {}
    }

    return () => {
      timers.forEach(t => window.clearTimeout(t));
      try { recognitionRef.current?.stop(); } catch {}
      recognitionRef.current = null;
    };
  }, [hearingAssist, status, contact.name]);

  const formatElapsed = (s: number) => {
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
  };

  const endCall = () => {
    try { recognitionRef.current?.stop(); } catch {}
    setStatus("ended");
    onEnd(elapsedRef.current);
  };

  const openNative = () => {
    const digits = digitsOnlyPhone(contact.phone);
    if (!digits) return;
    if (mode === "voice") {
      window.location.href = `tel:${digits}`;
    } else {
      window.location.href = `facetime:${digits}`;
    }
  };

  return (
    <div className="absolute inset-0 z-50 flex flex-col"
      style={{
        background: mode === "video"
          ? "linear-gradient(160deg, #0F172A 0%, #1E293B 55%, #0F172A 100%)"
          : `linear-gradient(160deg, ${theme.color} 0%, #0F172A 100%)`,
      }}>
      {mode === "video" && status === "connected" && (
        <div className="absolute inset-0 opacity-40"
          style={{ background: "radial-gradient(circle at 30% 20%, #38BDF8 0%, transparent 45%), radial-gradient(circle at 70% 80%, #A78BFA 0%, transparent 40%)" }} />
      )}

      <div className="relative flex-1 flex flex-col items-center justify-center px-6 text-center gap-4">
        <div className="w-24 h-24 rounded-full flex items-center justify-center text-white text-[28px] font-bold border-4 border-white/30"
          style={{ background: theme.color, boxShadow: status === "calling" ? "0 0 0 12px rgba(255,255,255,0.12)" : "none" }}>
          {contact.avatar}
        </div>
        <div>
          <p className="text-white text-[22px] font-bold">{contact.name}</p>
          <p className="text-white/70 text-[13px] mt-1">{contact.role}</p>
          {contact.phone && (
            <p className="text-white/50 text-[12px] mt-0.5">{contact.phone}</p>
          )}
        </div>
        <p className="text-white/90 text-[15px] font-semibold">
          {status === "calling" && (mode === "video" ? "FaceTime connecting…" : "Calling…")}
          {status === "connected" && (mode === "video" ? `FaceTime · ${formatElapsed(elapsed)}` : formatElapsed(elapsed))}
          {status === "ended" && "Call ended"}
        </p>
        {mode === "video" && status === "connected" && (
          <div className="absolute bottom-36 right-5 w-24 h-32 rounded-2xl border-2 border-white/40 overflow-hidden bg-[#1E293B] flex items-center justify-center">
            <p className="text-white/60 text-[10px] font-semibold">You</p>
          </div>
        )}
      </div>

      {hearingAssist && status === "connected" && (
        <div className="relative mx-4 mb-3 rounded-2xl bg-black/70 border border-white/20 px-3 py-2.5 max-h-36 overflow-y-auto text-left">
          <div className="flex items-center gap-1.5 mb-1.5">
            <Captions size={12} className="text-[#7DD3FC]" />
            <p className="text-[10px] font-bold uppercase tracking-wider text-[#7DD3FC]">Live call captions</p>
          </div>
          {callCaptions.length === 0 && !livePartial && (
            <p className="text-[12px] text-white/50 italic">Waiting for speech…</p>
          )}
          {callCaptions.slice(-4).map((c, i) => (
            <p key={i} className="text-[13px] text-white leading-snug mb-1">
              <span className="font-bold text-[#7DD3FC]">{c.speaker}: </span>{c.text}
            </p>
          ))}
          {livePartial && (
            <p className="text-[13px] text-white/70 italic">You: {livePartial}…</p>
          )}
        </div>
      )}

      <div className="relative px-6 pb-10 flex flex-col items-center gap-3">
        {contact.phone && status !== "ended" && (
          <button type="button" onClick={openNative}
            className="text-white/80 text-[12px] font-semibold underline">
            {mode === "video" ? "Open in FaceTime app" : "Open in Phone app"}
          </button>
        )}
        <button
          type="button"
          onClick={endCall}
          className="w-16 h-16 rounded-full flex items-center justify-center bg-[#EF4444] shadow-lg active:scale-95 transition-transform"
          aria-label="End call"
        >
          <PhoneOff size={26} className="text-white" />
        </button>
        <p className="text-white/60 text-[12px]">End call</p>
      </div>
    </div>
  );
}

function isDoctorContact(name: string, role: string): boolean {
  const hay = `${name} ${role}`.toLowerCase();
  return /\bdr\.?\b/.test(hay) || hay.includes("physician") || hay.includes("doctor");
}

function MessagesContent({
  theme, initialChatId, onChatOpened, linkedCaregivers = [], hearingAssist = false,
  messagingMode = "patient",
  patientName = "",
  caregiverName = "",
}: {
  theme: ModeTheme;
  initialChatId?: string | null;
  onChatOpened?: () => void;
  linkedCaregivers?: LinkedCaregiver[];
  hearingAssist?: boolean;
  messagingMode?: "patient" | "caregiver-doctor";
  patientName?: string;
  caregiverName?: string;
}) {
  const doctorOnly = messagingMode === "caregiver-doctor";
  const [activeChat, setActiveChat] = useState<string | null>(initialChatId ?? null);
  const [msgText, setMsgText] = useState("");
  const { isListening: micListening, toggle: micToggle } = useVoiceDictation(text =>
    setMsgText(prev => (prev.trim() ? `${prev.trim()} ${text}` : text))
  );
  const [messages, setMessages] = useState<Record<string, ChatMessage[]>>(loadChatMessages);
  const [conversations, setConversations] = useState<ChatConversation[]>(() => {
    const all = loadConversations();
    if (!doctorOnly) return all;
    const doctors = all.filter(c => isDoctorContact(c.name, c.role));
    if (doctors.length) return doctors;
    return [SAMPLE_CONVERSATIONS[0]];
  });
  const [showNewChat, setShowNewChat] = useState(false);
  const [newName, setNewName] = useState("");
  const [newRole, setNewRole] = useState("");
  const [newPhone, setNewPhone] = useState("");
  const [callSession, setCallSession] = useState<{ mode: "voice" | "video" } | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const conv = conversations.find(c => c.id === activeChat) ?? null;

  const careCircleSuggestions = linkedCaregivers
    .filter(cg => cg.status === "active")
    .map(cg => ({
      name: cg.name,
      role: cg.relationship,
      phone: cg.phone ?? "",
    }));

  const suggestions = doctorOnly
    ? [
        ...NEW_CHAT_SUGGESTIONS.filter(s => isDoctorContact(s.name, s.role)),
        ...careCircleSuggestions.filter(s => isDoctorContact(s.name, s.role)),
      ].filter((s, i, arr) => arr.findIndex(x => x.name.toLowerCase() === s.name.toLowerCase()) === i)
    : [
        ...careCircleSuggestions,
        ...NEW_CHAT_SUGGESTIONS.filter(
          s => !careCircleSuggestions.some(c => c.name.toLowerCase() === s.name.toLowerCase())
        ),
      ];

  useEffect(() => {
    setMessages(loadChatMessages());
    const all = loadConversations();
    if (doctorOnly) {
      const doctors = all.filter(c => isDoctorContact(c.name, c.role));
      setConversations(doctors.length ? doctors : [SAMPLE_CONVERSATIONS[0]]);
    } else {
      setConversations(all);
    }
  }, [initialChatId, doctorOnly]);

  useEffect(() => {
    if (initialChatId) {
      setActiveChat(initialChatId);
      onChatOpened?.();
    }
  }, [initialChatId, onChatOpened]);

  useEffect(() => {
    try {
      localStorage.setItem(CHAT_STORAGE_KEY, JSON.stringify(messages));
    } catch {}
  }, [messages]);

  useEffect(() => {
    if (doctorOnly) {
      try {
        const all = loadConversations();
        const nonDoctors = all.filter(c => !isDoctorContact(c.name, c.role));
        const byId = new Map(nonDoctors.map(c => [c.id, c]));
        for (const c of conversations) byId.set(c.id, c);
        saveConversations([...byId.values()]);
      } catch {}
      return;
    }
    saveConversations(conversations);
  }, [conversations, doctorOnly]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [activeChat, messages]);

  const conversationRows = conversations.map(c => {
    const thread = messages[c.id] ?? [];
    const last = thread[thread.length - 1];
    const alertUnread = thread.some(
      m => !m.mine && m.sender === "CareConnect Alerts" && m.id.startsWith("low-mood-")
    );
    return {
      ...c,
      lastMsg: last?.text ?? c.lastMsg,
      time: last?.time ?? c.time,
      unread: alertUnread && (!activeChat || activeChat !== c.id) ? Math.max(1, c.unread) : c.unread,
    };
  });

  const updateConversationPreview = (chatId: string, lastMsg: string) => {
    const now = new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    setConversations(prev => prev.map(c =>
      c.id === chatId ? { ...c, lastMsg, time: now, unread: 0 } : c
    ));
  };

  const createConversation = (name: string, role: string, phone: string) => {
    const cleaned = name.trim();
    if (!cleaned) return;
    if (doctorOnly && !isDoctorContact(cleaned, role)) return;
    const existing = conversations.find(
      c => c.name.toLowerCase() === cleaned.toLowerCase()
    );
    if (existing) {
      setActiveChat(existing.id);
      setShowNewChat(false);
      setNewName("");
      setNewRole("");
      setNewPhone("");
      return;
    }
    const id = `c-${Date.now()}`;
    const created: ChatConversation = {
      id,
      name: cleaned,
      role: role.trim() || (doctorOnly ? "Primary Care Physician" : "Contact"),
      lastMsg: "New conversation",
      time: "Just now",
      unread: 0,
      avatar: makeChatAvatar(cleaned),
      phone: phone.trim() || undefined,
    };
    setConversations(prev => [created, ...prev]);
    setMessages(prev => ({
      ...prev,
      [id]: [{
        id: `sys-${Date.now()}`,
        sender: "CareConnect",
        text: doctorOnly && patientName
          ? `Conversation with ${cleaned} on behalf of ${patientName}.`
          : `Conversation started with ${cleaned}. You can message, call, or FaceTime from here.`,
        time: new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }),
        mine: false,
      }],
    }));
    setActiveChat(id);
    setShowNewChat(false);
    setNewName("");
    setNewRole("");
    setNewPhone("");
  };

  const sendMessage = () => {
    const text = msgText.trim();
    if (!text || !activeChat || !conv) return;

    const chatId = activeChat;
    const now = new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    const onBehalfLabel =
      doctorOnly && patientName
        ? `${caregiverName || "Caregiver"} (on behalf of ${patientName})`
        : "You";
    const outgoing: ChatMessage = {
      id: `user-${Date.now()}`,
      sender: onBehalfLabel,
      text: doctorOnly && patientName
        ? `[On behalf of ${patientName}] ${text}`
        : text,
      time: now,
      mine: true,
    };

    setMessages(current => ({
      ...current,
      [chatId]: [...(current[chatId] ?? []), outgoing],
    }));
    updateConversationPreview(chatId, outgoing.text);
    setMsgText("");

    window.setTimeout(() => {
      const reply: ChatMessage = {
        id: `reply-${Date.now()}`,
        sender: conv.name,
        text: conv.id === "c3"
          ? "Thanks for contacting CareConnect Support. A team member will follow up shortly."
          : doctorOnly
            ? `Thanks for the update about ${patientName || "your patient"}. I'll review and follow up shortly.`
            : "Thank you for your message. I received it and will follow up with you shortly.",
        time: new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }),
        mine: false,
      };
      setMessages(current => ({
        ...current,
        [chatId]: [...(current[chatId] ?? []), reply],
      }));
      updateConversationPreview(chatId, reply.text);
    }, 900);
  };

  const logCallToChat = (mode: "voice" | "video", durationSec: number) => {
    if (!activeChat || !conv) return;
    const label = mode === "video" ? "FaceTime" : "Call";
    const mins = Math.floor(durationSec / 60);
    const secs = durationSec % 60;
    const duration =
      durationSec <= 0
        ? "no answer / ended early"
        : mins > 0
          ? `${mins}m ${secs}s`
          : `${secs}s`;
    const note: ChatMessage = {
      id: `call-${Date.now()}`,
      sender: "CareConnect",
      text: `${label} with ${conv.name} · ${duration}`,
      time: new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }),
      mine: false,
    };
    setMessages(current => ({
      ...current,
      [activeChat]: [...(current[activeChat] ?? []), note],
    }));
    updateConversationPreview(activeChat, note.text);
  };

  if (activeChat && conv) {
    return (
      <div className="relative flex flex-col h-full">
        {callSession && (
          <CallSessionOverlay
            theme={theme}
            contact={conv}
            mode={callSession.mode}
            hearingAssist={hearingAssist}
            onEnd={(durationSec) => {
              logCallToChat(callSession.mode, durationSec);
              setCallSession(null);
            }}
          />
        )}

        {/* Chat header */}
        <div className="px-4 py-3 border-b border-[#E5E7EB] bg-white flex items-center gap-3">
          <button type="button" onClick={() => setActiveChat(null)} className="text-[#6B7280]" aria-label="Back to conversations">
            <ChevronLeft size={20} />
          </button>
          <div className="w-9 h-9 rounded-full flex items-center justify-center text-white text-[12px] font-bold shrink-0" style={{ background: theme.color }}>
            {conv.avatar}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-[14px] font-bold text-[#0F172A] truncate">{conv.name}</p>
            <p className="text-[11px] text-[#6B7280] truncate">
              {conv.role}{conv.phone ? ` · ${conv.phone}` : ""}
            </p>
          </div>
          <button
            type="button"
            onClick={() => setCallSession({ mode: "voice" })}
            className="w-9 h-9 rounded-full flex items-center justify-center"
            style={{ background: theme.lightBg }}
            aria-label={`Call ${conv.name}`}
            title="Voice call"
          >
            <Phone size={15} style={{ color: theme.color }} />
          </button>
          <button
            type="button"
            onClick={() => setCallSession({ mode: "video" })}
            className="w-9 h-9 rounded-full flex items-center justify-center"
            style={{ background: theme.lightBg }}
            aria-label={`FaceTime ${conv.name}`}
            title="FaceTime / video call"
          >
            <Video size={15} style={{ color: theme.color }} />
          </button>
        </div>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-3">
          {(messages[activeChat] ?? []).map(m => (
            <div key={m.id} className={`flex ${m.mine ? "justify-end" : "justify-start"}`}>
              <div className="max-w-[78%]">
                {!m.mine && <p className="text-[10px] font-semibold text-[#6B7280] mb-1 ml-1">{m.sender}</p>}
                <div className="px-4 py-2.5 rounded-2xl"
                  style={{
                    background: m.mine ? theme.color : "#F3F4F6",
                    color: m.mine ? "white" : "#0F172A",
                    borderBottomRightRadius: m.mine ? 4 : 16,
                    borderBottomLeftRadius: m.mine ? 16 : 4,
                  }}>
                  <p className="text-[14px] leading-relaxed">{m.text}</p>
                </div>
                <p className="text-[10px] text-[#9CA3AF] mt-1 ml-1">{m.time}</p>
              </div>
            </div>
          ))}
          <div ref={messagesEndRef} />
        </div>

        {/* Input */}
        <div className="px-3 py-3 border-t border-[#E5E7EB] bg-white flex items-center gap-2">
          <MicButton isListening={micListening} onClick={micToggle} color={theme.color} size="md" />
          <input
            value={msgText} onChange={e => setMsgText(e.target.value)}
            onKeyDown={e => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                sendMessage();
              }
            }}
            placeholder={micListening ? "Listening — speak your message…" : "Message..."}
            className="flex-1 min-w-0 border rounded-full px-4 py-2.5 outline-none"
            style={{ fontSize: 16, borderColor: micListening ? "#EF4444" : "#E5E7EB", background: micListening ? "#FEF2F2" : "white" }}
          />
          <button onClick={sendMessage}
            disabled={!msgText.trim()}
            aria-label={`Send message to ${conv.name}`}
            className="w-10 h-10 rounded-full flex items-center justify-center text-white shrink-0"
            style={{ background: theme.color, opacity: msgText.trim() ? 1 : 0.45 }}>
            <Send size={16} />
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="relative flex flex-col min-h-full">
      <div className="px-4 pt-4 pb-2 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <MessageCircle size={18} style={{ color: theme.color }} />
          <div className="min-w-0">
            <h2 className="text-[18px] font-bold text-[#0F172A]">Messages</h2>
            {doctorOnly && (
              <p className="text-[11px] text-[#9CA3AF] truncate">
                Doctor only{patientName ? ` · on behalf of ${patientName}` : ""}
              </p>
            )}
          </div>
        </div>
        <button
          type="button"
          onClick={() => setShowNewChat(true)}
          className="flex items-center gap-1.5 px-3 py-2 rounded-xl text-[12px] font-bold text-white shrink-0"
          style={{ background: theme.color }}
        >
          <Plus size={14} />
          New
        </button>
      </div>

      <div className="flex flex-col divide-y divide-[#F3F4F6]">
        {conversationRows.map(c => (
          <button key={c.id} type="button" onClick={() => setActiveChat(c.id)}
            className="flex items-center gap-3 px-4 py-3.5 hover:bg-[#F9FAFB] transition-colors text-left w-full">
            <div className="relative shrink-0">
              <div className="w-11 h-11 rounded-full flex items-center justify-center text-white text-[13px] font-bold" style={{ background: theme.color }}>
                {c.avatar}
              </div>
              {c.unread > 0 && (
                <span className="absolute -top-1 -right-1 w-5 h-5 rounded-full bg-[#EF4444] text-white text-[9px] font-bold flex items-center justify-center">{c.unread}</span>
              )}
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex justify-between items-center mb-0.5">
                <p className="text-[14px] font-bold text-[#0F172A]">{c.name}</p>
                <span className="text-[11px] text-[#9CA3AF] shrink-0 ml-2">{c.time}</span>
              </div>
              <p className="text-[12px] text-[#6B7280] truncate">{c.lastMsg}</p>
            </div>
          </button>
        ))}
      </div>

      {showNewChat && (
        <div className="absolute inset-0 z-40 bg-black/40 flex flex-col justify-end">
          <div className="bg-white rounded-t-3xl px-5 pt-5 pb-8 max-h-[88%] overflow-y-auto">
            <div className="flex items-center justify-between mb-4">
              <div>
                <p className="text-[17px] font-bold text-[#0F172A]">New conversation</p>
                <p className="text-[12px] text-[#9CA3AF]">
                  {doctorOnly
                    ? `Message the patient’s doctor${patientName ? ` on behalf of ${patientName}` : ""}`
                    : "Message a care team member or add a contact"}
                </p>
              </div>
              <button type="button" onClick={() => setShowNewChat(false)}
                className="w-8 h-8 rounded-full bg-[#F3F4F6] flex items-center justify-center"
                aria-label="Close">
                <X size={16} className="text-[#6B7280]" />
              </button>
            </div>

            <p className="text-[11px] font-bold uppercase tracking-wide text-[#9CA3AF] mb-2">
              {doctorOnly ? "Doctors" : "Suggested"}
            </p>
            <div className="flex flex-col gap-2 mb-4">
              {suggestions.map(s => (
                <button
                  key={`${s.name}-${s.role}`}
                  type="button"
                  onClick={() => createConversation(s.name, s.role, s.phone)}
                  className="flex items-center gap-3 px-3 py-2.5 rounded-xl border border-[#E5E7EB] text-left hover:bg-[#F9FAFB]"
                >
                  <div className="w-9 h-9 rounded-full flex items-center justify-center text-white text-[11px] font-bold" style={{ background: theme.color }}>
                    {makeChatAvatar(s.name)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-[13px] font-bold text-[#0F172A]">{s.name}</p>
                    <p className="text-[11px] text-[#9CA3AF] truncate">{s.role}{s.phone ? ` · ${s.phone}` : ""}</p>
                  </div>
                  <PhoneCall size={14} style={{ color: theme.color }} />
                </button>
              ))}
            </div>

            {!doctorOnly && (
            <>
            <p className="text-[11px] font-bold uppercase tracking-wide text-[#9CA3AF] mb-2">Or add someone new</p>
            <div className="flex flex-col gap-2.5">
              <input
                value={newName}
                onChange={e => setNewName(e.target.value)}
                placeholder="Name"
                className="w-full px-4 py-3 rounded-xl border border-[#E5E7EB] text-[15px] outline-none focus:border-[#00A7C8]"
              />
              <input
                value={newRole}
                onChange={e => setNewRole(e.target.value)}
                placeholder="Role (e.g. Family, Nurse, Pharmacy)"
                className="w-full px-4 py-3 rounded-xl border border-[#E5E7EB] text-[15px] outline-none focus:border-[#00A7C8]"
              />
              <input
                value={newPhone}
                onChange={e => setNewPhone(e.target.value)}
                placeholder="Phone (for call / FaceTime)"
                className="w-full px-4 py-3 rounded-xl border border-[#E5E7EB] text-[15px] outline-none focus:border-[#00A7C8]"
              />
              <button
                type="button"
                disabled={!newName.trim()}
                onClick={() => createConversation(newName, newRole, newPhone)}
                className="w-full py-3.5 rounded-xl text-[14px] font-bold text-white mt-1"
                style={{ background: theme.color, opacity: newName.trim() ? 1 : 0.45 }}
              >
                Start conversation
              </button>
            </div>
            </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ── Caregiver: Patient list ────────────────────────────────────────────────────

const PATIENT_ROSTER = [
  { id: "p1", name: "Eleanor Wright", age: 72, condition: "Hypertension · Diabetes", status: "stable", lastSeen: "Today 9:00 AM", avatar: "EW" },
  { id: "p2", name: "James Nguyen", age: 68, condition: "COPD · Heart failure", status: "attention", lastSeen: "Yesterday 3:30 PM", avatar: "JN" },
  { id: "p3", name: "Rosa Martinez", age: 81, condition: "Dementia · Osteoporosis", status: "critical", lastSeen: "Today 7:45 AM", avatar: "RM" },
  { id: "p4", name: "Harold Thompson", age: 65, condition: "Post-surgery recovery", status: "stable", lastSeen: "Mon, Jul 14", avatar: "HT" },
];

function PatientListContent({ theme }: { theme: ModeTheme }) {
  const statusColors: Record<string, { bg: string; color: string; label: string }> = {
    stable:    { bg: "#D1FAE5", color: "#059669", label: "Stable" },
    attention: { bg: "#FEF3C7", color: "#D97706", label: "Attention" },
    critical:  { bg: "#FEE2E2", color: "#DC2626", label: "Critical" },
  };

  return (
    <div className="flex flex-col min-h-full">
      <div className="px-4 pt-4 pb-3 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Users size={18} style={{ color: theme.color }} />
          <h2 className="text-[18px] font-bold text-[#0F172A]">Patient List</h2>
        </div>
        <span className="text-[12px] font-semibold px-2.5 py-1 rounded-full" style={{ background: theme.lightBg, color: theme.color }}>
          {PATIENT_ROSTER.length} patients
        </span>
      </div>

      {/* Summary pills */}
      <div className="flex gap-2 px-4 pb-3 overflow-x-auto">
        {Object.entries(statusColors).map(([key, s]) => {
          const count = PATIENT_ROSTER.filter(p => p.status === key).length;
          return (
            <div key={key} className="flex items-center gap-1.5 px-3 py-1.5 rounded-full shrink-0" style={{ background: s.bg }}>
              <div className="w-2 h-2 rounded-full" style={{ background: s.color }} />
              <span className="text-[12px] font-semibold" style={{ color: s.color }}>{count} {s.label}</span>
            </div>
          );
        })}
      </div>

      <div className="flex flex-col divide-y divide-[#F3F4F6] px-4 gap-0">
        {PATIENT_ROSTER.map(p => {
          const sc = statusColors[p.status];
          return (
            <div key={p.id} className="py-3.5 flex items-center gap-3">
              <div className="w-11 h-11 rounded-full flex items-center justify-center text-white text-[12px] font-bold shrink-0" style={{ background: theme.color }}>
                {p.avatar}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-0.5">
                  <p className="text-[14px] font-bold text-[#0F172A] truncate">{p.name}</p>
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full shrink-0" style={{ background: sc.bg, color: sc.color }}>{sc.label}</span>
                </div>
                <p className="text-[12px] text-[#6B7280] truncate">{p.condition}</p>
                <p className="text-[11px] text-[#9CA3AF]">Last seen: {p.lastSeen}</p>
              </div>
              <div className="flex gap-1.5 shrink-0">
                <button className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "#EFF6FF" }}>
                  <Phone size={13} style={{ color: "#3B82F6" }} />
                </button>
                <button className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: theme.lightBg }}>
                  <MessageCircle size={13} style={{ color: theme.color }} />
                </button>
              </div>
            </div>
          );
        })}
      </div>

      <div className="px-4 pb-4 pt-2">
        <button className="w-full py-3 rounded-2xl border-2 border-dashed text-[14px] font-semibold transition-colors"
          style={{ borderColor: theme.color + "60", color: theme.color }}>
          + Add patient
        </button>
      </div>
    </div>
  );
}

// ── Caregiver: Analytics ───────────────────────────────────────────────────────

function AnalyticsContent({
  theme, patients, medications = [], medsChecked = {}, appointments = [],
  checkinsThisWeek = 0, moodHistory = [], patientMood = null,
}: {
  theme: ModeTheme;
  patients: PatientSnippet[];
  medications?: Medication[];
  medsChecked?: Record<string, boolean>;
  appointments?: Appointment[];
  checkinsThisWeek?: number;
  moodHistory?: MoodEntry[];
  patientMood?: number | null;
}) {
  const carePatients = patients;
  const [selectedId, setSelectedId] = useState(carePatients[0]?.id ?? "");

  useEffect(() => {
    if (!carePatients.some(p => p.id === selectedId)) {
      setSelectedId(carePatients[0]?.id ?? "");
    }
  }, [patients, selectedId]);

  const patient = carePatients.find(p => p.id === selectedId) ?? carePatients[0];
  const moodLabels = ["", "Poor", "Low", "Fair", "Good", "Great"];
  const medTotal = Math.max(1, medications.length || 1);
  const medTaken = Object.values(medsChecked).filter(Boolean).length;
  const liveAdherence = medications.length
    ? Math.round((medTaken / medTotal) * 100)
    : (patient?.medAdherence ?? 0);
  const adherence = patient?.grants.includes("med_adherence") ? (patient.medAdherence ?? liveAdherence) : null;
  const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const todayIdx = (new Date().getDay() + 6) % 7; // Mon=0
  const bars = days.map((_, i) => {
    if (adherence == null) return 0;
    if (i === todayIdx) return adherence;
    // Prior days: mild variance around current adherence (stable demo signal)
    const wobble = ((i * 17 + adherence) % 11) - 5;
    return Math.max(40, Math.min(100, adherence + wobble));
  });

  const vitals: { label: string; value: string; good: boolean }[] = patient ? [
    patient.grants.includes("mood") && {
      label: "Mood",
      value: patient.mood
        ? `${moodLabels[patient.mood]} (${patient.mood}/5)`
        : "Not logged",
      good: !!(patient.mood && patient.mood >= 3),
    },
    patient.grants.includes("med_adherence") && adherence != null && {
      label: "Med adherence",
      value: `${adherence}%`,
      good: adherence >= 80,
    },
    patient.grants.includes("checkin_summary") && {
      label: "Check-ins",
      value: `${Math.min(7, checkinsThisWeek || (patient.lastCheckin ? 1 : 0))} / 7`,
      good: !!(patient.lastCheckin || checkinsThisWeek),
    },
    patient.grants.includes("upcoming_visits") && {
      label: "Upcoming visits",
      value: `${appointments.length}`,
      good: appointments.length > 0,
    },
  ].filter(Boolean) as { label: string; value: string; good: boolean }[] : [];

  const alerts: { icon: React.ReactNode; text: string; time: string; color: string }[] = [];
  if (patient?.accessState === "ok") {
    const first = patient.name.split(" ")[0];
    if (patient.grants.includes("fall_alerts") && patient.hasFallAlert) {
      alerts.push({ icon: <AlertTriangle size={13} />, text: `${first} — possible fall alert`, time: "Today", color: "#EF4444" });
    }
    if (patient.grants.includes("med_adherence") && adherence != null && adherence < 80) {
      alerts.push({ icon: <Pill size={13} />, text: `${first} med adherence at ${adherence}%`, time: "Today", color: "#F59E0B" });
    }
    if (patient.grants.includes("checkin_summary") && patient.lastCheckin) {
      alerts.push({ icon: <Check size={13} />, text: `${first} completed virtual check-in`, time: patient.lastCheckin, color: "#10B981" });
    }
    if (patient.grants.includes("upcoming_visits") && appointments[0]) {
      alerts.push({
        icon: <Bell size={13} />,
        text: `Next visit: ${appointments[0].title}`,
        time: `${appointments[0].date} · ${appointments[0].time}`,
        color: "#00A7C8",
      });
    }
    if (patient.grants.includes("mood") && patient.mood && patient.mood <= 2) {
      alerts.push({ icon: <AlertTriangle size={13} />, text: `${first} logged a low mood`, time: "Today", color: "#EF4444" });
    }
    if (patient.grants.includes("mood") && moodHistory.length > 0) {
      const streak = countConsecutiveLowMoodDays(moodHistory);
      const streakAlert = loadLowMoodStreakAlert();
      if (streak >= LOW_MOOD_STREAK_THRESHOLD) {
        alerts.unshift({
          icon: <AlertTriangle size={13} />,
          text: `${first} has felt Poor/Low for ${streak} days in a row — care team notified`,
          time: streakAlert?.notifiedAt
            ? new Date(streakAlert.notifiedAt).toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
            : "Today",
          color: "#EF4444",
        });
      }
    }
  }

  return (
    <div className="flex flex-col min-h-full px-4 pt-4 pb-28 gap-4">
      <div className="flex items-center gap-2">
        <BarChart2 size={18} style={{ color: theme.color }} />
        <h2 className="text-[18px] font-bold text-[#0F172A]">Analytics</h2>
      </div>

      {carePatients.length === 0 ? (
        <div className="rounded-2xl bg-white border border-[#E5E7EB] p-5 text-center">
          <p className="text-[15px] font-bold text-[#0F172A] mb-1">No patient linked</p>
          <p className="text-[13px] text-[#9CA3AF]">
            Analytics appear for the User/Patient who added you in their Care Circle.
          </p>
        </div>
      ) : (
        <>
          <div className="flex gap-2 overflow-x-auto pb-1">
            {carePatients.map(p => (
              <button key={p.id} type="button" onClick={() => setSelectedId(p.id)}
                className="px-3 py-1.5 rounded-full text-[12px] font-semibold shrink-0 transition-all"
                style={{
                  background: selectedId === p.id ? theme.color : "#F3F4F6",
                  color: selectedId === p.id ? "white" : "#6B7280",
                }}>
                {p.name}
              </button>
            ))}
          </div>

          {patient && patient.accessState !== "ok" && (
            <div className="rounded-2xl px-4 py-3" style={{ background: "#FFFBEB", border: "1px solid #FDE68A" }}>
              <p className="text-[13px] font-semibold text-[#92400E]">
                {patient.accessState === "pending" && "Invite pending — shared analytics unlock when the patient approves this caregiver."}
                {patient.accessState === "inactive_profile" && "No active patient profile yet — analytics will appear after they finish setup."}
                {(patient.accessState === "suspended" || patient.accessState === "unauthorized") && "Access not authorized — no analytics available."}
              </p>
            </div>
          )}

          {patient?.accessState === "ok" && (
            <>
              <div className="rounded-xl px-3 py-2 flex items-center gap-2" style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}>
                <span className="text-[14px]">📊</span>
                <p className="text-[12px] font-semibold" style={{ color: theme.color }}>
                  Live data for {patient.name}
                  {patient.caregiverRelationship ? ` · as ${patient.caregiverRelationship}` : ""}
                </p>
              </div>

              <div className="grid grid-cols-2 gap-3">
                {vitals.length === 0 ? (
                  <div className="col-span-2 rounded-2xl p-4 bg-white border border-[#E5E7EB] text-center">
                    <p className="text-[13px] font-semibold text-[#0F172A]">No shared analytics yet</p>
                    <p className="text-[12px] text-[#9CA3AF] mt-1">Only features the patient shares appear here.</p>
                  </div>
                ) : vitals.map(v => (
                  <div key={v.label} className="rounded-2xl p-3.5 bg-white border border-[#E5E7EB]">
                    <p className="text-[11px] font-semibold text-[#9CA3AF] uppercase tracking-wide mb-1">{v.label}</p>
                    <p className="text-[18px] font-bold text-[#0F172A]">{v.value}</p>
                    <div className="flex items-center gap-1 mt-1">
                      <TrendingUp size={11} style={{ color: v.good ? "#10B981" : "#EF4444" }} />
                      <span className="text-[11px] font-semibold" style={{ color: v.good ? "#10B981" : "#EF4444" }}>
                        {v.good ? "On track" : "Needs attention"}
                      </span>
                    </div>
                  </div>
                ))}
              </div>

              {patient.grants.includes("mood") && (
                <MoodTrendCard
                  theme={theme}
                  history={moodHistory}
                  currentMood={patient.mood ?? patientMood}
                />
              )}

              {patient.grants.includes("med_adherence") && (
                <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB]">
                  <p className="text-[13px] font-bold text-[#0F172A] mb-1">Medication adherence — this week</p>
                  <p className="text-[11px] text-[#9CA3AF] mb-3">
                    Today: {medTaken}/{medications.length || 0} doses logged
                    {adherence != null ? ` · ${adherence}%` : ""}
                  </p>
                  <div className="flex items-end gap-2 h-20">
                    {bars.map((b, i) => (
                      <div key={i} className="flex-1 flex flex-col items-center gap-1">
                        <div className="w-full rounded-t-md" style={{
                          height: `${Math.max(8, b * 0.7)}%`,
                          background: i === todayIdx ? theme.color : b >= 90 ? "#10B981" : b >= 75 ? "#F59E0B" : "#EF4444",
                          opacity: i === todayIdx ? 1 : 0.55,
                        }} />
                        <span className="text-[9px] text-[#9CA3AF] font-semibold">{days[i]}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {patient.grants.includes("upcoming_visits") && appointments.length > 0 && (
                <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB]">
                  <p className="text-[13px] font-bold text-[#0F172A] mb-3">Upcoming visits</p>
                  <div className="flex flex-col gap-2">
                    {appointments.map(a => (
                      <div key={a.id} className="px-3 py-2 rounded-xl bg-[#F9FAFB] border border-[#E5E7EB]">
                        <p className="text-[13px] font-semibold text-[#0F172A]">{a.title}</p>
                        <p className="text-[11px] text-[#9CA3AF]">{a.date} · {a.time} · {a.type}</p>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB]">
                <p className="text-[13px] font-bold text-[#0F172A] mb-3">Recent alerts</p>
                {alerts.length === 0 ? (
                  <p className="text-[12px] text-[#9CA3AF]">No alerts from shared data right now.</p>
                ) : alerts.map((ev, i) => (
                  <div key={i} className="flex items-center gap-3 py-2 border-b border-[#F3F4F6] last:border-0">
                    <div className="w-6 h-6 rounded-full flex items-center justify-center shrink-0" style={{ background: ev.color + "20", color: ev.color }}>{ev.icon}</div>
                    <div className="flex-1 min-w-0">
                      <p className="text-[12px] text-[#374151] truncate">{ev.text}</p>
                      <p className="text-[11px] text-[#9CA3AF]">{ev.time}</p>
                    </div>
                  </div>
                ))}
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}

// ── Caregiver: Home dashboard ──────────────────────────────────────────────────

function CaregiverHomeContent({ theme, onTabChange }: { theme: ModeTheme; onTabChange: (t: Tab) => void }) {
  const critical = PATIENT_ROSTER.filter(p => p.status === "critical");
  const attention = PATIENT_ROSTER.filter(p => p.status === "attention");

  return (
    <div className="px-4 pt-4 pb-4 flex flex-col gap-3">
      {/* Alert banner */}
      {(critical.length + attention.length) > 0 && (
        <div className="rounded-2xl p-3.5 flex items-start gap-3" style={{ background: "#FEF3C7", border: "1.5px solid #FDE68A" }}>
          <AlertTriangle size={18} style={{ color: "#D97706" }} className="shrink-0 mt-0.5" />
          <div>
            <p className="text-[13px] font-bold text-[#92400E]">{critical.length} critical · {attention.length} needs attention</p>
            <p className="text-[12px] text-[#78350F]">Review patient statuses below</p>
          </div>
        </div>
      )}

      {/* Stats row */}
      <div className="grid grid-cols-3 gap-2">
        {[
          { label: "Patients", value: PATIENT_ROSTER.length.toString(), color: theme.color },
          { label: "Check-ins", value: "12", color: "#10B981" },
          { label: "Tasks due", value: "3", color: "#F59E0B" },
        ].map(s => (
          <div key={s.label} className="rounded-2xl p-3 bg-white border border-[#E5E7EB] text-center">
            <p className="text-[22px] font-bold" style={{ color: s.color }}>{s.value}</p>
            <p className="text-[11px] text-[#9CA3AF] font-semibold">{s.label}</p>
          </div>
        ))}
      </div>

      {/* Quick actions */}
      <div className="grid grid-cols-2 gap-2">
        {[
          { icon: <Users size={20} />, label: "Patient list", tab: "patients" as Tab },
          { icon: <Calendar size={20} />, label: "Schedule", tab: "schedule" as Tab },
          { icon: <BarChart2 size={20} />, label: "Analytics", tab: "analytics" as Tab },
          { icon: <MessageCircle size={20} />, label: "Messages", tab: "messages" as Tab },
        ].map(a => (
          <button key={a.label} onClick={() => onTabChange(a.tab)}
            className="flex items-center gap-2 p-3.5 rounded-2xl bg-white border border-[#E5E7EB] hover:border-current transition-colors"
            style={{ color: theme.color }}>
            {a.icon}
            <span className="text-[13px] font-semibold text-[#0F172A]">{a.label}</span>
          </button>
        ))}
      </div>

      {/* Priority patients */}
      <div className="rounded-2xl overflow-hidden border border-[#E5E7EB] bg-white">
        <div className="px-4 pt-3 pb-2 flex items-center justify-between">
          <p className="text-[12px] font-bold uppercase tracking-wider" style={{ color: theme.color }}>Priority patients</p>
          <button onClick={() => onTabChange("patients")} className="text-[12px] font-semibold" style={{ color: theme.color }}>See all</button>
        </div>
        {[...critical, ...attention].slice(0, 3).map(p => (
          <div key={p.id} className="flex items-center gap-3 px-4 py-3 border-t border-[#F3F4F6]">
            <div className="w-9 h-9 rounded-full flex items-center justify-center text-white text-[11px] font-bold shrink-0" style={{ background: theme.color }}>
              {p.avatar}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-[13px] font-bold text-[#0F172A] truncate">{p.name}</p>
              <p className="text-[11px] text-[#6B7280] truncate">{p.condition}</p>
            </div>
            <span className="text-[10px] font-bold px-2 py-0.5 rounded-full shrink-0"
              style={{ background: p.status === "critical" ? "#FEE2E2" : "#FEF3C7", color: p.status === "critical" ? "#DC2626" : "#D97706" }}>
              {p.status === "critical" ? "Critical" : "Attention"}
            </span>
          </div>
        ))}
      </div>

      {/* Today's visits */}
      <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB]">
        <p className="text-[12px] font-bold uppercase tracking-wider mb-3" style={{ color: theme.color }}>Today&apos;s visits</p>
        {[
          { name: "Eleanor Wright", time: "9:00 AM", type: "In-home visit", status: "completed" },
          { name: "Rosa Martinez", time: "11:30 AM", type: "Medication check", status: "upcoming" },
          { name: "James Nguyen", time: "3:00 PM", type: "Video call", status: "upcoming" },
        ].map((v, i) => (
          <div key={i} className="flex items-center gap-3 py-2.5 border-b border-[#F3F4F6] last:border-0">
            <Clock size={13} className="shrink-0 text-[#9CA3AF]" />
            <div className="flex-1 min-w-0">
              <p className="text-[13px] font-semibold text-[#0F172A]">{v.name}</p>
              <p className="text-[11px] text-[#9CA3AF]">{v.time} · {v.type}</p>
            </div>
            <span className="text-[10px] font-bold px-2 py-0.5 rounded-full shrink-0"
              style={{ background: v.status === "completed" ? "#D1FAE5" : "#E0F2FE", color: v.status === "completed" ? "#059669" : "#0284C7" }}>
              {v.status === "completed" ? "Done" : "Upcoming"}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Mood widget (Patient Home) ─────────────────────────────────────────────────

function MoodWidget({
  theme, mood, moodHistory = [], onMoodChange, careTeamAlert = null, onOpenMessages,
}: {
  theme: ModeTheme;
  mood: number | null;
  moodHistory?: MoodEntry[];
  onMoodChange: (score: number, symptom?: string) => void;
  careTeamAlert?: LowMoodStreakAlert | null;
  onOpenMessages?: () => void;
}) {
  const moods = [
    { score: 1, emoji: "😞", label: "Poor" },
    { score: 2, emoji: "😕", label: "Low" },
    { score: 3, emoji: "😐", label: "Fair" },
    { score: 4, emoji: "🙂", label: "Good" },
    { score: 5, emoji: "😄", label: "Great" },
  ];
  const [pendingScore, setPendingScore] = useState<number | null>(null);
  const [pickedSymptom, setPickedSymptom] = useState<string | null>(null);
  const [customSymptom, setCustomSymptom] = useState("");
  const todayKey = useLiveTodayKey();
  const todayEntry = moodHistory.find(e => e.date === todayKey);
  const loggedToday = !!todayEntry;
  const displayMood = pendingScore ?? (loggedToday ? (todayEntry?.score ?? mood) : null);

  const today = (() => {
    const [y, m, d] = todayKey.split("-").map(Number);
    return new Date(y, m - 1, d, 12);
  })();
  const weekday = today.toLocaleDateString([], { weekday: "long" });
  const fullDate = today.toLocaleDateString([], { month: "long", day: "numeric", year: "numeric" });
  const shortDate = today.toLocaleDateString([], { month: "short", day: "numeric", year: "numeric" });

  const commitMood = (score: number, symptom?: string) => {
    const cleaned = symptom?.trim();
    onMoodChange(
      score,
      cleaned && cleaned !== NONE_SYMPTOM ? cleaned : cleaned === NONE_SYMPTOM ? NONE_SYMPTOM : undefined,
    );
    setPendingScore(null);
    setPickedSymptom(null);
    setCustomSymptom("");
  };

  const handlePick = (score: number) => {
    setPendingScore(score);
    setPickedSymptom(todayEntry?.symptom && todayEntry.symptom !== NONE_SYMPTOM ? todayEntry.symptom : null);
    setCustomSymptom("");
  };

  const activeSymptom = customSymptom.trim() || pickedSymptom;

  return (
    <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB]">
      <div className="flex items-start justify-between gap-2 mb-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2 mb-0.5">
            <SmilePlus size={14} style={{ color: theme.color }} />
            <p className="text-[12px] font-bold uppercase tracking-wider" style={{ color: theme.color }}>How are you feeling?</p>
          </div>
          <p className="text-[14px] font-bold text-[#0F172A] pl-[22px]">
            {weekday}
          </p>
          <p className="text-[12px] text-[#6B7280] pl-[22px]">
            {fullDate}
          </p>
          <p className="text-[10px] text-[#9CA3AF] pl-[22px] mt-0.5">
            Date updates automatically each day
          </p>
        </div>
        <div
          className="shrink-0 px-2.5 py-1.5 rounded-xl text-center"
          style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}
        >
          <p className="text-[10px] font-bold uppercase tracking-wide" style={{ color: theme.color }}>Today</p>
          <p className="text-[11px] font-semibold text-[#0F172A]">{shortDate}</p>
        </div>
      </div>
      <div className="flex gap-2">
        {moods.map(m => (
          <button key={m.score} type="button" onClick={() => handlePick(m.score)}
            className="flex-1 flex flex-col items-center gap-1 py-2 rounded-xl transition-all"
            style={{
              background: displayMood === m.score ? theme.lightBg : "#F9FAFB",
              border: `1.5px solid ${displayMood === m.score ? theme.color : "#E5E7EB"}`,
            }}>
            <span className="text-[20px]">{m.emoji}</span>
            <span className="text-[9px] font-semibold" style={{ color: displayMood === m.score ? theme.color : "#9CA3AF" }}>{m.label}</span>
          </button>
        ))}
      </div>

      {pendingScore != null ? (
        <div className="mt-3 pt-3 border-t border-[#F3F4F6]">
          <p className="text-[13px] font-bold text-[#0F172A] mb-0.5">
            What symptom are you noticing on {weekday}?
          </p>
          <p className="text-[11px] text-[#9CA3AF] mb-2">
            Saved for {weekday}, {shortDate} · used for weekly & monthly tracking.
          </p>
          <div className="flex flex-wrap gap-1.5 mb-2">
            {QUICK_SYMPTOMS.map(s => (
              <button
                key={s}
                type="button"
                onClick={() => { setPickedSymptom(s); setCustomSymptom(""); }}
                className="px-2.5 py-1 rounded-full text-[11px] font-semibold border transition-all"
                style={{
                  background: pickedSymptom === s && !customSymptom.trim() ? theme.lightBg : "#F9FAFB",
                  borderColor: pickedSymptom === s && !customSymptom.trim() ? theme.color : "#E5E7EB",
                  color: pickedSymptom === s && !customSymptom.trim() ? theme.color : "#6B7280",
                }}
              >
                {s}
              </button>
            ))}
          </div>
          <input
            type="text"
            value={customSymptom}
            onChange={e => { setCustomSymptom(e.target.value); setPickedSymptom(null); }}
            placeholder="Or type your symptom…"
            className="w-full px-3 py-2.5 rounded-xl border border-[#E5E7EB] text-[14px] text-[#0F172A] outline-none mb-3 focus:border-[#00A7C8]"
          />
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => { setPendingScore(null); setPickedSymptom(null); setCustomSymptom(""); }}
              className="flex-1 py-2.5 rounded-xl text-[12px] font-bold"
              style={{ background: "#F3F4F6", color: "#6B7280" }}
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={() => commitMood(pendingScore, activeSymptom ?? undefined)}
              disabled={!activeSymptom}
              className="flex-1 py-2.5 rounded-xl text-[12px] font-bold text-white transition-opacity"
              style={{ background: theme.color, opacity: activeSymptom ? 1 : 0.45 }}
            >
              Save daily update
            </button>
          </div>
        </div>
      ) : loggedToday ? (
        <p className="text-[12px] text-center mt-2 font-semibold" style={{ color: theme.color }}>
          {weekday} update logged ✓ · {shortDate}
          {todayEntry?.symptom && todayEntry.symptom !== NONE_SYMPTOM
            ? ` · ${todayEntry.symptom}`
            : ""}
        </p>
      ) : (
        <p className="text-[11px] text-center mt-2 text-[#9CA3AF]">
          Pick a feeling for {weekday}, then tell us your symptom
        </p>
      )}

      {careTeamAlert && (
        <div className="mt-3 px-3 py-3 rounded-xl" style={{ background: "#FEF2F2", border: "1px solid #FECACA" }}>
          <div className="flex items-start gap-2">
            <AlertTriangle size={16} className="text-[#EF4444] shrink-0 mt-0.5" />
            <div className="flex-1 min-w-0">
              <p className="text-[13px] font-bold text-[#991B1B]">
                Care team notified
              </p>
              <p className="text-[12px] text-[#7F1D1D] mt-0.5 leading-snug">
                You’ve logged Poor or Low for {careTeamAlert.streakDays} days in a row.
                A message was sent to{" "}
                {careTeamAlert.recipientNames.join(" and ")}.
              </p>
              {onOpenMessages && (
                <button
                  type="button"
                  onClick={onOpenMessages}
                  className="mt-2 text-[12px] font-bold underline"
                  style={{ color: "#B91C1C" }}
                >
                  View messages
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/** Weekly + monthly feeling history for the patient profile (and caregiver analytics). */
function MoodTrendCard({
  theme, history, currentMood,
  title = "How you've been feeling",
  emptyHint = "Tap how you feel on Home — weekly and monthly history will build here automatically.",
}: {
  theme: ModeTheme;
  history: MoodEntry[];
  currentMood: number | null;
  title?: string;
  emptyHint?: string;
}) {
  const todayKey = useLiveTodayKey();
  const [view, setView] = useState<"week" | "month">("week");
  const now = (() => {
    const [y, m, d] = todayKey.split("-").map(Number);
    return new Date(y, m - 1, d, 12);
  })();
  const [monthCursor, setMonthCursor] = useState(() => ({
    year: now.getFullYear(),
    month: now.getMonth(),
  }));

  const enrichedHistory = (() => {
    try {
      const symptoms = loadLoggedSymptoms();
      return history.map(e => {
        if (e.symptom) return e;
        const found = findSymptomForDate(symptoms, e.date);
        return found ? { ...e, symptom: found } : e;
      });
    } catch {
      return history;
    }
  })();

  const series = buildWeekMoodSeries(enrichedHistory);
  const logged = series.filter(s => s.score != null) as {
    day: string; score: number; date: string; isToday: boolean; symptom?: string;
  }[];
  const avg = logged.length
    ? Math.round((logged.reduce((sum, s) => sum + s.score, 0) / logged.length) * 10) / 10
    : null;
  const worst = findWorstDayInWeek(enrichedHistory);
  const symptomAnalysis = analyzeSymptomPatterns(enrichedHistory);
  const firstHalf = logged.slice(0, Math.ceil(logged.length / 2));
  const secondHalf = logged.slice(Math.ceil(logged.length / 2));
  const avgFirst = firstHalf.length
    ? firstHalf.reduce((s, e) => s + e.score, 0) / firstHalf.length
    : null;
  const avgSecond = secondHalf.length
    ? secondHalf.reduce((s, e) => s + e.score, 0) / secondHalf.length
    : null;
  let trendLabel = "Need more check-ins";
  let trendColor = "#9CA3AF";
  if (avgFirst != null && avgSecond != null && logged.length >= 3) {
    const delta = avgSecond - avgFirst;
    if (delta >= 0.4) { trendLabel = "Improving"; trendColor = "#10B981"; }
    else if (delta <= -0.4) { trendLabel = "Declining"; trendColor = "#EF4444"; }
    else { trendLabel = "Steady"; trendColor = "#F59E0B"; }
  } else if (logged.length > 0) {
    trendLabel = "Building history";
    trendColor = theme.color;
  }

  const monthCells = buildMonthMoodGrid(enrichedHistory, monthCursor.year, monthCursor.month);
  const monthStats = monthFeelingStats(monthCells);
  const monthTitle = new Date(monthCursor.year, monthCursor.month, 1)
    .toLocaleDateString([], { month: "long", year: "numeric" });
  const startPad = monthCells[0]?.weekday ?? 0; // Sun=0
  const [selectedDay, setSelectedDay] = useState<{
    date: string; score: number | null; symptom?: string;
  } | null>(null);

  const shiftMonth = (delta: number) => {
    setSelectedDay(null);
    setMonthCursor(prev => {
      const d = new Date(prev.year, prev.month + delta, 1);
      return { year: d.getFullYear(), month: d.getMonth() };
    });
  };

  const moodColor = (score: number) =>
    score >= 4 ? "#10B981" : score === 3 ? "#F59E0B" : "#EF4444";

  const hasAnyHistory = enrichedHistory.length > 0;

  return (
    <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB]">
      <div className="flex items-start justify-between gap-2 mb-2">
        <div>
          <div className="flex items-center gap-2 mb-0.5">
            <Activity size={14} style={{ color: theme.color }} />
            <p className="text-[13px] font-bold text-[#0F172A]">{title}</p>
          </div>
          <p className="text-[11px] text-[#9CA3AF]">Daily logs · weekly trends · monthly history</p>
        </div>
        {currentMood != null && currentMood >= 1 && currentMood <= 5 && (
          <div className="text-right shrink-0">
            <p className="text-[20px] leading-none">{MOOD_EMOJIS[currentMood]}</p>
            <p className="text-[11px] font-bold mt-0.5" style={{ color: theme.color }}>
              {MOOD_LABELS[currentMood]}
            </p>
          </div>
        )}
      </div>

      <div className="flex gap-1 p-1 rounded-xl mb-3" style={{ background: "#F3F4F6" }}>
        {([
          { key: "week" as const, label: "This week" },
          { key: "month" as const, label: "Monthly history" },
        ]).map(t => (
          <button
            key={t.key}
            type="button"
            onClick={() => { setView(t.key); setSelectedDay(null); }}
            className="flex-1 py-1.5 rounded-lg text-[11px] font-bold transition-all"
            style={{
              background: view === t.key ? "white" : "transparent",
              color: view === t.key ? theme.color : "#9CA3AF",
              boxShadow: view === t.key ? "0 1px 2px rgba(0,0,0,0.08)" : "none",
            }}
          >
            {t.label}
          </button>
        ))}
      </div>

      {!hasAnyHistory ? (
        <div className="mt-1 px-3 py-4 rounded-xl text-center" style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}>
          <p className="text-[13px] font-semibold text-[#0F172A] mb-1">No mood logs yet</p>
          <p className="text-[12px] text-[#6B7280]">
            {emptyHint}
          </p>
        </div>
      ) : view === "week" ? (
        <>
          <div className="px-3 py-2.5 rounded-xl flex items-center justify-between"
            style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}>
            <div>
              <p className="text-[11px] font-bold uppercase tracking-wide" style={{ color: theme.color }}>Weekly average</p>
              <p className="text-[20px] font-bold text-[#0F172A] leading-tight">
                {avg != null ? `${avg} / 5` : "—"}
              </p>
            </div>
            <div className="text-right">
              <p className="text-[12px] font-semibold text-[#6B7280]">
                {avg != null ? MOOD_LABELS[Math.round(avg)] : ""}
              </p>
              <div className="flex items-center gap-1 justify-end mt-0.5">
                <TrendingUp size={11} style={{ color: trendColor }} />
                <span className="text-[11px] font-bold" style={{ color: trendColor }}>{trendLabel}</span>
              </div>
            </div>
          </div>

          <div className="flex items-end gap-2 h-24 mt-3 mb-1">
            {series.map((s) => {
              const score = s.score;
              const pct = score != null ? (score / 5) * 100 : 0;
              const isWorst = worst != null && score != null && s.date === worst.date;
              const selected = selectedDay?.date === s.date;
              return (
                <button
                  key={s.date}
                  type="button"
                  onClick={() => setSelectedDay({ date: s.date, score: s.score, symptom: s.symptom })}
                  className="flex-1 flex flex-col items-center gap-1 h-full justify-end"
                  title={
                    score != null
                      ? `${s.day}: ${MOOD_LABELS[score]} (${score}/5)${s.symptom ? ` · ${s.symptom}` : ""}`
                      : `${s.day}: not logged`
                  }
                >
                  <span className="text-[10px] font-bold leading-none" style={{ color: score != null ? moodColor(score) : "#D1D5DB" }}>
                    {score != null ? MOOD_EMOJIS[score] : "·"}
                  </span>
                  <div
                    className="w-full rounded-t-md transition-all"
                    style={{
                      height: score != null ? `${Math.max(12, pct)}%` : "8%",
                      background: score != null
                        ? (isWorst ? "#EF4444" : s.isToday ? theme.color : moodColor(score))
                        : "#E5E7EB",
                      opacity: score == null ? 0.5 : 1,
                      outline: selected ? `2px solid ${theme.color}` : isWorst ? "2px solid #FCA5A5" : undefined,
                      outlineOffset: selected || isWorst ? "1px" : undefined,
                    }}
                  />
                  <span className="text-[9px] font-semibold" style={{
                    color: selected ? theme.color : isWorst ? "#EF4444" : s.isToday ? theme.color : "#9CA3AF",
                  }}>
                    {s.day}
                  </span>
                </button>
              );
            })}
          </div>

          {selectedDay ? (
            <div className="mt-3 px-3 py-3 rounded-xl bg-[#F9FAFB] border border-[#E5E7EB]">
              <p className="text-[11px] font-bold uppercase tracking-wide text-[#9CA3AF] mb-1">Selected day</p>
              <p className="text-[14px] font-bold text-[#0F172A]">{formatMoodDayLabel(selectedDay.date)}</p>
              {selectedDay.score != null ? (
                <>
                  <p className="text-[13px] font-semibold mt-0.5" style={{ color: moodColor(selectedDay.score) }}>
                    {MOOD_EMOJIS[selectedDay.score]} {MOOD_LABELS[selectedDay.score]} ({selectedDay.score}/5)
                  </p>
                  <p className="text-[12px] text-[#6B7280] mt-1">
                    <span className="font-bold text-[#374151]">Symptom: </span>
                    {selectedDay.symptom && selectedDay.symptom !== NONE_SYMPTOM
                      ? selectedDay.symptom
                      : "None logged"}
                  </p>
                </>
              ) : (
                <p className="text-[12px] text-[#9CA3AF] mt-1">No feeling logged this day.</p>
              )}
            </div>
          ) : (
            <p className="text-[11px] text-center text-[#9CA3AF] mt-2">
              Tap a day to see how they felt
            </p>
          )}

          {worst && (
            <div className="mt-3 px-3 py-3 rounded-xl" style={{ background: "#FEF2F2", border: "1px solid #FECACA" }}>
              <p className="text-[11px] font-bold uppercase tracking-wide text-[#B91C1C] mb-1">Worst day this week</p>
              <div className="flex items-start gap-2">
                <span className="text-[22px] leading-none">{MOOD_EMOJIS[worst.score]}</span>
                <div className="flex-1 min-w-0">
                  <p className="text-[14px] font-bold text-[#0F172A]">{worst.label}</p>
                  <p className="text-[12px] font-semibold text-[#B91C1C]">
                    Felt {MOOD_LABELS[worst.score]} ({worst.score}/5)
                  </p>
                  <p className="text-[12px] text-[#7F1D1D] mt-1">
                    <span className="font-bold">Symptom: </span>
                    {worst.symptom && worst.symptom !== NONE_SYMPTOM
                      ? worst.symptom
                      : "No symptom logged for this day"}
                  </p>
                </div>
              </div>
            </div>
          )}

          <div className="mt-3 px-3 py-3 rounded-xl" style={{ background: "#FFF7ED", border: "1px solid #FED7AA" }}>
            <p className="text-[11px] font-bold uppercase tracking-wide text-[#C2410C] mb-1">Symptom patterns</p>
            <p className="text-[12px] text-[#9A3412] mb-2 leading-snug">{symptomAnalysis.insight}</p>
            {symptomAnalysis.patterns.length > 0 ? (
              <div className="flex flex-col gap-1.5">
                {symptomAnalysis.patterns.slice(0, 4).map(p => {
                  const isPattern = p.count >= 2;
                  return (
                    <div
                      key={p.name}
                      className="flex items-center justify-between gap-2 px-2.5 py-2 rounded-lg bg-white border border-[#FFEDD5]"
                    >
                      <div className="min-w-0 flex-1">
                        <p className="text-[13px] font-bold text-[#0F172A] truncate">{p.name}</p>
                        <p className="text-[11px] text-[#9CA3AF]">
                          {p.days.join(" · ")}
                          {isPattern ? " · recurring" : ""}
                        </p>
                      </div>
                      <div className="text-right shrink-0">
                        <p className="text-[12px] font-bold" style={{ color: p.avgScore <= 2.5 ? "#EF4444" : theme.color }}>
                          {p.count}× · avg {p.avgScore}/5
                        </p>
                        {isPattern && (
                          <p className="text-[10px] font-bold text-[#C2410C]">Pattern</p>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : (
              <p className="text-[12px] text-[#9A3412]">
                No symptoms linked yet — choose a symptom when you save your daily feeling on Home.
              </p>
            )}
          </div>

          <div className="flex items-center justify-between mt-3 pt-3 border-t border-[#F3F4F6]">
            <div>
              <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wide">Days logged</p>
              <p className="text-[16px] font-bold text-[#0F172A]">{logged.length}/7</p>
            </div>
            <div className="text-right">
              <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wide">Trend</p>
              <p className="text-[14px] font-bold" style={{ color: trendColor }}>{trendLabel}</p>
            </div>
          </div>
        </>
      ) : (
        <>
          <p className="text-[12px] text-[#6B7280] mb-3">
            Average mood by month (last 6 months).
          </p>
          <div className="flex flex-col gap-2 mb-2">
            {Array.from({ length: 6 }).map((_, idx) => {
              const d = new Date(now.getFullYear(), now.getMonth() - (5 - idx), 1);
              const y = d.getFullYear();
              const m = d.getMonth();
              const label = d.toLocaleDateString([], { month: "short", year: "numeric" });
              const cells = buildMonthMoodGrid(enrichedHistory, y, m);
              const stats = monthFeelingStats(cells);
              const selected = monthCursor.year === y && monthCursor.month === m;
              return (
                <button
                  key={`${y}-${m}`}
                  type="button"
                  onClick={() => {
                    setMonthCursor({ year: y, month: m });
                    setSelectedDay(null);
                  }}
                  className="w-full flex items-center justify-between px-3 py-2.5 rounded-xl border transition-all text-left"
                  style={{
                    background: selected ? theme.lightBg : "white",
                    borderColor: selected ? theme.color : "#E5E7EB",
                  }}
                >
                  <div>
                    <p className="text-[14px] font-bold text-[#0F172A]">{label}</p>
                    <p className="text-[11px] text-[#9CA3AF]">
                      {stats.loggedCount} day{stats.loggedCount === 1 ? "" : "s"} logged
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-[16px] font-bold" style={{ color: stats.avg != null ? moodColor(Math.round(stats.avg)) : "#9CA3AF" }}>
                      {stats.avg != null ? `${stats.avg}/5` : "—"}
                    </p>
                    <p className="text-[11px] font-semibold text-[#6B7280]">
                      {stats.avg != null ? MOOD_LABELS[Math.round(stats.avg)] : "No logs"}
                    </p>
                  </div>
                </button>
              );
            })}
          </div>
          {monthStats.loggedCount > 0 && (
            <div className="px-3 py-2.5 rounded-xl"
              style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}>
              <p className="text-[11px] font-bold uppercase tracking-wide" style={{ color: theme.color }}>
                {monthTitle} average: {monthStats.avg != null ? `${monthStats.avg}/5` : "—"}
              </p>
              {monthStats.worst && (
                <p className="text-[11px] font-semibold text-[#EF4444] mt-1">
                  Lowest day: {monthStats.worst.day} · {MOOD_EMOJIS[monthStats.worst.score]}
                </p>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
}

// ── SOS overlay ────────────────────────────────────────────────────────────────

function SOSOverlay({ onClose }: { onClose: () => void }) {
  const [countdown, setCountdown] = useState<number | null>(null);
  useEffect(() => {
    if (countdown === null) return;
    if (countdown <= 0) { onClose(); return; }
    const t = setTimeout(() => setCountdown(countdown - 1), 1000);
    return () => clearTimeout(t);
  }, [countdown, onClose]);

  return (
    <div className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-[#7F1D1D] px-6 gap-6">
      <div className="text-center">
        <p className="text-white/70 text-[13px] font-semibold uppercase tracking-wider mb-2">Emergency SOS</p>
        <p className="text-white text-[16px] leading-relaxed">Pressing the button below will alert your emergency contacts and care team.</p>
      </div>

      {countdown !== null ? (
        <div className="flex flex-col items-center gap-3">
          <div className="w-28 h-28 rounded-full border-4 border-white flex items-center justify-center">
            <span className="text-[40px] font-bold text-white">{countdown}</span>
          </div>
          <p className="text-white/80 text-[14px]">Calling emergency services...</p>
          <button onClick={() => setCountdown(null)} className="px-6 py-3 rounded-2xl bg-white/20 text-white font-bold border border-white/30">
            Cancel
          </button>
        </div>
      ) : (
        <>
          <button
            onPointerDown={() => setCountdown(5)}
            className="w-36 h-36 rounded-full flex flex-col items-center justify-center gap-2 shadow-2xl active:scale-95 transition-transform"
            style={{ background: "#EF4444", boxShadow: "0 0 0 12px rgba(239,68,68,0.25)" }}>
            <Phone size={40} className="text-white" />
            <span className="text-white font-bold text-[13px]">Hold to call</span>
          </button>

          <div className="flex flex-col gap-2 w-full">
            {[
              { icon: <MessageCircle size={16} />, label: "Text emergency contacts" },
              { icon: <MapPin size={16} />, label: "Share my location" },
            ].map(a => (
              <button key={a.label} className="w-full flex items-center gap-3 px-4 py-3 rounded-2xl bg-white/15 text-white text-[14px] font-semibold border border-white/20">
                {a.icon} {a.label}
              </button>
            ))}
          </div>

          <button onClick={onClose} className="mt-2 flex items-center gap-2 text-white/70 text-[14px] font-semibold">
            <X size={16} /> Dismiss
          </button>
        </>
      )}
    </div>
  );
}

// ── Menu bottom-sheet drawer ───────────────────────────────────────────────────

const MENU_ITEMS = [
  { icon: <FileText size={18} />, label: "Invoice Assistant",    category: "Tools" },
  { icon: <Activity size={18} />, label: "Notetaker Assistant",  category: "Tools" },
  { icon: <Mic size={18} />,      label: "Voice Commands",       category: "Tools" },
  { icon: <Calendar size={18} />, label: "Calendar Assistant",   category: "Tools" },
  { icon: <Pill size={18} />,     label: "Medication Tracker",   category: "Health" },
  { icon: <HeartPulse size={18} />, label: "Wellness Check",     category: "Health" },
  { icon: <Stethoscope size={18} />, label: "Virtual Check-In",  category: "Health" },
  { icon: <Star size={18} />,     label: "Gamification",         category: "Community" },
  { icon: <Users size={18} />,    label: "Social Feed",          category: "Community" },
  { icon: <Shield size={18} />,   label: "Fall Detection",       category: "Safety" },
  { icon: <AlertTriangle size={18} />, label: "SOS Emergency",   category: "Safety" },
  { icon: <LayoutGrid size={18} />, label: "Smart Devices",      category: "Integrations" },
  { icon: <Settings size={18} />, label: "Settings",             category: "Account" },
];

function MenuDrawer({ theme, onClose, onSOS }: { theme: ModeTheme; onClose: () => void; onSOS: () => void }) {
  const categories = Array.from(new Set(MENU_ITEMS.map(m => m.category)));

  return (
    <div className="absolute inset-0 z-50 flex flex-col">
      {/* Backdrop */}
      <div className="flex-1 bg-black/40" onClick={onClose} />
      {/* Sheet */}
      <div className="bg-white rounded-t-3xl overflow-hidden flex flex-col" style={{ maxHeight: "78%" }}>
        <div className="flex items-center justify-between px-5 pt-4 pb-3 border-b border-[#F3F4F6]">
          <p className="text-[16px] font-bold text-[#0F172A]">Menu</p>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center bg-[#F3F4F6]">
            <X size={16} className="text-[#6B7280]" />
          </button>
        </div>
        <div className="overflow-y-auto flex-1 pb-4">
          {categories.map(cat => (
            <div key={cat}>
              <p className="text-[11px] font-bold uppercase tracking-wider text-[#9CA3AF] px-5 pt-4 pb-2">{cat}</p>
              {MENU_ITEMS.filter(m => m.category === cat).map(item => (
                <button
                  key={item.label}
                  onClick={item.label === "SOS Emergency" ? onSOS : onClose}
                  className="w-full flex items-center gap-3 px-5 py-3 hover:bg-[#F9FAFB] transition-colors text-left"
                  style={{ color: item.label === "SOS Emergency" ? "#EF4444" : "#0F172A" }}
                >
                  <div className="w-8 h-8 rounded-xl flex items-center justify-center shrink-0"
                    style={{ background: item.label === "SOS Emergency" ? "#FEE2E2" : theme.lightBg, color: item.label === "SOS Emergency" ? "#EF4444" : theme.color }}>
                    {item.icon}
                  </div>
                  <span className="text-[14px] font-semibold">{item.label}</span>
                </button>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ── Role-aware bottom nav ──────────────────────────────────────────────────────

function RoleBottomNav({
  role, tab, onTab, color, large, onMenu,
}: {
  role: Role; tab: Tab; onTab: (t: Tab) => void; color: string; large: boolean;
  onMenu: () => void;
}) {
  const patientItems: { key: Tab; icon: React.ReactNode; label: string }[] = [
    { key: "home",     icon: <Home size={large ? 22 : 19} />,          label: "Home"     },
    { key: "symptoms", icon: <HeartPulse size={large ? 22 : 19} />,    label: "Symptoms" },
    { key: "checkin",  icon: <Stethoscope size={large ? 22 : 19} />,   label: "Check-In" },
    { key: "messages", icon: <MessageCircle size={large ? 22 : 19} />, label: "Messages" },
  ];
  const caregiverItems: { key: Tab; icon: React.ReactNode; label: string }[] = [
    { key: "home",     icon: <Home size={large ? 22 : 19} />,          label: "Home"     },
    { key: "patients", icon: <Users size={large ? 22 : 19} />,         label: "Patients" },
    { key: "analytics",icon: <BarChart2 size={large ? 22 : 19} />,     label: "Analytics"},
    { key: "schedule", icon: <Calendar size={large ? 22 : 19} />,      label: "Schedule" },
    { key: "messages", icon: <MessageCircle size={large ? 22 : 19} />, label: "Messages" },
  ];
  const items = role === "patient" ? patientItems : caregiverItems;

  return (
    <div className="flex bg-white px-1 py-1">
      {items.map(it => (
        <button
          key={it.key}
          onClick={() => onTab(it.key)}
          className="flex-1 flex flex-col items-center justify-center gap-0.5 rounded-xl py-2 transition-all duration-150"
          style={{ minHeight: large ? 64 : 54, color: tab === it.key ? color : "#9CA3AF" }}
        >
          {it.icon}
          <span className="text-[9px] font-semibold">{it.label}</span>
        </button>
      ))}
      {/* Menu button */}
      <button
        onClick={onMenu}
        className="flex-1 flex flex-col items-center justify-center gap-0.5 rounded-xl py-2 transition-all duration-150"
        style={{ minHeight: large ? 64 : 54, color: "#9CA3AF" }}
      >
        <MenuIcon size={large ? 22 : 19} />
        <span className="text-[9px] font-semibold">Menu</span>
      </button>
    </div>
  );
}

// ── New hero landing page ──────────────────────────────────────────────────────

function HeroLanding({
  onCreateProfile, onSignIn, hasSavedProfile, savedName,
}: {
  onCreateProfile: (preferredRole?: Role) => void;
  onSignIn: (preferredRole?: Role) => void;
  hasSavedProfile?: boolean; savedName?: string;
}) {
  const [createRole, setCreateRole] = useState<Role>("patient");

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-8 overflow-y-auto"
      style={{ background: "linear-gradient(160deg, #003B4D 0%, #005F7A 50%, #008DA8 100%)", paddingTop: "env(safe-area-inset-top, 16px)", paddingBottom: "env(safe-area-inset-bottom, 16px)" }}>
      <div className="w-full max-w-[390px] sm:max-w-[520px] lg:max-w-[640px]">
        {/* Brand mark */}
        <div className="flex flex-col items-center mb-10 sm:mb-12">
          <div className="w-20 h-20 sm:w-24 sm:h-24 rounded-3xl flex items-center justify-center mb-5 shadow-2xl"
            style={{ background: "rgba(255,255,255,0.15)", border: "1.5px solid rgba(255,255,255,0.3)" }}>
            <HeartPulse size={44} className="text-white" />
          </div>
          <h1 className="text-[34px] sm:text-[44px] lg:text-[52px] font-bold text-white tracking-tight">CareConnect</h1>
          <p className="text-white/70 text-[15px] sm:text-[17px] mt-1.5 text-center leading-relaxed max-w-[28rem]">
            {hasSavedProfile
              ? <>Welcome back{savedName ? `, ${savedName.split(" ")[0]}` : ""}.<br />Your profile is saved on this device.</>
              : <>Connecting patients and caregivers<br />for better health outcomes</>}
          </p>
        </div>

        {/* Value props */}
        <div className="flex flex-col gap-3 mb-8">
          {[
            { icon: "🛡️", text: "Secure health profile, always yours" },
            { icon: "🤝", text: "Share only what you choose with caregivers" },
            { icon: "💊", text: "Medications, check-ins, and more in one place" },
          ].map(item => (
            <div key={item.text} className="flex items-center gap-3 px-4 py-3 rounded-2xl"
              style={{ background: "rgba(255,255,255,0.1)" }}>
              <span className="text-[20px]">{item.icon}</span>
              <p className="text-white/90 text-[14px] font-medium">{item.text}</p>
            </div>
          ))}
        </div>

        {/* Role picker for new profiles / login */}
        <div className="mb-5">
          <p className="text-white/70 text-[12px] font-bold uppercase tracking-wider mb-2 text-center">I am a…</p>
          <div className="grid grid-cols-2 gap-2">
            {([
              { key: "patient" as Role, label: "Patient / User", icon: "👤" },
              { key: "caregiver" as Role, label: "Caregiver", icon: "🏥" },
            ]).map(opt => (
              <button key={opt.key} type="button" onClick={() => setCreateRole(opt.key)}
                className="py-3 px-2 rounded-2xl text-[13px] font-bold transition-all border-2"
                style={{
                  background: createRole === opt.key ? "white" : "rgba(255,255,255,0.08)",
                  color: createRole === opt.key ? "#003B4D" : "white",
                  borderColor: createRole === opt.key ? "white" : "rgba(255,255,255,0.25)",
                }}>
                {opt.icon} {opt.label}
              </button>
            ))}
          </div>
        </div>

        {/* CTAs — returning users see Log in first */}
        <div className="flex flex-col gap-3">
          {hasSavedProfile ? (
            <>
              <button
                onClick={() => onSignIn(createRole)}
                className="w-full py-4 rounded-2xl text-[16px] font-bold text-[#003B4D] transition-all hover:opacity-90 active:scale-[0.98]"
                style={{ background: "white", boxShadow: "0 8px 32px rgba(0,0,0,0.2)" }}>
                Log in as {createRole === "caregiver" ? "Caregiver" : "Patient"}
              </button>
              <button
                onClick={() => onCreateProfile(createRole)}
                className="w-full py-4 rounded-2xl text-[15px] font-semibold text-white border-2 transition-all hover:bg-white/10"
                style={{ borderColor: "rgba(255,255,255,0.4)" }}>
                Create a new {createRole === "caregiver" ? "caregiver" : "patient"} profile
              </button>
            </>
          ) : (
            <>
              <button
                onClick={() => onCreateProfile(createRole)}
                className="w-full py-4 rounded-2xl text-[16px] font-bold text-[#003B4D] transition-all hover:opacity-90 active:scale-[0.98]"
                style={{ background: "white", boxShadow: "0 8px 32px rgba(0,0,0,0.2)" }}>
                Create {createRole === "caregiver" ? "caregiver" : "patient"} profile
              </button>
              <button
                onClick={() => onSignIn(createRole)}
                className="w-full py-4 rounded-2xl text-[15px] font-semibold text-white border-2 transition-all hover:bg-white/10"
                style={{ borderColor: "rgba(255,255,255,0.4)" }}>
                Log in as {createRole === "caregiver" ? "Caregiver" : "Patient"}
              </button>
            </>
          )}
        </div>

        <p className="text-center text-white/40 text-[12px] mt-8">
          HIPAA-compliant · End-to-end encrypted
        </p>
      </div>
    </div>
  );
}

// ── Profile creation wizard ────────────────────────────────────────────────────

interface WizardProfile {
  name: string; email: string; password: string; pin: string; colorSeq: string[];
  authMethods: Record<SignInMethod, boolean>;
  role: Role; dob: string;
  address: string; organization: string; provider: string; emergencyContact: string;
  conditions: string; meds: string; allergies: string;
  accessibilityMode: AppMode | null;
  enabledFeatures: FeatureId[];
  caregiverPersonaId?: string;
  /** Caregiver must confirm which Patient/User they care for */
  linkedPatientName?: string;
  linkedPatientDob?: string;
  inviteCode?: string;
  /** Caregiver’s relation to the Patient/User */
  caregiverRelation?: string;
}

// ── Reusable form field — defined OUTSIDE wizard so its reference is stable ────
// (defining it inside would create a new component type on every render and
//  unmount the <input>, killing focus after every keystroke)

function WizardField({
  label, value, onChange, placeholder, type = "text",
}: {
  label: string; value: string; onChange: (v: string) => void;
  placeholder?: string; type?: string;
}) {
  const { isListening, voiceError, toggle } = useVoiceDictation(text =>
    onChange(value.trim() ? `${value.trim()} ${text}` : text)
  );
  const isEmail = /email/i.test(label) || type === "email";
  const allowVoice = type === "text" && !isEmail;
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between">
        <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">{label}</label>
        {allowVoice && <MicButton isListening={isListening} onClick={toggle} />}
      </div>
      <input
        type={isEmail ? "text" : type}
        inputMode={isEmail ? "email" : undefined}
        autoComplete={isEmail ? "email" : type === "password" ? "new-password" : "off"}
        autoCapitalize={isEmail ? "none" : undefined}
        autoCorrect={isEmail ? "off" : undefined}
        spellCheck={isEmail ? false : undefined}
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={allowVoice && isListening ? "Listening — speak now…" : placeholder}
        className="w-full border rounded-xl px-4 py-3.5 text-[15px] outline-none bg-white"
        style={{
          WebkitAppearance: "none", fontSize: 16 /* prevents iOS zoom */,
          borderColor: isListening ? "#EF4444" : "#E5E7EB",
          background: isListening ? "#FEF2F2" : "white",
        }}
      />
      {voiceError && <p className="text-[11px] font-semibold text-[#EF4444]">{voiceError}</p>}
    </div>
  );
}

function ProfileWizard({
  onComplete, onBack, initialRole = "patient", knownPatientName = "", knownPatientDob = "",
}: {
  onComplete: (profile: WizardProfile) => void;
  onBack?: () => void;
  initialRole?: Role;
  /** Active patient profile name — used to help caregivers confirm the right person */
  knownPatientName?: string;
  /** Active patient DOB (MM/DD/YYYY) — verified during caregiver confirmation */
  knownPatientDob?: string;
}) {
  const [step, setStep] = useState(1);
  const [data, setData] = useState<WizardProfile>({
    name: "", email: "", password: "", pin: "", colorSeq: [],
    authMethods: { pin: true, password: true, color: true },
    role: initialRole, dob: "", address: "", organization: "",
    provider: "", emergencyContact: "", conditions: "", meds: "", allergies: "",
    accessibilityMode: null, enabledFeatures: [...DEFAULT_PATIENT_FEATURES],
    caregiverPersonaId: "cg1",
    linkedPatientName: "",
    linkedPatientDob: "",
    inviteCode: "",
    caregiverRelation: "",
  });
  const [inviteLookupMsg, setInviteLookupMsg] = useState<string | null>(null);
  const set = (k: keyof WizardProfile, v: WizardProfile[typeof k]) => setData(d => ({ ...d, [k]: v }));

  const RELATION_OPTIONS = [
    "Spouse / Partner", "Child", "Parent", "Sibling", "Friend",
    "Care Coordinator", "Nurse", "Primary Care Physician", "Other",
  ];

  const totalSteps = data.role === "patient" ? 5 : 3;
  const progress = (step / totalSteps) * 100;

  const stepTitles = data.role === "patient"
    ? ["Account & login", "Personal & care details", "Health baseline", "Feature setup", "All set!"]
    : ["Account & login", "Caregiver details", "All set!"];

  const applyInviteInput = (raw: string) => {
    set("inviteCode", raw);
    const parsed = parseInviteFromUrl(raw);
    if (!parsed) {
      setInviteLookupMsg(raw.trim() ? "Enter a CareConnect invite code or paste the full invite link." : null);
      return;
    }
    set("inviteCode", parsed.code);
    if (parsed.patientName) {
      set("linkedPatientName", parsed.patientName);
      setInviteLookupMsg(`Invite linked to patient: ${parsed.patientName}`);
    } else {
      setInviteLookupMsg("Invite code accepted. Enter the Patient/User’s full name to confirm.");
    }
  };

  const toggleFeature = (id: FeatureId) => {
    const cur = data.enabledFeatures;
    set("enabledFeatures", cur.includes(id) ? cur.filter(f => f !== id) : [...cur, id]);
  };

  const toggleAuthMethod = (method: SignInMethod) => {
    setData(d => {
      const nextOn = !d.authMethods[method];
      return {
        ...d,
        authMethods: { ...d.authMethods, [method]: nextOn },
        password: method === "password" && !nextOn ? "" : d.password,
        pin: method === "pin" && !nextOn ? "" : d.pin,
        colorSeq: method === "color" && !nextOn ? [] : d.colorSeq,
      };
    });
  };

  const pressWizardPin = (d: string) => {
    if (!data.authMethods.pin) return;
    if (data.pin.length >= 4) return;
    set("pin", data.pin + d);
  };
  const deleteWizardPin = () => set("pin", data.pin.slice(0, -1));

  const tapWizardColor = (hex: string) => {
    if (!data.authMethods.color) return;
    if (data.colorSeq.includes(hex)) {
      set("colorSeq", data.colorSeq.filter(c => c !== hex));
      return;
    }
    if (data.colorSeq.length >= 3) return;
    set("colorSeq", [...data.colorSeq, hex]);
  };

  const renderStep = () => {
    if (step === 1) return (
      <div className="flex flex-col gap-4">
        <WizardField label="Full name" value={data.name} onChange={v => set("name", v)} placeholder="Your name" />
        <WizardField label="Email" value={data.email} onChange={v => set("email", v)} placeholder="you@email.com" type="text" />
        <div className="flex flex-col gap-1.5">
          <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">I am a…</label>
          <div className="grid grid-cols-2 gap-2">
            {(["patient", "caregiver"] as Role[]).map(r => (
              <button key={r} type="button" onClick={() => set("role", r)}
                className="py-3 rounded-xl text-[14px] font-semibold border-2 capitalize transition-all"
                style={{
                  borderColor: data.role === r ? "#00A7C8" : "#E5E7EB",
                  background: data.role === r ? "#E0F7FA" : "white",
                  color: data.role === r ? "#00A7C8" : "#6B7280",
                }}>
                {r === "patient" ? "👤 Patient" : "🏥 Caregiver"}
              </button>
            ))}
          </div>
        </div>

        <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB] flex flex-col gap-4">
          <div>
            <p className="text-[13px] font-bold text-[#0F172A]">Sign-in methods</p>
            <p className="text-[12px] text-[#6B7280] mt-0.5">
              Choose one or more ways to sign in. You can turn each method on or off.
            </p>
          </div>

          <div className="flex flex-wrap gap-2">
            {([
              { key: "password" as SignInMethod, label: "Password" },
              { key: "pin" as SignInMethod, label: "PIN" },
              { key: "color" as SignInMethod, label: "Colour" },
            ]).map(m => (
              <button key={m.key} type="button" onClick={() => toggleAuthMethod(m.key)}
                className="px-3 py-1.5 rounded-full text-[12px] font-bold border transition-all"
                style={{
                  background: data.authMethods[m.key] ? "#E0F7FA" : "#F9FAFB",
                  borderColor: data.authMethods[m.key] ? "#00A7C8" : "#E5E7EB",
                  color: data.authMethods[m.key] ? "#007A94" : "#9CA3AF",
                }}>
                {data.authMethods[m.key] ? "✓ " : ""}{m.label}
              </button>
            ))}
          </div>

          {data.authMethods.password && (
            <div className="flex flex-col gap-2">
              <WizardField label="Password" value={data.password} onChange={v => set("password", v)} placeholder="Create a password (min 4 characters)" type="password" />
              {data.password && (
                <button type="button" onClick={() => set("password", "")}
                  className="text-[12px] font-semibold text-[#9CA3AF] underline underline-offset-2 self-center">
                  Clear password
                </button>
              )}
            </div>
          )}

          {data.authMethods.pin && <div className="flex flex-col gap-2">
            <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">4-digit PIN</label>
            <div className="flex gap-3 justify-center mb-1">
              {[0, 1, 2, 3].map(i => (
                <div key={i} className="w-3.5 h-3.5 rounded-full border-2"
                  style={{
                    borderColor: "#00A7C8",
                    background: i < data.pin.length ? "#00A7C8" : "transparent",
                  }} />
              ))}
            </div>
            <div className="grid grid-cols-3 gap-2">
              {["1","2","3","4","5","6","7","8","9"].map(d => (
                <button key={d} type="button" onClick={() => pressWizardPin(d)}
                  className="py-3 rounded-xl text-[18px] font-semibold bg-[#F9FAFB] border border-[#E5E7EB]">
                  {d}
                </button>
              ))}
              <button type="button" onClick={deleteWizardPin}
                className="py-3 rounded-xl text-[16px] bg-[#F9FAFB] border border-[#E5E7EB] text-[#6B7280]">⌫</button>
              <button type="button" onClick={() => pressWizardPin("0")}
                className="py-3 rounded-xl text-[18px] font-semibold bg-[#F9FAFB] border border-[#E5E7EB]">0</button>
              <button type="button" onClick={() => set("pin", "")}
                className="py-3 rounded-xl text-[11px] font-bold bg-[#F9FAFB] border border-[#E5E7EB] text-[#9CA3AF]">Clear</button>
            </div>
          </div>}

          {data.authMethods.color && <div className="flex flex-col gap-2">
            <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">Colour sequence (pick 3)</label>
            <div className="flex gap-2 justify-center mb-1">
              {[0, 1, 2].map(i => (
                <div key={i} className="w-10 h-10 rounded-full border-2 flex items-center justify-center"
                  style={{
                    borderStyle: data.colorSeq[i] ? "solid" : "dashed",
                    borderColor: data.colorSeq[i] ?? "#CBD5E1",
                    background: data.colorSeq[i] ?? "transparent",
                  }}>
                  {!data.colorSeq[i] && <span className="text-[12px] font-bold text-[#CBD5E1]">{i + 1}</span>}
                </div>
              ))}
            </div>
            <div className="grid grid-cols-3 gap-2">
              {AUTH_COLORS.map(col => {
                const picked = data.colorSeq.includes(col.hex);
                return (
                  <button key={col.hex} type="button" onClick={() => tapWizardColor(col.hex)}
                    className="flex flex-col items-center gap-1.5 py-2.5 rounded-xl border-2 transition-all"
                    style={{
                      borderColor: picked ? col.hex : "#E5E7EB",
                      background: picked ? col.hex + "22" : "white",
                      opacity: data.colorSeq.length >= 3 && !picked ? 0.5 : 1,
                    }}>
                    <div className="w-8 h-8 rounded-full" style={{ background: col.hex }} />
                    <span className="text-[10px] font-bold text-[#595959] uppercase">{col.label}</span>
                  </button>
                );
              })}
            </div>
            {data.colorSeq.length > 0 && (
              <button type="button" onClick={() => set("colorSeq", [])}
                className="text-[12px] font-semibold text-[#9CA3AF] underline underline-offset-2 self-center">
                Clear colour sequence
              </button>
            )}
          </div>}
        </div>

        {data.role === "caregiver" && (
          <div className="rounded-2xl p-4 bg-white border border-[#E5E7EB] flex flex-col gap-3">
            <div>
              <p className="text-[13px] font-bold text-[#0F172A]">Confirm the Patient / User</p>
              <p className="text-[12px] text-[#6B7280] mt-0.5">
                Required verification. Paste their invite link or QR code, then enter their full name and date of birth, and your relation to them. If they did not already add you in Care Circle, they must approve your request.
              </p>
            </div>
            <WizardField
              label="Invite code or link"
              value={data.inviteCode || ""}
              onChange={applyInviteInput}
              placeholder="Paste invite link or cc-…"
            />
            {inviteLookupMsg && (
              <p className="text-[12px] font-semibold text-[#007A94] -mt-1">{inviteLookupMsg}</p>
            )}
            <WizardField
              label="Patient / User full name"
              value={data.linkedPatientName || ""}
              onChange={v => set("linkedPatientName", v)}
              placeholder="Exact name on their CareConnect profile"
            />
            <WizardField
              label="Patient date of birth"
              value={data.linkedPatientDob || ""}
              onChange={v => set("linkedPatientDob", v)}
              placeholder="MM/DD/YYYY"
            />
            {!!data.linkedPatientDob?.trim() && !normalizeDob(data.linkedPatientDob) && (
              <p className="text-[12px] font-semibold text-[#B45309] -mt-1">
                Enter date of birth as MM/DD/YYYY.
              </p>
            )}
            {!!data.linkedPatientDob?.trim() && !!knownPatientDob?.trim() && normalizeDob(data.linkedPatientDob) && !dobsMatch(data.linkedPatientDob, knownPatientDob) && (
              <p className="text-[12px] font-semibold text-[#B45309] -mt-1">
                Date of birth does not match the Patient/User profile on file.
              </p>
            )}
            {!!data.linkedPatientName?.trim() && knownPatientName && knownPatientName !== "Your Name" && !namesMatch(data.linkedPatientName, knownPatientName) && (
              <p className="text-[12px] font-semibold text-[#B45309]">
                Name does not match the Patient/User profile on file for access to be granted.
              </p>
            )}

            <div className="flex flex-col gap-2">
              <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">
                Your relation to this Patient / User
              </label>
              <div className="flex flex-wrap gap-2">
                {RELATION_OPTIONS.map(rel => (
                  <button
                    key={rel}
                    type="button"
                    onClick={() => set("caregiverRelation", rel === "Other" ? "" : rel)}
                    className="px-3 py-1.5 rounded-full text-[12px] font-bold border transition-all"
                    style={{
                      background: data.caregiverRelation === rel || (rel === "Other" && data.caregiverRelation && !RELATION_OPTIONS.slice(0, -1).includes(data.caregiverRelation))
                        ? "#E0F7FA" : "#F9FAFB",
                      borderColor: data.caregiverRelation === rel || (rel === "Other" && data.caregiverRelation && !RELATION_OPTIONS.slice(0, -1).includes(data.caregiverRelation))
                        ? "#00A7C8" : "#E5E7EB",
                      color: data.caregiverRelation === rel || (rel === "Other" && data.caregiverRelation && !RELATION_OPTIONS.slice(0, -1).includes(data.caregiverRelation))
                        ? "#007A94" : "#6B7280",
                    }}>
                    {rel}
                  </button>
                ))}
              </div>
              <WizardField
                label="Relation (confirm or type)"
                value={data.caregiverRelation || ""}
                onChange={v => set("caregiverRelation", v)}
                placeholder="e.g. Daughter, Care Coordinator, Neighbor"
              />
            </div>
          </div>
        )}
      </div>
    );

    if (step === 2 && data.role === "patient") return (
      <div className="flex flex-col gap-4">
        <WizardField label="Date of birth" value={data.dob} onChange={v => set("dob", v)} placeholder="MM / DD / YYYY" />
        <WizardField label="Home address" value={data.address} onChange={v => set("address", v)} placeholder="Start typing your address…" />
        <WizardField label="Primary care provider" value={data.provider} onChange={v => set("provider", v)} placeholder="Dr. Name · Clinic" />
        <WizardField label="Emergency contact" value={data.emergencyContact} onChange={v => set("emergencyContact", v)} placeholder="Name · Phone" />
      </div>
    );

    if (step === 2 && data.role === "caregiver") {
      const isClinical = isProfessionalCaregiverPersona(
        CAREGIVER_PERSONAS.find(p => p.id === data.caregiverPersonaId)?.persona,
      );
      return (
      <div className="flex flex-col gap-4">
        <div className="flex flex-col gap-2">
          <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">Caregiver account type</label>
          <p className="text-[12px] text-[#6B7280]">
            Pick your account. Your relationship to the patient (set on the previous step) is what patients and the app will show — for example Daughter or Primary Care Physician.
          </p>
          {CAREGIVER_PERSONAS.map(p => (
            <button key={p.id} type="button" onClick={() => {
              set("caregiverPersonaId", p.id);
              set("provider", p.label);
              if (p.persona === "primary_physician") {
                set("caregiverRelation", "Primary Care Physician");
              }
            }}
              className="text-left px-3 py-3 rounded-xl border-2 transition-all"
              style={{
                borderColor: data.caregiverPersonaId === p.id ? "#00A7C8" : "#E5E7EB",
                background: data.caregiverPersonaId === p.id ? "#E0F7FA" : "white",
              }}>
              <p className="text-[14px] font-bold text-[#0F172A]">{p.label}</p>
              <p className="text-[12px] text-[#6B7280]">{p.description}</p>
              {data.caregiverPersonaId === p.id && data.caregiverRelation?.trim() && (
                <p className="text-[12px] font-semibold mt-1" style={{ color: "#007A94" }}>
                  Showing as: {data.name.trim() || "Your name"} · {data.caregiverRelation.trim()}
                </p>
              )}
            </button>
          ))}
        </div>
        {isClinical && (
          <>
            <p className="text-[12px] font-bold text-[#374151] uppercase tracking-wider">Professional details</p>
            <p className="text-[12px] text-[#6B7280] -mt-2">
              For clinical caregivers. You enter your real name; relationship defaults to Primary Care Physician.
            </p>
            <WizardField
              label="Agency / Organization (optional)"
              value={data.organization}
              onChange={v => set("organization", v)}
              placeholder="Care agency, clinic, or practice name"
            />
            <WizardField
              label="License / Credentials (optional)"
              value={data.conditions}
              onChange={v => set("conditions", v)}
              placeholder="e.g. RN, LPN, MD"
            />
            <WizardField
              label="Phone number"
              value={data.emergencyContact}
              onChange={v => set("emergencyContact", v)}
              placeholder="(555) 000-0000"
            />
          </>
        )}
      </div>
      );
    }

    if (step === 3 && data.role === "patient") return (
      <div className="flex flex-col gap-4">
        <p className="text-[13px] text-[#6B7280] leading-relaxed">
          This helps your care team. All fields are optional — you can fill these in later from your profile.
        </p>
        <div className="flex flex-col gap-1.5">
        <VoiceField label="Health conditions" value={data.conditions} onChange={v => set("conditions", v)}
          placeholder="e.g. Hypertension, Type 2 diabetes…" multiline />
        </div>
        <WizardField label="Current medications" value={data.meds} onChange={v => set("meds", v)} placeholder="e.g. Lisinopril 10mg, Metformin…" />
        <WizardField label="Known allergies" value={data.allergies} onChange={v => set("allergies", v)} placeholder="e.g. Penicillin, Peanuts…" />
        <button onClick={() => setStep(s => s + 1)} className="text-[13px] font-semibold text-[#9CA3AF] text-center underline underline-offset-2">
          Skip for now
        </button>
      </div>
    );

    if (step === 3 && data.role === "caregiver") {
      // caregiver step 3 = confirmation
      return renderConfirmation();
    }

    if (step === 4 && data.role === "patient") return (
      <div className="flex flex-col gap-4">
        <p className="text-[13px] text-[#6B7280]">Choose what you want in your app. You can always change these in your profile.</p>

        {/* Accessibility mode */}
        <div>
          <p className="text-[12px] font-bold text-[#374151] uppercase tracking-wider mb-2">Accessibility mode</p>
          <div className="grid grid-cols-2 gap-2">
            {[
              { key: "stml" as AppMode, label: "Memory aid", icon: "🧠", color: "#7C3AED" },
              { key: "dyslexia" as AppMode, label: "Dyslexia", icon: "📖", color: "#0E7E57" },
              { key: "carpal" as AppMode, label: "Carpal tunnel", icon: "✋", color: "#B45309" },
              { key: "hearing" as AppMode, label: "Hearing", icon: "👂", color: "#0284C7" },
            ].map(m => (
              <button key={m.key} onClick={() => set("accessibilityMode", data.accessibilityMode === m.key ? null : m.key)}
                className="flex items-center gap-2 px-3 py-2.5 rounded-xl border-2 text-left transition-all"
                style={{
                  borderColor: data.accessibilityMode === m.key ? m.color : "#E5E7EB",
                  background: data.accessibilityMode === m.key ? m.color + "18" : "white",
                }}>
                <span className="text-[18px]">{m.icon}</span>
                <span className="text-[13px] font-semibold" style={{ color: data.accessibilityMode === m.key ? m.color : "#374151" }}>{m.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Features by category */}
        {(["health", "safety", "ai", "devices", "social", "documents"] as const).map(cat => {
          const items = FEATURE_DEFS.filter(f => f.category === cat);
          const catLabel: Record<string, string> = { health: "Health", safety: "Safety", ai: "AI & Assistants", devices: "Devices", social: "Social", documents: "Documents & Mail" };
          return (
            <div key={cat}>
              <p className="text-[12px] font-bold text-[#374151] uppercase tracking-wider mb-2">{catLabel[cat]}</p>
              <div className="flex flex-col rounded-2xl overflow-hidden border border-[#E5E7EB] bg-white">
                {items.map((f, i) => (
                  <div key={f.id} className={`flex items-center gap-3 px-4 py-3 ${i > 0 ? "border-t border-[#F3F4F6]" : ""}`}>
                    <span className="text-[20px] w-7 text-center shrink-0">{f.icon}</span>
                    <div className="flex-1 min-w-0">
                      <p className="text-[14px] font-semibold text-[#0F172A]">{f.label}</p>
                      <p className="text-[11px] text-[#9CA3AF] truncate">{f.description}</p>
                    </div>
                    <Switch checked={data.enabledFeatures.includes(f.id)} onChange={() => toggleFeature(f.id)} id={`wiz-${f.id}`} color="#00A7C8" />
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    );

    if (step === 5 || (step === 3 && data.role === "caregiver")) return renderConfirmation();
    return null;
  };

  const renderConfirmation = () => (
    <div className="flex flex-col items-center text-center gap-5 py-4">
      <div className="w-20 h-20 rounded-full flex items-center justify-center" style={{ background: "#D1FAE5" }}>
        <Check size={40} style={{ color: "#10B981" }} />
      </div>
      <div>
        <h2 className="text-[22px] font-bold text-[#0F172A]">
          {data.role === "patient" ? "Your profile is saved!" : "Welcome to CareConnect!"}
        </h2>
        <p className="text-[14px] text-[#6B7280] mt-2 leading-relaxed">
          {data.role === "patient"
            ? "Everything you set up is saved to your profile. You can change features or settings any time from the Profile tab."
            : "You're set up as a caregiver. Patients will invite you to their care circle — you'll see their shared data appear here."}
        </p>
        <div className="w-full rounded-2xl px-4 py-3 text-left bg-[#F0FDFA] border border-[#99F6E4]">
          <p className="text-[12px] font-bold text-[#0F766E] uppercase tracking-wider mb-1">Sign-in ready</p>
          <p className="text-[13px] text-[#115E59]">
            You can sign in with the methods you selected on the Account & Login page.
          </p>
          {data.role === "caregiver" && data.linkedPatientName?.trim() && (
            <p className="text-[13px] text-[#115E59] mt-1">
              Linked Patient/User: <span className="font-bold">{data.linkedPatientName.trim()}</span>
              {data.linkedPatientDob?.trim() && (
                <> · DOB <span className="font-bold">{normalizeDob(data.linkedPatientDob) || data.linkedPatientDob.trim()}</span></>
              )}
              {data.caregiverRelation?.trim() && (
                <> · Relation: <span className="font-bold">{data.caregiverRelation.trim()}</span></>
              )}
              {" "}— you will only see their shared page.
            </p>
          )}
        </div>
      </div>
      {data.role === "patient" && data.enabledFeatures.length > 0 && (
        <div className="w-full px-2 text-left">
          <p className="text-[12px] font-bold text-[#9CA3AF] uppercase tracking-wider mb-2">Features you enabled</p>
          <div className="flex flex-wrap gap-2">
            {data.enabledFeatures.map(id => {
              const f = FEATURE_DEFS.find(d => d.id === id)!;
              return (
                <span key={id} className="text-[12px] font-semibold px-3 py-1 rounded-full bg-[#E0F7FA] text-[#007A94]">
                  {f.icon} {f.label}
                </span>
              );
            })}
          </div>
        </div>
      )}
      <button
        onClick={() => onComplete(data)}
        className="w-full py-4 rounded-2xl text-[16px] font-bold text-white mt-2"
        style={{ background: "#00A7C8" }}>
        Go to my dashboard
      </button>
    </div>
  );

  const selectedAuthCount = Object.values(data.authMethods).filter(Boolean).length;
  const selectedAuthValid =
    (!data.authMethods.password || data.password.trim().length >= 4) &&
    (!data.authMethods.pin || data.pin.length === 4) &&
    (!data.authMethods.color || data.colorSeq.length === 3);
  const caregiverPatientConfirmedOk = data.role !== "caregiver" || (
    caregiverPatientConfirmed(
      data.linkedPatientName,
      knownPatientName,
      data.linkedPatientDob,
      knownPatientDob,
    )
    && !!data.caregiverRelation?.trim()
  );
  const professionalOk = true; // Agency / license optional for clinical caregivers
  const canAdvance = step === 1
    ? data.name.trim().length > 1 && selectedAuthCount > 0 && selectedAuthValid && caregiverPatientConfirmedOk
    : professionalOk;

  return (
    // Full-viewport container — scrolls as a whole page so the keyboard never
    // clips the active input field (no inner scroll containers on this screen)
    <div
      className="min-h-screen bg-[#F9FAFB]"
      style={{
        paddingTop: "env(safe-area-inset-top, 0px)",
        paddingBottom: "env(safe-area-inset-bottom, 0px)",
      }}
    >
      <div className="w-full max-w-[480px] mx-auto px-4 py-6">
        {/* Sticky header + progress — stays at top while content scrolls */}
        <div className="sticky top-0 z-10 bg-[#F9FAFB] pb-4 pt-2">
          <div className="flex items-center gap-3 mb-3">
            {(step === 1 && onBack) || step > 1 ? (
              <button
                type="button"
                onClick={() => {
                  if (step === 1) onBack?.();
                  else setStep(s => s - 1);
                }}
                className="w-9 h-9 rounded-xl flex items-center justify-center shrink-0 bg-white border border-[#E5E7EB] text-[#0F172A] hover:bg-[#F3F4F6] transition-colors"
                aria-label={step === 1 ? "Back to landing page" : "Go to previous step"}>
                <ChevronLeft size={20} />
              </button>
            ) : (
              <div className="w-9 h-9 rounded-xl flex items-center justify-center shrink-0" style={{ background: "#00A7C8" }}>
                <HeartPulse size={18} className="text-white" />
              </div>
            )}
            <div className="flex-1 min-w-0">
              <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wider">Step {step} of {totalSteps}</p>
              <p className="text-[15px] font-bold text-[#0F172A]">{stepTitles[step - 1]}</p>
            </div>
            {step === 1 && onBack && (
              <button
                type="button"
                onClick={onBack}
                className="text-[13px] font-semibold text-[#00A7C8] px-2 py-2 shrink-0">
                Cancel
              </button>
            )}
          </div>
          <div className="h-1.5 bg-[#E5E7EB] rounded-full overflow-hidden">
            <div className="h-full rounded-full transition-all duration-500" style={{ width: `${progress}%`, background: "#00A7C8" }} />
          </div>
        </div>

        {/* Step content — no inner scroll; the page itself scrolls */}
        {renderStep()}

        {/* Footer CTA */}
        {step < totalSteps && (
          <div className="mt-6 pb-4">
            <button
              disabled={!canAdvance}
              onClick={() => setStep(s => s + 1)}
              className="w-full py-4 rounded-2xl text-[16px] font-bold text-white transition-opacity"
              style={{ background: "#00A7C8", opacity: canAdvance ? 1 : 0.4, fontSize: 16 }}>
              {step === totalSteps - 1 ? "Finish setup" : "Continue"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

// ── Feature picker bottom sheet ────────────────────────────────────────────────

function FeaturePickerSheet({
  enabledFeatures, onToggle, onClose, onOpenMail,
}: {
  enabledFeatures: FeatureId[];
  onToggle: (id: FeatureId) => void;
  onClose: () => void;
  onOpenMail?: () => void;
}) {
  const categories: { key: string; label: string; emoji: string }[] = [
    { key: "health",    label: "Health",              emoji: "❤️" },
    { key: "safety",    label: "Safety",               emoji: "🛡️" },
    { key: "ai",        label: "AI & Assistants",      emoji: "🤖" },
    { key: "devices",   label: "Devices",              emoji: "⌚" },
    { key: "social",    label: "Social",               emoji: "👥" },
    { key: "documents", label: "Documents & Mail",     emoji: "📁" },
  ];

  const handleToggle = (id: FeatureId) => {
    const turningOn = !enabledFeatures.includes(id);
    onToggle(id);
    if (turningOn && id === "usps_mail" && onOpenMail) {
      onClose();
      onOpenMail();
    }
  };

  return (
    <div className="absolute inset-0 z-50 flex flex-col">
      <div className="flex-1 bg-black/40" onClick={onClose} />
      <div className="bg-white rounded-t-3xl flex flex-col" style={{ maxHeight: "82%" }}>
        {/* Handle + header */}
        <div className="flex justify-center pt-3 pb-1">
          <div className="w-10 h-1 rounded-full bg-[#E5E7EB]" />
        </div>
        <div className="flex items-center justify-between px-5 py-3 border-b border-[#F3F4F6]">
          <div>
            <p className="text-[17px] font-bold text-[#0F172A]">My Features</p>
            <p className="text-[12px] text-[#9CA3AF]">{enabledFeatures.length} enabled · changes take effect instantly</p>
          </div>
          <button onClick={onClose} className="w-8 h-8 rounded-full flex items-center justify-center bg-[#F3F4F6]">
            <X size={16} className="text-[#6B7280]" />
          </button>
        </div>

        <div className="overflow-y-auto flex-1 pb-6">
          {categories.map(cat => {
            const items = FEATURE_DEFS.filter(f => f.category === cat.key);
            return (
              <div key={cat.key} className="px-4 pt-4">
                <p className="text-[12px] font-bold text-[#9CA3AF] uppercase tracking-wider mb-2">
                  {cat.emoji} {cat.label}
                </p>
                <div className="rounded-2xl overflow-hidden border border-[#E5E7EB] bg-white">
                  {items.map((f, i) => (
                    <div key={f.id} className={`flex items-center gap-3 px-4 py-3.5 ${i > 0 ? "border-t border-[#F3F4F6]" : ""}`}>
                      <span className="text-[22px] w-8 text-center shrink-0">{f.icon}</span>
                      <div className="flex-1 min-w-0">
                        <p className="text-[14px] font-semibold text-[#0F172A]">{f.label}</p>
                        <p className="text-[11px] text-[#9CA3AF] leading-snug mt-0.5">{f.description}</p>
                      </div>
                      <Switch checked={enabledFeatures.includes(f.id)} onChange={() => handleToggle(f.id)} id={`fp-${f.id}`} color="#00A7C8" />
                    </div>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ── Patient profile page ───────────────────────────────────────────────────────

function PatientProfilePage({
  profileName, profileImage, setProfileImage, setProfileName,
  profileEmail, setProfileEmail, profileDob, setProfileDob,
  profileAddress, setProfileAddress, profileProvider, setProfileProvider,
  profileEmergency, setProfileEmergency,
  profileConditions, setProfileConditions,
  profileMeds, setProfileMeds, profileAllergies, setProfileAllergies,
  moodHistory, patientMood,
  mode, setMode, enabledFeatures, onToggleFeature,
  linkedCaregivers, setLinkedCaregivers,
  theme, customSettings, setCustomSettings,
  textSize, setTextSize, highContrast, setHighContrast,
  boldText, setBoldText, colorFilter, setColorFilter,
  reduceMotion, setReduceMotion, autoPlay, setAutoPlay,
  readAloudGlobal, setReadAloudGlobal, focusIndicators, setFocusIndicators,
  tremorMode, setTremorMode, confirmActions, setConfirmActions,
  disability, setDisability,
  vibration, setVibration, visualAlerts, setVisualAlerts,
  simplifiedNav, setSimplifiedNav,
  captions, setCaptions, soundAmplify, setSoundAmplify,
  ttySupport, setTtySupport, hearingAidMode, setHearingAidMode,
  onSignOut,
}: {
  profileName: string; profileImage: string | null;
  setProfileImage: (v: string | null) => void; setProfileName: (v: string) => void;
  profileEmail: string; setProfileEmail: (v: string) => void;
  profileDob: string; setProfileDob: (v: string) => void;
  profileAddress: string; setProfileAddress: (v: string) => void;
  profileProvider: string; setProfileProvider: (v: string) => void;
  profileEmergency: string; setProfileEmergency: (v: string) => void;
  profileConditions: string; setProfileConditions: (v: string) => void;
  profileMeds: string; setProfileMeds: (v: string) => void;
  profileAllergies: string; setProfileAllergies: (v: string) => void;
  moodHistory: MoodEntry[];
  patientMood: number | null;
  mode: AppMode | null; setMode: (m: AppMode) => void;
  enabledFeatures: FeatureId[]; onToggleFeature: (id: FeatureId) => void;
  linkedCaregivers: LinkedCaregiver[]; setLinkedCaregivers: (v: LinkedCaregiver[]) => void;
  theme: ModeTheme;
  customSettings: CustomSettings; setCustomSettings: (s: CustomSettings) => void;
  textSize: 0|1|2; setTextSize: (v: 0|1|2) => void;
  highContrast: boolean; setHighContrast: (v: boolean) => void;
  boldText: boolean; setBoldText: (v: boolean) => void;
  colorFilter: boolean; setColorFilter: (v: boolean) => void;
  reduceMotion: boolean; setReduceMotion: (v: boolean) => void;
  autoPlay: boolean; setAutoPlay: (v: boolean) => void;
  readAloudGlobal: boolean; setReadAloudGlobal: (v: boolean) => void;
  focusIndicators: boolean; setFocusIndicators: (v: boolean) => void;
  tremorMode: boolean; setTremorMode: (v: boolean) => void;
  confirmActions: boolean; setConfirmActions: (v: boolean) => void;
  disability: string; setDisability: (v: string) => void;
  vibration: boolean; setVibration: (v: boolean) => void;
  visualAlerts: boolean; setVisualAlerts: (v: boolean) => void;
  simplifiedNav: boolean; setSimplifiedNav: (v: boolean) => void;
  captions: boolean; setCaptions: (v: boolean) => void;
  soundAmplify: boolean; setSoundAmplify: (v: boolean) => void;
  ttySupport: boolean; setTtySupport: (v: boolean) => void;
  hearingAidMode: boolean; setHearingAidMode: (v: boolean) => void;
  onSignOut: () => void;
}) {
  type ProfileSection = "info" | "features" | "circle" | "settings";
  const [section, setSection] = useState<ProfileSection>("info");
  const [editingCgId, setEditingCgId] = useState<string | null>(null);
  const [cgDraft, setCgDraft] = useState<{
    name: string; relationship: string; email: string; phone: string; status: LinkedCaregiver["status"];
  } | null>(null);
  const [showInvite, setShowInvite] = useState(false);
  const [inviteDraft, setInviteDraft] = useState({ name: "", relationship: "", email: "", phone: "" });
  const [inviteResult, setInviteResult] = useState<{ code: string; url: string } | null>(null);
  const [inviteCopied, setInviteCopied] = useState(false);
  const [cgSavedFlash, setCgSavedFlash] = useState(false);
  const [profileShare, setProfileShare] = useState<{ token: string; url: string } | null>(null);
  const [profileShareCopied, setProfileShareCopied] = useState(false);
  const [shareFeedback, setShareFeedback] = useState<string | null>(null);

  // Draft copy of profile info for edit mode — committed on Save, thrown away on Discard.
  const currentInfo = {
    name: profileName, email: profileEmail, dob: profileDob, address: profileAddress,
    provider: profileProvider, emergency: profileEmergency,
    conditions: profileConditions, meds: profileMeds, allergies: profileAllergies,
  };
  const [editingInfo, setEditingInfo] = useState(false);
  const [draft, setDraft] = useState(currentInfo);
  const [justSaved, setJustSaved] = useState(false);
  const setDraftField = (key: keyof typeof currentInfo) => (v: string) =>
    setDraft(d => ({ ...d, [key]: v }));
  const draftDirty = (Object.keys(currentInfo) as (keyof typeof currentInfo)[])
    .some(k => draft[k] !== currentInfo[k]);

  const startEditing = () => { setDraft(currentInfo); setJustSaved(false); setEditingInfo(true); };
  const discardEdits = () => { setDraft(currentInfo); setEditingInfo(false); };
  const saveEdits = () => {
    setProfileName(draft.name.trim());
    setProfileEmail(draft.email.trim());
    setProfileDob(draft.dob.trim());
    setProfileAddress(draft.address.trim());
    setProfileProvider(draft.provider.trim());
    setProfileEmergency(draft.emergency.trim());
    setProfileConditions(draft.conditions.trim());
    setProfileMeds(draft.meds.trim());
    setProfileAllergies(draft.allergies.trim());
    setEditingInfo(false);
    setJustSaved(true);
    window.setTimeout(() => setJustSaved(false), 2500);
  };


  const tabs: { key: ProfileSection; label: string; icon: string }[] = [
    { key: "info",     label: "My Info",    icon: "👤" },
    { key: "features", label: "Features",   icon: "⚡" },
    { key: "circle",   label: "Care Circle", icon: "🤝" },
    { key: "settings", label: "Settings",   icon: "⚙️" },
  ];

  const toggleGrant = (cgId: string, item: GrantedItem) => {
    setLinkedCaregivers(linkedCaregivers.map(cg => {
      if (cg.id !== cgId) return cg;
      const grants = cg.grants.includes(item)
        ? cg.grants.filter(g => g !== item)
        : [...cg.grants, item];
      // Granting any item also activates a pending Care Circle link
      const status = grants.length > 0 && cg.status === "pending" ? "active" as const : cg.status;
      return { ...cg, grants, status };
    }));
  };

  const startEditCg = (cg: LinkedCaregiver) => {
    setEditingCgId(cg.id);
    setCgDraft({
      name: cg.name,
      relationship: cg.relationship,
      email: cg.email ?? "",
      phone: cg.phone ?? "",
      status: cg.status,
    });
    setCgSavedFlash(false);
  };

  const discardCgEdit = () => {
    setEditingCgId(null);
    setCgDraft(null);
  };

  const saveCgEdit = () => {
    if (!editingCgId || !cgDraft) return;
    const name = cgDraft.name.trim();
    if (!name) return;
    setLinkedCaregivers(linkedCaregivers.map(cg =>
      cg.id !== editingCgId ? cg : {
        ...cg,
        name,
        relationship: cgDraft.relationship.trim() || "Caregiver",
        email: cgDraft.email.trim(),
        phone: cgDraft.phone.trim(),
        status: cgDraft.status,
        initials: makeInitials(name),
      }
    ));
    setEditingCgId(null);
    setCgDraft(null);
    setCgSavedFlash(true);
    window.setTimeout(() => setCgSavedFlash(false), 2200);
  };

  const suspendCg = (cgId: string) => {
    setLinkedCaregivers(linkedCaregivers.map(cg =>
      cg.id !== cgId ? cg : {
        ...cg,
        status: cg.status === "suspended" ? "active" : "suspended",
      }
    ));
  };

  const removeCg = (cgId: string) => {
    if (editingCgId === cgId) discardCgEdit();
    setLinkedCaregivers(linkedCaregivers.filter(cg => cg.id !== cgId));
  };

  const approveCg = (cgId: string) => {
    setLinkedCaregivers(approveCaregiverInCircle(linkedCaregivers, cgId));
  };

  const approveGrantRequests = (cgId: string) => {
    setLinkedCaregivers(linkedCaregivers.map(cg => {
      if (cg.id !== cgId) return cg;
      const requested = cg.pendingGrantRequests ?? [];
      if (!requested.length) return cg;
      return {
        ...cg,
        grants: Array.from(new Set([...cg.grants, ...requested])),
        pendingGrantRequests: [],
        status: cg.status === "pending" ? "active" : cg.status,
      };
    }));
  };

  const dismissGrantRequests = (cgId: string) => {
    setLinkedCaregivers(linkedCaregivers.map(cg =>
      cg.id === cgId ? { ...cg, pendingGrantRequests: [] } : cg
    ));
  };

  const openInvite = () => {
    if (!canAddCaregiver(linkedCaregivers)) return;
    setShowInvite(true);
    setInviteDraft({ name: "", relationship: "", email: "", phone: "" });
    setInviteResult(null);
    setInviteCopied(false);
  };

  const generateInvite = () => {
    const code = `cc-${Date.now().toString(36)}`;
    const url = buildInviteUrl(code, profileName);
    setInviteResult({ code, url });
    setInviteCopied(false);
  };

  const generateProfileShare = () => {
    const token = createProfileShareToken();
    const url = buildProfileShareUrl(token, profileName);
    setProfileShare({ token, url });
    setProfileShareCopied(false);
  };

  const revokeProfileShare = () => {
    setProfileShare(null);
    setProfileShareCopied(false);
  };

  const flashShareFeedback = (msg: string) => {
    setShareFeedback(msg);
    window.setTimeout(() => setShareFeedback(null), 2800);
  };

  const shareNativeContent = async (opts: {
    title: string;
    text: string;
    url: string;
    qrImageSrc?: string;
    qrFileName?: string;
  }): Promise<"shared" | "copied" | "cancelled" | "unsupported"> => {
    const { title, text, url, qrImageSrc, qrFileName } = opts;
    const shareText = text.includes(url) ? text : `${text}\n${url}`;

    // Prefer Web Share API (opens the OS share sheet with installed apps).
    if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
      try {
        const data: ShareData = { title, text: shareText, url };
        if (qrImageSrc && typeof navigator.canShare === "function") {
          try {
            const res = await fetch(qrImageSrc);
            const blob = await res.blob();
            const file = new File([blob], qrFileName || "careconnect-qr.png", {
              type: blob.type || "image/png",
            });
            if (navigator.canShare({ files: [file] })) {
              data.files = [file];
            }
          } catch {
            // Share link/text only if QR file attach fails
          }
        }
        await navigator.share(data);
        return "shared";
      } catch (err) {
        const name = err instanceof DOMException ? err.name : "";
        if (name === "AbortError") return "cancelled";
        // Fall through to clipboard fallback
      }
    }

    try {
      await navigator.clipboard.writeText(url || shareText);
      return "copied";
    } catch {
      window.prompt("Copy this link:", url || shareText);
      return "copied";
    }
  };

  const copyProfileShareLink = async () => {
    if (!profileShare) return;
    try {
      await navigator.clipboard.writeText(profileShare.url);
      setProfileShareCopied(true);
      window.setTimeout(() => setProfileShareCopied(false), 2000);
    } catch {
      window.prompt("Copy this profile share link:", profileShare.url);
    }
  };

  const shareProfileNative = async () => {
    if (!profileShare) return;
    const title = `${profileName || "CareConnect"} profile`;
    const text = `View my CareConnect profile: ${profileShare.url}`;
    const result = await shareNativeContent({
      title,
      text,
      url: profileShare.url,
      qrImageSrc: qrImageUrl(profileShare.url, 512),
      qrFileName: "careconnect-profile-qr.png",
    });
    if (result === "shared") flashShareFeedback("Opened your device share sheet");
    else if (result === "copied") {
      setProfileShareCopied(true);
      flashShareFeedback("Sharing unavailable — link copied to clipboard");
      window.setTimeout(() => setProfileShareCopied(false), 2000);
    }
  };

  const copyInviteLink = async () => {
    if (!inviteResult) return;
    try {
      await navigator.clipboard.writeText(inviteResult.url);
      setInviteCopied(true);
      window.setTimeout(() => setInviteCopied(false), 2000);
    } catch {
      // Fallback for browsers without clipboard API
      window.prompt("Copy this invite link:", inviteResult.url);
    }
  };

  const shareInviteNative = async () => {
    if (!inviteResult) return;
    const title = "CareConnect Care Circle invite";
    const text = `${profileName || "A CareConnect patient"} invited you to their Care Circle: ${inviteResult.url}`;
    const result = await shareNativeContent({
      title,
      text,
      url: inviteResult.url,
      qrImageSrc: qrImageUrl(inviteResult.url, 512),
      qrFileName: "careconnect-invite-qr.png",
    });
    if (result === "shared") flashShareFeedback("Opened your device share sheet");
    else if (result === "copied") {
      setInviteCopied(true);
      flashShareFeedback("Sharing unavailable — invite link copied");
      window.setTimeout(() => setInviteCopied(false), 2000);
    }
  };

  const addInvitedCaregiver = () => {
    if (!inviteResult) return;
    if (!canAddCaregiver(linkedCaregivers)) return;
    const name = inviteDraft.name.trim() || "Invited caregiver";
    const newCg: LinkedCaregiver = {
      id: `cg-${Date.now()}`,
      name,
      relationship: inviteDraft.relationship.trim() || "Pending invite",
      initials: makeInitials(name),
      email: inviteDraft.email.trim(),
      phone: inviteDraft.phone.trim(),
      grants: ["mood", "checkin_summary", "med_adherence", "symptoms"],
      // Patient adding them here counts as approval — active as soon as they join/match.
      status: "active",
      inviteCode: inviteResult.code,
      addedByPatient: true,
    };
    setLinkedCaregivers([...linkedCaregivers, newCg]);
    setShowInvite(false);
    setInviteResult(null);
    setInviteDraft({ name: "", relationship: "", email: "", phone: "" });
  };

  return (
    <div className="flex flex-col min-h-full bg-[#F9FAFB]">
      {/* Profile header */}
      <div className="px-4 pt-5 pb-4 bg-white border-b border-[#E5E7EB]">
        <div className="flex items-center gap-3 mb-4">
          <div className="relative">
            <div className="w-14 h-14 rounded-full overflow-hidden flex items-center justify-center border-2"
              style={{ borderColor: theme.color, background: theme.lightBg }}>
              {profileImage
                ? <img src={profileImage} className="w-full h-full object-cover" />
                : <User size={24} style={{ color: theme.color }} />}
            </div>
            <label className="absolute -bottom-1 -right-1 w-6 h-6 rounded-full bg-white border border-[#E5E7EB] flex items-center justify-center cursor-pointer shadow-sm">
              <span className="text-[10px]">✏️</span>
              <input type="file" accept="image/*" className="hidden" onChange={e => {
                const f = e.target.files?.[0];
                if (!f) return;
                const r = new FileReader();
                r.onload = ev => setProfileImage(ev.target?.result as string);
                r.readAsDataURL(f);
              }} />
            </label>
          </div>
          <div className="flex-1">
            <p className="text-[18px] font-bold text-[#0F172A]">{profileName || "Your Name"}</p>
            <div className="flex items-center gap-1.5 mt-0.5">
              <div className="w-2 h-2 rounded-full" style={{ background: theme.color }} />
              <p className="text-[12px] font-semibold" style={{ color: theme.color }}>
                Patient / User{theme.name !== "Custom" ? ` · ${theme.name} mode` : ""}
              </p>
            </div>
          </div>
          <button onClick={onSignOut} className="text-[12px] font-semibold text-[#9CA3AF] px-3 py-1.5 rounded-lg bg-[#F3F4F6]">
            Sign out
          </button>
        </div>
        <p className="text-[11px] text-[#9CA3AF] mb-3">
          Signing out keeps your profile, accessibility settings, features, and health data saved for the next login.
        </p>

        {/* Section tabs */}
        <div className="flex gap-1 p-1 rounded-2xl" style={{ background: "#F3F4F6" }}>
          {tabs.map(t => (
            <button key={t.key} onClick={() => setSection(t.key)}
              className="flex-1 flex flex-col items-center gap-0.5 py-2 rounded-xl transition-all"
              style={{ background: section === t.key ? "white" : "transparent", boxShadow: section === t.key ? "0 1px 3px rgba(0,0,0,0.1)" : "none" }}>
              <span className="text-[14px]">{t.icon}</span>
              <span className="text-[9px] font-bold uppercase tracking-wide" style={{ color: section === t.key ? "#00A7C8" : "#9CA3AF" }}>{t.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Section content */}
      <div className="flex-1 overflow-y-auto px-4 py-4">

        {/* ── My Info ── */}
        {section === "info" && (
          <div className="flex flex-col gap-3">
            <MoodTrendCard theme={theme} history={moodHistory} currentMood={patientMood} />
            {!editingInfo ? (
              <>
                <div className="flex items-center justify-between">
                  <p className="text-[13px] text-[#6B7280]">Your personal and health details.</p>
                  <button onClick={startEditing}
                    className="px-4 py-2 rounded-xl text-[13px] font-bold text-white"
                    style={{ background: theme.color }}>
                    ✏️ Edit info
                  </button>
                </div>
                {justSaved && (
                  <div className="px-4 py-2.5 rounded-xl text-[13px] font-semibold"
                    style={{ background: "#ECFDF5", color: "#047857", border: "1px solid #A7F3D0" }}>
                    ✓ Your profile changes were saved.
                  </div>
                )}
                {[
                  { label: "Full name", value: profileName || "—", icon: "👤" },
                  { label: "Email", value: profileEmail || "Not set", icon: "✉️" },
                  { label: "Date of birth", value: profileDob || "Not set", icon: "🎂" },
                  { label: "Address", value: profileAddress || "Not set", icon: "📍" },
                  { label: "Primary care provider", value: profileProvider || "Not set", icon: "🩺" },
                  { label: "Emergency contact", value: profileEmergency || "Not set", icon: "🆘" },
                  { label: "Conditions", value: profileConditions || "Not set", icon: "📋" },
                  { label: "Medications", value: profileMeds || "Not set", icon: "💊" },
                  { label: "Allergies", value: profileAllergies || "Not set", icon: "⚠️" },
                ].map(item => (
                  <div key={item.label} className="flex items-center gap-3 px-4 py-3.5 rounded-2xl bg-white border border-[#E5E7EB]">
                    <span className="text-[20px] w-7 text-center shrink-0">{item.icon}</span>
                    <div className="flex-1 min-w-0">
                      <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wide">{item.label}</p>
                      <p className="text-[14px] font-semibold text-[#0F172A] break-words">{item.value}</p>
                    </div>
                  </div>
                ))}
                <AccessibilityModeCustomizer
                  mode={mode}
                  setMode={setMode}
                  customSettings={customSettings}
                  setCustomSettings={setCustomSettings}
                  theme={theme}
                />
              </>
            ) : (
              <>
                <div className="px-4 py-3 rounded-2xl" style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}>
                  <p className="text-[13px] font-semibold" style={{ color: theme.color }}>
                    Editing your info — tap the mic next to any field to speak instead of typing.
                  </p>
                </div>
                <div className="flex flex-col gap-4 px-4 py-4 rounded-2xl bg-white border border-[#E5E7EB]">
                  <VoiceField label="Full name" value={draft.name} onChange={setDraftField("name")} placeholder="Your full name" color={theme.color} />
                  <VoiceField label="Email" value={draft.email} onChange={setDraftField("email")} placeholder="you@example.com" color={theme.color} />
                  <VoiceField label="Date of birth" value={draft.dob} onChange={setDraftField("dob")} placeholder="MM/DD/YYYY" color={theme.color} />
                  <VoiceField label="Address" value={draft.address} onChange={setDraftField("address")} placeholder="Street, city, state, ZIP" multiline color={theme.color} />
                  <VoiceField label="Primary care provider" value={draft.provider} onChange={setDraftField("provider")} placeholder="Dr. name / clinic" color={theme.color} />
                  <VoiceField label="Emergency contact" value={draft.emergency} onChange={setDraftField("emergency")} placeholder="Name and phone number" color={theme.color} />
                  <VoiceField label="Conditions" value={draft.conditions} onChange={setDraftField("conditions")} placeholder="e.g., Hypertension, Diabetes" multiline color={theme.color} />
                  <VoiceField label="Medications" value={draft.meds} onChange={setDraftField("meds")} placeholder="e.g., Lisinopril 10mg daily" multiline color={theme.color} />
                  <VoiceField label="Allergies" value={draft.allergies} onChange={setDraftField("allergies")} placeholder="e.g., Penicillin, peanuts" multiline color={theme.color} />
                </div>
                <div className="flex gap-2 sticky bottom-0 pt-1 pb-2" style={{ background: "#FAFBFC" }}>
                  <button onClick={discardEdits}
                    className="flex-1 py-3.5 rounded-xl text-[14px] font-bold"
                    style={{ background: "#F3F4F6", color: "#6B7280", border: "1px solid #E5E7EB" }}>
                    Discard changes
                  </button>
                  <button onClick={saveEdits}
                    disabled={!draftDirty}
                    className="flex-1 py-3.5 rounded-xl text-[14px] font-bold text-white"
                    style={{ background: theme.color, opacity: draftDirty ? 1 : 0.45 }}>
                    Save changes
                  </button>
                </div>
              </>
            )}

            {/* Shareable profile link / QR (Feature 3) */}
            <div className="rounded-2xl bg-white border border-[#E5E7EB] p-4 flex flex-col gap-3">
              <div className="flex items-center gap-2">
                <QrCode size={18} style={{ color: theme.color }} />
                <div className="flex-1 min-w-0">
                  <p className="text-[14px] font-bold text-[#0F172A]">Share my profile</p>
                  <p className="text-[11px] text-[#9CA3AF]">
                    Generate a one-time link or QR others can open to view your CareConnect profile.
                  </p>
                </div>
              </div>
              {!profileShare ? (
                <button type="button" onClick={generateProfileShare}
                  className="w-full py-3 rounded-xl text-[14px] font-bold text-white flex items-center justify-center gap-2"
                  style={{ background: theme.color }}>
                  <Link2 size={16} /> Create share link &amp; QR
                </button>
              ) : (
                <div className="flex flex-col gap-3 items-center">
                  <img
                    src={qrImageUrl(profileShare.url, 160)}
                    alt="Profile share QR code"
                    width={160}
                    height={160}
                    className="rounded-lg border border-[#E5E7EB]"
                  />
                  <div className="w-full flex items-center gap-2 px-3 py-2.5 rounded-xl bg-[#F8FAFC] border border-[#E5E7EB]">
                    <Link2 size={14} className="text-[#00A7C8] shrink-0" />
                    <p className="flex-1 text-[12px] font-medium text-[#0F172A] break-all">{profileShare.url}</p>
                  </div>
                  {shareFeedback && (
                    <p className="text-[12px] font-semibold text-center" style={{ color: theme.color }}>
                      {shareFeedback}
                    </p>
                  )}
                  <button type="button" onClick={shareProfileNative}
                    className="w-full py-3 rounded-xl text-[14px] font-bold text-white flex items-center justify-center gap-2"
                    style={{ background: theme.color }}>
                    <Send size={16} /> Share
                  </button>
                  <p className="text-[11px] text-[#9CA3AF] text-center -mt-1">
                    Opens your device share sheet (Messages, Email, WhatsApp, and other installed apps).
                  </p>
                  <div className="flex gap-2 w-full">
                    <button type="button" onClick={copyProfileShareLink}
                      className="flex-1 py-2.5 rounded-xl text-[13px] font-bold flex items-center justify-center gap-1.5"
                      style={{
                        background: profileShareCopied ? "#ECFDF5" : "#F3F4F6",
                        color: profileShareCopied ? "#047857" : "#374151",
                      }}>
                      {profileShareCopied ? <><Check size={14} /> Copied</> : <><Copy size={14} /> Copy link</>}
                    </button>
                    <button type="button" onClick={revokeProfileShare}
                      className="flex-1 py-2.5 rounded-xl text-[13px] font-bold text-white bg-[#DC2626]">
                      Revoke
                    </button>
                  </div>
                  <button type="button" onClick={generateProfileShare}
                    className="text-[12px] font-semibold text-[#00A7C8]">
                    Generate a new link
                  </button>
                </div>
              )}
            </div>
          </div>
        )}

        {/* ── My Features ── */}
        {section === "features" && (
          <div className="flex flex-col gap-3">
            <p className="text-[13px] text-[#6B7280]">Toggle features on or off — changes take effect instantly everywhere in the app.</p>
            {(["health", "safety", "ai", "devices", "social", "documents"] as const).map(cat => {
              const items = FEATURE_DEFS.filter(f => f.category === cat);
              const catLabels: Record<string, string> = { health: "❤️ Health", safety: "🛡️ Safety", ai: "🤖 AI & Assistants", devices: "⌚ Devices", social: "👥 Social", documents: "📁 Documents & Mail" };
              return (
                <div key={cat}>
                  <p className="text-[12px] font-bold text-[#9CA3AF] uppercase tracking-wider mb-2">{catLabels[cat]}</p>
                  <div className="rounded-2xl overflow-hidden border border-[#E5E7EB] bg-white">
                    {items.map((f, i) => (
                      <div key={f.id} className={`flex items-center gap-3 px-4 py-3.5 ${i > 0 ? "border-t border-[#F3F4F6]" : ""}`}>
                        <span className="text-[20px] w-7 text-center shrink-0">{f.icon}</span>
                        <div className="flex-1 min-w-0">
                          <p className="text-[14px] font-semibold text-[#0F172A]">{f.label}</p>
                          <p className="text-[11px] text-[#9CA3AF] truncate">{f.description}</p>
                        </div>
                        <Switch checked={enabledFeatures.includes(f.id)} onChange={() => onToggleFeature(f.id)} id={`prof-${f.id}`} color="#00A7C8" />
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* ── Care Circle ── */}
        {section === "circle" && (
          <div className="flex flex-col gap-3">
            <p className="text-[13px] text-[#6B7280]">
              You can have up to {MAX_CAREGIVERS} caregivers. Add or remove anyone anytime. Approve pending requests from caregivers you did not invite yourself.
            </p>
            <p className="text-[12px] font-semibold text-[#374151]">
              Care Circle · {linkedCaregivers.length}/{MAX_CAREGIVERS}
            </p>
            {cgSavedFlash && (
              <div className="px-4 py-2.5 rounded-xl text-[13px] font-semibold"
                style={{ background: "#ECFDF5", color: "#047857", border: "1px solid #A7F3D0" }}>
                ✓ Caregiver details saved.
              </div>
            )}

            {linkedCaregivers.map(cg => {
              const isEditing = editingCgId === cg.id && cgDraft;
              return (
                <div key={cg.id} className="rounded-2xl bg-white border border-[#E5E7EB] overflow-hidden">
                  <div className="flex items-center gap-3 px-4 py-3 border-b border-[#F3F4F6]">
                    <div className="w-10 h-10 rounded-full flex items-center justify-center text-white text-[12px] font-bold shrink-0" style={{ background: "#00A7C8" }}>
                      {isEditing ? makeInitials(cgDraft.name) : cg.initials}
                    </div>
                    <div className="flex-1 min-w-0">
                      {!isEditing ? (
                        <>
                          <p className="text-[14px] font-bold text-[#0F172A]">{cg.name}</p>
                          <p className="text-[12px] text-[#9CA3AF]">{cg.relationship}</p>
                          {(cg.email || cg.phone) && (
                            <p className="text-[11px] text-[#9CA3AF] mt-0.5 truncate">
                              {[cg.email, cg.phone].filter(Boolean).join(" · ")}
                            </p>
                          )}
                        </>
                      ) : (
                        <p className="text-[12px] font-semibold" style={{ color: theme.color }}>Editing caregiver…</p>
                      )}
                    </div>
                    <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                      (isEditing ? cgDraft.status : cg.status) === "active" ? "bg-[#D1FAE5] text-[#059669]"
                      : (isEditing ? cgDraft.status : cg.status) === "pending" ? "bg-[#FEF3C7] text-[#D97706]"
                      : "bg-[#FEE2E2] text-[#EF4444]"
                    }`}>
                      {isEditing ? cgDraft.status : cg.status}
                    </span>
                  </div>

                  {isEditing ? (
                    <div className="px-4 py-3 flex flex-col gap-3">
                      <VoiceField label="Name" value={cgDraft.name} onChange={v => setCgDraft({ ...cgDraft, name: v })} placeholder="Caregiver name" color={theme.color} />
                      <VoiceField label="Relationship" value={cgDraft.relationship} onChange={v => setCgDraft({ ...cgDraft, relationship: v })} placeholder="e.g. Daughter, Care Coordinator" color={theme.color} />
                      <VoiceField label="Email" value={cgDraft.email} onChange={v => setCgDraft({ ...cgDraft, email: v })} placeholder="email@example.com" color={theme.color} />
                      <VoiceField label="Phone" value={cgDraft.phone} onChange={v => setCgDraft({ ...cgDraft, phone: v })} placeholder="(555) 000-0000" color={theme.color} />
                      <div>
                        <label className="text-[12px] font-bold text-[#374151] uppercase tracking-wider mb-1.5 block">Status</label>
                        <select
                          value={cgDraft.status}
                          onChange={e => setCgDraft({ ...cgDraft, status: e.target.value as LinkedCaregiver["status"] })}
                          className="w-full border border-[#E5E7EB] rounded-xl px-4 py-3 bg-white outline-none"
                          style={{ fontSize: 15 }}
                        >
                          <option value="active">Active</option>
                          <option value="pending">Pending</option>
                          <option value="suspended">Suspended</option>
                        </select>
                      </div>
                      <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wider">Shared with them</p>
                      {(Object.entries(GRANTED_LABELS) as [GrantedItem, string][]).map(([item, label]) => (
                        <div key={item} className="flex items-center justify-between py-1">
                          <p className="text-[13px] text-[#374151]">{label}</p>
                          <Switch checked={cg.grants.includes(item)} onChange={() => toggleGrant(cg.id, item)} id={`grant-edit-${cg.id}-${item}`} color="#00A7C8" />
                        </div>
                      ))}
                      <div className="flex gap-2 pt-1">
                        <button type="button" onClick={discardCgEdit}
                          className="flex-1 py-2.5 rounded-xl text-[13px] font-bold"
                          style={{ background: "#F3F4F6", color: "#6B7280", border: "1px solid #E5E7EB" }}>
                          Discard
                        </button>
                        <button type="button" onClick={saveCgEdit} disabled={!cgDraft.name.trim()}
                          className="flex-1 py-2.5 rounded-xl text-[13px] font-bold text-white"
                          style={{ background: theme.color, opacity: cgDraft.name.trim() ? 1 : 0.45 }}>
                          Save
                        </button>
                      </div>
                    </div>
                  ) : (
                    <>
                      {cg.status === "pending" && (
                        <div className="px-4 pt-3">
                          <div className="rounded-xl px-3 py-2.5 mb-1" style={{ background: "#FFFBEB", border: "1px solid #FDE68A" }}>
                            <p className="text-[12px] font-semibold text-[#92400E]">
                              {cg.addedByPatient
                                ? "Invite sent — waiting for this caregiver to join with your link or QR."
                                : "This caregiver requested access. Approve to grant shared access, or remove this request."}
                            </p>
                          </div>
                        </div>
                      )}
                      {(cg.pendingGrantRequests?.length ?? 0) > 0 && (
                        <div className="px-4 pt-3">
                          <div className="rounded-xl px-3 py-2.5" style={{ background: "#EFF6FF", border: "1px solid #BFDBFE" }}>
                            <p className="text-[12px] font-bold text-[#1D4ED8] mb-1">Access request</p>
                            <p className="text-[12px] text-[#1E40AF] mb-2">
                              {cg.name} asked to see: {(cg.pendingGrantRequests ?? []).map(i => GRANTED_LABELS[i]).join(", ")}
                            </p>
                            <div className="flex gap-2">
                              <button type="button" onClick={() => approveGrantRequests(cg.id)}
                                className="flex-1 py-2 rounded-xl text-[12px] font-semibold text-white"
                                style={{ background: "#2563EB" }}>
                                Approve sharing
                              </button>
                              <button type="button" onClick={() => dismissGrantRequests(cg.id)}
                                className="flex-1 py-2 rounded-xl text-[12px] font-semibold border border-[#E5E7EB] text-[#6B7280] bg-white">
                                Dismiss
                              </button>
                            </div>
                          </div>
                        </div>
                      )}
                      <div className="px-4 py-3">
                        <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wider mb-2">Shared with them</p>
                        {(Object.entries(GRANTED_LABELS) as [GrantedItem, string][]).map(([item, label]) => (
                          <div key={item} className="flex items-center justify-between py-1.5">
                            <p className="text-[13px] text-[#374151]">{label}</p>
                            <Switch checked={cg.grants.includes(item)} onChange={() => toggleGrant(cg.id, item)} id={`grant-${cg.id}-${item}`} color="#00A7C8" />
                          </div>
                        ))}
                      </div>
                      <div className="flex flex-wrap gap-2 px-4 pb-3">
                        {cg.status === "pending" && !cg.addedByPatient && (
                          <button type="button" onClick={() => approveCg(cg.id)}
                            className="flex-1 min-w-[40%] py-2 rounded-xl text-[12px] font-semibold text-white"
                            style={{ background: "#059669" }}>
                            Approve
                          </button>
                        )}
                        <button type="button" onClick={() => startEditCg(cg)}
                          className="flex-1 min-w-[30%] py-2 rounded-xl text-[12px] font-semibold border border-[#E5E7EB] text-[#00A7C8] bg-white">
                          Edit
                        </button>
                        {cg.status !== "pending" && (
                          <button type="button" onClick={() => suspendCg(cg.id)}
                            className="flex-1 min-w-[30%] py-2 rounded-xl text-[12px] font-semibold border border-[#FEE2E2] text-[#EF4444] bg-white">
                            {cg.status === "suspended" ? "Reactivate" : "Suspend"}
                          </button>
                        )}
                        <button type="button" onClick={() => removeCg(cg.id)}
                          className="flex-1 min-w-[30%] py-2 rounded-xl text-[12px] font-semibold border border-[#E5E7EB] text-[#6B7280] bg-white">
                          Remove
                        </button>
                      </div>
                    </>
                  )}
                </div>
              );
            })}

            {/* Invite caregiver */}
            {!showInvite ? (
              canAddCaregiver(linkedCaregivers) ? (
                <button type="button" onClick={openInvite}
                  className="w-full py-4 rounded-2xl border-2 border-dashed text-[14px] font-semibold flex items-center justify-center gap-2"
                  style={{ borderColor: "#00A7C8", color: "#00A7C8" }}>
                  <QrCode size={18} /> Invite a caregiver via QR or link
                </button>
              ) : (
                <div className="w-full py-4 px-4 rounded-2xl border border-[#E5E7EB] bg-[#F9FAFB] text-center">
                  <p className="text-[14px] font-semibold text-[#0F172A]">Care Circle is full ({MAX_CAREGIVERS}/{MAX_CAREGIVERS})</p>
                  <p className="text-[12px] text-[#6B7280] mt-1">
                    Remove a caregiver to invite or approve someone new.
                  </p>
                </div>
              )
            ) : (
              <div className="rounded-2xl bg-white border-2 p-4 flex flex-col gap-3" style={{ borderColor: theme.color + "50" }}>
                <div className="flex items-center justify-between">
                  <p className="text-[14px] font-bold" style={{ color: theme.color }}>Invite a caregiver</p>
                  <button type="button" onClick={() => { setShowInvite(false); setInviteResult(null); }}
                    className="text-[#9CA3AF]"><X size={18} /></button>
                </div>
                <p className="text-[12px] text-[#6B7280]">
                  Generate a QR code or shareable link for your Care Circle. Adding them here counts as your approval once they join. You can still remove them anytime.
                </p>
                <div className="rounded-xl px-3 py-2" style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}>
                  <p className="text-[11px] font-bold uppercase tracking-wider" style={{ color: theme.color }}>Patient / User on this invite</p>
                  <p className="text-[14px] font-bold text-[#0F172A]">{profileName || "Your Name"}</p>
                </div>
                <VoiceField label="Name (optional)" value={inviteDraft.name} onChange={v => setInviteDraft({ ...inviteDraft, name: v })} placeholder="Who are you inviting?" color={theme.color} />
                <VoiceField label="Relationship" value={inviteDraft.relationship} onChange={v => setInviteDraft({ ...inviteDraft, relationship: v })} placeholder="e.g. Daughter, Nurse" color={theme.color} />
                <VoiceField label="Email" value={inviteDraft.email} onChange={v => setInviteDraft({ ...inviteDraft, email: v })} placeholder="email@example.com" color={theme.color} />
                <VoiceField label="Phone" value={inviteDraft.phone} onChange={v => setInviteDraft({ ...inviteDraft, phone: v })} placeholder="(555) 000-0000" color={theme.color} />

                {!inviteResult ? (
                  <button type="button" onClick={generateInvite}
                    className="w-full py-3 rounded-xl text-[14px] font-bold text-white flex items-center justify-center gap-2"
                    style={{ background: theme.color }}>
                    <Link2 size={16} /> Generate invite link &amp; QR
                  </button>
                ) : (
                  <div className="flex flex-col gap-3 items-center pt-1">
                    <div className="p-3 rounded-2xl bg-white border border-[#E5E7EB]">
                      <img
                        src={qrImageUrl(inviteResult.url, 180)}
                        alt="Caregiver invite QR code"
                        width={180}
                        height={180}
                        className="rounded-lg"
                      />
                    </div>
                    <p className="text-[11px] text-[#9CA3AF] text-center">
                      Scan this QR — it is scoped to {profileName || "this Patient/User"} only
                    </p>
                    <div className="w-full flex items-center gap-2 px-3 py-2.5 rounded-xl bg-[#F8FAFC] border border-[#E5E7EB]">
                      <Link2 size={14} className="text-[#00A7C8] shrink-0" />
                      <p className="flex-1 text-[12px] font-medium text-[#0F172A] break-all">{inviteResult.url}</p>
                    </div>
                    <div className="flex flex-col gap-2 w-full">
                      <button type="button" onClick={shareInviteNative}
                        className="w-full py-3 rounded-xl text-[13px] font-bold text-white flex items-center justify-center gap-1.5"
                        style={{ background: theme.color }}>
                        <Send size={14} /> Share
                      </button>
                      <p className="text-[11px] text-[#9CA3AF] text-center">
                        Opens your device share sheet with installed apps.
                      </p>
                      <div className="flex gap-2 w-full">
                        <button type="button" onClick={copyInviteLink}
                          className="flex-1 py-2.5 rounded-xl text-[13px] font-bold flex items-center justify-center gap-1.5"
                          style={{ background: inviteCopied ? "#ECFDF5" : "#F3F4F6", color: inviteCopied ? "#047857" : "#374151" }}>
                          {inviteCopied ? <><Check size={14} /> Copied</> : <><Copy size={14} /> Copy link</>}
                        </button>
                        <button type="button" onClick={addInvitedCaregiver}
                          className="flex-1 py-2.5 rounded-xl text-[13px] font-bold text-white"
                          style={{ background: theme.color }}>
                          Add to Care Circle
                        </button>
                      </div>
                    </div>
                    <button type="button" onClick={generateInvite}
                      className="text-[12px] font-semibold text-[#00A7C8]">
                      Generate a new link
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {/* ── Settings (includes disability dropdown + full a11y controls) ── */}
        {section === "settings" && (
          <div className="-mx-4 -my-4">
            <SettingsContent
              mode={mode} setMode={setMode}
              customSettings={customSettings} setCustomSettings={setCustomSettings}
              theme={theme}
              disability={disability} setDisability={setDisability}
              textSize={textSize} setTextSize={setTextSize}
              highContrast={highContrast} setHighContrast={setHighContrast}
              boldText={boldText} setBoldText={setBoldText}
              colorFilter={colorFilter} setColorFilter={setColorFilter}
              reduceMotion={reduceMotion} setReduceMotion={setReduceMotion}
              autoPlay={autoPlay} setAutoPlay={setAutoPlay}
              readAloudGlobal={readAloudGlobal} setReadAloudGlobal={setReadAloudGlobal}
              focusIndicators={focusIndicators} setFocusIndicators={setFocusIndicators}
              tremorMode={tremorMode} setTremorMode={setTremorMode}
              confirmActions={confirmActions} setConfirmActions={setConfirmActions}
              vibration={vibration} setVibration={setVibration}
              visualAlerts={visualAlerts} setVisualAlerts={setVisualAlerts}
              simplifiedNav={simplifiedNav} setSimplifiedNav={setSimplifiedNav}
              captions={captions} setCaptions={setCaptions}
              soundAmplify={soundAmplify} setSoundAmplify={setSoundAmplify}
              ttySupport={ttySupport} setTtySupport={setTtySupport}
              hearingAidMode={hearingAidMode} setHearingAidMode={setHearingAidMode}
              onSignOut={onSignOut}
            />
          </div>
        )}
      </div>
    </div>
  );
}

// ── Shared patient data (Care Circle grants only) ──────────────────────────────

function SharedPatientDataPanel({
  patient,
  medications = [],
  medsChecked = {},
  appointments = [],
  theme,
  moodHistory = [],
}: {
  patient: PatientSnippet;
  medications?: Medication[];
  medsChecked?: Record<string, boolean>;
  appointments?: Appointment[];
  theme: ModeTheme;
  moodHistory?: MoodEntry[];
}) {
  const moodEmojis = ["", "😞", "😕", "😐", "🙂", "😄"];
  const grants = patient.grants;
  const access = patient.accessState ?? "ok";
  const sharedLabels = (Object.entries(GRANTED_LABELS) as [GrantedItem, string][])
    .filter(([item]) => grants.includes(item));

  if (access === "inactive_profile") {
    return (
      <div className="rounded-2xl p-4 text-center" style={{ background: "#FFFBEB", border: "1px solid #FDE68A" }}>
        <p className="text-[14px] font-bold text-[#92400E]">No active patient profile</p>
        <p className="text-[12px] text-[#B45309] mt-1">Access is blocked until the patient finishes setting up their account.</p>
      </div>
    );
  }
  if (access === "suspended" || access === "unauthorized") {
    return (
      <div className="rounded-2xl p-4 text-center" style={{ background: "#FEF2F2", border: "1px solid #FECACA" }}>
        <p className="text-[14px] font-bold text-[#991B1B]">Access not authorized</p>
        <p className="text-[12px] text-[#B91C1C] mt-1">
          {access === "suspended"
            ? "This link is suspended — no shared data is available."
            : "No active Care Circle link found yet. Ask the patient to add you and turn on sharing in Care Circle."}
        </p>
      </div>
    );
  }
  if (access === "pending") {
    return (
      <div className="rounded-2xl p-4 text-center" style={{ background: "#FFFBEB", border: "1px solid #FDE68A" }}>
        <p className="text-[14px] font-bold text-[#92400E]">Invite pending</p>
        <p className="text-[12px] text-[#B45309] mt-1">Shared health data will appear once the patient approves you in their Care Circle.</p>
      </div>
    );
  }
  if (grants.length === 0) {
    return (
      <div className="rounded-2xl p-4 text-center bg-white border border-[#E5E7EB]">
        <p className="text-[14px] font-bold text-[#0F172A]">Nothing shared yet</p>
        <p className="text-[12px] text-[#9CA3AF] mt-1">
          {patient.name} has not shared any Care Circle items with you
          {patient.caregiverRelationship ? ` as their ${patient.caregiverRelationship}` : ""}.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-xl px-3 py-2 flex items-center gap-2" style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}>
        <span className="text-[14px]">🤝</span>
        <p className="text-[12px] font-semibold" style={{ color: theme.color }}>
          {grants.length} item{grants.length !== 1 ? "s" : ""} shared by {patient.name}
          {patient.caregiverRelationship ? ` · ${patient.caregiverRelationship}` : ""}
        </p>
      </div>

      {/* Only show features the patient has granted — never list unshared items */}
      <div className="rounded-2xl bg-white border border-[#E5E7EB] p-4">
        <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wider mb-2">Allowed in Care Circle</p>
        <div className="flex flex-col gap-1.5">
          {sharedLabels.map(([item, label]) => (
            <div key={item} className="flex items-center justify-between py-1">
              <p className="text-[13px] text-[#0F172A]">{label}</p>
              <span className="text-[11px] font-bold px-2 py-0.5 rounded-full bg-[#D1FAE5] text-[#059669]">
                Shared
              </span>
            </div>
          ))}
        </div>
      </div>

      {grants.includes("mood") && (
        <>
          <div className="rounded-2xl bg-white border border-[#E5E7EB] p-4">
            <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wider mb-2">Current mood</p>
            {patient.mood !== undefined ? (
              <div className="flex items-center gap-3">
                <span className="text-[36px]">{moodEmojis[patient.mood]}</span>
                <div>
                  <p className="text-[20px] font-bold text-[#0F172A]">{["", "Poor", "Low", "Fair", "Good", "Great"][patient.mood]}</p>
                  <p className="text-[12px] text-[#9CA3AF]">{patient.mood}/5 · Updated today</p>
                </div>
              </div>
            ) : (
              <p className="text-[13px] text-[#6B7280]">Mood access is shared — waiting for the patient to log how they feel.</p>
            )}
          </div>
          <MoodTrendCard
            theme={theme}
            history={moodHistory}
            currentMood={patient.mood ?? null}
            title="How they've been feeling"
            emptyHint="Mood history will appear here when the patient logs how they feel."
          />
        </>
      )}

      {grants.includes("checkin_summary") && (
        <div className="rounded-2xl bg-white border border-[#E5E7EB] p-4">
          <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wider mb-1">Latest check-in</p>
          {patient.lastCheckin ? (
            <>
              <p className="text-[15px] font-semibold text-[#0F172A]">{patient.lastCheckin}</p>
              <p className="text-[12px] text-[#9CA3AF] mt-0.5">Completed via Virtual Check-In</p>
            </>
          ) : (
            <p className="text-[13px] text-[#6B7280]">Check-in access is shared — no check-in logged yet.</p>
          )}
        </div>
      )}

      {grants.includes("med_adherence") && (
        <div className="rounded-2xl bg-white border border-[#E5E7EB] p-4">
          <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wider mb-2">Medication adherence</p>
          {patient.medAdherence !== undefined && (
            <>
              <div className="flex items-center gap-3 mb-2">
                <p className="text-[28px] font-bold" style={{ color: patient.medAdherence >= 80 ? "#10B981" : patient.medAdherence >= 60 ? "#F59E0B" : "#EF4444" }}>
                  {patient.medAdherence}%
                </p>
                <span className="text-[12px] font-semibold px-2 py-0.5 rounded-full"
                  style={{ background: patient.medAdherence >= 80 ? "#D1FAE5" : "#FEF3C7", color: patient.medAdherence >= 80 ? "#059669" : "#D97706" }}>
                  {patient.medAdherence >= 80 ? "On track" : "Needs support"}
                </span>
              </div>
              <div className="h-2 rounded-full bg-[#E5E7EB] overflow-hidden mb-3">
                <div className="h-full rounded-full" style={{ width: `${patient.medAdherence}%`, background: patient.medAdherence >= 80 ? "#10B981" : "#F59E0B" }} />
              </div>
            </>
          )}
          {medications.length > 0 ? (
            <div className="flex flex-col gap-2">
              <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wider">Medications</p>
              {medications.map(m => (
                <div key={m.id} className="flex items-center justify-between px-3 py-2 rounded-xl bg-[#F9FAFB] border border-[#E5E7EB]">
                  <div>
                    <p className="text-[13px] font-semibold text-[#0F172A]">{m.name} · {m.dose}</p>
                    <p className="text-[11px] text-[#9CA3AF]">{m.time}{m.purpose ? ` · ${m.purpose}` : ""}</p>
                  </div>
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full"
                    style={{ background: medsChecked[m.id] ? "#D1FAE5" : "#FEF3C7", color: medsChecked[m.id] ? "#059669" : "#D97706" }}>
                    {medsChecked[m.id] ? "Taken" : "Due"}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-[12px] text-[#9CA3AF]">No medication list available yet.</p>
          )}
        </div>
      )}

      {grants.includes("fall_alerts") && (
        <div className="rounded-2xl p-4" style={{ background: patient.hasFallAlert ? "#FEF2F2" : "#F0FDF4", border: `1.5px solid ${patient.hasFallAlert ? "#FCA5A5" : "#86EFAC"}` }}>
          <p className="text-[11px] font-bold uppercase tracking-wider mb-1" style={{ color: patient.hasFallAlert ? "#EF4444" : "#059669" }}>Fall alerts</p>
          <p className="text-[15px] font-semibold" style={{ color: patient.hasFallAlert ? "#EF4444" : "#059669" }}>
            {patient.hasFallAlert ? "⚠️ Active alert — possible fall detected" : "✓ No alerts today"}
          </p>
        </div>
      )}

      {grants.includes("upcoming_visits") && (
        <div className="rounded-2xl bg-white border border-[#E5E7EB] p-4">
          <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wider mb-2">Upcoming visits</p>
          {appointments.length > 0 ? (
            <div className="flex flex-col gap-2">
              {appointments.map(a => (
                <div key={a.id} className="px-3 py-2 rounded-xl bg-[#F9FAFB] border border-[#E5E7EB]">
                  <p className="text-[13px] font-semibold text-[#0F172A]">{a.title}</p>
                  <p className="text-[11px] text-[#9CA3AF]">{a.date} · {a.time} · {a.type}</p>
                  {a.location && <p className="text-[11px] text-[#6B7280]">{a.location}</p>}
                </div>
              ))}
            </div>
          ) : patient.nextVisit ? (
            <p className="text-[15px] font-semibold text-[#0F172A]">{patient.nextVisit}</p>
          ) : (
            <p className="text-[12px] text-[#9CA3AF]">No upcoming visits listed.</p>
          )}
        </div>
      )}

      {grants.includes("symptoms") && (
        <div className="rounded-2xl bg-white border border-[#E5E7EB] p-4">
          <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wider mb-1">Symptoms & health summary</p>
          <p className="text-[14px] text-[#374151] leading-relaxed">
            {patient.symptomsSummary || "No symptoms summary shared."}
          </p>
        </div>
      )}
    </div>
  );
}

// ── Caregiver profile page ─────────────────────────────────────────────────────

function CaregiverProfilePage({
  account, onSaveAccount,
  profileImage, setProfileImage,
  theme, onSignOut, patients, roleTitle,
  medications, medsChecked, appointments, moodHistory = [],
  showProfessionalDetails = false,
}: {
  account: CaregiverAccountInfo;
  onSaveAccount: (info: CaregiverAccountInfo) => void;
  profileImage: string | null;
  setProfileImage: (v: string | null) => void;
  theme: ModeTheme; onSignOut: () => void;
  patients: PatientSnippet[];
  roleTitle: string;
  medications?: Medication[];
  medsChecked?: Record<string, boolean>;
  appointments?: Appointment[];
  moodHistory?: MoodEntry[];
  showProfessionalDetails?: boolean;
}) {
  const [section, setSection] = useState<"info" | "circle">("info");
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(account);
  const [justSaved, setJustSaved] = useState(false);

  useEffect(() => {
    setDraft(account);
    setEditing(false);
  }, [account.name, account.email, account.agency, account.credentials, account.phone, account.relationshipToPatient, account.linkedPatientName, account.linkedPatientDob]);

  const dirty = (Object.keys(account) as (keyof CaregiverAccountInfo)[])
    .some(k => draft[k] !== account[k]);

  const startEdit = () => { setDraft(account); setJustSaved(false); setEditing(true); };
  const discard = () => { setDraft(account); setEditing(false); };
  const save = () => {
    const next: CaregiverAccountInfo = {
      ...account,
      name: draft.name.trim() || account.name,
      email: draft.email.trim(),
      agency: draft.agency.trim(),
      credentials: draft.credentials.trim(),
      phone: draft.phone.trim(),
      relationshipToPatient: draft.relationshipToPatient?.trim() || account.relationshipToPatient,
      linkedPatientName: draft.linkedPatientName?.trim() || undefined,
      linkedPatientDob: normalizeDob(draft.linkedPatientDob || "") || draft.linkedPatientDob?.trim() || undefined,
    };
    onSaveAccount(next);
    setEditing(false);
    setJustSaved(true);
    window.setTimeout(() => setJustSaved(false), 2200);
  };

  const displayName = account.name || "Caregiver";

  return (
    <div className="flex flex-col min-h-full bg-[#F9FAFB] pb-28">
      <div className="px-4 pt-5 pb-4 bg-white border-b border-[#E5E7EB]">
        <div className="flex items-center gap-3 mb-3">
          <div className="relative">
            <div className="w-14 h-14 rounded-full overflow-hidden flex items-center justify-center border-2 text-white text-[16px] font-bold"
              style={{ borderColor: theme.color, background: theme.color }}>
              {profileImage
                ? <img src={profileImage} className="w-full h-full object-cover" />
                : makeInitials(displayName)}
            </div>
            <label className="absolute -bottom-1 -right-1 w-6 h-6 rounded-full bg-white border border-[#E5E7EB] flex items-center justify-center cursor-pointer shadow-sm">
              <span className="text-[10px]">✏️</span>
              <input type="file" accept="image/*" className="hidden" onChange={e => {
                const f = e.target.files?.[0];
                if (!f) return;
                const r = new FileReader();
                r.onload = ev => setProfileImage(ev.target?.result as string);
                r.readAsDataURL(f);
              }} />
            </label>
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-[18px] font-bold text-[#0F172A] truncate">{displayName}</p>
            <div className="flex items-center gap-1.5 mt-0.5">
              <div className="w-2 h-2 rounded-full" style={{ background: theme.color }} />
              <p className="text-[12px] font-semibold" style={{ color: theme.color }}>
                Caregiver · {roleTitle}
              </p>
            </div>
            {account.email && (
              <p className="text-[11px] text-[#9CA3AF] mt-0.5 truncate">{account.email}</p>
            )}
          </div>
          <button onClick={onSignOut} className="text-[12px] font-semibold text-[#9CA3AF] px-3 py-1.5 rounded-lg bg-[#F3F4F6] shrink-0">
            Sign out
          </button>
        </div>

        <div className="flex gap-1 p-1 rounded-2xl" style={{ background: "#F3F4F6" }}>
          {([
            { key: "info" as const, label: "My Info", icon: "👤" },
            { key: "circle" as const, label: "Care Circle", icon: "🤝" },
          ]).map(t => (
            <button key={t.key} type="button" onClick={() => { setSection(t.key); setEditing(false); }}
              className="flex-1 flex flex-col items-center gap-0.5 py-2 rounded-xl transition-all"
              style={{ background: section === t.key ? "white" : "transparent", boxShadow: section === t.key ? "0 1px 3px rgba(0,0,0,0.1)" : "none" }}>
              <span className="text-[14px]">{t.icon}</span>
              <span className="text-[10px] font-bold uppercase tracking-wide" style={{ color: section === t.key ? theme.color : "#9CA3AF" }}>{t.label}</span>
            </button>
          ))}
        </div>
      </div>

      <div className="px-4 py-4 flex flex-col gap-3">
        {section === "info" && (
          <>
            <p className="text-[13px] text-[#6B7280]">
              Your caregiver account details. You can edit only this information — not the patient’s accessibility or features.
            </p>

            {!editing ? (
              <>
                <div className="flex items-center justify-between">
                  <p className="text-[12px] font-bold text-[#9CA3AF] uppercase tracking-wider">Personal information</p>
                  <button type="button" onClick={startEdit}
                    className="px-4 py-2 rounded-xl text-[13px] font-bold text-white"
                    style={{ background: theme.color }}>
                    ✏️ Edit info
                  </button>
                </div>
                {justSaved && (
                  <div className="px-4 py-2.5 rounded-xl text-[13px] font-semibold"
                    style={{ background: "#ECFDF5", color: "#047857", border: "1px solid #A7F3D0" }}>
                    ✓ Your caregiver profile was saved.
                  </div>
                )}
                {[
                  { label: "Full name", value: account.name || "—", icon: "👤" },
                  { label: "Email", value: account.email || "Not set", icon: "✉️" },
                  { label: "Linked Patient / User", value: account.linkedPatientName?.trim() || "Not set", icon: "🫶" },
                  { label: "Patient date of birth", value: account.linkedPatientDob?.trim() || "Not set", icon: "🎂" },
                  { label: "Relationship to patient", value: account.relationshipToPatient?.trim() || roleTitle || "Not set", icon: "🏷️" },
                  ...(showProfessionalDetails ? [
                    { label: "Agency / Organization", value: account.agency || "Not set", icon: "🏥" },
                    { label: "Credentials", value: account.credentials || "Not set", icon: "📋" },
                    { label: "Contact phone", value: account.phone || "Not set", icon: "📞" },
                  ] : [
                    { label: "Contact phone", value: account.phone || "Not set", icon: "📞" },
                  ]),
                ].map(item => (
                  <div key={item.label} className="flex items-center gap-3 px-4 py-3.5 rounded-2xl bg-white border border-[#E5E7EB]">
                    <span className="text-[20px] w-7 text-center shrink-0">{item.icon}</span>
                    <div className="flex-1 min-w-0">
                      <p className="text-[11px] font-bold text-[#9CA3AF] uppercase tracking-wide">{item.label}</p>
                      <p className="text-[14px] font-semibold text-[#0F172A] break-words">{item.value}</p>
                    </div>
                  </div>
                ))}
                <div className="rounded-2xl bg-[#E0F7FA] border border-[#B2EBF2] p-4">
                  <p className="text-[13px] font-bold text-[#007A94] mb-1">Caregiver access only</p>
                  <p className="text-[12px] text-[#4BA3B5] leading-relaxed">
                    Patient accessibility modes, app features, and sharing controls are managed by the patient. You cannot change them.
                  </p>
                </div>
                <button type="button" onClick={onSignOut} className="w-full py-3.5 rounded-2xl text-[14px] font-bold text-[#EF4444] bg-white border-2 border-[#FEE2E2]">
                  Sign out
                </button>
              </>
            ) : (
              <>
                <div className="px-4 py-3 rounded-2xl" style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}>
                  <p className="text-[13px] font-semibold" style={{ color: theme.color }}>
                    Editing your caregiver info — use the mic to speak or type.
                  </p>
                </div>
                <div className="flex flex-col gap-4 px-4 py-4 rounded-2xl bg-white border border-[#E5E7EB]">
                  <VoiceField label="Full name" value={draft.name} onChange={v => setDraft({ ...draft, name: v })} placeholder="Your name" color={theme.color} />
                  <VoiceField label="Email" value={draft.email} onChange={v => setDraft({ ...draft, email: v })} placeholder="you@example.com" color={theme.color} />
                  <VoiceField label="Linked Patient / User" value={draft.linkedPatientName || ""} onChange={v => setDraft({ ...draft, linkedPatientName: v })} placeholder="e.g. Eleanor Wright" color={theme.color} />
                  <VoiceField label="Patient date of birth" value={draft.linkedPatientDob || ""} onChange={v => setDraft({ ...draft, linkedPatientDob: v })} placeholder="MM/DD/YYYY" color={theme.color} />
                  <VoiceField label="Relationship to patient" value={draft.relationshipToPatient || ""} onChange={v => setDraft({ ...draft, relationshipToPatient: v })} placeholder="e.g. Daughter, Friend, Neighbor" color={theme.color} />
                  {showProfessionalDetails && (
                    <>
                      <VoiceField label="Agency / Organization (optional)" value={draft.agency} onChange={v => setDraft({ ...draft, agency: v })} placeholder="Care agency, clinic, or practice name" color={theme.color} />
                      <VoiceField label="License / Credentials (optional)" value={draft.credentials} onChange={v => setDraft({ ...draft, credentials: v })} placeholder="e.g. RN, LPN, MD" color={theme.color} />
                    </>
                  )}
                  <VoiceField label="Phone number" value={draft.phone} onChange={v => setDraft({ ...draft, phone: v })} placeholder="(555) 000-0000" color={theme.color} />
                </div>
                <div className="flex gap-2">
                  <button type="button" onClick={discard}
                    className="flex-1 py-3.5 rounded-xl text-[14px] font-bold"
                    style={{ background: "#F3F4F6", color: "#6B7280", border: "1px solid #E5E7EB" }}>
                    Discard
                  </button>
                  <button type="button" onClick={save} disabled={!dirty}
                    className="flex-1 py-3.5 rounded-xl text-[14px] font-bold text-white"
                    style={{ background: theme.color, opacity: dirty ? 1 : 0.45 }}>
                    Save changes
                  </button>
                </div>
              </>
            )}
          </>
        )}

        {section === "circle" && (
          <>
            <div className="px-4 py-3 rounded-2xl" style={{ background: "#FFFBEB", border: "1px solid #FDE68A" }}>
              <p className="text-[13px] font-semibold text-[#92400E]">
                Read-only Care Circle — you can view the person you care for and what they shared. You cannot change access, invites, or patient settings.
              </p>
            </div>
            {patients.length === 0 && (
              <div className="rounded-2xl bg-white border border-[#E5E7EB] p-5 text-center">
                <p className="text-[15px] font-bold text-[#0F172A] mb-1">No patient linked</p>
                <p className="text-[13px] text-[#9CA3AF]">
                  When a patient with an active profile adds you in their Care Circle, they will appear here.
                </p>
              </div>
            )}
            {patients.map(p => (
              <div key={p.id} className="flex flex-col gap-3">
                <div className="flex items-center gap-3 px-4 py-3 rounded-2xl bg-white border border-[#E5E7EB]">
                  <div className="w-10 h-10 rounded-full flex items-center justify-center text-white text-[12px] font-bold" style={{ background: theme.color }}>
                    {p.initials}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-[15px] font-bold text-[#0F172A]">{p.name}</p>
                    <p className="text-[11px] text-[#9CA3AF]">
                      Person you care for
                      {p.caregiverRelationship ? ` · ${p.caregiverRelationship}` : ""}
                      {p.accessState === "ok" ? " · Active" : ""}
                    </p>
                  </div>
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#F3F4F6] text-[#6B7280]">View only</span>
                </div>
                <SharedPatientDataPanel
                  patient={p}
                  medications={medications}
                  medsChecked={medsChecked}
                  appointments={appointments}
                  theme={theme}
                  moodHistory={moodHistory}
                />
              </div>
            ))}
          </>
        )}
      </div>
    </div>
  );
}

// ── Caregiver: Patient detail (snippet view) ───────────────────────────────────

function CaregiverPatientDetail({
  patient, onClose, theme, medications, medsChecked, appointments, moodHistory = [],
  caregiverId, caregiverName, onRequestAccess,
}: {
  patient: PatientSnippet; onClose: () => void; theme: ModeTheme;
  medications?: Medication[]; medsChecked?: Record<string, boolean>; appointments?: Appointment[];
  moodHistory?: MoodEntry[];
  caregiverId?: string;
  caregiverName?: string;
  onRequestAccess?: (items: GrantedItem[]) => void;
}) {
  const [showRequest, setShowRequest] = useState(false);
  const [requestItems, setRequestItems] = useState<GrantedItem[]>([]);
  const [requestSent, setRequestSent] = useState(false);

  const ungranted = (Object.keys(GRANTED_LABELS) as GrantedItem[])
    .filter(item => !patient.grants.includes(item));

  const toggleRequestItem = (item: GrantedItem) => {
    setRequestItems(prev =>
      prev.includes(item) ? prev.filter(i => i !== item) : [...prev, item]
    );
  };

  const submitRequest = () => {
    if (!requestItems.length || !onRequestAccess) return;
    onRequestAccess(requestItems);
    setRequestSent(true);
    setShowRequest(false);
    setRequestItems([]);
    window.setTimeout(() => setRequestSent(false), 2800);
  };

  return (
    <div className="relative flex flex-col flex-1 min-h-0 h-full bg-[#F9FAFB]">
      <div className="shrink-0 flex items-center gap-3 px-4 py-3 border-b border-[#E5E7EB] bg-white">
        <button type="button" onClick={onClose} aria-label="Close patient details">
          <ChevronLeft size={20} className="text-[#6B7280]" />
        </button>
        <div className="w-9 h-9 rounded-full flex items-center justify-center text-white text-[12px] font-bold shrink-0" style={{ background: theme.color }}>
          {patient.initials}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-[15px] font-bold text-[#0F172A] truncate">{patient.name}</p>
          <p className="text-[11px] text-[#9CA3AF]">
            {patient.age > 0 ? `Age ${patient.age}` : "Age unknown"}
            {patient.caregiverRelationship ? ` · Viewing as ${patient.caregiverRelationship}` : ""}
          </p>
        </div>
      </div>
      <div className="flex-1 min-h-0 overflow-y-auto overscroll-contain px-4 py-3 pb-10 flex flex-col gap-3">
        <SharedPatientDataPanel
          patient={patient}
          medications={medications}
          medsChecked={medsChecked}
          appointments={appointments}
          theme={theme}
          moodHistory={moodHistory}
        />
        {requestSent && (
          <div className="rounded-xl px-3 py-2.5 text-center text-[13px] font-semibold"
            style={{ background: "#ECFDF5", color: "#047857", border: "1px solid #A7F3D0" }}>
            Access request sent to {patient.name.split(" ")[0]}.
          </div>
        )}
        {patient.accessState === "ok" && ungranted.length > 0 && (
          <p className="text-center text-[12px] font-semibold text-[#9CA3AF] mt-2 mb-2">
            Not seeing something?{" "}
            <button
              type="button"
              onClick={() => { setShowRequest(true); setRequestItems([]); }}
              className="text-[#00A7C8] underline underline-offset-2"
            >
              Ask {patient.name.split(" ")[0]} for access
            </button>
          </p>
        )}
      </div>

      {showRequest && (
        <div className="absolute inset-0 z-40 bg-black/40 flex flex-col justify-end">
          <div className="bg-white rounded-t-3xl px-5 pt-5 pb-8 max-h-[85%] overflow-y-auto">
            <div className="flex items-center justify-between mb-3">
              <div>
                <p className="text-[17px] font-bold text-[#0F172A]">Request access</p>
                <p className="text-[12px] text-[#9CA3AF]">
                  Choose features you need. {patient.name.split(" ")[0]} must approve before they appear.
                </p>
              </div>
              <button type="button" onClick={() => setShowRequest(false)}
                className="w-8 h-8 rounded-full bg-[#F3F4F6] flex items-center justify-center" aria-label="Close">
                <X size={16} className="text-[#6B7280]" />
              </button>
            </div>
            <div className="flex flex-col gap-2 mb-4">
              {ungranted.map(item => {
                const on = requestItems.includes(item);
                return (
                  <button
                    key={item}
                    type="button"
                    onClick={() => toggleRequestItem(item)}
                    className="flex items-center justify-between px-3 py-3 rounded-xl border text-left"
                    style={{
                      borderColor: on ? theme.color : "#E5E7EB",
                      background: on ? theme.lightBg : "white",
                    }}
                  >
                    <p className="text-[14px] font-semibold text-[#0F172A]">{GRANTED_LABELS[item]}</p>
                    <span className="text-[11px] font-bold px-2 py-0.5 rounded-full"
                      style={{ background: on ? "#D1FAE5" : "#F3F4F6", color: on ? "#059669" : "#9CA3AF" }}>
                      {on ? "Selected" : "Select"}
                    </span>
                  </button>
                );
              })}
            </div>
            <button
              type="button"
              onClick={submitRequest}
              disabled={!requestItems.length || !onRequestAccess}
              className="w-full py-3 rounded-xl text-[14px] font-bold text-white"
              style={{ background: theme.color, opacity: requestItems.length ? 1 : 0.45 }}
            >
              Send request{caregiverName ? ` as ${caregiverName}` : ""}
            </button>
            {!caregiverId && (
              <p className="text-[11px] text-center text-[#9CA3AF] mt-2">Sign in as a caregiver to send requests.</p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ── Caregiver home (linked patient with shared-data summary) ────────────────────

function CaregiverHomeV2({
  theme, patients, onOpenPatient, viewingAs,
  appointments = [], setAppointments, setModal, clearModal, useLarge = false,
}: {
  theme: ModeTheme; patients: PatientSnippet[]; onOpenPatient: (p: PatientSnippet) => void;
  viewingAs?: string;
  appointments?: Appointment[];
  setAppointments?: (v: Appointment[]) => void;
  setModal?: (node: React.ReactNode) => void;
  clearModal?: () => void;
  useLarge?: boolean;
}) {
  const moodEmojis = ["", "😞", "😕", "😐", "🙂", "😄"];
  const alertCount = patients.filter(p => p.hasFallAlert && p.grants.includes("fall_alerts") && p.accessState === "ok").length;
  const activeShared = patients.filter(p => p.accessState === "ok" && p.grants.length > 0).length;
  const [sectionOpen, setSectionOpen] = useState<Record<string, boolean>>({ schedule: true });

  return (
    <div className="flex flex-col min-h-full px-4 pt-4 pb-28 gap-3">
      {viewingAs && (
        <div className="rounded-2xl px-3 py-2.5" style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}>
          <p className="text-[12px] font-semibold" style={{ color: theme.color }}>
            Signed in as {viewingAs} — only Care Circle shared data is visible
          </p>
        </div>
      )}

      {/* Alert banner */}
      {alertCount > 0 && (
        <div className="rounded-2xl p-3.5 flex items-center gap-3" style={{ background: "#FEF2F2", border: "1.5px solid #FCA5A5" }}>
          <AlertTriangle size={18} style={{ color: "#EF4444" }} />
          <p className="text-[13px] font-bold text-[#991B1B]">{alertCount} fall alert{alertCount > 1 ? "s" : ""} require attention</p>
        </div>
      )}

      {/* Summary chips */}
      <div className="flex gap-2 flex-wrap">
        {[
          { label: `${patients.length} patient${patients.length === 1 ? "" : "s"}`, color: "#00A7C8", bg: "#E0F7FA" },
          { label: `${activeShared} sharing data`, color: "#059669", bg: "#D1FAE5" },
        ].map(c => (
          <span key={c.label} className="text-[11px] font-bold px-2.5 py-1.5 rounded-full shrink-0" style={{ background: c.bg, color: c.color }}>{c.label}</span>
        ))}
      </div>

      {appointments && setAppointments && setModal && clearModal && (
        <CollapsibleSection
          id="cg-schedule"
          title="Schedule"
          icon={<Calendar size={14} style={{ color: theme.color }} />}
          accent={theme.color}
          openMap={sectionOpen}
          setOpenMap={setSectionOpen}
        >
          <div className="-mx-4 -mb-4">
            <ScheduleContent
              theme={theme}
              useLarge={useLarge}
              appointments={appointments}
              setAppointments={setAppointments}
              setModal={setModal}
              clearModal={clearModal}
            />
          </div>
        </CollapsibleSection>
      )}

      {/* Linked patient and all data they have shared with this caregiver */}
      <p className="text-[12px] font-bold text-[#9CA3AF] uppercase tracking-wider">Your Patient</p>

      {patients.length === 0 && (
        <div className="rounded-2xl bg-white border border-[#E5E7EB] p-5 text-center">
          <p className="text-[15px] font-bold text-[#0F172A] mb-1">No linked Patient / User</p>
          <p className="text-[13px] text-[#9CA3AF] leading-relaxed">
            Confirm the Patient/User during caregiver profile setup using their invite link or QR code. You will only see that person’s shared page.
          </p>
        </div>
      )}

      {patients.map(p => {
        const blocked = p.accessState && p.accessState !== "ok";
        return (
          <button key={p.id} onClick={() => onOpenPatient(p)}
            className="w-full text-left rounded-2xl bg-white border border-[#E5E7EB] overflow-hidden hover:shadow-md transition-shadow">
            <div className="flex items-center gap-3 px-4 py-3 border-b border-[#F3F4F6]">
              <div className="w-10 h-10 rounded-full flex items-center justify-center text-white text-[12px] font-bold shrink-0"
                style={{ background: blocked ? "#9CA3AF" : "#00A7C8" }}>
                {p.initials}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-[15px] font-bold text-[#0F172A]">{p.name}</p>
                <p className="text-[11px] text-[#9CA3AF]">
                  {p.accessState === "ok"
                    ? (p.age > 0 ? `Age ${p.age}` : "Age unknown")
                    : ""}
                  {p.caregiverRelationship ? ` · ${p.caregiverRelationship}` : ""}
                </p>
              </div>
              {p.accessState === "inactive_profile" && (
                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#FEF3C7] text-[#D97706] shrink-0">Inactive</span>
              )}
              {p.accessState === "suspended" && (
                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#FEE2E2] text-[#EF4444] shrink-0">Suspended</span>
              )}
              {p.accessState === "pending" && (
                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#FEF3C7] text-[#D97706] shrink-0">Pending</span>
              )}
              {p.hasFallAlert && p.grants.includes("fall_alerts") && p.accessState === "ok" && (
                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#FEF2F2] text-[#EF4444] shrink-0">⚠️ Alert</span>
              )}
              <ChevronRight size={16} className="text-[#D1D5DB] shrink-0" />
            </div>

            {blocked ? (
              <div className="px-4 py-3">
                <p className="text-[12px] text-[#9CA3AF]">
                  {p.accessState === "inactive_profile" && "Patient must have an active profile before any data can be viewed."}
                  {p.accessState === "suspended" && "Access suspended by the patient — no health data is available."}
                  {p.accessState === "pending" && "Invite pending — waiting for the patient to approve this caregiver."}
                  {p.accessState === "unauthorized" && "Unauthorized — this caregiver is not linked in Care Circle."}
                </p>
              </div>
            ) : p.grants.length === 0 ? (
              <div className="px-4 py-3">
                <p className="text-[12px] text-[#9CA3AF] italic">No data shared yet</p>
                <p className="text-[11px] font-semibold text-[#00A7C8] mt-0.5">Ask for access ↗</p>
              </div>
            ) : (
              <div className="px-4 py-3 flex flex-col gap-2">
                <div className="flex flex-wrap gap-2">
                  {p.grants.includes("mood") && (
                    <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#F9FAFB] border border-[#E5E7EB]">
                      <span className="text-[14px]">{p.mood != null ? moodEmojis[p.mood] : "🙂"}</span>
                      <span className="text-[11px] font-semibold text-[#374151]">
                        Mood{p.mood != null ? `: ${["", "Poor", "Low", "Fair", "Good", "Great"][p.mood]}` : " shared"}
                      </span>
                    </div>
                  )}
                  {p.grants.includes("med_adherence") && (
                    <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full border"
                      style={{
                        background: (p.medAdherence ?? 0) >= 80 ? "#D1FAE5" : "#FEF3C7",
                        borderColor: (p.medAdherence ?? 0) >= 80 ? "#86EFAC" : "#FDE68A",
                      }}>
                      <span className="text-[11px] font-semibold" style={{ color: (p.medAdherence ?? 0) >= 80 ? "#059669" : "#D97706" }}>
                        💊 {p.medAdherence != null ? `${p.medAdherence}% meds` : "Meds shared"}
                      </span>
                    </div>
                  )}
                  {p.grants.includes("checkin_summary") && (
                    <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#E0F7FA] border border-[#B2EBF2]">
                      <span className="text-[11px] font-semibold text-[#007A94]">
                        ✓ {p.lastCheckin || "Check-ins shared"}
                      </span>
                    </div>
                  )}
                  {p.grants.includes("upcoming_visits") && (
                    <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#EEF2FF] border border-[#C7D2FE]">
                      <span className="text-[11px] font-semibold text-[#4338CA]">
                        📅 {p.nextVisit || "Visits shared"}
                      </span>
                    </div>
                  )}
                  {p.grants.includes("symptoms") && (
                    <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#FDF2F8] border border-[#FBCFE8]">
                      <span className="text-[11px] font-semibold text-[#9D174D]">
                        🌡️ {p.symptomsSummary || "Symptoms shared"}
                      </span>
                    </div>
                  )}
                  {p.grants.includes("fall_alerts") && (
                    <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#FEF2F2] border border-[#FECACA]">
                      <span className="text-[11px] font-semibold text-[#B91C1C]">Fall alerts shared</span>
                    </div>
                  )}
                </div>
                <p className="text-[11px] text-[#00A7C8] font-semibold">Tap to view shared details →</p>
              </div>
            )}
          </button>
        );
      })}
    </div>
  );
}

// ── Feature-driven patient bottom nav ─────────────────────────────────────────

function PatientBottomNav({
  tab, onTab, enabledFeatures, color, large, onOpenFeaturePicker, accessibilityMode = null,
}: {
  tab: Tab; onTab: (t: Tab) => void; enabledFeatures: FeatureId[];
  color: string; large: boolean; onOpenFeaturePicker: () => void;
  accessibilityMode?: AppMode | null;
}) {
  // Always exactly 5 icons — Schedule lives on the Home dashboard.
  // Hearing / Check-In remain reachable from the dashboard (not the bottom bar).
  void enabledFeatures;
  void accessibilityMode;
  void onOpenFeaturePicker;

  const navItems: { key: Tab; icon: React.ReactNode; label: string }[] = [
    { key: "home",     icon: <Home size={large ? 22 : 19} />,           label: "Home"     },
    { key: "symptoms", icon: <HeartPulse size={large ? 22 : 19} />,     label: "Health"   },
    { key: "mail",     icon: <Mail size={large ? 22 : 19} />,           label: "Mail"     },
    { key: "messages", icon: <MessageCircle size={large ? 22 : 19} />,  label: "Messages" },
    { key: "profile",  icon: <User size={large ? 22 : 19} />,           label: "Profile"  },
  ];

  return (
    <div className="flex bg-white px-1 py-1">
      {navItems.map(it => {
        const active = tab === it.key || (it.key === "symptoms" && tab === "meds");
        return (
          <button key={it.key} onClick={() => onTab(it.key)}
            className="flex-1 flex flex-col items-center justify-center gap-0.5 rounded-xl py-2 transition-all duration-150"
            style={{
              minHeight: large ? 64 : 54,
              color: active ? color : "#9CA3AF",
              transform: active ? "scale(1.08)" : "scale(1)",
              background: active ? `${color}14` : "transparent",
            }}>
            {it.icon}
            <span className="text-[9px] font-semibold">{it.label}</span>
          </button>
        );
      })}
    </div>
  );
}

// ── Caregiver bottom nav ───────────────────────────────────────────────────────

function CaregiverBottomNav({
  tab, onTab, color, large,
}: {
  tab: Tab; onTab: (t: Tab) => void; color: string; large: boolean;
}) {
  // Always exactly 5 icons — Schedule and linked-patient data live on Home.
  const items: { key: Tab; icon: React.ReactNode; label: string }[] = [
    { key: "home",      icon: <Users size={large ? 22 : 19} />,         label: "Patient"   },
    { key: "checkin",   icon: <Bell size={large ? 22 : 19} />,          label: "Alerts"    },
    { key: "messages",  icon: <MessageCircle size={large ? 22 : 19} />, label: "Messages"  },
    { key: "analytics", icon: <BarChart2 size={large ? 22 : 19} />,     label: "Analytics" },
    { key: "profile",   icon: <User size={large ? 22 : 19} />,          label: "Profile"   },
  ];
  return (
    <div className="flex bg-white px-1 py-1">
      {items.map(it => {
        const active = tab === it.key;
        return (
          <button key={it.key} onClick={() => onTab(it.key)}
            className="flex-1 flex flex-col items-center justify-center gap-0.5 rounded-xl py-2 transition-all duration-150"
            style={{
              minHeight: large ? 64 : 54,
              color: active ? color : "#9CA3AF",
              transform: active ? "scale(1.08)" : "scale(1)",
              background: active ? `${color}14` : "transparent",
            }}>
            {it.icon}
            <span className="text-[9px] font-semibold">{it.label}</span>
          </button>
        );
      })}
    </div>
  );
}

function CaregiverAlertsContent({ patients, theme }: { patients: PatientSnippet[]; theme: ModeTheme }) {
  const alerts = patients.flatMap(patient => {
    const items: { id: string; patientName: string; message: string; urgent: boolean }[] = [];
    if (patient.accessState === "ok" && patient.grants.includes("fall_alerts") && patient.hasFallAlert) {
      items.push({
        id: `${patient.id}-fall`,
        patientName: patient.name,
        message: "Fall alert requires attention",
        urgent: true,
      });
    }
    if (
      patient.accessState === "ok"
      && patient.grants.includes("med_adherence")
      && patient.medAdherence != null
      && patient.medAdherence < 80
    ) {
      items.push({
        id: `${patient.id}-meds`,
        patientName: patient.name,
        message: `Medication adherence is ${patient.medAdherence}%`,
        urgent: false,
      });
    }
    return items;
  });

  return (
    <div className="flex flex-col min-h-full px-4 pt-4 pb-28 gap-3">
      <p className="text-[13px] text-[#6B7280]">
        Notifications only. Open <span className="font-bold">Your Patient</span> to view all shared information.
      </p>
      {alerts.length === 0 ? (
        <div className="rounded-2xl bg-white border border-[#E5E7EB] p-6 text-center">
          <Bell size={28} className="mx-auto mb-2 text-[#9CA3AF]" />
          <p className="text-[15px] font-bold text-[#0F172A]">No new alerts</p>
          <p className="text-[12px] text-[#9CA3AF] mt-1">Patient alerts will appear here.</p>
        </div>
      ) : alerts.map(alert => (
        <div
          key={alert.id}
          className="rounded-2xl p-4 border flex items-start gap-3"
          style={{
            background: alert.urgent ? "#FEF2F2" : theme.lightBg,
            borderColor: alert.urgent ? "#FCA5A5" : theme.borderColor,
          }}
        >
          <AlertTriangle size={18} style={{ color: alert.urgent ? "#DC2626" : theme.color }} />
          <div>
            <p className="text-[14px] font-bold text-[#0F172A]">{alert.message}</p>
            <p className="text-[12px] text-[#6B7280]">{alert.patientName}</p>
          </div>
        </div>
      ))}
    </div>
  );
}

// ── Feature-aware app top bar ──────────────────────────────────────────────────

function FeatureAppBar({
  tab, theme, role, profileImage, onOpenProfile, onOpenFeaturePicker, accountLabel,
}: {
  tab: Tab; theme: ModeTheme; role: Role;
  profileImage: string | null; onOpenProfile: () => void; onOpenFeaturePicker?: () => void;
  accountLabel?: string;
}) {
  const titleMap: Partial<Record<Tab, string>> = {
    home: role === "caregiver" ? "Your Patient" : "Dashboard",
    meds: "Health", symptoms: "Health", checkin: role === "caregiver" ? "Alerts" : "Virtual Check-In",
    messages: "Messages", schedule: "Schedule", analytics: "Analytics",
    patients: "Your Patient", profile: role === "caregiver" ? "My Profile" : "My Profile",
    hearing: "Hearing Assist", mail: "Mail Digest",
  };
  const title = titleMap[tab] ?? "CareConnect";
  const roleLabel = role === "caregiver" ? "Caregiver" : "Patient / User";

  return (
    <div className="flex items-center justify-between px-4 py-3 bg-white border-b" style={{ borderColor: theme.borderColor, minHeight: 58 }}>
      <div className="flex items-center gap-2 min-w-0">
        <div className="w-2 h-2 rounded-full shrink-0" style={{ background: theme.color }} />
        <div className="min-w-0">
          <p className="text-[10px] font-bold uppercase tracking-wider" style={{ color: theme.color }}>
            {roleLabel}{accountLabel ? ` · ${accountLabel}` : ""}
          </p>
          <h2 className="text-[17px] font-bold text-[#0F172A] leading-tight truncate">{title}</h2>
        </div>
      </div>
      <div className="flex items-center gap-2 shrink-0">
        {role === "patient" && onOpenFeaturePicker && tab !== "profile" && (
          <button onClick={onOpenFeaturePicker}
            className="w-8 h-8 rounded-full flex items-center justify-center"
            style={{ background: theme.lightBg }}
            aria-label="Customize features">
            <Sliders size={14} style={{ color: theme.color }} />
          </button>
        )}
        <button onClick={onOpenProfile}
          className="w-10 h-10 rounded-full overflow-hidden flex items-center justify-center border-2"
          style={{ borderColor: theme.color, background: theme.lightBg }}
          aria-label="Open profile">
          {profileImage
            ? <img src={profileImage} className="w-full h-full object-cover" />
            : <User size={18} style={{ color: theme.color }} />}
        </button>
      </div>
    </div>
  );
}

export default function App() {
  // ── State — all initialised from localStorage where a saved value exists ──
  useState(() => {
    migrateDemoCaregiverData();
    seedPatientSnapshotRegistryFromActive();
    return true;
  });

  const [phase, setPhase]                     = useState<Phase>(() => loadSaved("isSignedIn", false) ? "app" : "splash");
  const [mode, setMode]                       = useState<AppMode | null>(() => loadSaved<AppMode | null>("mode", null));
  const [customSettings, setCustomSettings]   = useState<CustomSettings>(() => loadSaved("customSettings", {}));
  const [tab, setTab]                         = useState<Tab>(() => loadSaved<Tab>("tab", "home"));
  const [role, setRole]                       = useState<Role>(() => loadSaved<Role>("role", "patient"));
  const [showSOS, setShowSOS]                 = useState(false);
  const [profileComplete, setProfileComplete] = useState(() => loadSaved("profileComplete", false));
  const [enabledFeatures, setEnabledFeatures] = useState<FeatureId[]>(() => {
    const saved = loadSaved<FeatureId[]>("enabledFeatures", DEFAULT_PATIENT_FEATURES);
    return saved.includes("usps_mail") ? saved : [...saved, "usps_mail"];
  });
  const [linkedCaregivers, setLinkedCaregivers] = useState<LinkedCaregiver[]>(() => {
    const snap = loadPatientSnapshot();
    if (snap?.linkedCaregivers?.length) {
      return scrubDemoCaregivers(snap.linkedCaregivers);
    }
    return scrubDemoCaregivers(loadSaved("linkedCaregivers", DEFAULT_CAREGIVERS));
  });
  const [activeCaregiverId, setActiveCaregiverId] = useState<string>(() => loadSaved("activeCaregiverId", "cg1"));
  const [caregiverAccount, setCaregiverAccount] = useState<CaregiverAccountInfo>(() =>
    loadCaregiverAccount(loadSaved("activeCaregiverId", "cg1"))
  );
  const [wizardInitialRole, setWizardInitialRole] = useState<Role>("patient");
  const [signInInitialRole, setSignInInitialRole] = useState<Role>("patient");
  const [showFeaturePicker, setShowFeaturePicker] = useState(false);
  const [activePatient, setActivePatient]     = useState<PatientSnippet | null>(null);
  const [openChatId, setOpenChatId]           = useState<string | null>(null);
  const [careTeamMoodAlert, setCareTeamMoodAlert] = useState<LowMoodStreakAlert | null>(() => {
    const existing = loadLowMoodStreakAlert();
    if (!existing) return null;
    const streak = countConsecutiveLowMoodDays(loadMoodHistory());
    return streak >= LOW_MOOD_STREAK_THRESHOLD ? existing : null;
  });

  // Navigation history
  const [navHistory, setNavHistory]           = useState<NavState[]>(() => {
    const saved = loadSaved<NavState[] | null>("navHistory", null);
    return saved ?? [{ phase: loadSaved("isSignedIn", false) ? "app" : "splash" }];
  });
  const [navIndex, setNavIndex]               = useState(() => {
    const saved = loadSaved<NavState[] | null>("navHistory", null);
    return saved ? saved.length - 1 : 0;
  });

  // Home content
  const [stepsDone, setStepsDone]             = useState(() => loadSaved("stepsDone", 0));
  const [tint, setTint]                       = useState(() => loadSaved("tint", true));
  const [readAloud, setReadAloud]             = useState(() => loadSaved("readAloud", true));
  const [voice, setVoice]                     = useState(() => loadSaved("voice", true));
  const [swipe, setSwipe]                     = useState(() => loadSaved("swipe", true));
  const [medsReminder, setMedsReminder]       = useState(() => loadSaved("medsReminder", false));
  const [apptReminder, setApptReminder]       = useState(() => loadSaved("apptReminder", true));

  // Medications & appointments (lifted so they persist)
  const [medications, setMedications]         = useState<Medication[]>(() => loadSaved("medications", DEFAULT_MEDICATIONS));
  const [medsChecked, setMedsChecked]         = useState<Record<string, boolean>>(() => loadSaved("medsChecked", {}));
  const [appointments, setAppointments]       = useState<Appointment[]>(() => loadSaved("appointments", DEFAULT_APPOINTMENTS));
  const [patientMood, setPatientMood]         = useState<number | null>(() => loadSaved<number | null>("patientMood", null));
  const [moodHistory, setMoodHistory]         = useState<MoodEntry[]>(() => loadMoodHistory());
  const [patientLastCheckin, setPatientLastCheckin] = useState(() => loadSaved("patientLastCheckin", ""));
  const [checkinsThisWeek, setCheckinsThisWeek] = useState(() => loadSaved("checkinsThisWeek", 0));
  const [sharedPatientData, setSharedPatientData] = useState<PatientAccountSnapshot | null>(() => {
    const savedRole = loadSaved<Role>("role", "patient");
    if (savedRole === "caregiver") {
      const acct = loadCaregiverAccount(loadSaved("activeCaregiverId", "cg1"));
      return loadPatientSnapshotForCaregiver(acct.linkedPatientName, acct.linkedPatientDob, {
        id: loadSaved("activeCaregiverId", "cg1"),
        name: acct.name,
        email: acct.email,
        inviteCode: acct.linkedInviteCode,
      });
    }
    return loadPatientSnapshot();
  });
  const [hasFallAlert] = useState(() => loadSaved("hasFallAlert", false));

  const [appModal, setAppModal]               = useState<React.ReactNode>(null);
  const clearModal                            = () => setAppModal(null);

  // Profile
  const [profileImage, setProfileImage]       = useState<string | null>(() => {
    try { return localStorage.getItem(IMAGE_KEY); } catch { return null; }
  });
  const [profileName, setProfileName]         = useState(() => loadSaved("profileName", "Your Name"));
  const [profileEmail, setProfileEmail]       = useState(() => loadSaved("profileEmail", ""));
  const [profileDob, setProfileDob]           = useState(() => loadSaved("profileDob", ""));
  const [profileAddress, setProfileAddress]   = useState(() => loadSaved("profileAddress", ""));
  const [profileProvider, setProfileProvider] = useState(() => loadSaved("profileProvider", ""));
  const [profileEmergency, setProfileEmergency] = useState(() => loadSaved("profileEmergency", ""));
  const [profileConditions, setProfileConditions] = useState(() => loadSaved("profileConditions", ""));
  const [profileMeds, setProfileMeds]         = useState(() => loadSaved("profileMeds", ""));
  const [profileAllergies, setProfileAllergies] = useState(() => loadSaved("profileAllergies", ""));
  const [accountPassword, setAccountPassword] = useState(() => loadSaved("accountPassword", ""));
  const [accountPin, setAccountPin] = useState(() => loadSaved("accountPin", ""));
  const [accountColorSeq, setAccountColorSeq] = useState<string[]>(() => loadSaved<string[]>("accountColorSeq", []));
  const [showProfile, setShowProfile]         = useState(false);

  // Accessibility settings
  const [textSize, setTextSize]               = useState<0|1|2>(() => loadSaved<0|1|2>("textSize", 1));
  const [highContrast, setHighContrast]       = useState(() => loadSaved("highContrast", false));
  const [reduceMotion, setReduceMotion]       = useState(() => loadSaved("reduceMotion", false));
  const [readAloudGlobal, setReadAloudGlobal] = useState(() => loadSaved("readAloudGlobal", false));
  const [boldText, setBoldText]               = useState(() => loadSaved("boldText", false));
  const [colorFilter, setColorFilter]         = useState(() => loadSaved("colorFilter", false));
  const [tremorMode, setTremorMode]           = useState(() => loadSaved("tremorMode", false));
  const [confirmActions, setConfirmActions]   = useState(() => loadSaved("confirmActions", true));
  const [vibration, setVibration]             = useState(() => loadSaved("vibration", true));
  const [visualAlerts, setVisualAlerts]       = useState(() => loadSaved("visualAlerts", false));
  const [simplifiedNav, setSimplifiedNav]     = useState(() => loadSaved("simplifiedNav", false));
  const [autoPlay, setAutoPlay]               = useState(() => loadSaved("autoPlay", false));
  const [focusIndicators, setFocusIndicators] = useState(() => loadSaved("focusIndicators", true));
  const [disability, setDisability]           = useState(() => loadSaved("disability", "none"));
  // Hearing
  const [captions, setCaptions]               = useState(() => loadSaved("captions", false));
  const [soundAmplify, setSoundAmplify]       = useState(() => loadSaved("soundAmplify", false));
  const [ttySupport, setTtySupport]           = useState(() => loadSaved("ttySupport", false));
  const [hearingAidMode, setHearingAidMode]   = useState(() => loadSaved("hearingAidMode", false));

  // ── Persist all state to localStorage on every change ──

  const buildSessionSnapshot = (signedIn: boolean): Record<string, unknown> => ({
    isSignedIn: signedIn,
    mode, customSettings, tab, role,
    profileComplete: true,
    enabledFeatures, linkedCaregivers,
    activeCaregiverId,
    navHistory, stepsDone,
    tint, readAloud, voice, swipe, medsReminder, apptReminder,
    medications, medsChecked, appointments,
    patientMood, moodHistory, patientLastCheckin, checkinsThisWeek, hasFallAlert,
    profileName, profileEmail, profileDob, profileAddress,
    profileProvider, profileEmergency, profileConditions,
    profileMeds, profileAllergies, accountPassword,
    accountPin, accountColorSeq,
    textSize, highContrast, boldText, colorFilter, reduceMotion, autoPlay,
    readAloudGlobal, focusIndicators, tremorMode, confirmActions,
    vibration, visualAlerts, simplifiedNav, disability,
    captions, soundAmplify, ttySupport, hearingAidMode,
  });

  useEffect(() => {
    // While onboarding (before a profile exists), still persist progress,
    // but only mark the account complete after profile setup finishes.
    saveAll({
      ...buildSessionSnapshot(phase === "app"),
      profileComplete,
    });
  }, [
    phase, mode, customSettings, tab, role,
    profileComplete, enabledFeatures, linkedCaregivers,
    activeCaregiverId,
    navHistory, stepsDone,
    tint, readAloud, voice, swipe, medsReminder, apptReminder,
    medications, medsChecked, appointments,
    patientMood, moodHistory, patientLastCheckin, checkinsThisWeek, hasFallAlert,
    profileName, profileEmail, profileDob, profileAddress,
    profileProvider, profileEmergency, profileConditions,
    profileMeds, profileAllergies, accountPassword,
    accountPin, accountColorSeq,
    textSize, highContrast, boldText, colorFilter, reduceMotion, autoPlay,
    readAloudGlobal, focusIndicators, tremorMode, confirmActions,
    vibration, visualAlerts, simplifiedNav, disability,
    captions, soundAmplify, ttySupport, hearingAidMode,
  ]);

  // Persist profile image separately (large base64 string)
  useEffect(() => {
    try {
      if (profileImage) localStorage.setItem(IMAGE_KEY, profileImage);
      else localStorage.removeItem(IMAGE_KEY);
    } catch {}
  }, [profileImage]);

  // Keep a patient-account snapshot so caregivers can view granted data without
  // overwriting (or losing) the patient's active profile when switching roles.
  useEffect(() => {
    if (role !== "patient" || !profileComplete) return;
    if (!profileName || profileName === "Your Name") return;
    const snap: PatientAccountSnapshot = {
      profileComplete: true,
      profileName,
      profileDob,
      profileConditions,
      profileAllergies,
      profileMeds,
      linkedCaregivers,
      medications,
      medsChecked,
      appointments,
      mood: patientMood,
      moodHistory,
      lastCheckin: patientLastCheckin || undefined,
      checkinsThisWeek,
      hasFallAlert,
      lowMoodStreakAlert: loadLowMoodStreakAlert(),
    };
    savePatientSnapshot(snap);
    setSharedPatientData(snap);
  }, [
    role, profileComplete, profileName, profileDob, profileConditions,
    profileAllergies, profileMeds, linkedCaregivers, medications, medsChecked, appointments,
    patientMood, moodHistory, patientLastCheckin, checkinsThisWeek, hasFallAlert,
  ]);

  // When signing in as caregiver, load the shared patient snapshot into view state.
  // Also re-read on a short interval / focus so grants the patient just toggled appear.
  useEffect(() => {
    if (role !== "caregiver") return;
    const refresh = () => {
      const acct = loadCaregiverAccount(activeCaregiverId);
      const caregiverRef = {
        id: activeCaregiverId,
        name: acct.name,
        email: acct.email,
        inviteCode: acct.linkedInviteCode,
      };
      const snap = loadPatientSnapshotForCaregiver(
        acct.linkedPatientName,
        acct.linkedPatientDob,
        caregiverRef,
      );
      // Keep linked patient name aligned with the snapshot we actually resolved.
      if (
        snap?.profileName
        && snap.profileName !== "Your Name"
        && acct.linkedPatientName?.trim()
        && !namesMatch(acct.linkedPatientName, snap.profileName)
        && !namesLooselyMatch(acct.linkedPatientName, snap.profileName)
      ) {
        const repaired = {
          ...acct,
          linkedPatientName: snap.profileName,
          linkedPatientDob: snap.profileDob || acct.linkedPatientDob,
        };
        saveCaregiverAccount(activeCaregiverId, repaired);
        setCaregiverAccount(repaired);
      }
      let circle = scrubDemoCaregivers(snap?.linkedCaregivers ?? []);
      // Re-apply invite / name / email matching so patient grants show after approval.
      if (acct.name || acct.linkedInviteCode || acct.email) {
        circle = activateInviteInCareCircle(circle, {
          inviteCode: acct.linkedInviteCode,
          caregiverId: activeCaregiverId,
          caregiverName: acct.name || "Caregiver",
          caregiverEmail: acct.email,
          caregiverPhone: acct.phone,
          relationship: acct.relationshipToPatient || "Caregiver",
        });
        if (snap) {
          const changed = JSON.stringify(circle) !== JSON.stringify(snap.linkedCaregivers ?? []);
          if (changed) {
            const nextSnap = { ...snap, linkedCaregivers: circle };
            savePatientSnapshot(nextSnap);
            setSharedPatientData(nextSnap);
          } else {
            setSharedPatientData(snap);
          }
        } else {
          setSharedPatientData(null);
        }
      } else {
        setSharedPatientData(snap);
      }
      if (circle.length) setLinkedCaregivers(circle);
      if (snap?.appointments) setAppointments(snap.appointments);
      if (snap?.medications) setMedications(snap.medications);
      if (snap?.medsChecked) setMedsChecked(snap.medsChecked);
      if (snap?.mood != null) setPatientMood(snap.mood);
      if (snap?.moodHistory) setMoodHistory(snap.moodHistory);
      if (snap?.lastCheckin) setPatientLastCheckin(snap.lastCheckin);
      if (snap?.checkinsThisWeek != null) setCheckinsThisWeek(snap.checkinsThisWeek);
    };
    refresh();
    const onFocus = () => refresh();
    window.addEventListener("focus", onFocus);
    const timer = window.setInterval(refresh, 2000);
    return () => {
      window.removeEventListener("focus", onFocus);
      window.clearInterval(timer);
    };
  }, [role, activeCaregiverId]);

  // Patient session: pull Care Circle (incl. access requests) from the shared snapshot
  useEffect(() => {
    if (role !== "patient" || phase !== "app") return;
    const snap = loadPatientSnapshot();
    setSharedPatientData(snap);
    if (!snap?.linkedCaregivers?.length) return;
    const snapCircle = scrubDemoCaregivers(snap.linkedCaregivers);
    setLinkedCaregivers(prev => {
      const snapHasPending = snapCircle.some(
        c => (c.pendingGrantRequests?.length ?? 0) > 0 || (c.status === "pending" && !c.addedByPatient),
      );
      const localHasPending = prev.some(
        c => (c.pendingGrantRequests?.length ?? 0) > 0 || (c.status === "pending" && !c.addedByPatient),
      );
      if (snapHasPending || !localHasPending || snapCircle.length >= prev.length) {
        return snapCircle;
      }
      return prev;
    });
  }, [role, phase]);

  // Caregiver schedule/med updates write back so Analytics stays in sync
  useEffect(() => {
    if (role !== "caregiver") return;
    setSharedPatientData(prev => {
      const base = prev ?? loadPatientSnapshotForCaregiver(
        caregiverAccount.linkedPatientName,
        caregiverAccount.linkedPatientDob,
        {
          id: activeCaregiverId,
          name: caregiverAccount.name,
          email: caregiverAccount.email,
          inviteCode: caregiverAccount.linkedInviteCode,
        },
      );
      if (!base) return prev;
      const next: PatientAccountSnapshot = {
        ...base,
        appointments,
        medications,
        medsChecked,
        mood: patientMood,
        moodHistory,
        lastCheckin: patientLastCheckin || base.lastCheckin,
        checkinsThisWeek,
        hasFallAlert,
      };
      const same =
        JSON.stringify(base.appointments) === JSON.stringify(next.appointments) &&
        JSON.stringify(base.medications) === JSON.stringify(next.medications) &&
        JSON.stringify(base.medsChecked) === JSON.stringify(next.medsChecked) &&
        JSON.stringify(base.moodHistory ?? []) === JSON.stringify(next.moodHistory ?? []) &&
        base.mood === next.mood &&
        base.lastCheckin === next.lastCheckin &&
        base.checkinsThisWeek === next.checkinsThisWeek;
      if (same) return prev;
      savePatientSnapshot(next);
      return next;
    });
  }, [role, appointments, medications, medsChecked, patientMood, moodHistory, patientLastCheckin, checkinsThisWeek, hasFallAlert, caregiverAccount.linkedPatientName, caregiverAccount.linkedPatientDob]);

  // Load the selected caregiver's own account details (separate from patient profile)
  useEffect(() => {
    if (role !== "caregiver") return;
    setCaregiverAccount(loadCaregiverAccount(activeCaregiverId));
  }, [role, activeCaregiverId]);

  // ── Navigation helpers ──

  const applyState = (state: NavState) => {
    setPhase(state.phase);
    if (state.tab !== undefined) setTab(state.tab);
  };

  const navigate = (state: NavState) => {
    const newHistory = navHistory.slice(0, navIndex + 1).concat(state);
    setNavHistory(newHistory);
    setNavIndex(newHistory.length - 1);
    applyState(state);
  };

  const goBack = () => {
    if (navIndex <= 0) return;
    const state = navHistory[navIndex - 1];
    setNavIndex(navIndex - 1);
    applyState(state);
  };

  const goForward = () => {
    if (navIndex >= navHistory.length - 1) return;
    const state = navHistory[navIndex + 1];
    setNavIndex(navIndex + 1);
    applyState(state);
  };

  // When Hearing accessibility mode is active, keep Conversation Assist enabled.
  // Must stay above phase early-returns so hook order is stable across splash → app.
  useEffect(() => {
    if (phase !== "app") return;
    if (mode === "hearing") {
      setCaptions(true);
      setEnabledFeatures(prev =>
        prev.includes("hearing_assist") ? prev : [...prev, "hearing_assist"]
      );
      return;
    }
    if (tab === "hearing") {
      navigate({ phase: "app", tab: "home" });
    }
  }, [mode, phase, tab]);

  const nav: NavProps = {
    canGoBack:    navIndex > 0,
    canGoForward: navIndex < navHistory.length - 1,
    onBack:    goBack,
    onForward: goForward,
  };

  // ── Onboarding phases ──

  // ── Pre-profile routing ──

  if (phase === "splash") {
    return (
      <HeroLanding
        hasSavedProfile={profileComplete}
        savedName={profileName !== "Your Name" ? profileName : undefined}
        onCreateProfile={(preferredRole) => {
          setWizardInitialRole(preferredRole ?? "patient");
          navigate({ phase: "profile-create" });
        }}
        onSignIn={(preferredRole) => {
          setSignInInitialRole(preferredRole ?? "patient");
          navigate({ phase: "signin" });
        }}
      />
    );
  }

  if (phase === "signin") {
    return (
      <SignInScreen
        key={signInInitialRole}
        nav={nav}
        savedEmail={profileEmail}
        savedPassword={accountPassword}
        savedPin={accountPin}
        savedColorSeq={accountColorSeq}
        savedName={profileName !== "Your Name" ? profileName : undefined}
        initialRole={signInInitialRole}
        onSuccess={(loginRole, caregiverId) => {
          setRole(loginRole);
          if (loginRole === "caregiver") {
            const cgId = caregiverId || activeCaregiverId || "cg1";
            setActiveCaregiverId(cgId);
            const account = loadCaregiverAccount(cgId);
            setCaregiverAccount(account);
            const hasAuth = !!(account.password?.trim() || account.pin?.trim() || (account.colorSeq && account.colorSeq.length === 3));
            if (!hasAuth) {
              setWizardInitialRole("caregiver");
              navigate({ phase: "profile-create" });
              return;
            }
          } else {
            const hasAuth = !!(accountPassword?.trim() || accountPin?.trim() || accountColorSeq.length === 3);
            const savedComplete = profileComplete || loadSaved("profileComplete", false);
            if (!savedComplete || !hasAuth) {
              setWizardInitialRole("patient");
              navigate({ phase: "profile-create" });
              return;
            }
          }
          setProfileComplete(true);
          const lastTab = loadSaved<Tab>("tab", "home");
          const nextTab = lastTab && lastTab !== "profile" ? lastTab : "home";
          const cgIdForSave = loginRole === "caregiver" ? (caregiverId ?? activeCaregiverId) : activeCaregiverId;
          saveAll({
            ...buildSessionSnapshot(true),
            profileComplete: true,
            role: loginRole,
            activeCaregiverId: cgIdForSave,
            tab: nextTab,
            navHistory: [{ phase: "app", tab: nextTab }],
          });
          setNavHistory([{ phase: "app", tab: nextTab }]);
          setNavIndex(0);
          setPhase("app");
          setTab(nextTab);
        }}
      />
    );
  }

  if (phase === "profile-create" || phase === "role" || phase === "landing" || phase === "builder") {
    return (
      <ProfileWizard
        key={wizardInitialRole}
        initialRole={wizardInitialRole}
        knownPatientName=""
        knownPatientDob=""
        onBack={() => navigate({ phase: "splash" })}
        onComplete={profile => {
          const savedPassword = profile.authMethods.password ? profile.password.trim() : "";
          const savedPin = profile.authMethods.pin ? profile.pin : "";
          const savedColorSeq = profile.authMethods.color ? profile.colorSeq : [];
          setRole(profile.role);
          setProfileName(profile.name.trim() || "Your Name");
          setProfileEmail(profile.email.trim());
          setProfileDob(profile.dob.trim());
          setProfileAddress(profile.address.trim());
          setProfileProvider(profile.provider.trim());
          setProfileEmergency(profile.emergencyContact.trim());
          setProfileConditions(profile.conditions.trim());
          setProfileMeds(profile.meds.trim());
          setProfileAllergies(profile.allergies.trim());
          if (profile.role === "patient") {
            setAccountPassword(savedPassword);
            setAccountPin(savedPin);
            setAccountColorSeq(savedColorSeq);
          }
          if (profile.role === "caregiver" && profile.caregiverPersonaId) {
            setActiveCaregiverId(profile.caregiverPersonaId);
            const inviteParsed = parseInviteFromUrl(profile.inviteCode || "");
            const inviteCode = inviteParsed?.code || profile.inviteCode?.trim() || "";
            const linkedPatientName = profile.linkedPatientName?.trim() || "";
            const linkedPatientDob = normalizeDob(profile.linkedPatientDob || "") || profile.linkedPatientDob?.trim() || "";
            const relationshipToPatient = profile.caregiverRelation?.trim() || "";
            const enteredName = profile.name.trim();
            if (!enteredName || isDemoCaregiverName(enteredName)) {
              // Keep going with a clear placeholder only if somehow empty; wizard should block this
            }
            const account = loadCaregiverAccount(profile.caregiverPersonaId);
            const seeded: CaregiverAccountInfo = {
              ...account,
              name: enteredName || "Caregiver",
              email: profile.email.trim(),
              agency: profile.organization.trim() || profile.address.trim(),
              credentials: profile.conditions.trim(),
              phone: profile.emergencyContact.trim(),
              password: savedPassword,
              pin: savedPin,
              colorSeq: savedColorSeq,
              linkedPatientName,
              linkedPatientDob: linkedPatientDob || undefined,
              linkedInviteCode: inviteCode || undefined,
              relationshipToPatient: relationshipToPatient || undefined,
            };
            setCaregiverAccount(seeded);
            saveCaregiverAccount(profile.caregiverPersonaId, seeded);

            // Activate matching Care Circle invite for this caregiver + patient only
            if (inviteCode || linkedPatientName) {
              const snap = loadPatientSnapshotForCaregiver(linkedPatientName, linkedPatientDob, {
                id: profile.caregiverPersonaId,
                name: seeded.name,
                email: seeded.email,
                inviteCode: inviteCode || undefined,
              });
              const circle = scrubDemoCaregivers(snap?.linkedCaregivers ?? linkedCaregivers);
              const finalCircle = activateInviteInCareCircle(circle, {
                inviteCode,
                caregiverId: profile.caregiverPersonaId,
                caregiverName: seeded.name,
                caregiverEmail: seeded.email,
                caregiverPhone: seeded.phone,
                relationship: relationshipToPatient
                  || CAREGIVER_PERSONAS.find(p => p.id === profile.caregiverPersonaId)?.label
                  || "Caregiver",
              });
              setLinkedCaregivers(finalCircle);
              if (snap) {
                const nextSnap = { ...snap, linkedCaregivers: finalCircle };
                savePatientSnapshot(nextSnap);
                setSharedPatientData(nextSnap);
              }
            }
          }
          if (profile.accessibilityMode) setMode(profile.accessibilityMode);
          if (profile.role === "patient") setEnabledFeatures(profile.enabledFeatures);
          setProfileComplete(true);
          saveAll({
            ...JSON.parse(localStorage.getItem(PROFILE_KEY) ?? "{}"),
            isSignedIn: true,
            profileComplete: true,
            role: profile.role,
            activeCaregiverId: profile.caregiverPersonaId ?? activeCaregiverId,
            profileName: profile.name.trim() || "Your Name",
            profileEmail: profile.email.trim(),
            ...(profile.role === "patient" ? {
              accountPassword: savedPassword,
              accountPin: savedPin,
              accountColorSeq: savedColorSeq,
            } : {}),
            profileDob: profile.dob.trim(),
            profileAddress: profile.address.trim(),
            profileProvider: profile.provider.trim(),
            profileEmergency: profile.emergencyContact.trim(),
            profileConditions: profile.conditions.trim(),
            profileMeds: profile.meds.trim(),
            profileAllergies: profile.allergies.trim(),
            mode: profile.accessibilityMode,
            enabledFeatures: profile.role === "patient" ? profile.enabledFeatures : loadSaved("enabledFeatures", DEFAULT_PATIENT_FEATURES),
          });
          navigate({ phase: "app", tab: "home" });
        }}
      />
    );
  }

  // ── Main app ──

  const theme    = getTheme(mode);
  const has      = (id: string) => mode === "custom" ? !!customSettings[id] : false;
  const useLarge   = mode === "carpal" || has("ct_targets") || tremorMode;
  const useLexend  = mode === "dyslexia" || has("dys_font") || disability === "dyslexia_cond";
  const useTint    = (mode === "dyslexia" && tint) || (mode === "custom" && !!customSettings["dys_tint"]) || disability === "dyslexia_cond";
  const useSpacing = mode === "dyslexia" || has("dys_spacing") || disability === "dyslexia_cond";
  const textScale  = [1, 1.125, 1.25][textSize] ?? 1;

  // Caregiver roster resolves the linked patient from the multi-patient registry
  // (not whoever last signed in on this browser).
  const patientSnapshot = role === "caregiver"
    ? (sharedPatientData ?? loadPatientSnapshotForCaregiver(
        caregiverAccount.linkedPatientName,
        caregiverAccount.linkedPatientDob,
        {
          id: activeCaregiverId,
          name: caregiverAccount.name,
          email: caregiverAccount.email,
          inviteCode: caregiverAccount.linkedInviteCode,
        },
      ))
    : (sharedPatientData ?? loadPatientSnapshot());
  const patientSource = patientSnapshot ?? (
    role !== "caregiver"
    && profileComplete
    && profileName
    && profileName !== "Your Name"
      ? {
          profileComplete: true,
          profileName,
          profileDob,
          profileConditions,
          profileAllergies,
          profileMeds,
          linkedCaregivers,
          medications,
          medsChecked,
          appointments,
          mood: patientMood,
          lastCheckin: patientLastCheckin || undefined,
          checkinsThisWeek,
          hasFallAlert,
        }
      : null
  );
  const medTotal = Math.max(1, (patientSource?.medications.length ?? medications.length) || 1);
  const medTaken = Object.values(patientSource?.medsChecked ?? medsChecked).filter(Boolean).length;
  const liveMedAdherence = Math.round((medTaken / medTotal) * 100);
  const nextAppt = (patientSource?.appointments ?? appointments)[0];
  const caregiverPersona = CAREGIVER_PERSONAS.find(p => p.id === activeCaregiverId);

  const loggedSymptomsForSummary = loadLoggedSymptoms();
  const loggedAllergiesForSummary = loadLoggedAllergies();
  const circleForRoster =
    (patientSource?.linkedCaregivers && patientSource.linkedCaregivers.length > 0)
      ? patientSource.linkedCaregivers
      : linkedCaregivers;
  const patientSnippets: PatientSnippet[] = role === "caregiver"
    ? buildCaregiverPatientRoster({
        caregiverId: activeCaregiverId,
        linkedCaregivers: circleForRoster,
        patientActive: !!(patientSource?.profileComplete ?? (patientSource?.profileName && patientSource.profileName !== "Your Name")),
        profileName: patientSource?.profileName ?? "",
        profileDob: (patientSource?.profileDob || caregiverAccount.linkedPatientDob || "").trim(),
        profileConditions: patientSource?.profileConditions ?? "",
        profileAllergies: patientSource?.profileAllergies ?? "",
        medAdherence: liveMedAdherence,
        nextVisit: nextAppt ? `${nextAppt.date} ${nextAppt.time}` : undefined,
        symptomsSummary: patientSource
          ? [
              loggedSymptomsForSummary.length
                ? `Symptoms: ${loggedSymptomsForSummary.slice(0, 3).map(s => s.name).join(", ")}`
                : "",
              loggedAllergiesForSummary.length
                ? `Allergies: ${loggedAllergiesForSummary.slice(0, 3).map(a => a.name).join(", ")}`
                : (!loggedAllergiesForSummary.length && patientSource.profileAllergies
                    ? `Allergies: ${patientSource.profileAllergies}`
                    : ""),
              patientSource.profileConditions && `Conditions: ${patientSource.profileConditions}`,
              patientSource.profileMeds && `Meds: ${patientSource.profileMeds}`,
            ]
              .filter(Boolean).join(" · ") || undefined
          : undefined,
        mood: patientSource?.mood ?? patientMood ?? undefined,
        lastCheckin: patientSource?.lastCheckin ?? patientLastCheckin ?? undefined,
        hasFallAlert: patientSource?.hasFallAlert ?? hasFallAlert,
        linkedPatientName: caregiverAccount.linkedPatientName,
        linkedPatientDob: caregiverAccount.linkedPatientDob,
        linkedInviteCode: caregiverAccount.linkedInviteCode,
        caregiverName: caregiverAccount.name,
        caregiverEmail: caregiverAccount.email,
      })
    : [];

  const shellBg   = highContrast ? "bg-white" : useTint ? "bg-[#FFFDF0]" : "bg-white";
  const fontStyle: React.CSSProperties = {
    fontFamily: useLexend ? "'Lexend','Roboto',sans-serif" : "'Roboto',sans-serif",
    fontWeight: boldText || highContrast ? 600 : undefined,
    fontSize: `${textScale * 100}%`,
    ...(useSpacing ? { letterSpacing: "0.03em", wordSpacing: "0.1em" } : {}),
    ...(highContrast ? { color: "#000000", WebkitFontSmoothing: "antialiased" as const } : {}),
    ...(colorFilter ? { filter: "grayscale(0.15) contrast(1.1)" } : {}),
    ...(reduceMotion ? { scrollBehavior: "auto" as const } : {}),
  };

  const handleSetMode = (m: AppMode) => {
    setMode(m);
    setShowProfile(false);
    if (m === "hearing") {
      setCaptions(true);
      setVisualAlerts(true);
      setVibration(true);
      setEnabledFeatures(prev =>
        prev.includes("hearing_assist") ? prev : [...prev, "hearing_assist"]
      );
    }
  };
  const goToTab = (t: Tab) => navigate({ phase: "app", tab: t });

  const doSignOut = () => {
    // Flush the full session to storage before leaving so login restores everything
    const signedOutHistory: NavState[] = [{ phase: "splash" }];
    try {
      saveAll({
        ...buildSessionSnapshot(false),
        isSignedIn: false,
        profileComplete: true,
        navHistory: signedOutHistory,
        // Keep the current tab so login can restore context, but leave the app
        tab: tab === "profile" ? "home" : tab,
      });
      if (profileImage) localStorage.setItem(IMAGE_KEY, profileImage);
    } catch {}

    setShowProfile(false);
    setShowFeaturePicker(false);
    setActivePatient(null);
    setAppModal(null);
    setShowSOS(false);
    // Keep React state for profile/settings/features — only leave the signed-in phase
    setNavHistory(signedOutHistory);
    setNavIndex(0);
    setPhase("splash");
  };

  const toggleFeature = (id: FeatureId) => {
    setEnabledFeatures(prev =>
      prev.includes(id) ? prev.filter(f => f !== id) : [...prev, id]
    );
  };

  // ── Active overlay stack (patient vs caregiver differ) ──

  const activeOverlay: React.ReactNode =
    showSOS ? <SOSOverlay onClose={() => setShowSOS(false)} /> :
    showFeaturePicker && role === "patient" ? (
      <FeaturePickerSheet
        enabledFeatures={enabledFeatures}
        onToggle={toggleFeature}
        onClose={() => setShowFeaturePicker(false)}
        onOpenMail={() => goToTab("mail")}
      />
    ) :
    activePatient && role === "caregiver" ? (
      <CaregiverPatientDetail
        patient={patientSnippets.find(p => p.id === activePatient.id) ?? activePatient}
        onClose={() => setActivePatient(null)}
        theme={theme}
        medications={patientSource?.medications}
        medsChecked={patientSource?.medsChecked}
        appointments={patientSource?.appointments}
        moodHistory={patientSource?.moodHistory ?? moodHistory}
        caregiverId={activeCaregiverId ?? undefined}
        caregiverName={caregiverAccount.name}
        onRequestAccess={(items) => {
          if (!activeCaregiverId || !items.length) return;
          setLinkedCaregivers(prev => {
            const matchIdx = prev.findIndex(cg =>
              cg.id === activeCaregiverId ||
              namesMatch(cg.name, caregiverAccount.name || "")
            );
            let next: LinkedCaregiver[];
            if (matchIdx >= 0) {
              next = prev.map((cg, i) => {
                if (i !== matchIdx) return cg;
                const merged = Array.from(new Set([...(cg.pendingGrantRequests ?? []), ...items]))
                  .filter(item => !cg.grants.includes(item));
                return { ...cg, pendingGrantRequests: merged };
              });
            } else {
              if (!canAddCaregiver(prev)) return prev;
              next = [
                ...prev,
                {
                  id: activeCaregiverId,
                  name: caregiverAccount.name || "Caregiver",
                  relationship: caregiverAccount.relationshipToPatient || caregiverPersona?.label || "Caregiver",
                  initials: makeInitials(caregiverAccount.name || "CG"),
                  email: caregiverAccount.email,
                  phone: caregiverAccount.phone,
                  grants: [],
                  status: "pending" as const,
                  pendingGrantRequests: items,
                  addedByPatient: false,
                },
              ];
            }
            const snap = role === "caregiver"
              ? loadPatientSnapshotForCaregiver(
                  caregiverAccount.linkedPatientName,
                  caregiverAccount.linkedPatientDob,
                  {
                    id: activeCaregiverId,
                    name: caregiverAccount.name,
                    email: caregiverAccount.email,
                    inviteCode: caregiverAccount.linkedInviteCode,
                  },
                )
              : loadPatientSnapshot();
            if (snap) {
              const nextSnap = { ...snap, linkedCaregivers: next };
              savePatientSnapshot(nextSnap);
              setSharedPatientData(nextSnap);
            } else if (profileComplete && profileName && profileName !== "Your Name") {
              const nextSnap: PatientAccountSnapshot = {
                profileComplete: true,
                profileName,
                profileDob,
                profileConditions,
                profileAllergies,
                profileMeds,
                linkedCaregivers: next,
                medications,
                medsChecked,
                appointments,
                mood: patientMood,
                moodHistory,
                lastCheckin: patientLastCheckin || undefined,
                checkinsThisWeek,
                hasFallAlert,
              };
              savePatientSnapshot(nextSnap);
              setSharedPatientData(nextSnap);
            }
            return next;
          });
        }}
      />
    ) :
    appModal ? appModal :
    null;

  // SOS FAB must NOT go through the full-screen overlay — that blocked all Dashboard clicks
  const sosFab = role === "patient" && tab === "home" && !showSOS ? (
    <button
      onClick={() => setShowSOS(true)}
      className="absolute bottom-20 right-4 z-40 w-14 h-14 rounded-full flex items-center justify-center"
      style={{ background: "#EF4444", boxShadow: "0 4px 20px rgba(239,68,68,0.4)" }}
      aria-label="SOS">
      <Phone size={20} className="text-white" />
    </button>
  ) : null;

  // ── Conditional dashboard widget for patient home ──
  const logMood = (score: number, symptom?: string) => {
    setPatientMood(score);
    const cleaned = symptom?.trim();
    const isNone = !cleaned || cleaned === NONE_SYMPTOM;
    const linked = isNone ? NONE_SYMPTOM : cleaned;

    setMoodHistory(prev => {
      const next = upsertMoodHistory(prev, score, { symptom: linked });
      if (score <= 2) {
        const alert = maybeNotifyCareTeamLowMoodStreak({
          history: next,
          score,
          patientName: profileName,
          symptom: linked,
          linkedCaregivers,
        });
        if (alert) {
          window.setTimeout(() => setCareTeamMoodAlert(alert), 0);
        } else {
          const streak = countConsecutiveLowMoodDays(next);
          if (streak >= LOW_MOOD_STREAK_THRESHOLD) {
            window.setTimeout(() => setCareTeamMoodAlert(loadLowMoodStreakAlert()), 0);
          }
        }
      } else {
        // Streak broken — clear banner (keep alert record for caregiver history)
        window.setTimeout(() => setCareTeamMoodAlert(null), 0);
      }
      return next;
    });

    if (!isNone && cleaned) {
      syncSymptomFromMoodLog(cleaned, score);
    }
  };

  const patientHomeWidgets = (
    <>
      {linkedCaregivers.some(cg =>
        (cg.pendingGrantRequests?.length ?? 0) > 0
        || (cg.status === "pending" && !cg.addedByPatient)
      ) && (
        <div className="mx-4 mt-3 rounded-2xl px-4 py-3 flex flex-col gap-2"
          style={{ background: "#EFF6FF", border: "1.5px solid #BFDBFE" }}>
          <div className="flex items-start gap-2">
            <Bell size={18} className="text-[#2563EB] shrink-0 mt-0.5" />
            <div className="flex-1 min-w-0">
              <p className="text-[14px] font-bold text-[#1E40AF]">Caregiver access needs your approval</p>
              <p className="text-[12px] text-[#1D4ED8] mt-0.5 leading-relaxed">
                {linkedCaregivers
                  .filter(cg =>
                    (cg.pendingGrantRequests?.length ?? 0) > 0
                    || (cg.status === "pending" && !cg.addedByPatient)
                  )
                  .map(cg => {
                    const reqs = (cg.pendingGrantRequests ?? []).map(i => GRANTED_LABELS[i]).join(", ");
                    return reqs
                      ? `${cg.name} requested: ${reqs}`
                      : `${cg.name} requested to join your Care Circle`;
                  })
                  .join(" · ")}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={() => goToTab("profile")}
            className="w-full py-2.5 rounded-xl text-[13px] font-bold text-white"
            style={{ background: "#2563EB" }}
          >
            Review in Care Circle
          </button>
        </div>
      )}
      {enabledFeatures.includes("usps_mail") && (
        <div className="mx-4 mt-3 rounded-2xl px-4 py-3 flex flex-col gap-2"
          style={{ background: "#F0FDFA", border: "1.5px solid #99F6E4" }}>
          <div className="flex items-start gap-2">
            <Mail size={18} className="text-[#0F766E] shrink-0 mt-0.5" />
            <div className="flex-1 min-w-0">
              <p className="text-[14px] font-bold text-[#115E59]">USPS Mail Digest</p>
              <p className="text-[12px] text-[#0F766E] mt-0.5 leading-relaxed">
                Connect your email to see today’s Informed Delivery mail, ranked by priority.
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={() => goToTab("mail")}
            className="w-full py-2.5 rounded-xl text-[13px] font-bold text-white"
            style={{ background: "#0D9488" }}
          >
            Open Mail · Connect email
          </button>
        </div>
      )}
      {enabledFeatures.length === 0 && (
        <div className="mx-4 mt-4 p-4 rounded-2xl border-2 border-dashed border-[#00A7C8]/40 text-center">
          <p className="text-[14px] font-semibold text-[#00A7C8] mb-1">Add features to your app</p>
          <p className="text-[12px] text-[#9CA3AF] mb-3">Turn on the tools that matter to you from your Profile.</p>
          <button onClick={() => goToTab("profile")} className="px-4 py-2 rounded-xl text-[13px] font-bold text-white" style={{ background: "#00A7C8" }}>
            Set up my features
          </button>
        </div>
      )}
      <div className="px-4 pt-4">
        <MoodWidget
          theme={theme}
          mood={patientMood}
          moodHistory={moodHistory}
          onMoodChange={logMood}
          careTeamAlert={careTeamMoodAlert}
          onOpenMessages={() => {
            setOpenChatId("c1");
            goToTab("messages");
          }}
        />
      </div>
    </>
  );

  return (
    <PhoneShell
      shellBg={shellBg}
      nav={nav}
      overlay={activeOverlay}
      floatingAction={sosFab}
      topBar={
        <FeatureAppBar
          tab={tab} theme={theme} role={role}
          profileImage={profileImage}
          accountLabel={role === "caregiver"
            ? (caregiverAccount.name || caregiverPersona?.name)
            : (profileName !== "Your Name" ? profileName.split(" ")[0] : undefined)}
          onOpenProfile={() => goToTab("profile")}
          onOpenFeaturePicker={role === "patient" ? () => setShowFeaturePicker(true) : undefined}
        />
      }
      bottomNav={
        role === "patient" ? (
          <PatientBottomNav
            tab={tab} onTab={goToTab}
            enabledFeatures={enabledFeatures}
            accessibilityMode={mode}
            color={theme.color} large={useLarge}
            onOpenFeaturePicker={() => setShowFeaturePicker(true)}
          />
        ) : (
          <CaregiverBottomNav
            tab={tab} onTab={goToTab} color={theme.color} large={useLarge}
          />
        )
      }
    >
      <div style={fontStyle}>

        {/* ═══════════ PATIENT APP ═══════════ */}
        {role === "patient" && (
          <>
            {tab === "home" && (
              <>
                {patientHomeWidgets}
                <HomeContent
                  mode={mode} customSettings={customSettings}
                  tint={tint} setTint={setTint}
                  readAloud={readAloud} setReadAloud={setReadAloud}
                  voice={voice} setVoice={setVoice}
                  swipe={swipe} setSwipe={setSwipe}
                  medsReminder={medsReminder} setMedsReminder={setMedsReminder}
                  apptReminder={apptReminder} setApptReminder={setApptReminder}
                  stepsDone={stepsDone} setStepsDone={setStepsDone}
                  onGoSettings={() => goToTab("profile")}
                  captions={captions} setCaptions={setCaptions}
                  visualAlerts={visualAlerts} setVisualAlerts={setVisualAlerts}
                  vibration={vibration} setVibration={setVibration}
                  medications={medications}
                  medsChecked={medsChecked}
                  setMedsChecked={setMedsChecked}
                  providerName={profileProvider || "Dr. Sarah Patel, MD"}
                  onMessageProvider={() => {
                    setOpenChatId("c1"); // Dr. Sarah Patel conversation
                    goToTab("messages");
                  }}
                  onOpenHearingAssist={() => goToTab("hearing")}
                  appointments={appointments}
                  setAppointments={setAppointments}
                  setModal={setAppModal}
                  clearModal={clearModal}
                  useLargeSchedule={useLarge}
                  onOpenCheckin={() => goToTab("checkin")}
                />
              </>
            )}
            {tab === "hearing" && (mode === "hearing" || enabledFeatures.includes("hearing_assist")) && (
              <HearingAssistContent
                theme={theme}
                onOpenMessages={() => goToTab("messages")}
              />
            )}
            {(tab === "symptoms" || tab === "meds") && (
              <>
                {enabledFeatures.includes("medication_tracker") && (
                  <MedsContent theme={theme} useLarge={useLarge}
                    medications={medications} setMedications={setMedications}
                    medsChecked={medsChecked} setMedsChecked={setMedsChecked}
                    setModal={setAppModal} clearModal={clearModal} />
                )}
                {enabledFeatures.includes("symptoms_tracker") && <SymptomsContent theme={theme} />}
              </>
            )}
            {tab === "mail" && (
              <MailDigestContent theme={theme} readAloudGlobal={readAloudGlobal} />
            )}
            {tab === "checkin" && (
              <VirtualCheckinContent
                theme={theme}
                lastCheckin={patientLastCheckin}
                checkinsThisWeek={checkinsThisWeek}
                onCheckinComplete={({ lastCheckin, score, checkinsThisWeek: week, symptomNote }) => {
                  setPatientLastCheckin(lastCheckin);
                  setCheckinsThisWeek(week);
                  if (score >= 1 && score <= 5) logMood(score, symptomNote);
                }}
              />
            )}
            {/* Schedule moved to Home dashboard — keep tab for deep links / caregiver */}
            {tab === "schedule" && (
              <ScheduleContent theme={theme} useLarge={useLarge}
                appointments={appointments} setAppointments={setAppointments}
                setModal={setAppModal} clearModal={clearModal} />
            )}
            {tab === "messages" && (
              <MessagesContent
                theme={theme}
                initialChatId={openChatId}
                onChatOpened={() => setOpenChatId(null)}
                linkedCaregivers={linkedCaregivers}
                hearingAssist={mode === "hearing" || enabledFeatures.includes("hearing_assist") || captions}
              />
            )}
            {tab === "profile"  && (
              <PatientProfilePage
                profileName={profileName} profileImage={profileImage}
                setProfileImage={setProfileImage} setProfileName={setProfileName}
                profileEmail={profileEmail} setProfileEmail={setProfileEmail}
                profileDob={profileDob} setProfileDob={setProfileDob}
                profileAddress={profileAddress} setProfileAddress={setProfileAddress}
                profileProvider={profileProvider} setProfileProvider={setProfileProvider}
                profileEmergency={profileEmergency} setProfileEmergency={setProfileEmergency}
                profileConditions={profileConditions} setProfileConditions={setProfileConditions}
                profileMeds={profileMeds} setProfileMeds={setProfileMeds}
                profileAllergies={profileAllergies} setProfileAllergies={setProfileAllergies}
                moodHistory={moodHistory} patientMood={patientMood}
                mode={mode} setMode={handleSetMode}
                enabledFeatures={enabledFeatures} onToggleFeature={toggleFeature}
                linkedCaregivers={linkedCaregivers} setLinkedCaregivers={setLinkedCaregivers}
                theme={theme}
                customSettings={customSettings} setCustomSettings={setCustomSettings}
                textSize={textSize} setTextSize={setTextSize}
                highContrast={highContrast} setHighContrast={setHighContrast}
                boldText={boldText} setBoldText={setBoldText}
                colorFilter={colorFilter} setColorFilter={setColorFilter}
                reduceMotion={reduceMotion} setReduceMotion={setReduceMotion}
                autoPlay={autoPlay} setAutoPlay={setAutoPlay}
                readAloudGlobal={readAloudGlobal} setReadAloudGlobal={setReadAloudGlobal}
                focusIndicators={focusIndicators} setFocusIndicators={setFocusIndicators}
                tremorMode={tremorMode} setTremorMode={setTremorMode}
                confirmActions={confirmActions} setConfirmActions={setConfirmActions}
                disability={disability} setDisability={setDisability}
                vibration={vibration} setVibration={setVibration}
                visualAlerts={visualAlerts} setVisualAlerts={setVisualAlerts}
                simplifiedNav={simplifiedNav} setSimplifiedNav={setSimplifiedNav}
                captions={captions} setCaptions={setCaptions}
                soundAmplify={soundAmplify} setSoundAmplify={setSoundAmplify}
                ttySupport={ttySupport} setTtySupport={setTtySupport}
                hearingAidMode={hearingAidMode} setHearingAidMode={setHearingAidMode}
                onSignOut={doSignOut}
              />
            )}
          </>
        )}

        {/* ═══════════ CAREGIVER APP ═══════════ */}
        {role === "caregiver" && (
          <>
            {(tab === "home" || tab === "patients") && (
              <CaregiverHomeV2
                theme={theme}
                patients={patientSnippets}
                viewingAs={
                  !isDemoCaregiverName(caregiverAccount.name)
                    ? `${caregiverRoleLabel(caregiverAccount, activeCaregiverId)} (${caregiverAccount.name})`
                    : "Caregiver (set your name in Profile)"
                }
                onOpenPatient={p => setActivePatient(p)}
                appointments={appointments}
                setAppointments={setAppointments}
                setModal={setAppModal}
                clearModal={clearModal}
                useLarge={useLarge}
              />
            )}
            {tab === "checkin" && (
              <CaregiverAlertsContent patients={patientSnippets} theme={theme} />
            )}
            {tab === "schedule" && (
              <ScheduleContent theme={theme} useLarge={useLarge}
                appointments={appointments} setAppointments={setAppointments}
                setModal={setAppModal} clearModal={clearModal} />
            )}
            {tab === "messages"  && (
              <MessagesContent
                theme={theme}
                messagingMode="caregiver-doctor"
                patientName={patientSource?.profileName || profileName}
                caregiverName={caregiverAccount.name}
                linkedCaregivers={patientSource?.linkedCaregivers ?? linkedCaregivers}
              />
            )}
            {tab === "analytics" && (
              <AnalyticsContent
                theme={theme}
                patients={patientSnippets}
                medications={patientSource?.medications ?? medications}
                medsChecked={patientSource?.medsChecked ?? medsChecked}
                appointments={patientSource?.appointments ?? appointments}
                checkinsThisWeek={patientSource?.checkinsThisWeek ?? checkinsThisWeek}
                moodHistory={patientSource?.moodHistory ?? moodHistory}
                patientMood={patientSource?.mood ?? patientMood}
              />
            )}
            {tab === "profile"   && (
              <CaregiverProfilePage
                account={caregiverAccount}
                onSaveAccount={(info) => {
                  setCaregiverAccount(info);
                  saveCaregiverAccount(activeCaregiverId, info);
                  const snap = loadPatientSnapshotForCaregiver(
                    info.linkedPatientName,
                    info.linkedPatientDob,
                    {
                      id: activeCaregiverId,
                      name: info.name,
                      email: info.email,
                      inviteCode: info.linkedInviteCode,
                    },
                  );
                  setSharedPatientData(snap);
                  if (snap?.linkedCaregivers?.length) {
                    setLinkedCaregivers(scrubDemoCaregivers(snap.linkedCaregivers));
                  }
                  // Keep Care Circle relationship label in sync with who this caregiver is
                  if (info.relationshipToPatient?.trim() && activeCaregiverId) {
                    setLinkedCaregivers(prev => prev.map(cg =>
                      cg.id === activeCaregiverId || namesMatch(cg.name, info.name)
                        ? { ...cg, relationship: info.relationshipToPatient!.trim(), name: info.name || cg.name }
                        : cg
                    ));
                  }
                }}
                profileImage={profileImage}
                setProfileImage={setProfileImage}
                theme={theme}
                onSignOut={doSignOut}
                patients={patientSnippets}
                roleTitle={caregiverRoleLabel(caregiverAccount, activeCaregiverId)}
                medications={patientSource?.medications}
                medsChecked={patientSource?.medsChecked}
                appointments={patientSource?.appointments}
                moodHistory={patientSource?.moodHistory ?? moodHistory}
                showProfessionalDetails={
                  isProfessionalCaregiverPersona(
                    CAREGIVER_PERSONAS.find(p => p.id === activeCaregiverId)?.persona,
                  )
                  || /primary care physician/i.test(caregiverAccount.relationshipToPatient || "")
                }
              />
            )}
          </>
        )}
      </div>
    </PhoneShell>
  );
}
