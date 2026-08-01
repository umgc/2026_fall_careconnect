# CareConnect UI Integration (SWEN 661 / 670)

React + Vite mobile-first prototype for CareConnect patient / caregiver flows.

## Features in this drop
- Care Circle: max 3 caregivers, patient approval for self-requested access, grant requests
- Real patient age from DOB on caregiver screens
- Symptoms & allergies: user-provided data only
- USPS Mail Digest: priority by well-being impact, category taxonomy, Connect Gmail,
  OCR fallback, NL search, missing-image UI, credential revoke/reauth, ADA read-aloud

## Run locally
```bash
cd ui-integration/mobile-app
npm install
npm run dev
```

## Tests
```bash
npm test                 # unit (vitest)
npm run test:coverage    # unit coverage (core + mail classify)
npm run test:e2e         # Playwright e2e (pass rate target > 92%)
```

## Note
This is a web prototype (not Flutter). Deploy as a static web app / PWA; native store
builds would require Capacitor/Flutter packaging separately.
