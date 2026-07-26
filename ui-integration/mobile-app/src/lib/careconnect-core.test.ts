import { describe, expect, it } from "vitest";
import {
  activateInviteInCareCircle,
  approveCaregiverInCircle,
  ageFromDob,
  buildCaregiverPatientRoster,
  buildInviteUrl,
  canAddCaregiver,
  caregiverInPatientCircle,
  caregiverPatientConfirmed,
  credentialsForSelectedMethods,
  dobsMatch,
  formatCheckinStamp,
  hasAnyAuthConfigured,
  isDemoCaregiverName,
  makeInitials,
  MAX_CAREGIVERS,
  medAdherencePercent,
  namesMatch,
  normalizeDob,
  parseInviteFromUrl,
  patientSnapshotKey,
  resolvePatientForCaregiver,
  qrImageUrl,
  validateSelectedAuthMethods,
  verifySignIn,
  MIN_COLOR_SEQ_LENGTH,
  recordSignInFailure,
  clearSignInAttempts,
  isSignInLocked,
  remainingSignInAttempts,
  emptySignInAttemptState,
  MAX_SIGNIN_ATTEMPTS,
  detectEmailProvider,
  isValidEmailFormat,
  buildProfileShareUrl,
  createProfileShareToken,
  buildSymptomTrendPoints,
  inferSpeakerFromText,
  isProfessionalCaregiverPersona,
  type LinkedCaregiver,
  type PatientSnapshotLike,
} from "./careconnect-core";

const personas = [
  { id: "cg1", label: "Care Coordinator", name: "Maria Rodriguez" },
  { id: "cg2", label: "Primary Care Physician", name: "Dr. Sarah Patel" },
];

const activeLink: LinkedCaregiver = {
  id: "cg1",
  name: "Maria Rodriguez",
  relationship: "Care Coordinator",
  initials: "MR",
  grants: ["mood", "checkin_summary", "med_adherence", "upcoming_visits", "symptoms", "fall_alerts"],
  status: "active",
  inviteCode: "cc-abc123",
};

describe("makeInitials", () => {
  it("returns ? for empty", () => expect(makeInitials("")).toBe("?"));
  it("uses two letters for single name", () => expect(makeInitials("Ada")).toBe("AD"));
  it("uses first/last initials", () => expect(makeInitials("Ada Lovelace")).toBe("AL"));
});

describe("namesMatch", () => {
  it("ignores case and trim", () => {
    expect(namesMatch("  Eleanor Wright ", "eleanor wright")).toBe(true);
    expect(namesMatch("A", "B")).toBe(false);
  });
});

describe("normalizeDob / dobsMatch", () => {
  it("normalizes slash and ISO dates", () => {
    expect(normalizeDob("7/17/1954")).toBe("07/17/1954");
    expect(normalizeDob("1954-07-17")).toBe("07/17/1954");
    expect(normalizeDob("bad")).toBe("");
    expect(dobsMatch("7/17/1954", "07/17/1954")).toBe(true);
    expect(dobsMatch("07/17/1954", "07/18/1954")).toBe(false);
  });
});

describe("ageFromDob", () => {
  const today = new Date(2026, 6, 17); // Jul 17, 2026
  it("returns 0 for blank", () => expect(ageFromDob("", today)).toBe(0));
  it("parses ISO date", () => expect(ageFromDob("1954-07-17", today)).toBe(72));
  it("parses slash date", () => expect(ageFromDob("07/17/1954", today)).toBe(72));
  it("parses two-digit year as 19xx", () => expect(ageFromDob("07/17/54", today)).toBe(72));
  it("returns 0 for invalid", () => expect(ageFromDob("not-a-date", today)).toBe(0));
  it("decrements before birthday", () => {
    expect(ageFromDob("1954-12-25", today)).toBe(71);
  });
});

describe("formatCheckinStamp", () => {
  it("formats AM time", () => {
    expect(formatCheckinStamp(new Date(2026, 0, 1, 9, 5))).toBe("Today 9:05 AM");
  });
  it("formats PM time", () => {
    expect(formatCheckinStamp(new Date(2026, 0, 1, 15, 30))).toBe("Today 3:30 PM");
  });
  it("formats noon-ish as PM", () => {
    expect(formatCheckinStamp(new Date(2026, 0, 1, 12, 0))).toBe("Today 12:00 PM");
  });
  it("formats midnight as AM", () => {
    expect(formatCheckinStamp(new Date(2026, 0, 1, 0, 0))).toBe("Today 12:00 AM");
  });
});

describe("invite URL helpers", () => {
  it("builds URL without patient", () => {
    expect(buildInviteUrl("cc-1")).toBe("https://careconnect.app/invite/cc-1");
  });
  it("builds URL with patient query", () => {
    expect(buildInviteUrl("cc-1", "Eleanor Wright")).toContain("patient=Eleanor%20Wright");
  });
  it("parses bare code", () => {
    expect(parseInviteFromUrl("cc-xyz9")).toEqual({ code: "cc-xyz9" });
  });
  it("parses full URL with patient", () => {
    const parsed = parseInviteFromUrl(
      "https://careconnect.app/invite/cc-xyz9?patient=Eleanor%20Wright",
    );
    expect(parsed).toEqual({ code: "cc-xyz9", patientName: "Eleanor Wright" });
  });
  it("parses path-only invite", () => {
    expect(parseInviteFromUrl("cc-hello")).toEqual({ code: "cc-hello" });
  });
  it("returns null for empty/invalid", () => {
    expect(parseInviteFromUrl("")).toBeNull();
    expect(parseInviteFromUrl("https://example.com/nope")).toBeNull();
  });
  it("builds QR image URL", () => {
    expect(qrImageUrl("hello", 100)).toContain("size=100x100");
    expect(qrImageUrl("hello")).toContain(encodeURIComponent("hello"));
  });
});

describe("auth helpers", () => {
  const sixColors = ["#1", "#2", "#3", "#4", "#5", "#6"];

  it("detects configured auth", () => {
    expect(hasAnyAuthConfigured({})).toBe(false);
    expect(hasAnyAuthConfigured({ password: "abcd" })).toBe(true);
    expect(hasAnyAuthConfigured({ pin: "1234" })).toBe(true);
    expect(hasAnyAuthConfigured({ colorSeq: ["a", "b", "c"] })).toBe(false);
    expect(hasAnyAuthConfigured({ colorSeq: sixColors })).toBe(true);
  });

  it("validates selected methods", () => {
    expect(
      validateSelectedAuthMethods(
        { pin: false, password: false, color: false },
        { password: "abcd" },
      ),
    ).toBe(false);
    expect(
      validateSelectedAuthMethods(
        { pin: false, password: true, color: false },
        { password: "ab" },
      ),
    ).toBe(false);
    expect(
      validateSelectedAuthMethods(
        { pin: true, password: true, color: true },
        { password: "abcd", pin: "1234", colorSeq: sixColors },
      ),
    ).toBe(true);
    expect(
      validateSelectedAuthMethods(
        { pin: false, password: false, color: true },
        { colorSeq: ["#1", "#2", "#3"] },
      ),
    ).toBe(false);
  });

  it("strips deselected credentials", () => {
    expect(
      credentialsForSelectedMethods(
        { pin: true, password: false, color: false },
        { password: "secret", pin: "9999", colorSeq: sixColors },
      ),
    ).toEqual({ password: "", pin: "9999", colorSeq: [] });
  });

  it("verifies password/pin/color sign-in", () => {
    const stored = {
      password: "care123",
      pin: "4321",
      colorSeq: ["#3B82F6", "#F59E0B", "#10B981", "#000000", "#FFFFFF", "#00A7C8"],
    };
    expect(verifySignIn("password", { password: "care123" }, stored)).toBe(true);
    expect(verifySignIn("password", { password: "nope" }, stored)).toBe(false);
    expect(verifySignIn("password", { password: "x" }, {})).toBe(false);
    expect(verifySignIn("pin", { pin: "4321" }, stored)).toBe(true);
    expect(verifySignIn("pin", { pin: "0000" }, stored)).toBe(false);
    expect(verifySignIn("pin", { pin: "1" }, { pin: "" })).toBe(false);
    expect(
      verifySignIn("color", {
        colorSeq: ["#3B82F6", "#F59E0B", "#10B981", "#000000", "#FFFFFF", "#00A7C8"],
      }, stored),
    ).toBe(true);
    expect(verifySignIn("color", { colorSeq: ["#3B82F6"] }, stored)).toBe(false);
    expect(verifySignIn("color", { colorSeq: sixColors }, { colorSeq: [] })).toBe(false);
  });

  it("locks after too many failed attempts", () => {
    let state = emptySignInAttemptState();
    for (let i = 0; i < MAX_SIGNIN_ATTEMPTS - 1; i++) {
      state = recordSignInFailure(state, 1_000);
      expect(isSignInLocked(state, 1_000)).toBe(false);
    }
    expect(remainingSignInAttempts(state)).toBe(1);
    state = recordSignInFailure(state, 1_000);
    expect(isSignInLocked(state, 1_000)).toBe(true);
    expect(remainingSignInAttempts(state)).toBe(0);
    expect(clearSignInAttempts(state, 1_000).failures).toBe(MAX_SIGNIN_ATTEMPTS);
    expect(clearSignInAttempts(state, 1_000 + 60_001)).toEqual(emptySignInAttemptState());
  });

  it("exports a colour-sequence minimum of 6", () => {
    expect(MIN_COLOR_SEQ_LENGTH).toBe(6);
  });

  it("requires patient confirmation for caregivers", () => {
    expect(caregiverPatientConfirmed("")).toBe(false);
    expect(caregiverPatientConfirmed("Eleanor")).toBe(false);
    expect(caregiverPatientConfirmed("Eleanor", undefined, "07/17/1954")).toBe(true);
    expect(caregiverPatientConfirmed("Eleanor", "Your Name", "07/17/1954")).toBe(true);
    expect(caregiverPatientConfirmed("Eleanor", "Eleanor Wright", "07/17/1954")).toBe(false);
    expect(caregiverPatientConfirmed("Eleanor Wright", "eleanor wright", "07/17/1954")).toBe(true);
    expect(caregiverPatientConfirmed("Eleanor Wright", "Eleanor Wright", "bad")).toBe(false);
    expect(caregiverPatientConfirmed("Eleanor Wright", "Eleanor Wright", "07/17/1954", "07/18/1954")).toBe(false);
    expect(caregiverPatientConfirmed("Eleanor Wright", "Eleanor Wright", "7/17/1954", "07/17/1954")).toBe(true);
  });
});

describe("medAdherencePercent", () => {
  it("computes percentage", () => {
    expect(medAdherencePercent(4, { a: true, b: true, c: false, d: false })).toBe(50);
  });
  it("returns 0 when no medications", () => {
    expect(medAdherencePercent(0, {})).toBe(0);
  });
});

describe("buildCaregiverPatientRoster", () => {
  const base = {
    caregiverId: "cg1",
    linkedCaregivers: [activeLink],
    patientActive: true,
    profileName: "Eleanor Wright",
    profileDob: "07/17/1954",
    profileConditions: "Hypertension",
    profileAllergies: "Penicillin",
    medAdherence: 90,
    personas,
    linkedPatientName: "Eleanor Wright",
    mood: 4,
    lastCheckin: "Today 8:00 AM",
    nextVisit: "Thu 2:00 PM",
    hasFallAlert: false,
  };

  it("returns empty without confirmed patient", () => {
    expect(buildCaregiverPatientRoster({ ...base, linkedPatientName: "" })).toEqual([]);
  });

  it("blocks unmatched patient names", () => {
    const result = buildCaregiverPatientRoster({
      ...base,
      linkedPatientName: "Someone Else",
    });
    expect(result[0].accessState).toBe("unauthorized");
    expect(result[0].id).toBe("patient-unmatched");
  });

  it("allows access when DOB matches even if names differ slightly", () => {
    const result = buildCaregiverPatientRoster({
      ...base,
      linkedPatientName: "Eleanor",
      linkedPatientDob: "07/17/1954",
      caregiverId: "other-id",
      caregiverName: "Maria Rodriguez",
    });
    expect(result[0].accessState).toBe("ok");
    expect(result[0].grants).toEqual(activeLink.grants);
  });

  it("matches the only active Care Circle member with grants when ids differ", () => {
    const result = buildCaregiverPatientRoster({
      ...base,
      caregiverId: "session-xyz",
      caregiverName: "Different Label",
      linkedInviteCode: undefined,
      linkedCaregivers: [{
        ...activeLink,
        id: "cg-patient-created",
        name: "James Wright",
        status: "active",
        grants: ["mood", "checkin_summary"],
      }],
    });
    expect(result[0].accessState).toBe("ok");
    expect(result[0].grants).toEqual(["mood", "checkin_summary"]);
  });

  it("matches caregiver by email", () => {
    const result = buildCaregiverPatientRoster({
      ...base,
      caregiverId: "other",
      caregiverName: "Someone",
      caregiverEmail: "maria@example.com",
      linkedInviteCode: undefined,
      linkedCaregivers: [{
        ...activeLink,
        id: "cg-x",
        name: "Maria R",
        email: "maria@example.com",
        grants: ["mood"],
      }],
    });
    expect(result[0].accessState).toBe("ok");
    expect(result[0].mood).toBe(4);
  });

  it("blocks when Care Circle link missing", () => {
    const result = buildCaregiverPatientRoster({
      ...base,
      linkedCaregivers: [],
    });
    expect(result[0].accessState).toBe("unauthorized");
  });

  it("returns inactive profile state", () => {
    const result = buildCaregiverPatientRoster({ ...base, patientActive: false });
    expect(result[0].accessState).toBe("inactive_profile");
  });

  it("returns pending/suspended states", () => {
    expect(
      buildCaregiverPatientRoster({
        ...base,
        linkedCaregivers: [{ ...activeLink, status: "pending", grants: [] }],
      })[0].accessState,
    ).toBe("pending");
    expect(
      buildCaregiverPatientRoster({
        ...base,
        linkedCaregivers: [{ ...activeLink, status: "suspended" }],
      })[0].accessState,
    ).toBe("suspended");
  });

  it("authorizes pending links that already have patient grants", () => {
    expect(
      buildCaregiverPatientRoster({
        ...base,
        linkedCaregivers: [{
          ...activeLink,
          status: "pending",
          grants: ["mood", "checkin_summary"],
        }],
      })[0].accessState,
    ).toBe("ok");
  });

  it("matches by invite code and exposes only granted fields", () => {
    const result = buildCaregiverPatientRoster({
      ...base,
      linkedInviteCode: "cc-abc123",
      linkedCaregivers: [{
        ...activeLink,
        grants: ["mood", "med_adherence"],
      }],
    });
    expect(result).toHaveLength(1);
    expect(result[0].accessState).toBe("ok");
    expect(result[0].mood).toBe(4);
    expect(result[0].medAdherence).toBe(90);
    expect(result[0].lastCheckin).toBeUndefined();
    expect(result[0].name).toBe("Eleanor Wright");
  });

  it("matches caregiver by name when id differs", () => {
    const result = buildCaregiverPatientRoster({
      ...base,
      caregiverId: "other",
      caregiverName: "Maria Rodriguez",
      linkedInviteCode: undefined,
    });
    expect(result[0].accessState).toBe("ok");
  });

  it("includes symptoms summary from conditions when granted", () => {
    const result = buildCaregiverPatientRoster({
      ...base,
      linkedCaregivers: [{ ...activeLink, grants: ["symptoms"] }],
    });
    expect(result[0].symptomsSummary).toContain("Conditions:");
    expect(result[0].symptomsSummary).toContain("Allergies:");
  });

  it("uses provided symptoms summary when granted", () => {
    const result = buildCaregiverPatientRoster({
      ...base,
      symptomsSummary: "Headache today",
      linkedCaregivers: [{ ...activeLink, grants: ["symptoms"] }],
    });
    expect(result[0].symptomsSummary).toBe("Headache today");
  });

  it("scopes to a single patient only", () => {
    const result = buildCaregiverPatientRoster(base);
    expect(result).toHaveLength(1);
  });
});

describe("activateInviteInCareCircle", () => {
  it("activates pending invite by code when patient already added them", () => {
    const circle: LinkedCaregiver[] = [{
      id: "pending-1",
      name: "Invited caregiver",
      relationship: "Pending invite",
      initials: "IC",
      grants: ["mood"],
      status: "pending",
      inviteCode: "cc-new",
    }];
    const next = activateInviteInCareCircle(circle, {
      inviteCode: "cc-new",
      caregiverId: "cg1",
      caregiverName: "Maria Rodriguez",
      caregiverEmail: "m@example.com",
    });
    expect(next).toHaveLength(1);
    expect(next[0].status).toBe("active");
    expect(next[0].name).toBe("Maria Rodriguez");
  });

  it("adds caregiver as pending when not previously added by patient", () => {
    const next = activateInviteInCareCircle([], {
      inviteCode: "cc-brand",
      caregiverId: "cg2",
      caregiverName: "Dr. Sarah Patel",
      relationship: "Primary Care Physician",
    });
    expect(next).toHaveLength(1);
    expect(next[0].id).toBe("cg2");
    expect(next[0].status).toBe("pending");
    expect(next[0].inviteCode).toBe("cc-brand");
  });

  it("activates by caregiver name match when patient already listed them", () => {
    const circle: LinkedCaregiver[] = [{
      id: "x",
      name: "Maria Rodriguez",
      relationship: "Care Coordinator",
      initials: "MR",
      grants: ["mood"],
      status: "pending",
    }];
    const next = activateInviteInCareCircle(circle, {
      caregiverId: "cg1",
      caregiverName: "Maria Rodriguez",
    });
    expect(next[0].status).toBe("active");
  });

  it("does not append when Care Circle is already at max caregivers", () => {
    const circle: LinkedCaregiver[] = [
      { id: "a", name: "A", relationship: "R", initials: "A", grants: ["mood"], status: "active" },
      { id: "b", name: "B", relationship: "R", initials: "B", grants: ["mood"], status: "active" },
      { id: "c", name: "C", relationship: "R", initials: "C", grants: ["mood"], status: "active" },
    ];
    const next = activateInviteInCareCircle(circle, {
      inviteCode: "cc-overflow",
      caregiverId: "cg-new",
      caregiverName: "New Person",
    });
    expect(next).toHaveLength(3);
    expect(next.every(cg => cg.id !== "cg-new")).toBe(true);
  });
});

describe("approveCaregiverInCircle / canAddCaregiver", () => {
  it("approves a pending caregiver", () => {
    const circle: LinkedCaregiver[] = [{
      id: "cg1",
      name: "Maria",
      relationship: "Daughter",
      initials: "M",
      grants: ["mood"],
      status: "pending",
    }];
    expect(approveCaregiverInCircle(circle, "cg1")[0].status).toBe("active");
  });

  it("reports capacity against MAX_CAREGIVERS", () => {
    expect(canAddCaregiver([])).toBe(true);
    expect(canAddCaregiver([
      { id: "1", name: "A", relationship: "R", initials: "A", grants: [], status: "active" },
      { id: "2", name: "B", relationship: "R", initials: "B", grants: [], status: "active" },
      { id: "3", name: "C", relationship: "R", initials: "C", grants: [], status: "active" },
    ])).toBe(false);
    expect(MAX_CAREGIVERS).toBe(3);
  });
});

describe("coverage branch gaps", () => {
  it("covers slash-date edge branches", () => {
    const today = new Date(2026, 6, 17);
    expect(ageFromDob("99-99-9999", today)).toBe(0);
    expect(ageFromDob("07/17/2027", today)).toBe(0);
    expect(ageFromDob("12/25/54", today)).toBe(71);
  });

  it("parses invite URL without scheme and null catch", () => {
    expect(parseInviteFromUrl("not a url !!!")).toBeNull();
    expect(parseInviteFromUrl("https://careconnect.app/invite/cc-only")).toEqual({
      code: "cc-only",
      patientName: undefined,
    });
  });

  it("covers auth optional false branches", () => {
    expect(hasAnyAuthConfigured({ password: "   ", pin: "  ", colorSeq: ["a", "b"] })).toBe(false);
    expect(
      validateSelectedAuthMethods(
        { pin: true, password: false, color: false },
        { pin: "12" },
      ),
    ).toBe(false);
    expect(
      validateSelectedAuthMethods(
        { pin: false, password: false, color: true },
        { colorSeq: ["a"] },
      ),
    ).toBe(false);
    expect(
      credentialsForSelectedMethods(
        { pin: false, password: true, color: true },
        { password: "  secret  " },
      ),
    ).toEqual({ password: "secret", pin: "", colorSeq: [] });
    expect(verifySignIn("pin", { pin: "1234" }, { pin: "123" })).toBe(false);
    expect(verifySignIn("color", {}, { colorSeq: ["a", "b", "c", "d", "e", "f"] })).toBe(false);
  });

  it("covers roster fallback branches", () => {
    const activeLinkLocal: LinkedCaregiver = {
      id: "cg1",
      name: "Maria Rodriguez",
      relationship: "Care Coordinator",
      initials: "MR",
      grants: ["mood", "checkin_summary", "med_adherence", "upcoming_visits", "symptoms", "fall_alerts"],
      status: "active",
      inviteCode: "cc-abc123",
    };
    const personasLocal = [
      { id: "cg1", label: "Care Coordinator", name: "Maria Rodriguez" },
    ];
    const baseLocal = {
      caregiverId: "cg1",
      linkedCaregivers: [activeLinkLocal],
      patientActive: true,
      profileName: "Eleanor Wright",
      profileDob: "",
      profileConditions: "",
      profileAllergies: "",
      medAdherence: 90,
      personas: personasLocal,
      linkedPatientName: "Eleanor Wright",
    };
    expect(
      buildCaregiverPatientRoster({ ...baseLocal, profileName: "Your Name" })[0].accessState,
    ).toBe("unauthorized");
    expect(
      buildCaregiverPatientRoster({ ...baseLocal, profileName: "" })[0].accessState,
    ).toBe("unauthorized");
    expect(buildCaregiverPatientRoster(baseLocal)[0].age).toBe(0);
    expect(
      buildCaregiverPatientRoster({
        ...baseLocal,
        linkedCaregivers: [{ ...activeLinkLocal, grants: ["symptoms"] }],
      })[0].symptomsSummary,
    ).toBe("No recent symptoms logged");
    expect(
      buildCaregiverPatientRoster({
        ...baseLocal,
        linkedInviteCode: undefined,
        caregiverName: undefined,
      })[0].accessState,
    ).toBe("ok");
    const fallVisit = buildCaregiverPatientRoster({
      ...baseLocal,
      hasFallAlert: true,
      nextVisit: "",
      lastCheckin: "",
      mood: undefined,
      linkedCaregivers: [{
        ...activeLinkLocal,
        grants: ["fall_alerts", "upcoming_visits", "checkin_summary", "mood"],
      }],
    });
    expect(fallVisit[0].hasFallAlert).toBe(true);
    expect(fallVisit[0].nextVisit).toBeUndefined();
    expect(fallVisit[0].lastCheckin).toBeUndefined();
    expect(fallVisit[0].mood).toBeUndefined();
    const noPersona = buildCaregiverPatientRoster({
      ...baseLocal,
      caregiverId: "missing",
      linkedCaregivers: [],
      caregiverName: "Ghost",
      personas: [],
    });
    expect(noPersona[0].accessState).toBe("unauthorized");
    expect(noPersona[0].caregiverName).toBe("Ghost");
  });

  it("covers activateInvite unmatched and id-already branches", () => {
    const circle: LinkedCaregiver[] = [
      {
        id: "keep",
        name: "Other Person",
        relationship: "Friend",
        initials: "OP",
        grants: ["mood"],
        status: "pending",
        inviteCode: "cc-other",
      },
      {
        id: "cg1",
        name: "Someone",
        relationship: "Care Coordinator",
        initials: "S",
        grants: ["mood"],
        status: "pending",
      },
    ];
    const next = activateInviteInCareCircle(circle, {
      inviteCode: "cc-nomatch",
      caregiverId: "cg1",
      caregiverName: "Brand New Name",
      caregiverPhone: "555",
    });
    expect(next.find(c => c.id === "keep")?.status).toBe("pending");
    expect(next.find(c => c.id === "cg1")?.name).toBe("Someone");
    expect(next).toHaveLength(2);

    const added = activateInviteInCareCircle(
      [{
        id: "keep",
        name: "Other Person",
        relationship: "Friend",
        initials: "OP",
        grants: ["mood"],
        status: "pending",
      }],
      {
        caregiverId: "new-id",
        caregiverName: "",
      },
    );
    expect(added).toHaveLength(2);
    expect(added[1].name).toBe("Caregiver");
    expect(added[1].relationship).toBe("Caregiver");
  });
});

/** End-to-end domain flow: invite → confirm patient → roster visibility */
describe("e2e domain: invite scopes caregiver to one patient", () => {
  it("patient invite + caregiver confirmation unlocks only that patient", () => {
    const patientName = "Eleanor Wright";
    const code = "cc-e2e01";
    const url = buildInviteUrl(code, patientName);
    const parsed = parseInviteFromUrl(url);
    expect(parsed?.code).toBe(code);
    expect(parsed?.patientName).toBe(patientName);

    expect(caregiverPatientConfirmed(parsed!.patientName!, patientName, "01/01/1950", "01/01/1950")).toBe(true);

    const methods = { pin: true, password: true, color: false };
    const creds = credentialsForSelectedMethods(methods, {
      password: "secure1",
      pin: "2468",
      colorSeq: ["#1", "#2", "#3"],
    });
    expect(validateSelectedAuthMethods(methods, creds)).toBe(true);
    expect(verifySignIn("pin", { pin: "2468" }, creds)).toBe(true);
    expect(verifySignIn("color", { colorSeq: ["#1", "#2", "#3"] }, creds)).toBe(false);

    const circle = activateInviteInCareCircle([], {
      inviteCode: code,
      caregiverId: "cg1",
      caregiverName: "Maria Rodriguez",
    });
    expect(circle[0].status).toBe("pending");

    const approved = approveCaregiverInCircle(circle, "cg1");

    const roster = buildCaregiverPatientRoster({
      caregiverId: "cg1",
      linkedCaregivers: approved,
      patientActive: true,
      profileName: patientName,
      profileDob: "01/01/1950",
      profileConditions: "",
      profileAllergies: "",
      medAdherence: 100,
      linkedPatientName: patientName,
      linkedInviteCode: code,
      personas,
    });

    expect(roster).toHaveLength(1);
    expect(roster[0].name).toBe(patientName);
    expect(roster[0].accessState).toBe("ok");

    const other = buildCaregiverPatientRoster({
      caregiverId: "cg1",
      linkedCaregivers: approved,
      patientActive: true,
      profileName: patientName,
      profileDob: "01/01/1950",
      profileConditions: "",
      profileAllergies: "",
      medAdherence: 100,
      linkedPatientName: "Wrong Patient",
      linkedInviteCode: code,
      personas,
    });
    expect(other[0].accessState).toBe("unauthorized");
  });
});

describe("email provider detection", () => {
  it("validates email format", () => {
    expect(isValidEmailFormat("a@b.com")).toBe(true);
    expect(isValidEmailFormat("bad")).toBe(false);
  });

  it("routes known domains", () => {
    expect(detectEmailProvider("me@gmail.com")?.provider).toBe("gmail");
    expect(detectEmailProvider("me@outlook.com")?.provider).toBe("microsoft");
    expect(detectEmailProvider("me@yahoo.com")?.authMode).toBe("imap");
    expect(detectEmailProvider("me@icloud.com")?.label).toContain("Apple");
    expect(detectEmailProvider("me@custom.org")?.provider).toBe("imap");
  });
});

describe("profile share helpers", () => {
  it("creates token and share URL", () => {
    const token = createProfileShareToken();
    expect(token.startsWith("ps-")).toBe(true);
    expect(buildProfileShareUrl(token, "Ada")).toContain(`/p/${token}`);
    expect(buildProfileShareUrl(token, "Ada")).toContain("patient=Ada");
  });
});

describe("symptom trend aggregation", () => {
  it("builds week points for logged symptoms", () => {
    const today = new Date();
    const key = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
    const points = buildSymptomTrendPoints(
      [{ name: "Headache", severity: 4, date: key }],
      "week",
      today,
    );
    expect(points).toHaveLength(7);
    expect(points.some(p => p.series.Headache === 4)).toBe(true);
  });

  it("builds month view with month buckets only", () => {
    const today = new Date();
    const points = buildSymptomTrendPoints([], "month", today);
    expect(points).toHaveLength(6);
    expect(points.every(p => /^[A-Z][a-z]{2}$/.test(p.label) || p.label.length >= 3)).toBe(true);
  });

  it("identifies professional caregiver persona", () => {
    expect(isProfessionalCaregiverPersona("primary_physician")).toBe(true);
    expect(isProfessionalCaregiverPersona("care_coordinator")).toBe(false);
  });
});

describe("inferSpeakerFromText", () => {
  it("labels clinical guidance as Doctor", () => {
    expect(
      inferSpeakerFromText("That's expected with the new dosage. Please continue your medication."),
    ).toBe("Doctor");
  });

  it("labels first-person patient lines as You", () => {
    expect(
      inferSpeakerFromText("A little tired in the mornings, but my blood pressure feels steadier."),
    ).toBe("You");
  });

  it("labels reminder help as Caregiver", () => {
    expect(
      inferSpeakerFromText("I'll help set phone reminders for the evening dose."),
    ).toBe("Caregiver");
  });

  it("alternates when cues are weak", () => {
    expect(inferSpeakerFromText("Okay.", "You")).toBe("Doctor");
    expect(inferSpeakerFromText("Okay.", "Doctor")).toBe("You");
  });
});

// ── Multi-patient resolution (one browser, several patient accounts) ───────────

function caregiverEntry(over: Partial<LinkedCaregiver> = {}): LinkedCaregiver {
  return {
    id: "cg1",
    name: "James Wright",
    relationship: "Son",
    initials: "JW",
    grants: ["mood"],
    status: "active",
    ...over,
  };
}

function snapshot(
  profileName: string,
  profileDob: string,
  linkedCaregivers: LinkedCaregiver[] = [],
): PatientSnapshotLike {
  return { profileName, profileDob, linkedCaregivers };
}

const james = { id: "cg1", name: "James Wright", email: "james.wright@demo.com" };

/** Eleanor's circle contains James; Jean's does not. */
const eleanor = snapshot("Eleanor Wright", "07/17/1954", [
  caregiverEntry({ email: "james.wright@demo.com", inviteCode: "cc-eleanor" }),
]);
const jean = snapshot("Jean Carter", "03/02/1948", [
  caregiverEntry({ id: "cg2", name: "Nina Patel", initials: "NP", email: "nina@demo.com" }),
]);

describe("isDemoCaregiverName", () => {
  it("treats seeded and placeholder names as demo data", () => {
    expect(isDemoCaregiverName("Maria Rodriguez")).toBe(true);
    expect(isDemoCaregiverName("Dr. Sarah Patel")).toBe(true);
    expect(isDemoCaregiverName("Dr Sarah Patel")).toBe(true);
    expect(isDemoCaregiverName("Your Name")).toBe(true);
    expect(isDemoCaregiverName("Caregiver")).toBe(true);
    expect(isDemoCaregiverName("  ")).toBe(true);
    expect(isDemoCaregiverName()).toBe(true);
  });

  it("accepts a real caregiver name", () => {
    expect(isDemoCaregiverName("James Wright")).toBe(false);
  });
});

describe("patientSnapshotKey", () => {
  it("normalizes case, spacing, and DOB format", () => {
    expect(patientSnapshotKey("  Eleanor   Wright ", "7/17/1954")).toBe(
      "eleanor wright|07/17/1954",
    );
  });

  it("falls back to a name-only key without a DOB", () => {
    expect(patientSnapshotKey("Eleanor Wright")).toBe("eleanor wright");
  });

  it("keeps an unparseable DOB as a raw qualifier", () => {
    expect(patientSnapshotKey("Eleanor Wright", "unknown")).toBe("eleanor wright|unknown");
  });
});

describe("caregiverInPatientCircle", () => {
  it("is false when the circle is empty or missing", () => {
    expect(caregiverInPatientCircle(snapshot("Eleanor Wright", "07/17/1954"), james)).toBe(false);
    expect(caregiverInPatientCircle({ profileName: "Eleanor Wright" }, james)).toBe(false);
  });

  it("matches on invite code, id, name, and email", () => {
    expect(
      caregiverInPatientCircle(eleanor, { inviteCode: "CC-ELEANOR" }),
    ).toBe(true);
    expect(caregiverInPatientCircle(eleanor, { id: "cg1" })).toBe(true);
    expect(caregiverInPatientCircle(eleanor, { name: "James Wright" })).toBe(true);
    expect(caregiverInPatientCircle(eleanor, { email: "james.wright@demo.com" })).toBe(true);
  });

  it("matches a partial name loosely", () => {
    expect(caregiverInPatientCircle(eleanor, { name: "James" })).toBe(true);
  });

  it("ignores demo placeholder names so they cannot match a real person", () => {
    expect(caregiverInPatientCircle(eleanor, { name: "Caregiver" })).toBe(false);
  });

  it("is false for an unrelated caregiver", () => {
    expect(caregiverInPatientCircle(jean, james)).toBe(false);
  });
});

describe("resolvePatientForCaregiver", () => {
  it("returns the linked patient even when another patient signed in last", () => {
    const result = resolvePatientForCaregiver({
      snapshots: [eleanor, jean],
      activeSnapshot: jean,
      linkedPatientName: "Eleanor Wright",
      linkedPatientDob: "07/17/1954",
      caregiver: james,
    });
    expect(result?.profileName).toBe("Eleanor Wright");
  });

  it("prefers Care Circle membership when the linked name points at the wrong patient", () => {
    // James's stored account still says "Jean Carter", but only Eleanor's
    // Care Circle contains him — he must still see Eleanor.
    const result = resolvePatientForCaregiver({
      snapshots: [eleanor, jean],
      activeSnapshot: jean,
      linkedPatientName: "Jean Carter",
      linkedPatientDob: "03/02/1948",
      caregiver: james,
    });
    expect(result?.profileName).toBe("Eleanor Wright");
  });

  it("uses membership when no patient is linked yet", () => {
    const result = resolvePatientForCaregiver({
      snapshots: [eleanor, jean],
      activeSnapshot: jean,
      caregiver: james,
    });
    expect(result?.profileName).toBe("Eleanor Wright");
  });

  it("disambiguates by linked name when the caregiver is in several circles", () => {
    const shared = snapshot("Jean Carter", "03/02/1948", [
      caregiverEntry({ email: "james.wright@demo.com" }),
    ]);
    const result = resolvePatientForCaregiver({
      snapshots: [eleanor, shared],
      activeSnapshot: eleanor,
      linkedPatientName: "Jean Carter",
      caregiver: james,
    });
    expect(result?.profileName).toBe("Jean Carter");
  });

  it("falls back to the linked name when membership is ambiguous and unnamed", () => {
    const shared = snapshot("Jean Carter", "03/02/1948", [
      caregiverEntry({ email: "james.wright@demo.com" }),
    ]);
    const result = resolvePatientForCaregiver({
      snapshots: [eleanor, shared],
      activeSnapshot: eleanor,
      linkedPatientName: "Someone Else",
      caregiver: james,
    });
    expect(result).toBeNull();
  });

  it("matches a linked first name loosely", () => {
    const result = resolvePatientForCaregiver({
      snapshots: [eleanor, jean],
      linkedPatientName: "Eleanor",
      caregiver: james,
    });
    expect(result?.profileName).toBe("Eleanor Wright");
  });

  it("rejects a linked name whose DOB disagrees", () => {
    const result = resolvePatientForCaregiver({
      snapshots: [jean],
      activeSnapshot: jean,
      linkedPatientName: "Jean Carter",
      linkedPatientDob: "01/01/1900",
    });
    expect(result).toBeNull();
  });

  it("skips placeholder and duplicate snapshots", () => {
    const duplicate = snapshot("Eleanor Wright", "07/17/1954", []);
    const result = resolvePatientForCaregiver({
      snapshots: [
        { profileName: "Your Name" },
        { profileName: "" },
        eleanor,
        duplicate,
      ],
      linkedPatientName: "Eleanor Wright",
      caregiver: james,
    });
    // The first Eleanor entry wins, so her Care Circle is preserved.
    expect(result?.linkedCaregivers).toHaveLength(1);
  });

  it("uses the active snapshot only when it matches the linked patient", () => {
    expect(
      resolvePatientForCaregiver({
        snapshots: [],
        activeSnapshot: eleanor,
        linkedPatientName: "Eleanor Wright",
      })?.profileName,
    ).toBe("Eleanor Wright");

    expect(
      resolvePatientForCaregiver({
        snapshots: [],
        activeSnapshot: jean,
        linkedPatientName: "Eleanor Wright",
      }),
    ).toBeNull();
  });

  it("accepts the active snapshot without a linked name only via membership", () => {
    expect(
      resolvePatientForCaregiver({
        snapshots: [],
        activeSnapshot: eleanor,
        caregiver: james,
      })?.profileName,
    ).toBe("Eleanor Wright");

    expect(
      resolvePatientForCaregiver({
        snapshots: [],
        activeSnapshot: jean,
        caregiver: james,
      }),
    ).toBeNull();
  });

  it("returns null when nothing is stored", () => {
    expect(resolvePatientForCaregiver({ snapshots: [] })).toBeNull();
    expect(
      resolvePatientForCaregiver({ snapshots: [], activeSnapshot: null }),
    ).toBeNull();
    expect(
      resolvePatientForCaregiver({
        snapshots: [],
        activeSnapshot: { profileName: "Your Name" },
        linkedPatientName: "Eleanor Wright",
      }),
    ).toBeNull();
  });
});

describe("remaining branch coverage", () => {
  it("ages a spelled-out date that is not slash formatted", () => {
    expect(ageFromDob("July 17, 1954", new Date(2026, 6, 25))).toBe(72);
    expect(ageFromDob("July 17, 2027", new Date(2026, 6, 25))).toBe(0);
  });

  it("returns null when the invite URL cannot be parsed", () => {
    expect(parseInviteFromUrl("://")).toBeNull();
  });

  it("matches a caregiver by partial email in the roster", () => {
    const roster = buildCaregiverPatientRoster({
      caregiverId: "cg-unknown",
      linkedCaregivers: [{
        id: "cgA",
        name: "Alice Adams",
        relationship: "Friend",
        initials: "AA",
        grants: ["mood"],
        status: "active",
        email: "alice.adams@demo.com",
      }],
      patientActive: true,
      profileName: "Eleanor Wright",
      profileDob: "07/17/1954",
      profileConditions: "",
      profileAllergies: "",
      medAdherence: 80,
      linkedPatientName: "Eleanor Wright",
      linkedPatientDob: "07/17/1954",
      caregiverEmail: "alice.adams@demo",
    });
    expect(roster[0].accessState).toBe("ok");
  });

  it("falls back to the only active caregiver holding grants", () => {
    const roster = buildCaregiverPatientRoster({
      caregiverId: "cg-unknown",
      linkedCaregivers: [
        {
          id: "cgA",
          name: "Alice Adams",
          relationship: "Friend",
          initials: "AA",
          grants: ["mood"],
          status: "active",
        },
        {
          id: "cgB",
          name: "Bob Brown",
          relationship: "Neighbor",
          initials: "BB",
          grants: ["mood"],
          status: "pending",
        },
      ],
      patientActive: true,
      profileName: "Eleanor Wright",
      profileDob: "07/17/1954",
      profileConditions: "",
      profileAllergies: "",
      medAdherence: 80,
      linkedPatientName: "Eleanor Wright",
      linkedPatientDob: "07/17/1954",
    });
    expect(roster[0].accessState).toBe("ok");
    expect(roster[0].caregiverName).toBe("Alice Adams");
  });

  it("authorizes the only linked caregiver even before any data is shared", () => {
    const roster = buildCaregiverPatientRoster({
      caregiverId: "cg-unknown",
      linkedCaregivers: [{
        id: "cgA",
        name: "Alice Adams",
        relationship: "Friend",
        initials: "AA",
        grants: [],
        status: "active",
      }],
      patientActive: true,
      profileName: "Eleanor Wright",
      profileDob: "07/17/1954",
      profileConditions: "High blood pressure",
      profileAllergies: "Penicillin",
      medAdherence: 80,
      linkedPatientName: "Eleanor Wright",
      linkedPatientDob: "07/17/1954",
    });
    expect(roster[0].accessState).toBe("ok");
    expect(roster[0].grants).toEqual([]);
    expect(roster[0].mood).toBeUndefined();
    expect(roster[0].medAdherence).toBeUndefined();
    expect(roster[0].symptomsSummary).toBeUndefined();
  });

  it("activates an existing circle entry matched only by partial email", () => {
    const circle: LinkedCaregiver[] = [{
      id: "cg1",
      name: "Alice Adams",
      relationship: "Friend",
      initials: "AA",
      grants: [],
      status: "pending",
      email: "alice.adams@demo.com",
    }];
    const next = activateInviteInCareCircle(circle, {
      caregiverId: "cg9",
      caregiverName: "",
      caregiverEmail: "alice.adams@demo",
    });
    expect(next).toHaveLength(1);
    expect(next[0].status).toBe("active");
    // An entry with no grants yet receives the default starter set.
    expect(next[0].grants).toEqual(["mood", "checkin_summary", "med_adherence"]);
  });

  it("leaves unrelated caregivers untouched when approving", () => {
    const circle: LinkedCaregiver[] = [
      {
        id: "cg1",
        name: "Alice Adams",
        relationship: "Friend",
        initials: "AA",
        grants: ["mood"],
        status: "active",
      },
      {
        id: "cg2",
        name: "Bob Brown",
        relationship: "Neighbor",
        initials: "BB",
        grants: [],
        status: "pending",
      },
    ];
    const next = approveCaregiverInCircle(circle, "cg2");
    expect(next[0]).toBe(circle[0]);
    expect(next[1].status).toBe("active");
  });

  it("routes AOL and Zoho mailboxes over IMAP", () => {
    expect(detectEmailProvider("me@aol.com")?.provider).toBe("aol");
    expect(detectEmailProvider("me@zoho.com")?.provider).toBe("zoho");
    expect(detectEmailProvider("me@team.zoho.com")?.provider).toBe("zoho");
  });

  it("builds a share URL without a patient name", () => {
    const url = buildProfileShareUrl("ps-token");
    expect(url).toContain("/p/ps-token");
    expect(url).not.toContain("patient=");
  });

  it("averages month buckets and ignores entries with no usable date", () => {
    const today = new Date(2026, 6, 15);
    const points = buildSymptomTrendPoints(
      [
        { name: "Headache", severity: 4, date: "2026-07-02" },
        { name: "Headache", severity: 2, date: "2026-07-20" },
        { name: "Nausea", severity: 3, time: new Date(2026, 6, 10, 9, 0).toISOString() },
        { name: "Nausea", severity: 1 },
        { name: "Nausea", severity: 5, time: "not-a-date" },
      ],
      "month",
      today,
    );
    const july = points[points.length - 1];
    expect(july.series.Headache).toBe(3);
    expect(july.series.Nausea).toBe(3);
    expect(points[0].series.Headache).toBeNull();
  });

  it("alternates away from caregiver turns and defaults to Doctor", () => {
    expect(inferSpeakerFromText("Okay.", "Caregiver")).toBe("You");
    expect(inferSpeakerFromText("Okay.")).toBe("Doctor");
  });
});
