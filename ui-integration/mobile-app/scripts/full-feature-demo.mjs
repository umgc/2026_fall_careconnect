/**
 * Paced under-10-minute CareConnect demo (headed Chrome).
 * Creates patient + caregiver profiles from scratch and walks main features.
 *
 * Run: node scripts/full-feature-demo.mjs
 * App must be at http://127.0.0.1:5173/
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
  address: "120 Maple Street, Baltimore MD",
  provider: "Dr. Patel · City Medical",
  emergency: "James Wright · (555) 111-2222",
  conditions: "Hypertension",
  meds: "Lisinopril 10mg, Metformin 500mg",
  allergies: "Penicillin",
};
const CAREGIVER = {
  name: "James Wright",
  email: "james.wright@demo.com",
  password: "Care1234",
  relation: "Child",
  phone: "(555) 111-2222",
};

const HOLD = 1600; // pause so a screen recording can breathe

function log(n, msg) {
  console.log(`\n▶ [${n}] ${msg}`);
}

async function narrate(page, title, detail = "") {
  await page.evaluate(
    ({ title, detail }) => {
      let el = document.getElementById("cc-demo-narration");
      if (!el) {
        el = document.createElement("div");
        el.id = "cc-demo-narration";
        Object.assign(el.style, {
          position: "fixed",
          left: "12px",
          right: "12px",
          top: "10px",
          bottom: "auto",
          zIndex: "99999",
          background: "rgba(0, 59, 77, 0.92)",
          color: "white",
          padding: "10px 12px",
          borderRadius: "14px",
          fontFamily: "system-ui, sans-serif",
          boxShadow: "0 8px 24px rgba(0,0,0,0.25)",
          pointerEvents: "none",
        });
        document.body.appendChild(el);
      }
      el.innerHTML = `<div style="font-size:11px;font-weight:800;letter-spacing:.04em;text-transform:uppercase;opacity:.85;margin-bottom:2px">CareConnect demo</div>
        <div style="font-size:15px;font-weight:700;line-height:1.25">${title}</div>
        ${detail ? `<div style="font-size:12px;margin-top:3px;opacity:.9;line-height:1.35">${detail}</div>` : ""}`;
    },
    { title, detail },
  );
}

async function clickCreateProfile(page, role) {
  const re =
    role === "caregiver"
      ? /Create (a new )?caregiver profile/i
      : /Create (a new )?patient profile/i;
  await page.getByRole("button", { name: re }).first().click({ timeout: 10_000 });
}

async function clearNarration(page) {
  await page.evaluate(() => document.getElementById("cc-demo-narration")?.remove()).catch(() => {});
}

async function shot(page, name) {
  const file = path.join(OUT, `full-${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  console.log(`  📷 ${file}`);
}

async function hold(ms = HOLD) {
  await new Promise((r) => setTimeout(r, ms));
}

async function fillByPlaceholder(page, placeholder, value) {
  const input = page.locator(`input[placeholder="${placeholder}"], textarea[placeholder="${placeholder}"]`).first();
  await input.waitFor({ state: "visible", timeout: 10_000 });
  await input.fill(value);
}

async function clickContinue(page) {
  const btn = page.getByRole("button", { name: /Continue|Finish setup/i }).first();
  await btn.click();
  await hold(500);
}

async function setPasswordOnlyAuth(page) {
  // Leave Password on; turn off PIN and Colour if currently enabled
  const pin = page.getByRole("button", { name: /^✓?\s*PIN$/i }).first();
  if (await pin.isVisible().catch(() => false)) {
    const t = await pin.innerText();
    if (t.includes("✓")) await pin.click();
  }
  const colour = page.getByRole("button", { name: /^✓?\s*Colou?r$/i }).first();
  if (await colour.isVisible().catch(() => false)) {
    const t = await colour.innerText();
    if (t.includes("✓")) await colour.click();
  }
  const password = page.getByRole("button", { name: /^✓?\s*Password$/i }).first();
  if (await password.isVisible().catch(() => false)) {
    const t = await password.innerText();
    if (!t.includes("✓")) await password.click();
  }
}

async function main() {
  const browser = await chromium.launch({
    channel: "chrome",
    headless: false,
    slowMo: 220,
    args: ["--start-maximized"],
  }).catch(() =>
    chromium.launch({ headless: false, slowMo: 220 }),
  );

  const context = await browser.newContext({
    viewport: { width: 420, height: 860 },
    deviceScaleFactor: 1.25,
  });
  const page = await context.newPage();
  const results = [];
  let inviteCode = "";

  try {
    log(1, "Landing — clear storage for a fresh demo");
    await page.goto(BASE, { waitUntil: "networkidle" });
    await page.evaluate(() => {
      localStorage.clear();
      sessionStorage.clear();
    });
    await page.reload({ waitUntil: "networkidle" });
    await narrate(page, "Welcome to CareConnect", "We'll create a patient, tour features, then create a caregiver.");
    await shot(page, "01-landing");
    await hold(2200);

    // ── Create patient ──────────────────────────────────────────────
    log(2, "Create patient profile — Eleanor Wright");
    await page.getByRole("button", { name: /Patient \/ User/i }).first().click();
    await clickCreateProfile(page, "patient");
    await hold(600);
    await narrate(page, "Create patient profile", "Eleanor Wright · password sign-in");

    await fillByPlaceholder(page, "Your name", PATIENT.name);
    await fillByPlaceholder(page, "you@email.com", PATIENT.email);
    await page.getByRole("button", { name: /👤 Patient/i }).click();
    await setPasswordOnlyAuth(page);
    await fillByPlaceholder(page, "Create a password (min 4 characters)", PATIENT.password);
    await clickContinue(page);

    await narrate(page, "Personal & care details");
    await fillByPlaceholder(page, "MM / DD / YYYY", PATIENT.dob);
    await fillByPlaceholder(page, "Start typing your address…", PATIENT.address);
    await fillByPlaceholder(page, "Dr. Name · Clinic", PATIENT.provider);
    await fillByPlaceholder(page, "Name · Phone", PATIENT.emergency);
    await clickContinue(page);

    await narrate(page, "Health baseline", "Conditions, meds, allergies");
    await fillByPlaceholder(page, "e.g. Hypertension, Type 2 diabetes…", PATIENT.conditions);
    await fillByPlaceholder(page, "e.g. Lisinopril 10mg, Metformin…", PATIENT.meds);
    await fillByPlaceholder(page, "e.g. Penicillin, Peanuts…", PATIENT.allergies);
    await clickContinue(page);

    await narrate(page, "Features & accessibility", "Enable health tools + Memory aid mode");
    const memory = page.getByRole("button", { name: /Memory aid/i }).first();
    if (await memory.isVisible().catch(() => false)) await memory.click();
    await clickContinue(page);

    await narrate(page, "All set!", "Open Eleanor’s dashboard");
    await shot(page, "02-patient-ready");
    await hold(1200);
    await page.getByRole("button", { name: /Go to my dashboard/i }).click();
    await hold(1200);
    results.push("PASS: Patient profile created");

    // ── Patient home ────────────────────────────────────────────────
    log(3, "Patient dashboard — home, mood, schedule");
    await narrate(page, "Patient home", "Schedule on the dashboard · 5 bottom icons");
    await shot(page, "03-patient-home");
    await hold(2000);

    const moodBtn = page.getByRole("button", { name: /Good|🙂|feeling/i }).first();
    if (await moodBtn.isVisible().catch(() => false)) {
      await moodBtn.click().catch(() => {});
      await hold(400);
    }
    // Try tap a mood emoji / score if present
    const good = page.locator("button").filter({ hasText: /^Good$|^🙂$|^4$/ }).first();
    if (await good.isVisible().catch(() => false)) await good.click().catch(() => {});

    const schedule = page.getByRole("button", { name: /Schedule/i }).first();
    if (await schedule.isVisible().catch(() => false)) {
      await schedule.click();
      await hold(800);
      await schedule.click();
    }

    // ── Health / meds ───────────────────────────────────────────────
    log(4, "Health tab — medications under Health");
    await narrate(page, "Health", "Medications live under Health (not a separate nav icon)");
    await page.getByRole("button", { name: /^Health$/i }).last().click();
    await hold(1000);
    await shot(page, "04-health-meds");
    const medsTab = page.getByRole("button", { name: /Meds|Medication/i }).first();
    if (await medsTab.isVisible().catch(() => false)) await medsTab.click();
    await hold(1200);
    results.push("PASS: Health / meds opened");

    // ── Mail ────────────────────────────────────────────────────────
    log(5, "Mail — Informed Delivery");
    await narrate(page, "Mail digest", "USPS Informed Delivery · Connect Gmail (demo)");
    await page.getByRole("button", { name: /^Mail$/i }).last().click();
    await hold(1000);
    const connect = page.getByRole("button", { name: /Connect Gmail/i }).first();
    if (await connect.isVisible().catch(() => false)) {
      await connect.click();
      await hold(1500);
    }
    await shot(page, "05-mail");
    results.push("PASS: Mail opened");

    // ── Messages ────────────────────────────────────────────────────
    log(6, "Messages");
    await narrate(page, "Messages", "Chat with care team contacts");
    await page.getByRole("button", { name: /^Messages$/i }).last().click();
    await hold(1400);
    await shot(page, "06-messages");

    // ── Profile share ───────────────────────────────────────────────
    log(7, "Profile → share link channels");
    await narrate(page, "Share my profile", "SMS · Email · WhatsApp dropdown");
    await page.getByRole("button", { name: /^Profile$/i }).last().click();
    await hold(600);
    const myInfo = page.getByRole("button", { name: /My Info/i }).first();
    if (await myInfo.isVisible().catch(() => false)) await myInfo.click();
    await hold(500);

    const createShare = page.getByRole("button", { name: /Create share link/i }).first();
    if (await createShare.isVisible().catch(() => false)) {
      await createShare.click();
      await hold(800);
    }
    const channelDrop = page
      .locator("button")
      .filter({ hasText: /SMS \/ Text message|Open your messaging|WhatsApp|Open email/i })
      .first();
    if (await channelDrop.isVisible().catch(() => false)) {
      await channelDrop.click();
      await hold(600);
      await shot(page, "07-share-channels");
      const emailOpt = page.locator('[role="option"], li, button').filter({ hasText: /^Email$/i }).first();
      if (await emailOpt.isVisible().catch(() => false)) await emailOpt.click();
      await hold(700);
      results.push("PASS: Profile share channels");
    } else {
      results.push("WARN: Share channel dropdown not found");
    }

    // ── Care Circle invite ──────────────────────────────────────────
    log(8, "Care Circle — invite James Wright");
    await narrate(page, "Care Circle", "Invite James and grant shared access");
    const circle = page.getByRole("button", { name: /Care Circle/i }).first();
    await circle.click();
    await hold(700);

    await page.getByRole("button", { name: /Invite a caregiver via QR or link/i }).click();
    await hold(400);
    await fillByPlaceholder(page, "Who are you inviting?", CAREGIVER.name);
    await fillByPlaceholder(page, "e.g. Daughter, Nurse", CAREGIVER.relation);
    await fillByPlaceholder(page, "email@example.com", CAREGIVER.email);
    await fillByPlaceholder(page, "(555) 000-0000", CAREGIVER.phone);
    await page.getByRole("button", { name: /Generate invite link/i }).click();
    await hold(1000);
    await shot(page, "08-invite-qr");

    const inviteText = await page.locator("body").innerText();
    const codeMatch = inviteText.match(/cc-[a-z0-9]+/i);
    inviteCode = codeMatch?.[0] || "";
    console.log(`  invite code: ${inviteCode || "(none)"}`);

    await page.getByRole("button", { name: /Add to Care Circle/i }).click();
    await hold(1000);

    // Turn on any remaining grant switches for a fuller caregiver view
    const switches = page.locator('[role="switch"], button[id^="grant-"]');
    const swCount = await switches.count();
    for (let i = 0; i < Math.min(swCount, 8); i++) {
      const sw = switches.nth(i);
      const checked = await sw.getAttribute("aria-checked").catch(() => null);
      if (checked === "false") await sw.click().catch(() => {});
    }
    await shot(page, "09-care-circle");
    results.push(inviteCode ? "PASS: Care Circle invite created" : "WARN: Invite added but code not parsed");

    // Sign out
    log(9, "Sign out patient");
    const myInfo2 = page.getByRole("button", { name: /My Info/i }).first();
    if (await myInfo2.isVisible().catch(() => false)) await myInfo2.click();
    await hold(400);
    let signOut = page.getByRole("button", { name: /Sign out/i }).first();
    if (!(await signOut.isVisible().catch(() => false))) {
      await page.getByRole("button", { name: /^Profile$/i }).last().click();
      await hold(400);
      await page.getByRole("button", { name: /My Info/i }).first().click().catch(() => {});
      await hold(300);
      signOut = page.getByRole("button", { name: /Sign out/i }).first();
    }
    await signOut.click();
    await hold(1200);

    // ── Create caregiver ────────────────────────────────────────────
    log(10, "Create caregiver profile — James Wright");
    await narrate(page, "Create caregiver", "James Wright · Son · linked to Eleanor");
    await page.getByRole("button", { name: /^Caregiver$/i }).first().click();
    await hold(300);
    await clickCreateProfile(page, "caregiver");
    await hold(600);

    await fillByPlaceholder(page, "Your name", CAREGIVER.name);
    await fillByPlaceholder(page, "you@email.com", CAREGIVER.email);
    await page.getByRole("button", { name: /🏥 Caregiver/i }).click();
    await setPasswordOnlyAuth(page);
    await fillByPlaceholder(page, "Create a password (min 4 characters)", CAREGIVER.password);

    if (inviteCode) {
      await fillByPlaceholder(page, "Paste invite link or cc-…", inviteCode);
    }
    await fillByPlaceholder(page, "Exact name on their CareConnect profile", PATIENT.name);
    await fillByPlaceholder(page, "MM/DD/YYYY", PATIENT.dob);
    await page.getByRole("button", { name: /^Child$/i }).click();
    await hold(400);
    await clickContinue(page);

    await narrate(page, "Caregiver account type", "Family caregiver");
    // Keep default family persona (cg1)
    await clickContinue(page);

    await narrate(page, "Caregiver ready", "Go to caregiver dashboard");
    await shot(page, "10-caregiver-ready");
    await hold(1000);
    await page.getByRole("button", { name: /Go to my dashboard/i }).click();
    await hold(1500);
    results.push("PASS: Caregiver profile created");

    // ── Caregiver sees patient ──────────────────────────────────────
    log(11, "Caregiver home — shared Eleanor data");
    await narrate(page, "Caregiver view", "Eleanor’s shared mood, meds, check-in — not unauthorized");
    await shot(page, "11-caregiver-home");
    await hold(2200);

    const body = await page.locator("body").innerText();
    const sees = /Eleanor Wright/i.test(body);
    const bad = /Access not authorized|This link is unauthorized/i.test(body);
    results.push(
      sees && !bad
        ? "PASS: Caregiver sees Eleanor (authorized)"
        : `FAIL: caregiver sees=${sees} unauthorized=${bad}`,
    );

    const eleanor = page.getByRole("button", { name: /Eleanor Wright/i }).first();
    if (await eleanor.isVisible().catch(() => false)) {
      await eleanor.click();
      await hold(1600);
      await shot(page, "12-patient-detail");
      const detail = await page.locator("body").innerText();
      results.push(
        /Allowed in Care Circle|Shared|Current mood/i.test(detail) && !/Access not authorized/i.test(detail)
          ? "PASS: Shared patient detail visible"
          : "FAIL: Patient detail blocked",
      );
      await page.getByRole("button", { name: /Close patient details/i }).click().catch(() => {});
      await hold(600);
    }

    // Caregiver nav: 5 icons, no Roster
    await narrate(page, "Caregiver navigation", "Patient · Alerts · Messages · Analytics · Profile");
    await page.getByRole("button", { name: /^Alerts$/i }).last().click();
    await hold(900);
    await page.getByRole("button", { name: /^Analytics$/i }).last().click();
    await hold(900);
    await page.getByRole("button", { name: /^Profile$/i }).last().click();
    await hold(700);
    const cgCircle = page.getByRole("button", { name: /Care Circle/i }).first();
    if (await cgCircle.isVisible().catch(() => false)) await cgCircle.click();
    await hold(1200);
    await shot(page, "13-caregiver-circle");

    await clearNarration(page);
    await narrate(
      page,
      "Demo complete",
      "Patient + caregiver created · Care Circle sharing · Mail · Messages · Profile share channels",
    );
    await shot(page, "14-complete");
    await hold(3500);

    console.log("\n=== FULL DEMO RESULTS ===");
    results.forEach((r) => console.log(r));
    const failed = results.filter((r) => r.startsWith("FAIL"));
    console.log(failed.length ? `\nFAILED: ${failed.length}` : "\nALL CHECKS PASSED");
    console.log(`Screenshots: ${OUT}`);
    console.log("\nLeaving Chrome open ~20s for you to inspect, then closing…");
    await hold(20_000);

    process.exit(failed.length ? 1 : 0);
  } catch (err) {
    console.error("\nDEMO ERROR:", err);
    await shot(page, "error").catch(() => {});
    const t = await page.locator("body").innerText().catch(() => "");
    console.error("PAGE TEXT:\n", t.slice(0, 1200));
    await hold(8000);
    process.exit(1);
  } finally {
    await browser.close().catch(() => {});
  }
}

main();
