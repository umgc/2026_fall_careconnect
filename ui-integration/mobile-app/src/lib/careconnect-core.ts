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

/** True when names are exact or one full name contains the other (e.g. Eleanor vs Eleanor Wright). */
export function namesLooselyMatch(a: string, b: string): boolean {
  const na = a.trim().toLowerCase().replace(/\s+/g, " ");
  const nb = b.trim().toLowerCase().replace(/\s+/g, " ");
  if (!na || !nb) return false;
  if (na === nb) return true;
  return na.includes(nb) || nb.includes(na);
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

/** Minimum length for a color-sequence passcode (open-ended above this). */
export const MIN_COLOR_SEQ_LENGTH = 6;

/** Failed sign-in attempts before a temporary lockout. */
export const MAX_SIGNIN_ATTEMPTS = 5;

/** Lockout duration after too many failed sign-ins. */
export const SIGNIN_LOCKOUT_MS = 60_000;

export interface SignInAttemptState {
  failures: number;
  lockedUntil: number | null;
}

export function emptySignInAttemptState(): SignInAttemptState {
  return { failures: 0, lockedUntil: null };
}

export function isSignInLocked(state: SignInAttemptState, now = Date.now()): boolean {
  return state.lockedUntil != null && state.lockedUntil > now;
}

export function remainingSignInAttempts(state: SignInAttemptState): number {
  return Math.max(0, MAX_SIGNIN_ATTEMPTS - state.failures);
}

/** Record a failed attempt; locks when the failure cap is reached. */
export function recordSignInFailure(
  state: SignInAttemptState,
  now = Date.now(),
): SignInAttemptState {
  if (isSignInLocked(state, now)) return state;
  const failures = state.failures + 1;
  if (failures >= MAX_SIGNIN_ATTEMPTS) {
    return { failures, lockedUntil: now + SIGNIN_LOCKOUT_MS };
  }
  return { failures, lockedUntil: null };
}

/** Clear failures after a successful sign-in or when a lockout expires. */
export function clearSignInAttempts(
  state: SignInAttemptState = emptySignInAttemptState(),
  now = Date.now(),
): SignInAttemptState {
  if (state.lockedUntil != null && state.lockedUntil > now) return state;
  return emptySignInAttemptState();
}

export function isColorSeqConfigured(colorSeq?: string[] | null): boolean {
  return !!colorSeq && colorSeq.length >= MIN_COLOR_SEQ_LENGTH;
}

export function hasAnyAuthConfigured(creds: AuthCredentials): boolean {
  return !!(
    creds.password?.trim() ||
    creds.pin?.trim() ||
    isColorSeqConfigured(creds.colorSeq)
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
  if (methods.color && !isColorSeqConfigured(creds.colorSeq)) return false;
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
  if (expected.length < MIN_COLOR_SEQ_LENGTH) return false;
  const got = attempt.colorSeq || [];
  return got.length === expected.length && got.join() === expected.join();
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

const DEMO_CAREGIVER_NAMES = new Set([
  "maria rodriguez",
  "dr. sarah patel",
  "dr sarah patel",
]);

/** Seeded demo names and blank placeholders must never match a real caregiver. */
export function isDemoCaregiverName(name?: string): boolean {
  const n = (name || "").trim().toLowerCase();
  return !n || DEMO_CAREGIVER_NAMES.has(n) || n === "your name" || n === "caregiver";
}

/** Minimal patient snapshot shape needed to decide who a caregiver cares for. */
export interface PatientSnapshotLike {
  profileName: string;
  profileDob?: string;
  linkedCaregivers?: LinkedCaregiver[];
}

export interface CaregiverIdentity {
  id?: string;
  name?: string;
  email?: string;
  inviteCode?: string;
}

/** Stable key for a stored patient, qualified by DOB when one is known. */
export function patientSnapshotKey(name: string, dob?: string): string {
  const n = (name || "").trim().toLowerCase().replace(/\s+/g, " ");
  const d = normalizeDob(dob || "") || (dob || "").trim();
  return d ? `${n}|${d}` : n;
}

/** True when this caregiver appears in the patient's Care Circle. */
export function caregiverInPatientCircle(
  snap: PatientSnapshotLike,
  caregiver: CaregiverIdentity,
): boolean {
  const circle = snap.linkedCaregivers ?? [];
  if (!circle.length) return false;
  const invite = (caregiver.inviteCode || "").trim();
  const id = (caregiver.id || "").trim();
  const name = (caregiver.name || "").trim();
  const email = (caregiver.email || "").trim();
  return circle.some(c => {
    if (invite && c.inviteCode && namesMatch(c.inviteCode, invite)) return true;
    if (id && c.id === id) return true;
    if (
      name
      && !isDemoCaregiverName(name)
      && (namesMatch(c.name, name) || namesLooselyMatch(c.name, name))
    ) return true;
    if (
      email
      && c.email?.trim()
      && (namesMatch(c.email, email) || namesLooselyMatch(c.email, email))
    ) return true;
    return false;
  });
}

/**
 * Pick which patient a caregiver is caring for.
 *
 * The caregiver's linked patient name normally wins, but Care Circle membership
 * overrides it when that name points at someone whose circle does not contain
 * this caregiver — the situation created when a second patient signs in on the
 * same browser and overwrites the single "active patient" slot.
 */
export function resolvePatientForCaregiver<T extends PatientSnapshotLike>(opts: {
  snapshots: T[];
  activeSnapshot?: T | null;
  linkedPatientName?: string;
  linkedPatientDob?: string;
  caregiver?: CaregiverIdentity;
}): T | null {
  const wantedName = (opts.linkedPatientName || "").trim();
  const wantedDob =
    normalizeDob(opts.linkedPatientDob || "") || (opts.linkedPatientDob || "").trim();

  const seen = new Set<string>();
  const all: T[] = [];
  for (const snap of opts.snapshots) {
    if (!snap?.profileName || snap.profileName === "Your Name") continue;
    const key = patientSnapshotKey(snap.profileName, snap.profileDob);
    if (seen.has(key)) continue;
    seen.add(key);
    all.push(snap);
  }

  const nameMatch = (snap: T): boolean => {
    if (!wantedName) return false;
    const nameOk =
      namesMatch(snap.profileName, wantedName)
      || namesLooselyMatch(snap.profileName, wantedName);
    const dobOk = !wantedDob || !snap.profileDob || dobsMatch(snap.profileDob, wantedDob);
    return nameOk && dobOk;
  };

  const byLinkedName = wantedName ? (all.find(nameMatch) ?? null) : null;
  const membership = opts.caregiver
    ? all.filter(snap => caregiverInPatientCircle(snap, opts.caregiver!))
    : [];

  if (
    opts.caregiver
    && membership.length === 1
    && (!byLinkedName || !caregiverInPatientCircle(byLinkedName, opts.caregiver))
  ) {
    return membership[0];
  }

  if (membership.length > 1 && wantedName) {
    const namedMember = membership.find(nameMatch);
    if (namedMember) return namedMember;
  }

  if (byLinkedName) return byLinkedName;
  if (membership.length === 1) return membership[0];

  // Fall back to the active snapshot only when it is plausibly the right person.
  const active = opts.activeSnapshot;
  if (!active?.profileName || active.profileName === "Your Name") return null;
  if (!wantedName) {
    return opts.caregiver && caregiverInPatientCircle(active, opts.caregiver) ? active : null;
  }
  return nameMatch(active) ? active : null;
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
  linkedPatientDob?: string;
  linkedInviteCode?: string;
  caregiverName?: string;
  caregiverEmail?: string;
  personas?: CaregiverPersonaInfo[];
}): PatientSnippet[] {
  if (!opts.linkedPatientName?.trim()) {
    return [];
  }

  const nameOk =
    !!opts.profileName
    && opts.profileName !== "Your Name"
    && (
      namesMatch(opts.linkedPatientName, opts.profileName)
      || namesLooselyMatch(opts.linkedPatientName, opts.profileName)
    );
  const dobOk = !!(
    opts.linkedPatientDob
    && opts.profileDob
    && dobsMatch(opts.linkedPatientDob, opts.profileDob)
  );

  // Patient identity is confirmed by matching name and/or DOB from caregiver setup.
  if (!opts.profileName || opts.profileName === "Your Name" || (!nameOk && !dobOk)) {
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
  const byInvite = opts.linkedInviteCode
    ? opts.linkedCaregivers.find(
        c => c.inviteCode && namesMatch(c.inviteCode, opts.linkedInviteCode!),
      )
    : undefined;
  const byId = opts.linkedCaregivers.find(c => c.id === opts.caregiverId);
  const byName = opts.caregiverName
    ? opts.linkedCaregivers.find(c =>
        namesMatch(c.name, opts.caregiverName!)
        || namesLooselyMatch(c.name, opts.caregiverName!),
      )
    : undefined;
  const byEmail = opts.caregiverEmail?.trim()
    ? opts.linkedCaregivers.find(
        c => !!c.email?.trim() && (
          namesMatch(c.email!, opts.caregiverEmail!)
          || namesLooselyMatch(c.email!, opts.caregiverEmail!)
        ),
      )
    : undefined;
  // Prefer caregivers who already have shared grants so patient-granted access
  // shows even when caregiver ids differ across sessions.
  const withGrants = opts.linkedCaregivers.filter(
    c => c.status !== "suspended" && c.grants.length > 0,
  );
  const bySoloGranted =
    !byInvite && !byId && !byName && !byEmail && withGrants.length === 1
      ? withGrants[0]
      : undefined;
  const activeWithGrants = opts.linkedCaregivers.filter(
    c => c.status === "active" && c.grants.length > 0,
  );
  const bySoloActive =
    !byInvite && !byId && !byName && !byEmail && !bySoloGranted && activeWithGrants.length === 1
      ? activeWithGrants[0]
      : undefined;
  const activeOrPending = opts.linkedCaregivers.filter(c => c.status !== "suspended");
  const bySolo =
    !byInvite && !byId && !byName && !byEmail && !bySoloGranted && !bySoloActive && activeOrPending.length === 1
      ? activeOrPending[0]
      : undefined;
  const link = byInvite || byId || byName || byEmail || bySoloGranted || bySoloActive || bySolo;

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

  // If the patient already shared grant items, treat the link as authorized even when
  // status is still "pending" (invite waiting to join) or otherwise non-active.
  // Suspended is handled above. This fixes "Access not authorized" after grants are on.
  const grants = [...link.grants];
  if (grants.length > 0 && link.status !== "suspended") {
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

  if (link.status === "pending") {
    return [{ ...base, grants: [], accessState: "pending" as const }];
  }

  if (link.status !== "active") {
    return [{ ...base, grants: [], accessState: "unauthorized" as const }];
  }

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
    const nameMatch = !!(opts.caregiverName && (
      namesMatch(cg.name, opts.caregiverName)
      || namesLooselyMatch(cg.name, opts.caregiverName)
    ));
    const emailMatch = !!(opts.caregiverEmail?.trim() && cg.email?.trim() && (
      namesMatch(cg.email, opts.caregiverEmail)
      || namesLooselyMatch(cg.email, opts.caregiverEmail)
    ));
    // Only treat as patient-approved when the Care Circle already has this invite or person.
    if (codeMatch || nameMatch || emailMatch) {
      matchedExisting = true;
      return {
        ...cg,
        // Patient already added this person → treat as approved/active (unless suspended).
        // Keep any grants the patient already toggled on.
        status: cg.status === "suspended" ? ("suspended" as const) : ("active" as const),
        name: opts.caregiverName || cg.name,
        relationship: opts.relationship || cg.relationship,
        email: opts.caregiverEmail || cg.email,
        phone: opts.caregiverPhone || cg.phone,
        inviteCode: inviteCode || cg.inviteCode,
        initials: makeInitials(opts.caregiverName || cg.name),
        grants: cg.grants.length > 0
          ? cg.grants
          : (["mood", "checkin_summary", "med_adherence"] as GrantedItem[]),
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

/** Multi-provider email detection for Mail Digest connect flow. */
export type EmailProviderId =
  | "gmail"
  | "microsoft"
  | "yahoo"
  | "apple"
  | "aol"
  | "zoho"
  | "imap";

export type EmailAuthMode = "oauth" | "imap";

export interface DetectedEmailProvider {
  provider: EmailProviderId;
  authMode: EmailAuthMode;
  label: string;
  imapHost?: string;
  imapPort?: number;
}

const EMAIL_BASIC_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function isValidEmailFormat(email: string): boolean {
  return EMAIL_BASIC_RE.test(email.trim());
}

export function detectEmailProvider(email: string): DetectedEmailProvider | null {
  if (!isValidEmailFormat(email)) return null;
  const domain = email.trim().split("@")[1]?.toLowerCase() || "";
  if (["gmail.com", "googlemail.com"].includes(domain)) {
    return { provider: "gmail", authMode: "oauth", label: "Gmail" };
  }
  if (["outlook.com", "hotmail.com", "live.com", "msn.com", "office365.com"].includes(domain)
    || domain.endsWith(".onmicrosoft.com")) {
    return { provider: "microsoft", authMode: "oauth", label: "Microsoft / Outlook" };
  }
  if (["yahoo.com", "ymail.com", "rocketmail.com"].includes(domain)) {
    return { provider: "yahoo", authMode: "imap", label: "Yahoo", imapHost: "imap.mail.yahoo.com", imapPort: 993 };
  }
  if (["icloud.com", "me.com", "mac.com"].includes(domain)) {
    return { provider: "apple", authMode: "imap", label: "Apple iCloud", imapHost: "imap.mail.me.com", imapPort: 993 };
  }
  if (["aol.com"].includes(domain)) {
    return { provider: "aol", authMode: "imap", label: "AOL", imapHost: "imap.aol.com", imapPort: 993 };
  }
  if (domain === "zoho.com" || domain.endsWith(".zoho.com")) {
    return { provider: "zoho", authMode: "imap", label: "Zoho", imapHost: "imap.zoho.com", imapPort: 993 };
  }
  return {
    provider: "imap",
    authMode: "imap",
    label: "Other IMAP",
    imapHost: `imap.${domain}`,
    imapPort: 993,
  };
}

/** Patient profile share tokens (demo / local). */
export function createProfileShareToken(): string {
  const rand = Math.random().toString(36).slice(2, 10);
  return `ps-${Date.now().toString(36)}-${rand}`;
}

export function buildProfileShareUrl(token: string, patientName?: string): string {
  const origin = typeof window !== "undefined" ? window.location.origin : "https://careconnect.app";
  const q = patientName?.trim()
    ? `?patient=${encodeURIComponent(patientName.trim())}`
    : "";
  return `${origin}/p/${token}${q}`;
}

export type SymptomTrendRange = "week" | "month" | "year";

export interface SymptomTrendPoint {
  label: string;
  dateKey: string;
  /** Average severity per named symptom series */
  series: Record<string, number | null>;
}

function parseSymptomDay(date?: string, time?: string): Date | null {
  if (date && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
    const d = new Date(`${date}T12:00:00`);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (time) {
    const d = new Date(time);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function dayKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/** Aggregate raw symptom logs into Week / Month / Year trend points. */
export function buildSymptomTrendPoints(
  entries: { name: string; severity: number; date?: string; time?: string }[],
  range: SymptomTrendRange,
  now = new Date(),
): SymptomTrendPoint[] {
  const names = Array.from(new Set(entries.map(e => e.name).filter(Boolean))).slice(0, 5);
  const points: SymptomTrendPoint[] = [];

  // Year and Month both use calendar-month buckets (Month = last 6, Year = last 12).
  if (range === "month" || range === "year") {
    const monthCount = range === "month" ? 6 : 12;
    const start = new Date(now.getFullYear(), now.getMonth() - (monthCount - 1), 1);
    for (let i = 0; i < monthCount; i++) {
      const cursor = new Date(start.getFullYear(), start.getMonth() + i, 1);
      const key = `${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, "0")}`;
      const series: Record<string, number | null> = {};
      for (const name of names) {
        const matches = entries.filter(e => {
          const d = parseSymptomDay(e.date, e.time);
          if (!d || e.name !== name) return false;
          return d.getFullYear() === cursor.getFullYear() && d.getMonth() === cursor.getMonth();
        });
        if (!matches.length) series[name] = null;
        else series[name] = matches.reduce((s, m) => s + m.severity, 0) / matches.length;
      }
      points.push({
        label: cursor.toLocaleString(undefined, { month: "short" }),
        dateKey: key,
        series,
      });
    }
    return points;
  }

  // Week: last 7 calendar days
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  start.setDate(start.getDate() - 6);
  for (let i = 0; i < 7; i++) {
    const cursor = new Date(start);
    cursor.setDate(start.getDate() + i);
    const key = dayKey(cursor);
    const series: Record<string, number | null> = {};
    for (const name of names) {
      const matches = entries.filter(e => {
        const d = parseSymptomDay(e.date, e.time);
        return d && e.name === name && dayKey(d) === key;
      });
      if (!matches.length) series[name] = null;
      else series[name] = matches.reduce((s, m) => s + m.severity, 0) / matches.length;
    }
    points.push({
      label: cursor.toLocaleString(undefined, { weekday: "short" }),
      dateKey: key,
      series,
    });
  }
  return points;
}

export function isProfessionalCaregiverPersona(persona?: string | null): boolean {
  return persona === "primary_physician";
}

/** Heuristic speaker labels used by Hearing Conversation Assist. */
export const HEARING_SPEAKER_LABELS = ["You", "Doctor", "Caregiver", "Nurse", "Other"] as const;
export type HearingSpeakerLabel = (typeof HEARING_SPEAKER_LABELS)[number];

/**
 * Automatically identify who is talking from caption text (demo / browser-safe
 * diarization). Prefers content cues; otherwise alternates with the previous speaker.
 */
export function inferSpeakerFromText(
  text: string,
  previousSpeaker?: string | null,
): HearingSpeakerLabel {
  const t = (text || "").toLowerCase().trim();
  if (!t) return (previousSpeaker as HearingSpeakerLabel) || "Doctor";

  const youCue =
    /\b(i (feel|felt|have|had|am|was|need|took|will|can|could|want|don'?t)|my (blood pressure|medication|pills|pain)|a little tired)\b/.test(t);
  const doctorCue =
    /\b(dosage|prescription|diagnosis|clinic|continue your|we'?ll review|good morning|how have you been|expected with|appointment time|blood pressure looks|vitals look|with me in clinic)\b/.test(t)
    || /\b(dr\.|doctor)\b/.test(t);
  const nurseCue =
    /\b(nurse|bandage|injection|i('ll| will) take (your|the) (vitals|blood pressure)|chart)\b/.test(t);
  const caregiverCue =
    /\b(i('ll| will) help|set (phone )?reminders|picked (you )?up|caregiver|as your (son|daughter|spouse))\b/.test(t);

  const scores: Record<HearingSpeakerLabel, number> = {
    You: youCue ? 3 : 0,
    Doctor: doctorCue ? 3 : 0,
    Nurse: nurseCue ? 3 : 0,
    Caregiver: caregiverCue ? 3 : 0,
    Other: 0,
  };

  // Soft first-person vs clinical imperative
  if (/\byou (should|need to|must|will)\b/.test(t)) scores.Doctor += 2;
  if (/\bcan you (repeat|say|explain)\b/.test(t)) scores.You += 2;

  let best: HearingSpeakerLabel = "Other";
  let bestScore = 0;
  (Object.keys(scores) as HearingSpeakerLabel[]).forEach(label => {
    if (scores[label] > bestScore) {
      bestScore = scores[label];
      best = label;
    }
  });

  if (bestScore > 0) return best;

  // Alternate when cues are weak so consecutive turns don't all share one label
  if (previousSpeaker === "You") return "Doctor";
  if (previousSpeaker === "Doctor" || previousSpeaker === "Nurse") return "You";
  if (previousSpeaker === "Caregiver") return "You";
  return "Doctor";
}
