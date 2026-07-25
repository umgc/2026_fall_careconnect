/**
 * Mail Digest (USPS Informed Delivery) — priority ranking + category taxonomy
 * for managing conversations and mail by impact on the user's well-being.
 *
 * Also covers Capstone PR capabilities:
 * - Textract OCR + fallback (#317)
 * - MailPiece normalization + local persistence / search index (#323)
 * - Rule-based + AI-assist classification (#324)
 * - Natural-language mail search (#325)
 * - Missing-mail-image UI (#326)
 * - Credential revocation / reauth (#327)
 * - ADA audio read-out (#352)
 */

import React, { useEffect, useMemo, useState } from "react";
import {
  AlertTriangle, Link2, Mail, Mic, RefreshCw, Search, Volume2, X, Square,
} from "lucide-react";
import {
  detectEmailProvider,
  isValidEmailFormat,
  type DetectedEmailProvider,
  type EmailProviderId,
} from "../lib/careconnect-core";

export interface ModeTheme {
  color: string;
  lightBg: string;
  borderColor: string;
  name: string;
}

/** Well-being impact ranking (highest urgency first). */
export type MailPriority =
  | "immediate"      // Immediate Attention Needed
  | "action_soon"    // Action Needed Soon
  | "review"         // Review When Convenient
  | "informational"  // Informational Only
  | "promotional";   // Promotional / Low Value

export type MailCategory =
  | "critical"
  | "financial"
  | "deliveries"
  | "personal"
  | "business"
  | "informational"
  | "promotional";

export type MailSubcategory =
  | "legal" | "government" | "medical" | "security_fraud"
  | "bills" | "banking" | "taxes" | "insurance"
  | "packages" | "signature_required" | "missed_delivery"
  | "friends" | "family" | "greeting_cards"
  | "employer" | "payroll" | "hr" | "contracts"
  | "statements" | "school" | "community"
  | "coupons" | "catalogs" | "advertisements";

export type OcrSource = "textract" | "fallback" | "none";
export type CredentialStatus = "connected" | "revoked" | "reauth_required" | "disconnected";

/** @deprecated kept for stored-data migration */
export type MailImportance = "critical" | "important" | "routine" | "junk";

/** Normalized mail piece (PR #323). */
export interface MailPiece {
  id: string;
  digestDate: string;
  senderHint: string;
  subjectHint: string;
  ocrText: string;
  ocrSource: OcrSource;
  imageUrl?: string | null;
  imageMissing: boolean;
  /** Well-being impact priority */
  priority: MailPriority;
  category: MailCategory;
  subcategory: MailSubcategory;
  importanceSource: "rules" | "ai_assist";
  embeddingTokens: string[];
  receivedAt: string;
  /** Legacy field — mapped on load */
  importance?: MailImportance;
}

interface MailDigestStore {
  pieces: MailPiece[];
  credentialStatus: CredentialStatus;
  lastSyncedAt?: string;
  aiAssistEnabled: boolean;
  emailAddress?: string;
  provider?: EmailProviderId;
  authMode?: "oauth" | "imap";
}

const MAIL_STORE_KEY = "careconnect_mail_digest_v2";

export const PRIORITY_META: Record<MailPriority, {
  label: string;
  short: string;
  description: string;
  bg: string;
  color: string;
  rank: number;
}> = {
  immediate: {
    label: "Immediate Attention Needed",
    short: "Immediate",
    description: "Missing this could have serious legal, financial, or health consequences.",
    bg: "#FEE2E2",
    color: "#991B1B",
    rank: 0,
  },
  action_soon: {
    label: "Action Needed Soon",
    short: "Action soon",
    description: "Requires a response within a few days or weeks.",
    bg: "#FFEDD5",
    color: "#9A3412",
    rank: 1,
  },
  review: {
    label: "Review When Convenient",
    short: "Review",
    description: "Useful information with no immediate deadline.",
    bg: "#FEF3C7",
    color: "#92400E",
    rank: 2,
  },
  informational: {
    label: "Informational Only",
    short: "Info only",
    description: "No action expected.",
    bg: "#E0F2FE",
    color: "#075985",
    rank: 3,
  },
  promotional: {
    label: "Promotional / Low Value",
    short: "Promo",
    description: "Advertising or other nonessential mail.",
    bg: "#F3F4F6",
    color: "#6B7280",
    rank: 4,
  },
};

export const CATEGORY_META: Record<MailCategory, {
  emoji: string;
  label: string;
  color: string;
  bg: string;
  subs: { id: MailSubcategory; label: string }[];
}> = {
  critical: {
    emoji: "🚨",
    label: "Critical",
    color: "#991B1B",
    bg: "#FEF2F2",
    subs: [
      { id: "legal", label: "Legal" },
      { id: "government", label: "Government" },
      { id: "medical", label: "Medical" },
      { id: "security_fraud", label: "Security/Fraud" },
    ],
  },
  financial: {
    emoji: "💰",
    label: "Financial",
    color: "#166534",
    bg: "#ECFDF5",
    subs: [
      { id: "bills", label: "Bills" },
      { id: "banking", label: "Banking" },
      { id: "taxes", label: "Taxes" },
      { id: "insurance", label: "Insurance" },
    ],
  },
  deliveries: {
    emoji: "📦",
    label: "Deliveries",
    color: "#1E40AF",
    bg: "#EFF6FF",
    subs: [
      { id: "packages", label: "Packages" },
      { id: "signature_required", label: "Signature Required" },
      { id: "missed_delivery", label: "Missed Delivery" },
    ],
  },
  personal: {
    emoji: "👤",
    label: "Personal",
    color: "#6B21A8",
    bg: "#F5F3FF",
    subs: [
      { id: "friends", label: "Friends" },
      { id: "family", label: "Family" },
      { id: "greeting_cards", label: "Greeting cards" },
    ],
  },
  business: {
    emoji: "💼",
    label: "Business",
    color: "#1E3A5F",
    bg: "#F1F5F9",
    subs: [
      { id: "employer", label: "Employer" },
      { id: "payroll", label: "Payroll" },
      { id: "hr", label: "HR" },
      { id: "contracts", label: "Contracts" },
    ],
  },
  informational: {
    emoji: "📰",
    label: "Informational",
    color: "#0E7490",
    bg: "#ECFEFF",
    subs: [
      { id: "statements", label: "Statements" },
      { id: "school", label: "School" },
      { id: "community", label: "Community" },
    ],
  },
  promotional: {
    emoji: "🛍",
    label: "Promotional",
    color: "#9A3412",
    bg: "#FFF7ED",
    subs: [
      { id: "coupons", label: "Coupons" },
      { id: "catalogs", label: "Catalogs" },
      { id: "advertisements", label: "Advertisements" },
    ],
  },
};

function subcategoryLabel(sub: MailSubcategory): string {
  for (const cat of Object.values(CATEGORY_META)) {
    const found = cat.subs.find(s => s.id === sub);
    if (found) return found.label;
  }
  return sub;
}

function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter(t => t.length > 2);
}

type Classified = {
  priority: MailPriority;
  category: MailCategory;
  subcategory: MailSubcategory;
  source: "rules" | "ai_assist";
};

/** Rule-based + AI-assist category & well-being priority classifier. */
export function classifyMail(
  text: string,
  aiAssist: boolean,
): Classified {
  const t = text.toLowerCase();

  // ── Critical ──────────────────────────────────────────────────────────────
  if (/summons|lawsuit|eviction|court date|subpoena|legal notice|attorney/.test(t)) {
    return { priority: "immediate", category: "critical", subcategory: "legal", source: "rules" };
  }
  if (/irs|social security|dmv|passport|voter|census|department of|city of|county of|government/.test(t)) {
    const immediate = /final notice|urgent|action required|deadline|penalty/.test(t);
    return {
      priority: immediate ? "immediate" : "action_soon",
      category: "critical",
      subcategory: "government",
      source: "rules",
    };
  }
  if (/medicare|medicaid|hospital|clinic|lab results?|prescription|pharmacy|appointment|diagnosis|medical/.test(t)) {
    const immediate = /urgent|critical|results? ready|missed appointment|prior auth/.test(t);
    return {
      priority: immediate ? "immediate" : "action_soon",
      category: "critical",
      subcategory: "medical",
      source: "rules",
    };
  }
  if (/fraud|suspicious|unauthorized|security alert|identity|breach|compromised/.test(t)) {
    return { priority: "immediate", category: "critical", subcategory: "security_fraud", source: "rules" };
  }

  // ── Financial ─────────────────────────────────────────────────────────────
  if (/tax|1040|w-2|w2|irs refund|estimated tax/.test(t)) {
    return { priority: "action_soon", category: "financial", subcategory: "taxes", source: "rules" };
  }
  if (/insurance|premium|policy|claim|coverage|deductible/.test(t)) {
    const immediate = /lapsed|cancellation|deny|denial|final/.test(t);
    return {
      priority: immediate ? "immediate" : "action_soon",
      category: "financial",
      subcategory: "insurance",
      source: "rules",
    };
  }
  if (/bank|checking|savings|account statement|overdraft|wire|credit union/.test(t)) {
    return { priority: "review", category: "financial", subcategory: "banking", source: "rules" };
  }
  if (/bill|invoice|payment due|past due|collections?|utility|electric|water|gas bill/.test(t)) {
    const immediate = /final notice|collections?|shut.?off|past due|disconnect/.test(t);
    return {
      priority: immediate ? "immediate" : "action_soon",
      category: "financial",
      subcategory: "bills",
      source: "rules",
    };
  }

  // ── Deliveries ────────────────────────────────────────────────────────────
  if (/signature required|sign for|certified mail|registered mail/.test(t)) {
    return { priority: "action_soon", category: "deliveries", subcategory: "signature_required", source: "rules" };
  }
  if (/missed delivery|we missed you|redeliver|pickup notice|held at/.test(t)) {
    return { priority: "action_soon", category: "deliveries", subcategory: "missed_delivery", source: "rules" };
  }
  if (/package|parcel|shipment|tracking|out for delivery|amazon|ups|fedex|usps package/.test(t)) {
    return { priority: "review", category: "deliveries", subcategory: "packages", source: "rules" };
  }

  // ── Business ──────────────────────────────────────────────────────────────
  if (/payroll|direct deposit|pay stub|paycheck|wages/.test(t)) {
    return { priority: "review", category: "business", subcategory: "payroll", source: "rules" };
  }
  if (/\bhr\b|human resources|benefits enrollment|open enrollment|personnel/.test(t)) {
    return { priority: "action_soon", category: "business", subcategory: "hr", source: "rules" };
  }
  if (/contract|agreement|terms of service|nda|amendment/.test(t)) {
    return { priority: "action_soon", category: "business", subcategory: "contracts", source: "rules" };
  }
  if (/employer|from your company|workplace|job offer|employment/.test(t)) {
    return { priority: "review", category: "business", subcategory: "employer", source: "rules" };
  }

  // ── Personal ──────────────────────────────────────────────────────────────
  if (/happy birthday|holiday|christmas|valentine|sympathy|get well|greeting card|postcard/.test(t)) {
    return { priority: "informational", category: "personal", subcategory: "greeting_cards", source: "rules" };
  }
  if (/mom|dad|grandma|grandpa|aunt|uncle|family reunion|from your (son|daughter|sister|brother)/.test(t)) {
    return { priority: "informational", category: "personal", subcategory: "family", source: "rules" };
  }
  if (/dear friend|thinking of you|miss you|from a friend/.test(t)) {
    return { priority: "informational", category: "personal", subcategory: "friends", source: "rules" };
  }

  // ── Informational ─────────────────────────────────────────────────────────
  if (/school|university|college|tuition|report card|pta|student/.test(t)) {
    return { priority: "review", category: "informational", subcategory: "school", source: "rules" };
  }
  if (/community|neighborhood|hoa|town hall|library|newsletter|civic/.test(t)) {
    return { priority: "informational", category: "informational", subcategory: "community", source: "rules" };
  }
  if (/statement|annual summary|year.?end|account summary/.test(t)) {
    return { priority: "informational", category: "informational", subcategory: "statements", source: "rules" };
  }

  // ── Promotional ───────────────────────────────────────────────────────────
  if (/coupon|% off|save \$|promo code|discount/.test(t)) {
    return { priority: "promotional", category: "promotional", subcategory: "coupons", source: "rules" };
  }
  if (/catalog|lookbook|new arrivals|seasonal collection/.test(t)) {
    return { priority: "promotional", category: "promotional", subcategory: "catalogs", source: "rules" };
  }
  if (/sale!|sweepstakes|current resident|occupant|advertisement|special offer|limited time/.test(t)) {
    return { priority: "promotional", category: "promotional", subcategory: "advertisements", source: "rules" };
  }

  // ── AI-assist nudge for borderline medical/finance wording ────────────────
  if (aiAssist) {
    if (/pharmacy|prescription|benefit|claim|coverage/.test(t)) {
      return {
        priority: "action_soon",
        category: "critical",
        subcategory: "medical",
        source: "ai_assist",
      };
    }
    if (/account|balance|payment|due/.test(t)) {
      return {
        priority: "action_soon",
        category: "financial",
        subcategory: "bills",
        source: "ai_assist",
      };
    }
  }

  return {
    priority: "informational",
    category: "informational",
    subcategory: "statements",
    source: "rules",
  };
}

/** Backward-compatible wrapper used by older call sites / tests. */
export function classifyMailImportance(
  text: string,
  aiAssist: boolean,
): { importance: MailImportance; source: "rules" | "ai_assist" } {
  const c = classifyMail(text, aiAssist);
  const map: Record<MailPriority, MailImportance> = {
    immediate: "critical",
    action_soon: "important",
    review: "routine",
    informational: "routine",
    promotional: "junk",
  };
  return { importance: map[c.priority], source: c.source };
}

/** Simulate Textract OCR with fallback path (PR #317). */
export function runOcrPipeline(
  piece: Pick<MailPiece, "senderHint" | "subjectHint" | "imageMissing">,
  forceFallback = false,
): { text: string; source: OcrSource } {
  if (piece.imageMissing) {
    return {
      text: `${piece.senderHint}. ${piece.subjectHint}. Image unavailable — OCR limited to envelope metadata.`,
      source: "none",
    };
  }
  if (forceFallback) {
    return {
      text: `[Fallback OCR] ${piece.senderHint}: ${piece.subjectHint}`,
      source: "fallback",
    };
  }
  return {
    text: `[Textract] From ${piece.senderHint}. ${piece.subjectHint}. Scanned body text extracted for accessibility and search.`,
    source: "textract",
  };
}

function normalizeMailPiece(input: Partial<MailPiece> & {
  senderHint: string;
  subjectHint: string;
  digestDate: string;
}, aiAssist: boolean): MailPiece {
  const imageMissing = !!input.imageMissing || !input.imageUrl;
  const ocr = input.ocrText && input.ocrSource
    ? { text: input.ocrText, source: input.ocrSource }
    : runOcrPipeline({
        senderHint: input.senderHint,
        subjectHint: input.subjectHint,
        imageMissing,
      });
  const classified = (input.priority && input.category && input.subcategory)
    ? {
        priority: input.priority,
        category: input.category,
        subcategory: input.subcategory,
        source: input.importanceSource || "rules" as const,
      }
    : classifyMail(`${input.senderHint} ${input.subjectHint} ${ocr.text}`, aiAssist);
  const embeddingTokens = tokenize(
    `${input.senderHint} ${input.subjectHint} ${ocr.text} ${classified.category} ${classified.subcategory} ${classified.priority}`,
  );
  return {
    id: input.id || `mail-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    digestDate: input.digestDate,
    senderHint: input.senderHint.trim(),
    subjectHint: input.subjectHint.trim(),
    ocrText: ocr.text,
    ocrSource: ocr.source,
    imageUrl: imageMissing ? null : input.imageUrl,
    imageMissing,
    priority: classified.priority,
    category: classified.category,
    subcategory: classified.subcategory,
    importanceSource: classified.source,
    embeddingTokens,
    receivedAt: input.receivedAt || new Date().toISOString(),
  };
}

function sortByPriority(pieces: MailPiece[]): MailPiece[] {
  return [...pieces].sort(
    (a, b) => PRIORITY_META[a.priority].rank - PRIORITY_META[b.priority].rank,
  );
}

/** Natural-language mail search over token index (PR #325). */
export function searchMailPieces(pieces: MailPiece[], query: string): MailPiece[] {
  const q = query.trim().toLowerCase();
  if (!q) return sortByPriority(pieces);
  const terms = tokenize(q);
  const scored = pieces.map(p => {
    const hay = `${p.senderHint} ${p.subjectHint} ${p.ocrText} ${p.priority} ${p.category} ${p.subcategory}`.toLowerCase();
    let score = 0;
    if (hay.includes(q)) score += 5;
    for (const t of terms) {
      if (p.embeddingTokens.includes(t)) score += 2;
      if (hay.includes(t)) score += 1;
    }
    if (/urgent|critical|immediate|attention/.test(q) && p.priority === "immediate") score += 4;
    if (/action|soon|due/.test(q) && p.priority === "action_soon") score += 3;
    if (/promo|junk|coupon|ad/.test(q) && (p.priority === "promotional" || p.category === "promotional")) score += 3;
    if (/medical|health|clinic/.test(q) && p.subcategory === "medical") score += 3;
    if (/bill|financial|money/.test(q) && p.category === "financial") score += 3;
    if (/package|delivery|missed/.test(q) && p.category === "deliveries") score += 3;
    if (/missing image|no photo|no scan/.test(q) && p.imageMissing) score += 4;
    if (Object.keys(CATEGORY_META).some(c => q.includes(c)) && q.includes(p.category)) score += 2;
    return { p, score };
  });
  return scored
    .filter(s => s.score > 0)
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return PRIORITY_META[a.p.priority].rank - PRIORITY_META[b.p.priority].rank;
    })
    .map(s => s.p);
}

function migrateLegacyPiece(raw: Record<string, unknown>, aiAssist: boolean): MailPiece {
  if (raw.priority && raw.category && raw.subcategory) {
    return normalizeMailPiece(raw as unknown as MailPiece, aiAssist);
  }
  const importance = raw.importance as MailImportance | undefined;
  const base = normalizeMailPiece({
    id: String(raw.id || ""),
    digestDate: String(raw.digestDate || new Date().toISOString().slice(0, 10)),
    senderHint: String(raw.senderHint || "Unknown sender"),
    subjectHint: String(raw.subjectHint || ""),
    ocrText: typeof raw.ocrText === "string" ? raw.ocrText : undefined,
    ocrSource: raw.ocrSource as OcrSource | undefined,
    imageUrl: (raw.imageUrl as string | null | undefined) ?? null,
    imageMissing: !!raw.imageMissing,
    receivedAt: typeof raw.receivedAt === "string" ? raw.receivedAt : undefined,
  }, aiAssist);
  if (importance && !raw.priority) {
    const map: Record<MailImportance, MailPriority> = {
      critical: "immediate",
      important: "action_soon",
      routine: "review",
      junk: "promotional",
    };
    return { ...base, priority: map[importance] || base.priority };
  }
  return base;
}

function loadMailStore(): MailDigestStore {
  try {
    const raw = localStorage.getItem(MAIL_STORE_KEY)
      || localStorage.getItem("careconnect_mail_digest_v1");
    if (raw) {
      const parsed = JSON.parse(raw) as MailDigestStore;
      const ai = parsed.aiAssistEnabled !== false;
      return {
        ...parsed,
        aiAssistEnabled: ai,
        pieces: (parsed.pieces || []).map(p =>
          migrateLegacyPiece(p as unknown as Record<string, unknown>, ai),
        ),
      };
    }
  } catch {}
  return {
    pieces: [],
    credentialStatus: "disconnected",
    aiAssistEnabled: true,
  };
}

function saveMailStore(store: MailDigestStore) {
  try {
    localStorage.setItem(MAIL_STORE_KEY, JSON.stringify(store));
  } catch {}
}

function seedDemoDigest(aiAssist: boolean): MailPiece[] {
  const today = new Date().toISOString().slice(0, 10);
  const seeds: Array<Partial<MailPiece> & { senderHint: string; subjectHint: string; digestDate: string }> = [
    {
      id: "mp-legal",
      digestDate: today,
      senderHint: "County Court Clerk",
      subjectHint: "Summons — appearance required",
      imageUrl: "https://placehold.co/320x200/fecaca/991b1b?text=Legal",
      imageMissing: false,
    },
    {
      id: "mp-medical",
      digestDate: today,
      senderHint: "Metro Health Clinic",
      subjectHint: "Lab results ready — appointment follow-up",
      imageUrl: "https://placehold.co/320x200/dbeafe/1e40af?text=Medical",
      imageMissing: false,
    },
    {
      id: "mp-fraud",
      digestDate: today,
      senderHint: "Card Security Alerts",
      subjectHint: "Suspicious activity — unauthorized charge review",
      imageUrl: null,
      imageMissing: true,
    },
    {
      id: "mp-bill",
      digestDate: today,
      senderHint: "City Power & Water",
      subjectHint: "Monthly utility bill — payment due",
      imageUrl: "https://placehold.co/320x200/d1fae5/166534?text=Bill",
      imageMissing: false,
    },
    {
      id: "mp-bank",
      digestDate: today,
      senderHint: "First Neighborhood Bank",
      subjectHint: "Checking account statement",
      imageUrl: "https://placehold.co/320x200/ecfdf5/166534?text=Banking",
      imageMissing: false,
    },
    {
      id: "mp-missed",
      digestDate: today,
      senderHint: "USPS",
      subjectHint: "We missed you — redelivery or pickup notice",
      imageUrl: "https://placehold.co/320x200/dbeafe/1e3a8a?text=Missed+Delivery",
      imageMissing: false,
    },
    {
      id: "mp-package",
      digestDate: today,
      senderHint: "UPS",
      subjectHint: "Package out for delivery — tracking update",
      imageUrl: "https://placehold.co/320x200/eff6ff/1e40af?text=Package",
      imageMissing: false,
    },
    {
      id: "mp-family",
      digestDate: today,
      senderHint: "From Grandma",
      subjectHint: "Thinking of you — family note",
      imageUrl: "https://placehold.co/320x200/ede9fe/6b21a8?text=Family",
      imageMissing: false,
    },
    {
      id: "mp-hr",
      digestDate: today,
      senderHint: "Employer Benefits / HR",
      subjectHint: "Open enrollment — benefits action needed",
      imageUrl: "https://placehold.co/320x200/f1f5f9/1e3a5f?text=HR",
      imageMissing: false,
    },
    {
      id: "mp-community",
      digestDate: today,
      senderHint: "Neighborhood Association",
      subjectHint: "Community newsletter — town hall dates",
      imageUrl: "https://placehold.co/320x200/ecfeff/0e7490?text=Community",
      imageMissing: false,
    },
    {
      id: "mp-promo",
      digestDate: today,
      senderHint: "Current Resident",
      subjectHint: "Weekend sale! Coupons and sweepstakes inside",
      imageUrl: "https://placehold.co/320x200/ffedd5/9a3412?text=Promo",
      imageMissing: false,
    },
  ];
  return seeds.map(s => normalizeMailPiece(s, aiAssist));
}

function speakText(text: string, onEnd?: () => void) {
  try {
    window.speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.rate = 0.95;
    if (onEnd) u.onend = onEnd;
    window.speechSynthesis.speak(u);
  } catch {
    onEnd?.();
  }
}

function stopSpeaking() {
  try {
    window.speechSynthesis.cancel();
  } catch {
    /* ignore */
  }
}

type FilterMode = "all" | MailCategory | MailPriority;

export default function MailDigestContent({
  theme,
  readAloudGlobal = false,
}: {
  theme: ModeTheme;
  readAloudGlobal?: boolean;
}) {
  const [store, setStore] = useState<MailDigestStore>(() => loadMailStore());
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<FilterMode>("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [speakingId, setSpeakingId] = useState<string | null>(null);
  const [syncFlash, setSyncFlash] = useState<string | null>(null);
  const [showLegend, setShowLegend] = useState(false);
  const [emailInput, setEmailInput] = useState("");
  const [detected, setDetected] = useState<DetectedEmailProvider | null>(null);
  const [emailError, setEmailError] = useState<string | null>(null);
  const [imapPassword, setImapPassword] = useState("");
  const [imapHost, setImapHost] = useState("");
  const [showImapForm, setShowImapForm] = useState(false);

  useEffect(() => {
    saveMailStore(store);
  }, [store]);

  const filtered = useMemo(() => {
    let list = searchMailPieces(store.pieces, query);
    if (filter === "all") return list;
    if (filter in PRIORITY_META) {
      return list.filter(p => p.priority === filter);
    }
    return list.filter(p => p.category === filter);
  }, [store.pieces, query, filter]);

  const selected = store.pieces.find(p => p.id === selectedId) ?? null;

  const priorityCounts = useMemo(() => {
    const counts = {} as Record<MailPriority, number>;
    (Object.keys(PRIORITY_META) as MailPriority[]).forEach(k => { counts[k] = 0; });
    for (const p of store.pieces) counts[p.priority] = (counts[p.priority] || 0) + 1;
    return counts;
  }, [store.pieces]);

  const categoryCounts = useMemo(() => {
    const counts = {} as Record<MailCategory, number>;
    (Object.keys(CATEGORY_META) as MailCategory[]).forEach(k => { counts[k] = 0; });
    for (const p of store.pieces) counts[p.category] = (counts[p.category] || 0) + 1;
    return counts;
  }, [store.pieces]);

  const connectProvider = (info: DetectedEmailProvider, email: string) => {
    setStore(s => ({
      ...s,
      credentialStatus: "connected",
      lastSyncedAt: new Date().toISOString(),
      emailAddress: email.trim(),
      provider: info.provider,
      authMode: info.authMode,
      pieces: s.pieces.length ? s.pieces : seedDemoDigest(s.aiAssistEnabled),
    }));
    setSyncFlash(`${info.label} connected · Informed Delivery digest synced`);
    setShowImapForm(false);
    setImapPassword("");
    window.setTimeout(() => setSyncFlash(null), 2500);
  };

  const validateEmailAndRoute = () => {
    const email = emailInput.trim();
    if (!isValidEmailFormat(email)) {
      setEmailError("Enter a valid email address");
      setDetected(null);
      setShowImapForm(false);
      return;
    }
    const info = detectEmailProvider(email);
    if (!info) {
      setEmailError("Could not detect email provider");
      return;
    }
    setEmailError(null);
    setDetected(info);
    if (info.authMode === "oauth") {
      connectProvider(info, email);
      return;
    }
    setImapHost(info.imapHost || "");
    setShowImapForm(true);
  };

  const submitImapConnect = () => {
    if (!detected || !emailInput.trim()) return;
    if (!imapPassword.trim()) {
      setEmailError("App password is required for IMAP");
      return;
    }
    if (!imapHost.trim()) {
      setEmailError("IMAP host is required");
      return;
    }
    setEmailError(null);
    connectProvider(
      { ...detected, imapHost: imapHost.trim(), imapPort: detected.imapPort || 993 },
      emailInput.trim(),
    );
  };

  const connectGmail = () => {
    setEmailInput("demo@gmail.com");
    connectProvider(
      { provider: "gmail", authMode: "oauth", label: "Gmail" },
      "demo@gmail.com",
    );
  };

  const simulateRevocation = () => {
    setStore(s => ({ ...s, credentialStatus: "revoked" }));
  };

  const requestReauth = () => {
    setStore(s => ({ ...s, credentialStatus: "reauth_required" }));
  };

  const completeReauth = () => {
    setStore(s => ({
      ...s,
      credentialStatus: "connected",
      lastSyncedAt: new Date().toISOString(),
    }));
    setSyncFlash("Credentials refreshed");
    window.setTimeout(() => setSyncFlash(null), 2000);
  };

  const refreshDigest = () => {
    if (store.credentialStatus !== "connected") return;
    setStore(s => ({
      ...s,
      lastSyncedAt: new Date().toISOString(),
      pieces: seedDemoDigest(s.aiAssistEnabled),
    }));
    setSyncFlash("Digest refreshed · reclassified by priority & category");
    window.setTimeout(() => setSyncFlash(null), 2000);
  };

  const retryOcrFallback = (id: string) => {
    setStore(s => ({
      ...s,
      pieces: s.pieces.map(p => {
        if (p.id !== id) return p;
        const ocr = runOcrPipeline(p, true);
        const classified = classifyMail(
          `${p.senderHint} ${p.subjectHint} ${ocr.text}`,
          s.aiAssistEnabled,
        );
        return {
          ...p,
          ocrText: ocr.text,
          ocrSource: ocr.source,
          priority: classified.priority,
          category: classified.category,
          subcategory: classified.subcategory,
          importanceSource: classified.source,
          embeddingTokens: tokenize(
            `${p.senderHint} ${p.subjectHint} ${ocr.text} ${classified.category} ${classified.subcategory}`,
          ),
        };
      }),
    }));
  };

  const readPiece = (p: MailPiece) => {
    if (speakingId === p.id) {
      stopSpeaking();
      setSpeakingId(null);
      return;
    }
    const pri = PRIORITY_META[p.priority];
    const cat = CATEGORY_META[p.category];
    const text = `${pri.label}. ${cat.label}, ${subcategoryLabel(p.subcategory)}. From ${p.senderHint}. ${p.subjectHint}. ${p.ocrText}`;
    setSpeakingId(p.id);
    speakText(text, () => setSpeakingId(null));
  };

  const disconnect = () => {
    window.speechSynthesis?.cancel();
    setStore(s => ({
      ...s,
      credentialStatus: "disconnected",
      pieces: [],
      lastSyncedAt: undefined,
    }));
    setSelectedId(null);
    setFilter("all");
  };

  return (
    <div className="flex flex-col min-h-full px-4 pt-4 pb-28 gap-3">
      <div className="flex items-center gap-2">
        <Mail size={18} style={{ color: theme.color }} />
        <div className="flex-1 min-w-0">
          <h2 className="text-[18px] font-bold text-[#0F172A]">Mail Digest</h2>
          <p className="text-[11px] text-[#9CA3AF]">USPS Informed Delivery · priority & categories</p>
        </div>
        {store.credentialStatus === "connected" && (
          <button type="button" onClick={refreshDigest}
            className="p-2 rounded-xl border border-[#E5E7EB] bg-white" aria-label="Refresh digest">
            <RefreshCw size={16} style={{ color: theme.color }} />
          </button>
        )}
      </div>

      {syncFlash && (
        <div className="rounded-xl px-3 py-2 text-[12px] font-semibold"
          style={{ background: "#ECFDF5", color: "#047857", border: "1px solid #A7F3D0" }}>
          {syncFlash}
        </div>
      )}

      {/* Multi-provider email connect */}
      {store.credentialStatus !== "connected" && (
        <div className="rounded-2xl p-5 flex flex-col gap-3"
          style={{
            background: "linear-gradient(160deg, #ECFEFF 0%, #F0FDFA 55%, #FFFFFF 100%)",
            border: "2px solid #5EEAD4",
          }}>
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-2xl flex items-center justify-center text-[22px] bg-white border border-[#99F6E4]">
              📬
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-[16px] font-bold text-[#0F172A]">Connect your email</p>
              <p className="text-[12px] text-[#0F766E] leading-snug">
                Gmail, Outlook, Yahoo, Apple, AOL, Zoho, or any IMAP inbox for USPS Informed Delivery.
              </p>
            </div>
          </div>

          {(store.credentialStatus === "disconnected"
            || store.credentialStatus === "revoked"
            || store.credentialStatus === "reauth_required") && (
            <div className="flex flex-col gap-2">
              {store.credentialStatus === "revoked" && (
                <p className="text-[12px] font-semibold text-[#991B1B]">
                  Access was revoked. Re-authorize with your email below.
                </p>
              )}
              {store.credentialStatus === "reauth_required" && (
                <p className="text-[12px] font-semibold text-[#92400E]">
                  Session expired. Sign in again with your email below.
                </p>
              )}
              <label className="text-[11px] font-bold text-[#0F766E] uppercase tracking-wider">
                Email address
              </label>
              <input
                type="email"
                value={emailInput}
                onChange={e => {
                  setEmailInput(e.target.value);
                  setEmailError(null);
                }}
                placeholder="you@gmail.com"
                className="w-full px-3 py-3 rounded-xl border border-[#99F6E4] bg-white text-[14px] outline-none"
                aria-label="Email address for mail digest"
              />
              {emailError && (
                <p className="text-[12px] font-semibold text-[#B91C1C]">{emailError}</p>
              )}
              {detected && !showImapForm && (
                <p className="text-[12px] text-[#0F766E]">
                  Detected: <strong>{detected.label}</strong> ({detected.authMode.toUpperCase()})
                </p>
              )}
              {!showImapForm && (
                <button type="button" onClick={validateEmailAndRoute}
                  className="w-full py-3.5 rounded-xl text-[15px] font-bold text-white flex items-center justify-center gap-2 shadow-sm"
                  style={{ background: "#0D9488" }}>
                  <Link2 size={18} /> Continue with this email
                </button>
              )}
              {showImapForm && detected && (
                <div className="rounded-xl p-3 flex flex-col gap-2" style={{ background: "#F0FDFA", border: "1px solid #99F6E4" }}>
                  <p className="text-[13px] font-bold text-[#0F172A]">
                    Connect {detected.label} via IMAP
                  </p>
                  <label className="text-[11px] font-bold text-[#6B7280] uppercase">IMAP host</label>
                  <input
                    value={imapHost}
                    onChange={e => setImapHost(e.target.value)}
                    className="w-full px-3 py-2.5 rounded-xl border border-[#E5E7EB] bg-white text-[14px]"
                    aria-label="IMAP host"
                  />
                  <label className="text-[11px] font-bold text-[#6B7280] uppercase">App password</label>
                  <input
                    type="password"
                    value={imapPassword}
                    onChange={e => setImapPassword(e.target.value)}
                    placeholder="Provider app password"
                    className="w-full px-3 py-2.5 rounded-xl border border-[#E5E7EB] bg-white text-[14px]"
                    aria-label="IMAP app password"
                  />
                  <button type="button" onClick={submitImapConnect}
                    className="w-full py-3 rounded-xl text-[14px] font-bold text-white"
                    style={{ background: "#0D9488" }}>
                    Connect IMAP
                  </button>
                </div>
              )}
              <button type="button" onClick={connectGmail}
                className="w-full py-2.5 rounded-xl text-[13px] font-semibold border border-[#99F6E4] text-[#0F766E]">
                Quick demo: Connect Gmail
              </button>
            </div>
          )}
          <p className="text-[11px] text-[#6B7280] text-center">
            Demo mode: OAuth / IMAP complete locally (no real provider sign-in).
          </p>
        </div>
      )}

      {/* Credential lifecycle details (when connected) */}
      {store.credentialStatus === "connected" && (
      <div className="rounded-2xl bg-white border border-[#E5E7EB] p-4 flex flex-col gap-2">
        <p className="text-[11px] font-bold uppercase tracking-wider text-[#9CA3AF]">Email credentials</p>
        <p className="text-[13px] font-semibold text-[#0F172A]">
          Status:{" "}
          <span style={{ color: "#059669" }}>connected</span>
          {store.provider && (
            <span className="text-[#6B7280] font-medium">
              {" "}· {store.provider.toUpperCase()}
              {store.authMode ? ` (${store.authMode})` : ""}
            </span>
          )}
        </p>
        {store.emailAddress && (
          <p className="text-[12px] text-[#374151]">{store.emailAddress}</p>
        )}
        {store.lastSyncedAt && (
          <p className="text-[11px] text-[#9CA3AF]">
            Last sync {new Date(store.lastSyncedAt).toLocaleString()}
          </p>
        )}
          <div className="flex flex-wrap gap-2 pt-1">
            <button type="button" onClick={simulateRevocation}
              className="flex-1 min-w-[40%] py-2 rounded-xl text-[11px] font-semibold border border-[#FEE2E2] text-[#EF4444] bg-white">
              Simulate revoke
            </button>
            <button type="button" onClick={requestReauth}
              className="flex-1 min-w-[40%] py-2 rounded-xl text-[11px] font-semibold border border-[#FDE68A] text-[#B45309] bg-white">
              Simulate reauth needed
            </button>
            <button type="button" onClick={disconnect}
              className="w-full py-2 rounded-xl text-[11px] font-semibold border border-[#E5E7EB] text-[#6B7280] bg-white">
              Disconnect
            </button>
          </div>
        <label className="flex items-center justify-between gap-3 pt-2 border-t border-[#F3F4F6]">
          <span className="text-[12px] font-semibold text-[#374151]">AI-assist ranking & categories</span>
          <input
            type="checkbox"
            checked={store.aiAssistEnabled}
            onChange={e => setStore(s => ({ ...s, aiAssistEnabled: e.target.checked }))}
          />
        </label>
      </div>
      )}

      {store.credentialStatus === "connected" && (
        <>
          {/* Well-being priority guide */}
          <div className="rounded-2xl bg-white border border-[#E5E7EB] overflow-hidden">
            <button
              type="button"
              onClick={() => setShowLegend(v => !v)}
              className="w-full flex items-center justify-between px-4 py-3 text-left"
            >
              <div>
                <p className="text-[13px] font-bold text-[#0F172A]">Priority by well-being impact</p>
                <p className="text-[11px] text-[#9CA3AF]">Tap to {showLegend ? "hide" : "show"} ranking guide</p>
              </div>
              <span className="text-[12px] font-bold" style={{ color: theme.color }}>
                {showLegend ? "Hide" : "Guide"}
              </span>
            </button>
            {showLegend && (
              <div className="px-4 pb-4 flex flex-col gap-2 border-t border-[#F3F4F6] pt-3">
                {(Object.keys(PRIORITY_META) as MailPriority[]).map(key => {
                  const meta = PRIORITY_META[key];
                  return (
                    <button
                      key={key}
                      type="button"
                      onClick={() => setFilter(key)}
                      className="text-left rounded-xl px-3 py-2.5"
                      style={{
                        background: meta.bg,
                        border: filter === key ? `2px solid ${meta.color}` : "1px solid transparent",
                      }}
                    >
                      <p className="text-[12px] font-bold" style={{ color: meta.color }}>{meta.label}</p>
                      <p className="text-[11px] text-[#4B5563] mt-0.5 leading-snug">{meta.description}</p>
                    </button>
                  );
                })}
              </div>
            )}
            <div className="flex gap-1.5 px-3 pb-3 overflow-x-auto">
              {(Object.keys(PRIORITY_META) as MailPriority[]).map(key => {
                const meta = PRIORITY_META[key];
                const on = filter === key;
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setFilter(on ? "all" : key)}
                    className="shrink-0 text-[10px] font-bold px-2.5 py-1.5 rounded-full"
                    style={{
                      background: on ? meta.color : meta.bg,
                      color: on ? "#fff" : meta.color,
                    }}
                  >
                    {meta.short} · {priorityCounts[key]}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Category taxonomy */}
          <div className="rounded-2xl bg-white border border-[#E5E7EB] p-3">
            <p className="text-[11px] font-bold uppercase tracking-wider text-[#9CA3AF] mb-2 px-1">
              Manage by category
            </p>
            <div className="flex flex-wrap gap-1.5">
              <button
                type="button"
                onClick={() => setFilter("all")}
                className="text-[11px] font-bold px-2.5 py-1.5 rounded-full border"
                style={{
                  background: filter === "all" ? theme.color : "#F9FAFB",
                  color: filter === "all" ? "#fff" : "#374151",
                  borderColor: filter === "all" ? theme.color : "#E5E7EB",
                }}
              >
                All mail
              </button>
              {(Object.keys(CATEGORY_META) as MailCategory[]).map(key => {
                const meta = CATEGORY_META[key];
                const on = filter === key;
                const count = categoryCounts[key];
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setFilter(on ? "all" : key)}
                    className="text-[11px] font-bold px-2.5 py-1.5 rounded-full"
                    style={{
                      background: on ? meta.color : meta.bg,
                      color: on ? "#fff" : meta.color,
                    }}
                    title={meta.subs.map(s => s.label).join(", ")}
                  >
                    {meta.emoji} {meta.label} · {count}
                  </button>
                );
              })}
            </div>
            {filter !== "all" && filter in CATEGORY_META && (
              <div className="mt-2 pt-2 border-t border-[#F3F4F6] flex flex-wrap gap-1">
                {CATEGORY_META[filter as MailCategory].subs.map(sub => (
                  <span
                    key={sub.id}
                    className="text-[10px] font-semibold px-2 py-1 rounded-lg bg-[#F9FAFB] text-[#6B7280]"
                  >
                    {sub.label}
                  </span>
                ))}
              </div>
            )}
          </div>

          {/* NL search (PR #325) */}
          <div className="flex items-center gap-2 px-3 py-2.5 rounded-2xl bg-white border border-[#E5E7EB]">
            <Search size={16} className="text-[#9CA3AF] shrink-0" />
            <input
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder='Search… e.g. "urgent medical" or "missed delivery"'
              className="flex-1 text-[14px] outline-none bg-transparent"
            />
            {query && (
              <button type="button" onClick={() => setQuery("")} aria-label="Clear search">
                <X size={14} className="text-[#9CA3AF]" />
              </button>
            )}
          </div>

          <p className="text-[12px] text-[#6B7280]">
            {filtered.length} piece{filtered.length === 1 ? "" : "s"}
            {query ? " matching" : ""}
            {filter !== "all" ? ` · filtered` : " · sorted by priority"}
          </p>

          {filtered.length === 0 ? (
            <div className="rounded-2xl bg-white border border-[#E5E7EB] p-5 text-center">
              <p className="text-[14px] font-bold text-[#0F172A]">No mail pieces</p>
              <p className="text-[12px] text-[#9CA3AF] mt-1">
                {query || filter !== "all" ? "Try clearing filters or search." : "Refresh after connecting Gmail."}
              </p>
            </div>
          ) : (
            filtered.map(p => {
              const pri = PRIORITY_META[p.priority];
              const cat = CATEGORY_META[p.category];
              return (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => setSelectedId(p.id)}
                  className="w-full text-left rounded-2xl bg-white border border-[#E5E7EB] overflow-hidden"
                >
                  {p.imageMissing ? (
                    <div className="h-28 flex flex-col items-center justify-center gap-1"
                      style={{ background: "#F8FAFC", borderBottom: "1px dashed #CBD5E1" }}>
                      <AlertTriangle size={20} className="text-[#F59E0B]" />
                      <p className="text-[12px] font-bold text-[#92400E]">Mail image unavailable</p>
                      <p className="text-[10px] text-[#9CA3AF]">Envelope metadata + OCR fallback only</p>
                    </div>
                  ) : (
                    <img src={p.imageUrl!} alt="" className="w-full h-28 object-cover bg-[#F1F5F9]" />
                  )}
                  <div className="px-3 py-3 flex flex-col gap-1.5">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full"
                        style={{ background: pri.bg, color: pri.color }}>
                        {pri.short}
                        {p.importanceSource === "ai_assist" ? " · AI" : ""}
                      </span>
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full"
                        style={{ background: cat.bg, color: cat.color }}>
                        {cat.emoji} {cat.label}
                      </span>
                      <span className="text-[10px] font-semibold text-[#9CA3AF]">
                        {subcategoryLabel(p.subcategory)}
                      </span>
                    </div>
                    <p className="text-[14px] font-bold text-[#0F172A]">{p.senderHint}</p>
                    <p className="text-[12px] text-[#6B7280] line-clamp-2">{p.subjectHint}</p>
                  </div>
                </button>
              );
            })
          )}
        </>
      )}

      {selected && (
        <div className="fixed inset-0 z-50 bg-black/40 flex flex-col justify-end">
          <div className="bg-white rounded-t-3xl px-5 pt-4 pb-8 max-h-[88%] overflow-y-auto">
            <div className="flex items-center justify-between mb-3">
              <p className="text-[16px] font-bold text-[#0F172A]">Mail detail</p>
              <button type="button" onClick={() => setSelectedId(null)}
                className="w-8 h-8 rounded-full bg-[#F3F4F6] flex items-center justify-center" aria-label="Close">
                <X size={16} />
              </button>
            </div>

            <div className="flex flex-wrap gap-1.5 mb-3">
              <span className="text-[11px] font-bold px-2.5 py-1 rounded-full"
                style={{
                  background: PRIORITY_META[selected.priority].bg,
                  color: PRIORITY_META[selected.priority].color,
                }}>
                {PRIORITY_META[selected.priority].label}
              </span>
              <span className="text-[11px] font-bold px-2.5 py-1 rounded-full"
                style={{
                  background: CATEGORY_META[selected.category].bg,
                  color: CATEGORY_META[selected.category].color,
                }}>
                {CATEGORY_META[selected.category].emoji}{" "}
                {CATEGORY_META[selected.category].label} · {subcategoryLabel(selected.subcategory)}
              </span>
            </div>
            <p className="text-[12px] text-[#6B7280] mb-3 leading-relaxed">
              {PRIORITY_META[selected.priority].description}
            </p>

            {selected.imageMissing ? (
              <div className="rounded-2xl p-6 text-center mb-3"
                style={{ background: "#FFFBEB", border: "1px dashed #F59E0B" }}>
                <AlertTriangle size={28} className="mx-auto text-[#F59E0B] mb-2" />
                <p className="text-[14px] font-bold text-[#92400E]">Missing mail image</p>
                <p className="text-[12px] text-[#B45309] mt-1">
                  USPS did not provide a scan. Showing OCR / metadata only.
                </p>
              </div>
            ) : (
              <img
                src={selected.imageUrl!}
                alt=""
                className="w-full mb-3 rounded-2xl border border-[#E5E7EB] object-contain bg-[#F8FAFC]"
                style={{ maxHeight: 220, height: 220 }}
              />
            )}
            <p className="text-[15px] font-bold text-[#0F172A]">{selected.senderHint}</p>
            <p className="text-[13px] text-[#6B7280] mb-2">{selected.subjectHint}</p>
            <p className="text-[11px] font-bold uppercase tracking-wider text-[#9CA3AF] mb-1">
              OCR text ({selected.ocrSource})
            </p>
            <p className="text-[13px] text-[#374151] leading-relaxed mb-3">{selected.ocrText}</p>
            <div className="flex flex-col gap-2">
              <button type="button" onClick={() => readPiece(selected)}
                className="w-full py-3 rounded-xl text-[14px] font-bold text-white flex items-center justify-center gap-2"
                style={{ background: speakingId === selected.id ? "#DC2626" : theme.color }}
                aria-label={speakingId === selected.id ? "Stop reading aloud" : "Start reading aloud"}>
                {speakingId === selected.id ? <Square size={16} /> : <Volume2 size={16} />}
                {speakingId === selected.id ? "Stop reading" : "Start reading aloud"}
              </button>
              {selected.ocrSource !== "fallback" && (
                <button type="button" onClick={() => retryOcrFallback(selected.id)}
                  className="w-full py-2.5 rounded-xl text-[13px] font-semibold border border-[#E5E7EB] text-[#374151]">
                  Retry with OCR fallback (Textract → fallback)
                </button>
              )}
              {readAloudGlobal && (
                <p className="text-[11px] text-center text-[#9CA3AF] flex items-center justify-center gap-1">
                  <Mic size={12} /> Global read-aloud preference is on
                </p>
              )}
            </div>
            <p className="text-[10px] text-[#9CA3AF] text-center mt-3">
              Classified via {selected.importanceSource} · {selected.embeddingTokens.length} search tokens
            </p>
          </div>
        </div>
      )}

      <div className="rounded-xl px-3 py-2 text-[10px] text-[#9CA3AF] leading-relaxed"
        style={{ background: theme.lightBg, border: `1px solid ${theme.borderColor}` }}>
        Mail is ranked by well-being impact and filed into Critical, Financial, Deliveries, Personal,
        Business, Informational, and Promotional categories (with subtypes). Also includes OCR,
        search, missing-image handling, credential lifecycle, and ADA read-aloud.
      </div>
    </div>
  );
}
