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

Then open something like `http://127.0.0.1:5173/`.

## Build
```bash
npm ci
npm run build
```

Output is written to `dist/` (static files for Amplify or any static host).

## Deploy to AWS Amplify (React demo — separate app)

This folder is **not** the Flutter CareConnect web app. The existing Amplify site
(e.g. `https://deploy.…amplifyapp.com/#/dashboard`) builds `frontend/` with Flutter
and will **not** show this UI.

To put this React demo on a public URL, create a **second** Amplify Hosting app:

1. AWS Console → **Amplify** → **Create new app** → Host web app → connect
   `umgc/2026_summer_careconnect` (do **not** change the Flutter Amplify app).
2. Set the **application root** / monorepo root to `ui-integration/mobile-app`.
3. Amplify should pick up [`amplify.yml`](./amplify.yml) in this folder
   (`npm ci` → `npm run build` → artifacts from `dist/`).
4. Connect a branch used for demos (for example `team-ae-develop` or a feature branch
   that includes this folder).
5. Deploy, then open the new `https://….amplifyapp.com` URL (not the Flutter URL).

### SPA rewrite (Amplify Console)

If client-side paths 404 on refresh, add a rewrite under the app’s **Rewrites and redirects**:

| Source | Target | Type |
| ------ | ------ | ---- |
| `/<*>` | `/index.html` | 200 (Rewrite) |

### Verify
- Build succeeds in Amplify (`npm ci` / `vite build` / `dist` published).
- New URL shows the React landing / role login (not Flutter `#/dashboard`).
- Exercise Care Circle, share, and at least one patient/caregiver path.
- Confirm the existing Flutter Amplify URL still serves Flutter unchanged.

## Tests
```bash
npm test                 # unit (vitest)
npm run test:coverage    # unit coverage (core + mail classify)
npm run test:e2e         # Playwright e2e (pass rate target > 92%)
```

## Note
This is a web prototype (not Flutter). Deploy as a static web app / PWA; native store
builds would require Capacitor/Flutter packaging separately. Porting these flows into
the Flutter `frontend/` app (so the main CareConnect Amplify URL shows them) is a
separate follow-up after this demo host is verified.
