/**
 * Live demo: patient grants Care Circle access → caregiver sees shared data.
 * Also checks profile share channel dropdown.
 */
import { chromium } from "playwright";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(__dirname, "..", "docs", "demo-screens");
const BASE = "http://127.0.0.1:5173/";

fs.mkdirSync(OUT, { recursive: true });

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

function log(step, msg) {
  console.log(`[${step}] ${msg}`);
}

async function shot(page, name) {
  const file = path.join(OUT, `${name}.png`);
  await page.screenshot({ path: file, fullPage: true });
  log("shot", file);
}

async function clearStorage(page) {
  await page.goto(BASE, { waitUntil: "domcontentloaded" });
  await page.evaluate(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
  await page.reload({ waitUntil: "networkidle" });
}

async function seedLinkedSession(page) {
  await page.evaluate(({ PATIENT, CAREGIVER }) => {
    const inviteCode = "cc-demodemo01";
    const linkedCaregivers = [
      {
        id: "cg1",
        name: CAREGIVER.name,
        relationship: CAREGIVER.relation,
        initials: "JW",
        email: CAREGIVER.email,
        phone: "(555) 111-2222",
        grants: ["mood", "checkin_summary", "med_adherence", "symptoms"],
        status: "active",
        inviteCode,
        addedByPatient: true,
      },
    ];

    const patientSnap = {
      profileComplete: true,
      profileName: PATIENT.name,
      profileDob: PATIENT.dob,
      profileConditions: "Hypertension",
      profileAllergies: "Penicillin",
      profileMeds: "Lisinopril 10mg",
      linkedCaregivers,
      medications: [
        { id: "m1", name: "Lisinopril", dose: "10mg", time: "8:00 AM", purpose: "Blood pressure" },
        { id: "m2", name: "Metformin", dose: "500mg", time: "12:00 PM", purpose: "Blood sugar" },
      ],
      medsChecked: { m1: true },
      appointments: [
        {
          id: "1",
          date: "Today",
          time: "2:30 PM",
          title: "Dr. Patel — Checkup",
          type: "In person",
          location: "Room 204",
          confirmed: false,
        },
      ],
      mood: 4,
      moodHistory: [
        { date: new Date().toISOString().slice(0, 10), score: 4, symptom: "None / Feeling fine" },
      ],
      lastCheckin: "Today 8:15 AM",
      checkinsThisWeek: 2,
      hasFallAlert: false,
    };
    localStorage.setItem("careconnect_patient_snapshot", JSON.stringify(patientSnap));

    localStorage.setItem(
      "careconnect_caregiver_account_cg1",
      JSON.stringify({
        name: CAREGIVER.name,
        email: CAREGIVER.email,
        agency: "",
        credentials: "",
        phone: "(555) 111-2222",
        password: CAREGIVER.password,
        pin: "1234",
        colorSeq: ["#EF4444", "#3B82F6", "#10B981"],
        linkedPatientName: PATIENT.name,
        linkedPatientDob: PATIENT.dob,
        linkedInviteCode: inviteCode,
        relationshipToPatient: CAREGIVER.relation,
      }),
    );

    localStorage.setItem(
      "careconnect_v1",
      JSON.stringify({
        isSignedIn: false,
        profileComplete: true,
        role: "patient",
        profileName: PATIENT.name,
        profileEmail: PATIENT.email,
        profileDob: PATIENT.dob,
        accountPassword: PATIENT.password,
        accountPin: "2468",
        accountColorSeq: ["#EF4444", "#3B82F6", "#10B981"],
        linkedCaregivers,
        medications: patientSnap.medications,
        medsChecked: patientSnap.medsChecked,
        appointments: patientSnap.appointments,
        patientMood: 4,
        moodHistory: patientSnap.moodHistory,
        patientLastCheckin: patientSnap.lastCheckin,
        checkinsThisWeek: 2,
        enabledFeatures: [
          "medication_tracker",
          "virtual_checkin",
          "symptoms_tracker",
          "usps_mail",
        ],
        mode: null,
        navHistory: [{ phase: "splash" }],
        tab: "home",
      }),
    );
  }, { PATIENT, CAREGIVER });
}

async function clickLogin(page, role) {
  // Role toggle on landing
  if (role === "caregiver") {
    await page.getByRole("button", { name: /Caregiver/i }).first().click();
  } else {
    await page.getByRole("button", { name: /Patient \/ User/i }).first().click();
  }
  await page.waitForTimeout(200);
  const loginBtn = page.getByRole("button", { name: /Log in as/i }).first();
  await loginBtn.click({ timeout: 10_000 });
  await page.waitForTimeout(500);
}

async function signInAs(page, role) {
  await page.goto(BASE, { waitUntil: "networkidle" });
  await clickLogin(page, role);

  // On sign-in screen, ensure role + password method
  if (role === "caregiver") {
    const cgRole = page.getByRole("button", { name: /Caregiver/i }).first();
    if (await cgRole.isVisible().catch(() => false)) await cgRole.click();
    const james = page.getByRole("button", { name: /James Wright/i }).first();
    if (await james.isVisible().catch(() => false)) await james.click();
  } else {
    const ptRole = page.getByRole("button", { name: /Patient \/ User/i }).first();
    if (await ptRole.isVisible().catch(() => false)) await ptRole.click();
  }

  const pwMethod = page.getByRole("button", { name: /^Password$/i }).first();
  if (await pwMethod.isVisible().catch(() => false)) await pwMethod.click();
  await page.waitForTimeout(200);

  const email = page.locator('input[type="email"], input[placeholder*="email" i]').first();
  if (await email.isVisible().catch(() => false)) {
    await email.fill("");
    await email.fill(role === "caregiver" ? CAREGIVER.email : PATIENT.email);
  }
  const pw = page.locator('input[type="password"], input[placeholder="Password"]').first();
  await pw.waitFor({ state: "visible", timeout: 10_000 });
  await pw.fill(role === "caregiver" ? CAREGIVER.password : PATIENT.password);
  await page.getByRole("button", { name: /^Sign in$/i }).click();
  await page.waitForTimeout(1000);
}

async function main() {
  const browser = await chromium.launch({ channel: "chrome", headless: true }).catch(() =>
    chromium.launch({ headless: true }),
  );
  const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
  const results = [];

  try {
    log(1, "Clear storage and seed linked patient ↔ caregiver session");
    await clearStorage(page);
    await seedLinkedSession(page);
    await page.reload({ waitUntil: "networkidle" });
    results.push("Seeded Eleanor (patient) + James (caregiver) with active grants");

    log(2, "Sign in as caregiver James Wright");
    await signInAs(page, "caregiver");
    await shot(page, "01-caregiver-home");
    let body = await page.locator("body").innerText();
    const seesPatient = /Eleanor Wright/i.test(body);
    const unauthorized = /Access not authorized|This link is unauthorized/i.test(body);
    log(2, `seesPatient=${seesPatient} unauthorized=${unauthorized}`);
    results.push(
      seesPatient && !unauthorized
        ? "PASS: Caregiver home shows Eleanor (not unauthorized)"
        : `FAIL: Caregiver home — patient=${seesPatient} unauthorized=${unauthorized}`,
    );

    const patientCard = page.getByRole("button", { name: /Eleanor Wright/i }).first();
    if (await patientCard.isVisible().catch(() => false)) {
      await patientCard.click();
      await page.waitForTimeout(600);
      await shot(page, "02-caregiver-patient-detail");
      const detail = await page.locator("body").innerText();
      const detailOk =
        /Allowed in Care Circle|Mood|Check-in|shared/i.test(detail) &&
        !/Access not authorized/i.test(detail);
      results.push(
        detailOk
          ? "PASS: Patient detail shows granted shared data"
          : "FAIL: Patient detail still blocked or empty",
      );
      const closeDetail = page.getByRole("button", { name: /Close patient details/i });
      await closeDetail.click({ timeout: 5_000 });
      await page.waitForTimeout(400);
    } else {
      results.push("INFO: No tappable Eleanor card on home");
    }

    log(3, "Caregiver Profile → Care Circle");
    const profileTab = page.getByRole("button", { name: /^Profile$/i }).last();
    await profileTab.click();
    await page.waitForTimeout(400);
    const circleTab = page.getByRole("button", { name: /Care Circle/i }).first();
    if (await circleTab.isVisible().catch(() => false)) await circleTab.click();
    await page.waitForTimeout(400);
    await shot(page, "03-caregiver-profile-circle");
    body = await page.locator("body").innerText();
    results.push(
      /Eleanor|Mood|Active|shared/i.test(body) && !/Access not authorized/i.test(body)
        ? "PASS: Caregiver profile Care Circle shows shared data"
        : "FAIL: Caregiver profile Care Circle still unauthorized",
    );

    log(4, "Sign out → patient login → Share my profile dropdown");
    let signOut = page.getByRole("button", { name: /Sign out/i }).first();
    if (!(await signOut.isVisible().catch(() => false))) {
      await page.getByRole("button", { name: /My Info/i }).first().click().catch(() => {});
      await page.waitForTimeout(300);
      signOut = page.getByRole("button", { name: /Sign out/i }).first();
    }
    await signOut.click();
    await page.waitForTimeout(700);

    await signInAs(page, "patient");
    await shot(page, "04-patient-home");
    body = await page.locator("body").innerText();
    results.push(
      /Dashboard|Medications|Schedule|Ready for today/i.test(body)
        ? "PASS: Patient signed in to dashboard"
        : "FAIL: Patient dashboard not visible",
    );

    await page.getByRole("button", { name: /^Profile$/i }).last().click();
    await page.waitForTimeout(400);
    const myInfo = page.getByRole("button", { name: /My Info/i }).first();
    if (await myInfo.isVisible().catch(() => false)) await myInfo.click();
    await page.waitForTimeout(300);

    const createShare = page.getByRole("button", { name: /Create share link/i }).first();
    if (await createShare.isVisible().catch(() => false)) {
      await createShare.click();
      await page.waitForTimeout(500);
    }
    await shot(page, "05-profile-share");

    const dropdown = page
      .locator("button")
      .filter({ hasText: /SMS \/ Text message|Open your messaging|WhatsApp|Open email/i })
      .first();
    if (await dropdown.isVisible().catch(() => false)) {
      await dropdown.click();
      await page.waitForTimeout(300);
      await shot(page, "06-share-channel-dropdown");
      const emailOpt = page.locator('[role="option"]').filter({ hasText: /^Email$/i }).first();
      if (await emailOpt.isVisible().catch(() => false)) {
        await emailOpt.click();
      } else {
        await page.locator("li").filter({ hasText: /Email/i }).first().click();
      }
      await page.waitForTimeout(300);
      await shot(page, "07-share-email-selected");
      const shareBtn = page.getByRole("button", { name: /Share via Email/i }).first();
      results.push(
        (await shareBtn.isVisible().catch(() => false))
          ? "PASS: Share channel dropdown selects Email and updates button"
          : "FAIL: Share via Email button missing after selecting Email",
      );
    } else {
      results.push("FAIL: Share channel dropdown not found");
    }

    log(5, "Patient Care Circle");
    const circle = page.getByRole("button", { name: /Care Circle/i }).first();
    if (await circle.isVisible().catch(() => false)) {
      await circle.click();
      await page.waitForTimeout(400);
      await shot(page, "08-patient-care-circle");
      body = await page.locator("body").innerText();
      results.push(
        /James Wright|Son/i.test(body)
          ? "PASS: Patient Care Circle lists James Wright"
          : "WARN: Care Circle content unexpected",
      );
    }

    console.log("\n=== DEMO RESULTS ===");
    results.forEach((r) => console.log(r));
    const failed = results.filter((r) => r.startsWith("FAIL"));
    console.log(`\nScreenshots: ${OUT}`);
    console.log(failed.length ? `FAILED: ${failed.length}` : "ALL CHECKS PASSED");

    // Leave seeded state for the user to try manually (caregiver signed out, patient may be in)
    process.exit(failed.length ? 1 : 0);
  } catch (err) {
    console.error("DEMO ERROR:", err);
    await shot(page, "error").catch(() => {});
    const t = await page.locator("body").innerText().catch(() => "");
    console.error("PAGE TEXT (first 800 chars):\n", t.slice(0, 800));
    process.exit(1);
  } finally {
    await browser.close();
  }
}

main();
