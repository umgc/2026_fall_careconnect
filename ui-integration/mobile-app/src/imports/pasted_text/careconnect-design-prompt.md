# CareConnect — Figma Design Prompt
*(Based on umgc/2026_summer_careconnect `develop` branch @ commit eb4a6a5, PR #335, July 16, 2026)*

---

Design a complete, modern mobile app UI kit for **CareConnect**, a caregiver–patient care coordination platform built in Flutter (iOS/Android/Web). Update the existing design to match the current codebase, covering every feature below. Use Material 3 conventions with a clean, accessible, healthcare-friendly aesthetic.

## Design System

- **Primary color:** Cyan #00A7C8 · **Primary dark:** #008DA8 · **Primary light / accent:** #25BEDA
- **Semantic colors:** Success #10B981 (emerald), Warning #F59E0B (amber), Error #EF4444 (red), Info #00A7C8
- **Text:** Primary #0F172A (slate-900), Secondary #6B7280, on-primary white
- **Backgrounds:** White primary, #F3F4F6 secondary, white cards, #E5E7EB borders
- **Dark mode variant:** Background #0B1220, surface #111827, cards #131B2B, borders #1F2A3A, primary #00A7C8 → light #5AD4E8, text #E5E7EB
- Replace any remaining legacy navy (#14366E) accents with the cyan palette for consistency
- Rounded cards, soft elevation, large tap targets, WCAG AA contrast, dynamic text scaling support (accessibility is a core requirement — elderly patient audience)

## Roles & Navigation (design both role variants)

**Patient bottom nav (5 tabs):** Home · Symptoms & Allergies · Virtual Check-In · Messages · Menu (opens bottom-sheet drawer). Floating "Call" FAB on Home.

**Caregiver bottom nav (6 tabs):** Home (dashboard) · Patient List · Analytics · Schedule · Messages · Menu (bottom-sheet drawer). Floating "Call" FAB on Home. Unread badge on Messages tab.

**Menu bottom-sheet drawer** (profile header with avatar + searchable shortcuts): Invoice Assistant, Patient Report (patient only), EVV (caregiver/admin only), Calendar Assistant, Medication Tracker (patient only), Social Feed, Gamification, Wearables, Notetaker Assistant, Voice Commands, Informed Delivery, Smart Devices, File Management, Fall Detection, USPS Mail Digest, Add Patient (caregiver/admin only), Settings. All menu labels are localized.

**Internationalization:** The app ships in 8 languages — English, Spanish, French, Arabic, Amharic, Hindi, Nepali, Urdu. Design an in-app language picker and include RTL layout variants for Arabic and Urdu on key screens.

## Screens to Design

### 1. Onboarding & Auth
- Welcome/landing page with "Get started" CTA
- Login (email/password + OAuth), Sign-up, role selection
- Caregiver registration and Patient registration flows (multi-step, address autocomplete)
- Password reset (request, email confirm, new password screens)
- Alexa account-linking login page
- OAuth callback/loading state

### 2. Dashboards
- **Patient Home dashboard** with widget cards: Medication Reminders, Notifications panel, Current Mood, Recent Check-In summary, Primary Care Provider card, Alert notification banner, Offline-mode notification banner
- **Caregiver dashboard**: patient roster cards with status, quick actions (call, message, view), suspend/reactivate relationship dialogs, video-call policy toggle
- Patient status detail page, patient medical notes page
- Add Patient screen

### 3. Health & Wellness (Patient)
- Symptoms & Allergies tracker (tabbed: Symptoms / Allergies, redesigned structured input forms, history cards)
- Mood & Wellness check-in (emoji/scale mood picker)
- Virtual Check-In flow (guided question bank, structured answer forms with typed field entry, confirmation, configurable check-in settings sheet, check-in history cards, and a check-in detail/review page — mobile and web layouts)
- Structured entry form component (reusable typed form: text, numeric, select, date fields with validation states) used across check-ins and assessments
- Meal tracking screen
- Medication Tracker with reminder list and dose logging

### 4. Emergency & Safety
- SOS screen (large emergency button, cancel/countdown screen)
- Fall Detection: alert page (caregiver view + patient view), alert details with skeleton-motion playback visualization, mock alert lab
- Emergency QR code screen (scannable patient info)

### 5. EVV (Electronic Visit Verification — Caregiver)
Full flow: EVV dashboard → patient selection → check-in location (map + GPS confirm) → visit in progress (timer, task checklist) → checkout location → visit complete summary → success screen. Plus: visit history, corrections/edit requests, review records, offline sync queue screen.

### 6. Scheduling & Tasks
- Shift scheduling: week/month/day calendar views, schedule-visit dialog, conflict warning banner, audit history bottom sheet
- Tasks: task list, assign task (caregiver→patient), custom task creation, pre-defined task templates, recurrence form, ICS calendar import button, color-coded legend editor, filters panel
- Calendar Assistant view

### 7. Communication
- Chat inbox (conversation previews, unread indicators) and chat thread (bubbles, attachments, pending/offline queue states)
- Video call screens (Chime/WebRTC): incoming call, in-call controls, post-call telemetry summary
- Social feed: posts with comments and reactions, friend list, friend requests, user search

### 8. AI Features
- AI Assistant chat interface (chat UI with mic input)
- **Voice Commands screen** (`/voice`): hands-free wake-word activation ("listening" state indicator), live speech-to-text transcript, recognized-intent confirmation, and voice-driven navigation feedback states (idle / listening / processing / executed / error)
- **Call & Visit Summaries**: AI-generated post-call summary cards with a **Clinical Urgency Banner** (color-coded risk level: routine / elevated / urgent), typed extracted items (medications, symptoms, action items), sentiment indicators, and citation/source references
- AI Configuration page (model/provider settings)
- Notetaker Assistant: search screen, note detail view, notetaker configuration; live transcription screen with streaming ASR + speaker diarization labels
- Invoice Assistant: dashboard, upload (camera/file OCR), invoice list with filters, invoice detail with parsed line items, Excel export action

### 9. USPS Informed Delivery / Mail Digest
- Informed Delivery screen: daily mail digest cards with item counts and scanned mail images, refresh state
- Gmail account connect/disconnect flow (OAuth consent, connection status states)
- USPS mail digest test/detail screen

### 10. Integrations & Devices
- Wearables screen (Fitbit connect, synced metrics)
- Smart devices list, add device flow, home monitoring dashboard
- Medication management (integration view)

### 11. Analytics & Reports
- Caregiver analytics: patient selector, vitals/mood trend charts (line/bar), sentiment color coding
- Dashboards suite: behavioral trend, participation, competency trend screens
- Patient Reports tab (exportable summaries)
- Activity tracking: ADL/IADL management, client activities by category, activity log history, behavioral incident report screens
- Audit log screen (filterable event table)

### 12. Gamification
- Patient gamification screen (points, streaks, badges), achievement detail, leaderboard, caregiver gamification landing + management screens

### 13. Payments & Subscription
- Subscription tier selection (package cards), select package page, Stripe checkout, native billing (App Store/Play), web pay, payment success and payment cancel screens, subscription management

### 14. Care Circle Invites
- Invite share screen with generated **QR code** and shareable link for a caregiver–patient link (`/care-circle/:linkId/invite`)
- Invite landing/accept screen (`/invite/:token`): invite preview card (who's inviting, role), accept/decline actions, pending-invite state, expired/invalid-token error state

### 15. Documents & Compliance
- **Home care document digitization**: upload/scan card, digitized document review page (extracted fields side-by-side with source image, field-level edit/confirm)
- **Compliance dashboard**: document compliance status overview with progress indicators, and a compliance checklist page (per-document required/complete/missing states) — accessed from File Management
- Assessment review workflow screens (submitted structured forms with reviewer approve/flag actions)

### 16. Profile & Settings
- Profile page + profile settings, avatar upload with cropper
- Settings: notification settings, reminders & escalation rules editor, telemetry/privacy settings, language selector (8 locales incl. RTL), theme toggle (light/dark), account deletion flow

### 17. System States
- Offline mode banners and sync-queue progress UI (per-item sync status, failed-item retry)
- Empty states, loading skeletons, and error states for all list screens
- Push notification and in-app notification center designs

## Deliverables
Produce mobile-first frames (390×844) for both Patient and Caregiver roles, light and dark mode variants for key screens, a shared component library (buttons, cards, nav bars, dialogs, bottom sheets, form fields, chips, badges), and the color/typography styles above as Figma variables.