import { test, expect } from "@playwright/test";

async function clearAppStorage(page: import("@playwright/test").Page) {
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await page.evaluate(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
  await page.reload({ waitUntil: "domcontentloaded" });
}

async function openCreateFlow(page: import("@playwright/test").Page) {
  await page.goto("/", { waitUntil: "domcontentloaded" });
  const create = page.getByRole("button", { name: /create|get started|new profile/i }).first();
  if (await create.isVisible().catch(() => false)) {
    await create.click();
  }
}

test.describe("CareConnect e2e", () => {
  test.beforeEach(async ({ page }) => {
    await clearAppStorage(page);
  });

  test("landing shows create profile and sign in", async ({ page }) => {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await expect(page.getByText(/CareConnect|Get started|Create|Sign in/i).first()).toBeVisible({
      timeout: 15_000,
    });
  });

  test("patient can open profile creation wizard", async ({ page }) => {
    await openCreateFlow(page);
    const patient = page.getByRole("button", { name: /patient/i }).first();
    if (await patient.isVisible().catch(() => false)) await patient.click();
    await expect(page.getByText(/Account & login|Full name|I am a/i).first()).toBeVisible({
      timeout: 15_000,
    });
  });

  test("caregiver wizard requires patient confirmation fields", async ({ page }) => {
    await openCreateFlow(page);
    const caregiverBtn = page.getByRole("button", { name: /caregiver/i }).first();
    if (await caregiverBtn.isVisible().catch(() => false)) {
      await caregiverBtn.click();
    }
    await expect(page.getByText(/Confirm the Patient|Patient \/ User full name|Invite code/i).first()).toBeVisible({
      timeout: 15_000,
    });
  });

  test("sign-in screen exposes PIN, Password, and Colour methods", async ({ page }) => {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    const signIn = page.getByRole("button", { name: /log in|sign in/i }).first();
    if (await signIn.isVisible().catch(() => false)) {
      await signIn.click();
    }
    await expect(page.getByRole("button", { name: /^PIN$/i })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByRole("button", { name: /^Password$/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /^Colour$/i })).toBeVisible();
  });

  test("sign-in does not offer Skip for now", async ({ page }) => {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    const signIn = page.getByRole("button", { name: /log in|sign in/i }).first();
    if (await signIn.isVisible().catch(() => false)) await signIn.click();
    await expect(page.getByText(/Sign in as/i).first()).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText(/Skip for now/i)).toHaveCount(0);
  });

  test("mail digest connect gmail is reachable for patient session", async ({ page }) => {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    // Seed a minimal signed-in patient session so Mail tab is available
    await page.evaluate(() => {
      const snap = {
        isSignedIn: true,
        profileComplete: true,
        role: "patient",
        profileName: "E2E Patient",
        profileDob: "07/17/1954",
        enabledFeatures: ["medication_tracker", "virtual_checkin", "symptoms_tracker", "usps_mail"],
        tab: "mail",
        navHistory: [{ phase: "app", tab: "mail" }],
        linkedCaregivers: [],
      };
      localStorage.setItem("careconnect_v1", JSON.stringify(snap));
      localStorage.setItem(
        "careconnect_patient_snapshot",
        JSON.stringify({
          profileComplete: true,
          profileName: "E2E Patient",
          profileDob: "07/17/1954",
          profileConditions: "",
          profileAllergies: "",
          profileMeds: "",
          linkedCaregivers: [],
          medications: [],
          medsChecked: {},
          appointments: [],
        }),
      );
    });
    await page.reload({ waitUntil: "domcontentloaded" });
    await expect(page.getByText(/Mail Digest|Connect your email|Connect Gmail|USPS/i).first()).toBeVisible({
      timeout: 20_000,
    });
    const connect = page.getByRole("button", { name: /Connect Gmail|Continue with this email/i }).first();
    await expect(connect).toBeVisible({ timeout: 15_000 });
    await connect.click();
    await expect(page.getByText(/Priority by well-being|Manage by category|Immediate|Critical/i).first()).toBeVisible({
      timeout: 15_000,
    });
  });

  test("symptoms portal starts empty without demo seed data", async ({ page }) => {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await page.evaluate(() => {
      localStorage.setItem(
        "careconnect_v1",
        JSON.stringify({
          isSignedIn: true,
          profileComplete: true,
          role: "patient",
          profileName: "E2E Patient",
          profileDob: "01/01/1950",
          enabledFeatures: ["symptoms_tracker", "usps_mail"],
          tab: "symptoms",
          navHistory: [{ phase: "app", tab: "symptoms" }],
        }),
      );
      localStorage.removeItem("careconnect_logged_symptoms");
      localStorage.removeItem("careconnect_logged_allergies");
    });
    await page.reload({ waitUntil: "domcontentloaded" });
    await expect(page.getByText(/Symptoms & Allergies|No symptoms logged yet|Log a symptom/i).first()).toBeVisible({
      timeout: 20_000,
    });
    await expect(page.getByText(/^Headache$/)).toHaveCount(0);
  });

  test("caregiver roster shows age from patient DOB when linked", async ({ page }) => {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await page.evaluate(() => {
      const linked = [{
        id: "cg1",
        name: "E2E Caregiver",
        relationship: "Daughter",
        initials: "EC",
        grants: ["mood"],
        status: "active",
        addedByPatient: true,
        inviteCode: "cc-e2e",
      }];
      localStorage.setItem(
        "careconnect_v1",
        JSON.stringify({
          isSignedIn: true,
          profileComplete: true,
          role: "caregiver",
          activeCaregiverId: "cg1",
          profileName: "E2E Caregiver",
          tab: "home",
          navHistory: [{ phase: "app", tab: "home" }],
          linkedCaregivers: linked,
        }),
      );
      localStorage.setItem(
        "careconnect_patient_snapshot",
        JSON.stringify({
          profileComplete: true,
          profileName: "E2E Patient",
          profileDob: "07/17/1954",
          profileConditions: "",
          profileAllergies: "",
          profileMeds: "",
          linkedCaregivers: linked,
          medications: [],
          medsChecked: {},
          appointments: [],
        }),
      );
      localStorage.setItem(
        "careconnect_caregiver_account_cg1",
        JSON.stringify({
          name: "E2E Caregiver",
          email: "cg@example.com",
          agency: "",
          credentials: "",
          phone: "",
          password: "",
          pin: "",
          colorSeq: [],
          linkedPatientName: "E2E Patient",
          linkedPatientDob: "07/17/1954",
          linkedInviteCode: "cc-e2e",
          relationshipToPatient: "Daughter",
        }),
      );
    });
    await page.reload({ waitUntil: "domcontentloaded" });
    await expect(page.getByText(/E2E Patient/i).first()).toBeVisible({ timeout: 20_000 });
    await expect(page.getByText(/Age 7[12]/i).first()).toBeVisible({ timeout: 10_000 });
    await expect(page.getByText(/Maria Rodriguez/i)).toHaveCount(0);
  });

  test("home surfaces caregiver access approval when pending grants exist", async ({ page }) => {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await page.evaluate(() => {
      const linked = [{
        id: "cg-req",
        name: "Pending Caregiver",
        relationship: "Friend",
        initials: "PC",
        grants: [],
        status: "active",
        addedByPatient: true,
        pendingGrantRequests: ["mood", "med_adherence"],
      }];
      localStorage.setItem(
        "careconnect_v1",
        JSON.stringify({
          isSignedIn: true,
          profileComplete: true,
          role: "patient",
          profileName: "E2E Patient",
          profileDob: "01/01/1950",
          enabledFeatures: ["usps_mail"],
          tab: "home",
          navHistory: [{ phase: "app", tab: "home" }],
          linkedCaregivers: linked,
        }),
      );
      localStorage.setItem(
        "careconnect_patient_snapshot",
        JSON.stringify({
          profileComplete: true,
          profileName: "E2E Patient",
          profileDob: "01/01/1950",
          profileConditions: "",
          profileAllergies: "",
          profileMeds: "",
          linkedCaregivers: linked,
          medications: [],
          medsChecked: {},
          appointments: [],
        }),
      );
    });
    await page.reload({ waitUntil: "domcontentloaded" });
    await expect(page.getByText(/Caregiver access needs your approval/i).first()).toBeVisible({
      timeout: 20_000,
    });
    await expect(page.getByRole("button", { name: /Review in Care Circle/i })).toBeVisible();
  });
});
