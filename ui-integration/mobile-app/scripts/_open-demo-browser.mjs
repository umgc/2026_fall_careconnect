import { chromium } from "playwright";

const BASE = "http://127.0.0.1:5173/";
const PATIENT = {
  name: "Eleanor Wright",
  email: "eleanor.wright@demo.com",
  password: "Demo1234",
  dob: "07/17/1954",
};
const CAREGIVER = {
  name: "James Wright",
  email: "james.wright@demo.com",
  password: "Care1234",
  relation: "Son",
};

const browser = await chromium.launch({ channel: "chrome", headless: false }).catch(() =>
  chromium.launch({ headless: false }),
);
const context = await browser.newContext({ viewport: { width: 420, height: 900 } });
const page = await context.newPage();
await page.goto(BASE, { waitUntil: "domcontentloaded" });
await page.evaluate(({ PATIENT, CAREGIVER }) => {
  localStorage.clear();
  sessionStorage.clear();
  const inviteCode = "cc-demodemo01";
  const linkedCaregivers = [{
    id: "cg1", name: CAREGIVER.name, relationship: CAREGIVER.relation,
    initials: "JW", email: CAREGIVER.email, phone: "(555) 111-2222",
    grants: ["mood", "checkin_summary", "med_adherence", "symptoms"],
    status: "active", inviteCode, addedByPatient: true,
  }];
  const patientSnap = {
    profileComplete: true, profileName: PATIENT.name, profileDob: PATIENT.dob,
    profileConditions: "Hypertension", profileAllergies: "Penicillin",
    profileMeds: "Lisinopril 10mg", linkedCaregivers,
    medications: [
      { id: "m1", name: "Lisinopril", dose: "10mg", time: "8:00 AM", purpose: "Blood pressure" },
      { id: "m2", name: "Metformin", dose: "500mg", time: "12:00 PM", purpose: "Blood sugar" },
    ],
    medsChecked: { m1: true },
    appointments: [{ id: "1", date: "Today", time: "2:30 PM", title: "Dr. Patel — Checkup", type: "In person", location: "Room 204", confirmed: false }],
    mood: 4,
    moodHistory: [{ date: new Date().toISOString().slice(0, 10), score: 4, symptom: "None / Feeling fine" }],
    lastCheckin: "Today 8:15 AM", checkinsThisWeek: 2, hasFallAlert: false,
  };
  localStorage.setItem("careconnect_patient_snapshot", JSON.stringify(patientSnap));
  localStorage.setItem("careconnect_caregiver_account_cg1", JSON.stringify({
    name: CAREGIVER.name, email: CAREGIVER.email, agency: "", credentials: "",
    phone: "(555) 111-2222", password: CAREGIVER.password, pin: "1234",
    colorSeq: ["#EF4444", "#3B82F6", "#10B981"],
    linkedPatientName: PATIENT.name, linkedPatientDob: PATIENT.dob,
    linkedInviteCode: inviteCode, relationshipToPatient: CAREGIVER.relation,
  }));
  localStorage.setItem("careconnect_v1", JSON.stringify({
    isSignedIn: false, profileComplete: true, role: "patient",
    profileName: PATIENT.name, profileEmail: PATIENT.email, profileDob: PATIENT.dob,
    accountPassword: PATIENT.password, accountPin: "2468",
    accountColorSeq: ["#EF4444", "#3B82F6", "#10B981"], linkedCaregivers,
    medications: patientSnap.medications, medsChecked: patientSnap.medsChecked,
    appointments: patientSnap.appointments, patientMood: 4,
    moodHistory: patientSnap.moodHistory, patientLastCheckin: patientSnap.lastCheckin,
    checkinsThisWeek: 2,
    enabledFeatures: ["medication_tracker", "virtual_checkin", "symptoms_tracker", "usps_mail"],
    mode: null, navHistory: [{ phase: "splash" }], tab: "home",
  }));
}, { PATIENT, CAREGIVER });
await page.reload({ waitUntil: "networkidle" });
console.log("Ready — Chrome left open with seeded Eleanor + James. Close the window when done.");
console.log("Patient: eleanor.wright@demo.com / Demo1234");
console.log("Caregiver: james.wright@demo.com / Care1234");
// Keep process alive until browser closes
await new Promise((resolve) => browser.on("disconnected", resolve));
