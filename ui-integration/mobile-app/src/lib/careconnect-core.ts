/** Core CareConnect auth, invite, and caregiver-access helpers (testable). */

export type GrantedItem =
  | "mood"
  | "checkin_summary"
  | "med_adherence"
  | "fall_alerts"
  | "upcoming_visits"
  | "symptoms";

export type SignInMethod = "pin" | "password" | "color";

/** Patients may have at most this many caregivers in their Care Circle. */
export const MAX_CAREGIVERS = 3;

export interface LinkedCaregiver {
  id: string;
  name: string;
  relationship: string;
  initials: string;
  grants: GrantedItem[];
  status: "active" | "pending" | "suspended";
  email?: string;
  phone?: string;
  inviteCode?: string;
  /** True when the patient added this person from Care Circle (counts as pre-approval). */
  addedByPatient?: boolean;
  /** Features the caregiver has asked the patient to share. */
  pendingGrantRequests?: GrantedItem[];
}

export interface PatientSnippet {
  id: string;
  name: string;
  age: number;
  initials: string;
  grants: GrantedItem[];
  mood?: number;
  lastCheckin?: string;
  medAdherence?: number;
  hasFallAlert?: boolean;
  nextVisit?: string;
  symptomsSummary?: string;
  accessState?: "ok" | "inactive_profile" | "suspended" | "pending" | "unauthorized";
  caregiverRelationship?: string;
  caregiverName?: string;
}

export interface CaregiverPersonaInfo {
  id: string;
  label: string;
  name: string;
}

export interface AuthCredentials {
  password?: string;
  pin?: string;
  colorSeq?: string[];
}

export interface AuthMethodSelection {
  pin: boolean;
  password: boolean;
  color: boolean;
}

export function makeInitials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

export function namesMatch(a: string, b: string): boolean {
  return a.trim().toLowerCase() === b.trim().toLowerCase();
}

/** Normalize DOB to MM/DD/YYYY; returns "" if invalid. */
export function normalizeDob(dob: string): string {
  if (!dob.trim()) return "";
  const iso = dob.trim().match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (iso) {
    const year = Number(iso[1]);
    const month = Number(iso[2]);
    const day = Number(iso[3]);
    if (month < 1 || month > 12 || day < 1 || day > 31) return "";
    return `${String(month).padStart(2, "0")}/${String(day).padStart(2, "0")}/${year}`;
  }
  const m = dob.match(/(\d{1,2})\s*[\/\-]\s*(\d{1,2})\s*[\/\-]\s*(\d{2,4})/);
  if (!m) return "";
  const month = Number(m[1]);
  const day = Number(m[2]);
  const year = Number(m[3].length === 2 ? `19${m[3]}` : m[3]);
  if (month < 1 || month > 12 || day < 1 || day > 31 || year < 1900) return "";
  return `${String(month).padStart(2, "0")}/${String(day).padStart(2, "0")}/${year}`;
}

export function dobsMatch(a: string, b: string): boolean {
  const na = normalizeDob(a);
  const nb = normalizeDob(b);
  if (!na || !nb) return false;
  return na === nb;
}

export function ageFromDob(dob: string, today = new Date()): number {
  if (!dob.trim()) return 0;
  const normalized = normalizeDob(dob);
  const source = normalized || dob.trim();
  const slash = source.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (slash) {
    const month = Number(slash[1]) - 1;
    const day = Number(slash[2]);
    const year = Number(slash[3]);
    const d = new Date(year, month, day);
    if (Number.isNaN(d.getTime())) return 0;
    let age = today.getFullYear() - d.getFullYear();
    if (today < new Date(today.getFullYear(), d.getMonth(), d.getDate())) age--;
    return age > 0 ? age : 0;
  }
  const parsed = new Date(source);
  if (Number.isNaN(parsed.getTime())) {
    const m = source.match(/(\d{1,2})\s*[\/\-]\s*(\d{1,2})\s*[\/\-]\s*(\d{2,4})/);
    if (!m) return 0;
    const year = Number(m[3].length === 2 ? `19${m[3]}` : m[3]);
    const month = Number(m[1]) - 1;
    const day = Number(m[2]);
    const d = new Date(year, month, day);
    if (Number.isNaN(d.getTime())) return 0;
    let age = today.getFullYear() - d.getFullYear();
    if (today < new Date(today.getFullYear(), d.getMonth(), d.getDate())) age--;
    return age > 0 ? age : 0;
  }
  let age = today.getFullYear() - parsed.getFullYear();
  if (today < new Date(today.getFullYear(), parsed.getMonth(), parsed.getDate())) age--;
  return age > 0 ? age : 0;
}

export function formatCheckinStamp(d = new Date()): string {
  const h = d.getHours();
  const m = d.getMinutes();
  const ampm = h >= 12 ? "PM" : "AM";
  const hr = ((h + 11) % 12) + 1;
  const mm = String(m).padStart(2, "0");
  return `Today ${hr}:${mm} ${ampm}`;
}

export function buildInviteUrl(code: string, patientName?: string): string {
  const base = `https://careconnect.app/invite/${code}`;
  if (!patientName?.trim()) return base;
  return `${base}?patient=${encodeURIComponent(patientName.trim())}`;
}

export function parseInviteFromUrl(raw: string): { code: string; patientName?: string } | null {
  const text = raw.trim();
  if (!text) return null;
  const codeOnly = text.match(/^cc-[a-z0-9]+$/i);
  if (codeOnly) return { code: codeOnly[0] };
  try {
    const url = new URL(text.includes("://") ? text : `https://careconnect.app/invite/${text}`);
    const parts = url.pathname.split("/").filter(Boolean);
    const code = parts[parts.length - 1] || "";
    if (!code.startsWith("cc-")) return null;
    const patientName = url.searchParams.get("patient") || undefined;
    return { code, patientName: patientName ? decodeURIComponent(patientName) : undefined };
  } catch {
    return null;
  }
}

export function qrImageUrl(data: string, size = 200): string {
  return `https://api.qrserver.com/v1/create-qr-code/?size=${size}x${size}&data=${encodeURIComponent(data)}`;
}

export function hasAnyAuthConfigured(creds: AuthCredentials): boolean {
  return !!(
    creds.password?.trim() ||
    creds.pin?.trim() ||
    (creds.colorSeq && creds.colorSeq.length === 3)
  );
}

export function validateSelectedAuthMethods(
  methods: AuthMethodSelection,
  creds: AuthCredentials,
): boolean {
  const selected =
    (methods.password ? 1 : 0) + (methods.pin ? 1 : 0) + (methods.color ? 1 : 0);
  if (selected === 0) return false;
  if (methods.password && (!creds.password || creds.password.trim().length < 4)) return false;
  if (methods.pin && (!creds.pin || creds.pin.length !== 4)) return false;
  if (methods.color && (!creds.colorSeq || creds.colorSeq.length !== 3)) return false;
  return true;
}

export function credentialsForSelectedMethods(
  methods: AuthMethodSelection,
  creds: AuthCredentials,
): AuthCredentials {
  return {
    password: methods.password ? (creds.password?.trim() || "") : "",
    pin: methods.pin ? (creds.pin || "") : "",
    colorSeq: methods.color ? (creds.colorSeq || []) : [],
  };
}

export function verifySignIn(
  method: SignInMethod,
  attempt: { password?: string; pin?: string; colorSeq?: string[] },
  stored: AuthCredentials,
): boolean {
  if (method === "password") {
    const expected = stored.password?.trim() || "";
    if (!expected) return false;
    return attempt.password === expected;
  }
  if (method === "pin") {
    const expected = stored.pin?.trim() || "";
    if (!expected || expected.length !== 4) return false;
    return attempt.pin === expected;
  }
  const expected = stored.colorSeq || [];
  if (expected.length !== 3) return false;
  const got = attempt.colorSeq || [];
  return got.length === 3 && got.join() === expected.join();
}

export function caregiverPatientConfirmed(
  linkedPatientName: string | undefined,
  knownPatientName?: string,
  linkedPatientDob?: string,
  knownPatientDob?: string,
): boolean {
  if (!linkedPatientName?.trim()) return false;
  if (!linkedPatientDob?.trim() || !normalizeDob(linkedPatientDob)) return false;
  if (knownPatientName && knownPatientName !== "Your Name" && !namesMatch(linkedPatientName, knownPatientName)) {
    return false;
  }
  if (knownPatientDob?.trim() && !dobsMatch(linkedPatientDob, knownPatientDob)) {
    return false;
  }
  return true;
}

export function buildCaregiverPatientRoster(opts: {
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
  personas?: CaregiverPersonaInfo[];
}): PatientSnippet[] {
  if (!opts.linkedPatientName?.trim()) {
    return [];
  }

  if (
    !opts.profileName ||
    opts.profileName === "Your Name" ||
    !namesMatch(opts.linkedPatientName, opts.profileName)
  ) {
    return [{
      id: "patient-unmatched",
      name: opts.linkedPatientName.trim(),
      age: 0,
      initials: makeInitials(opts.linkedPatientName),
      grants: [],
      accessState: "unauthorized",
      caregiverRelationship: "Linked patient",
    }];
  }

  const personas = opts.personas || [];
  const persona = personas.find(p => p.id === opts.caregiverId);
  const link =
    (opts.linkedInviteCode
      ? opts.linkedCaregivers.find(
          c => c.inviteCode && namesMatch(c.inviteCode, opts.linkedInviteCode!),
        )
      : undefined) ||
    opts.linkedCaregivers.find(c => c.id === opts.caregiverId) ||
    (opts.caregiverName
      ? opts.linkedCaregivers.find(c => namesMatch(c.name, opts.caregiverName!))
      : undefined);

  if (!link) {
    return [{
      id: "patient-local",
      name: opts.profileName,
      age: ageFromDob(opts.profileDob) || 0,
      initials: makeInitials(opts.profileName),
      grants: [],
      accessState: "unauthorized",
      caregiverRelationship: persona?.label,
      caregiverName: opts.caregiverName || persona?.name,
    }];
  }

  const displayName = opts.profileName;
  const age = ageFromDob(opts.profileDob) || 0;
  const base = {
    id: "patient-local",
    name: displayName,
    age,
    initials: makeInitials(displayName),
    caregiverRelationship: link.relationship || persona?.label,
    caregiverName: link.name || opts.caregiverName || persona?.name,
  };

  if (!opts.patientActive) {
    return [{
      ...base,
      name: "No active patient profile",
      initials: "?",
      grants: [],
      accessState: "inactive_profile" as const,
    }];
  }

  if (link.status === "suspended") {
    return [{ ...base, grants: [], accessState: "suspended" as const }];
  }

  if (link.status === "pending") {
    return [{ ...base, grants: [], accessState: "pending" as const }];
  }

  if (link.status !== "active") {
    return [{ ...base, grants: [], accessState: "unauthorized" as const }];
  }

  const grants = [...link.grants];
  return [{
    ...base,
    grants,
    accessState: "ok" as const,
    mood: grants.includes("mood") ? (opts.mood ?? undefined) : undefined,
    lastCheckin: grants.includes("checkin_summary")
      ? (opts.lastCheckin || undefined)
      : undefined,
    medAdherence: grants.includes("med_adherence") ? opts.medAdherence : undefined,
    hasFallAlert: grants.includes("fall_alerts") ? !!opts.hasFallAlert : undefined,
    nextVisit: grants.includes("upcoming_visits")
      ? (opts.nextVisit || undefined)
      : undefined,
    symptomsSummary: grants.includes("symptoms")
      ? (opts.symptomsSummary ||
          [
            opts.profileConditions && `Conditions: ${opts.profileConditions}`,
            opts.profileAllergies && `Allergies: ${opts.profileAllergies}`,
          ]
            .filter(Boolean)
            .join(" · ") ||
          "No recent symptoms logged")
      : undefined,
  }];
}

export function canAddCaregiver(circle: LinkedCaregiver[]): boolean {
  return circle.length < MAX_CAREGIVERS;
}

/**
 * Links a caregiver after they complete setup with an invite / patient confirmation.
 *
 * - If the patient already added this caregiver in their Care Circle (invite code or name match),
 *   the link becomes active (patient already chose them).
 * - If the caregiver was not previously added by the patient, they are appended as pending
 *   and must wait for the patient to approve — and only when under the caregiver cap.
 */
export function activateInviteInCareCircle(
  circle: LinkedCaregiver[],
  opts: {
    inviteCode?: string;
    caregiverId: string;
    caregiverName: string;
    caregiverEmail?: string;
    caregiverPhone?: string;
    relationship?: string;
  },
): LinkedCaregiver[] {
  const inviteCode = opts.inviteCode?.trim() || "";
  let matchedExisting = false;
  const next = circle.map(cg => {
    const codeMatch = !!(inviteCode && cg.inviteCode && namesMatch(cg.inviteCode, inviteCode));
    const nameMatch = !!(opts.caregiverName && namesMatch(cg.name, opts.caregiverName));
    // Only treat as patient-approved when the Care Circle already has this invite or person.
    if (codeMatch || nameMatch) {
      matchedExisting = true;
      return {
        ...cg,
        // Patient already added this person → treat as approved/active (unless suspended).
        status: cg.status === "suspended" ? ("suspended" as const) : ("active" as const),
        name: opts.caregiverName || cg.name,
        relationship: opts.relationship || cg.relationship,
        email: opts.caregiverEmail || cg.email,
        phone: opts.caregiverPhone || cg.phone,
        inviteCode: inviteCode || cg.inviteCode,
        initials: makeInitials(opts.caregiverName || cg.name),
      };
    }
    return cg;
  });

  if (matchedExisting) return next;

  const already = next.some(
    cg =>
      (inviteCode && cg.inviteCode && namesMatch(cg.inviteCode, inviteCode)) ||
      (!!opts.caregiverName && namesMatch(cg.name, opts.caregiverName)) ||
      cg.id === opts.caregiverId,
  );

  if (already) return next;

  // Caregiver self-requested access — patient must approve. Respect max caregivers.
  if (!canAddCaregiver(next)) return next;

  return [
    ...next,
    {
      id: opts.caregiverId,
      name: opts.caregiverName || "Caregiver",
      relationship: opts.relationship || "Caregiver",
      initials: makeInitials(opts.caregiverName || "CG"),
      email: opts.caregiverEmail,
      phone: opts.caregiverPhone,
      grants: ["mood", "checkin_summary", "med_adherence"],
      status: "pending",
      inviteCode: inviteCode || undefined,
      addedByPatient: false,
    },
  ];
}

export function approveCaregiverInCircle(
  circle: LinkedCaregiver[],
  caregiverId: string,
): LinkedCaregiver[] {
  return circle.map(cg =>
    cg.id === caregiverId && cg.status === "pending"
      ? { ...cg, status: "active" as const }
      : cg,
  );
}

export function medAdherencePercent(
  medicationsCount: number,
  medsChecked: Record<string, boolean>,
): number {
  const total = Math.max(1, medicationsCount || 1);
  const taken = Object.values(medsChecked).filter(Boolean).length;
  if (medicationsCount === 0) return 0;
  return Math.round((taken / total) * 100);
}
