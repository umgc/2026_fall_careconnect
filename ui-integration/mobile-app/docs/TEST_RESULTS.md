# UI Integration test results (2026-07-22)

## E2E (Playwright)
- Suite: `ui-integration/mobile-app/e2e/careconnect.spec.ts`
- Result: **9 / 9 passed (100%)** — exceeds 92% target
- Coverage areas: splash/sign-in, caregiver wizard, Connect Gmail mail digest,
  empty symptoms portal, caregiver age from DOB, patient approval banner

## Unit (Vitest)
- Result: **62 / 62 passed (100%)**
- `careconnect-core` coverage: **≥95% lines/statements/functions** (threshold enforced)

## Merge notes
- React prototype lives under `ui-integration/mobile-app` (does not replace Flutter `frontend/`)
- `node_modules` / Playwright reports are gitignored
- Playwright uses system Chrome channel (`channel: chrome`) for local/CI environments without downloaded Chromium
