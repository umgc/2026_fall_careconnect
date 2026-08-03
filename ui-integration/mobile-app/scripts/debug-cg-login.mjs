import { chromium } from "playwright";
import fs from "fs";

const BASE = "http://127.0.0.1:5173/";

const browser = await chromium.launch({ channel: "chrome", headless: true }).catch(() =>
  chromium.launch({ headless: true }),
);
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => {
  if (m.type() === "error") errors.push(m.text());
});

await page.goto(BASE, { waitUntil: "networkidle" });
await page.evaluate(() => localStorage.clear());
await page.evaluate(() => {
  localStorage.setItem(
    "careconnect_caregiver_account_cg1",
    JSON.stringify({
      name: "James Wright",
      email: "james.wright@demo.com",
      agency: "",
      credentials: "",
      phone: "",
      password: "Care1234",
      pin: "1234",
      colorSeq: ["#EF4444", "#3B82F6", "#10B981"],
      linkedPatientName: "Eleanor Wright",
      linkedPatientDob: "07/17/1954",
      linkedInviteCode: "cc-demodemo01",
      relationshipToPatient: "Son",
    }),
  );
  localStorage.setItem(
    "careconnect_patient_snapshot",
    JSON.stringify({
      profileComplete: true,
      profileName: "Eleanor Wright",
      profileDob: "07/17/1954",
      profileConditions: "Hypertension",
      profileAllergies: "Penicillin",
      profileMeds: "Lisinopril",
      linkedCaregivers: [
        {
          id: "cg1",
          name: "James Wright",
          relationship: "Son",
          initials: "JW",
          email: "james.wright@demo.com",
          grants: ["mood", "checkin_summary"],
          status: "active",
          inviteCode: "cc-demodemo01",
          addedByPatient: true,
        },
      ],
      medications: [],
      medsChecked: {},
      appointments: [],
      mood: 4,
      moodHistory: [],
      lastCheckin: "Today 8:00 AM",
      checkinsThisWeek: 1,
      hasFallAlert: false,
    }),
  );
  localStorage.setItem(
    "careconnect_v1",
    JSON.stringify({
      isSignedIn: false,
      profileComplete: true,
      role: "patient",
      profileName: "Eleanor Wright",
      profileEmail: "eleanor.wright@demo.com",
      profileDob: "07/17/1954",
      accountPassword: "Demo1234",
      accountPin: "2468",
      accountColorSeq: ["#EF4444", "#3B82F6", "#10B981"],
      enabledFeatures: [
        "medication_tracker",
        "usps_mail",
        "symptoms_tracker",
        "virtual_checkin",
      ],
      mode: null,
      tab: "home",
      navHistory: [{ phase: "splash" }],
    }),
  );
});
await page.reload({ waitUntil: "networkidle" });
console.log("LANDING", (await page.locator("body").innerText()).slice(0, 180).replace(/\n/g, " | "));

await page.getByRole("button", { name: /Caregiver/i }).first().click();
await page.getByRole("button", { name: /Log in as Caregiver/i }).click();
await page.waitForTimeout(800);
console.log("SIGNIN", (await page.locator("body").innerText()).slice(0, 250).replace(/\n/g, " | "));

await page.getByRole("button", { name: /^Password$/i }).click();
const email = page.locator('input[type="email"]');
if ((await email.count()) > 0) await email.fill("james.wright@demo.com");
await page.locator('input[type="password"]').fill("Care1234");
await page.getByRole("button", { name: /^Sign in$/i }).click();
await page.waitForTimeout(2000);

const text = await page.locator("body").innerText();
console.log("AFTER", text.slice(0, 600).replace(/\n/g, " | "));
console.log("ERRORS", JSON.stringify(errors.slice(0, 12), null, 2));
fs.mkdirSync("docs/demo-screens", { recursive: true });
await page.screenshot({ path: "docs/demo-screens/debug-cg.png", fullPage: true });
await browser.close();
