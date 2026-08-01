Redesign the mobile app UI for CareConnect, a caregiver–patient care coordination platform built in Flutter (iOS/Android/Web). This redesign restructures how features are accessed: all features are gated behind profile creation, live inside the user's profile rather than the landing page, and caregiver visibility is strictly limited to what the patient chooses to share. Use Material 3 conventions with a clean, accessible, healthcare-friendly aesthetic. The design must connect to and stay consistent with the existing CareConnect app (same brand, navigation patterns, and backend feature set).

Core UX Rules (apply everywhere)


Profile-first gating. No feature is accessible until the user has created their profile. Pre-profile, the app shows only the landing page and the profile-creation flow. Post-profile, all features unlock automatically.
Landing page is for profile creation only. Remove the feature menu/dropdown from the main landing page entirely. The landing page contains: brand hero, a single "Create your profile" primary CTA, and a "Log in" secondary action. Nothing else.
Features live in the user's profile, not the landing page. Everything that used to be in the landing-page menu drawer (Invoice Assistant, Calendar Assistant, Medication Tracker, Social Feed, Gamification, Wearables, Notetaker Assistant, Voice Commands, Informed Delivery, Smart Devices, File Management, Fall Detection, USPS Mail Digest, Settings) moves into a "My Features" section inside the user's Profile & Settings area.
No repeat reminders. Feature setup, permissions prompts, and onboarding tips appear once during profile creation. Never re-prompt or re-remind the user of these on subsequent logins — returning users go straight to their home dashboard.
Caregivers see a snippet, not the catalog. Caregivers never see the patient's full feature list, feature toggles, or personal settings. From the caregiver's own profile they see only a compact patient snippet card containing exactly what the patient has granted.
Patient controls access. The patient adds a caregiver from their own profile and grants limited, item-by-item access. Caregiver access is opt-in, granular, and revocable at any time.
Selection-driven UI on every page. The user can select or deselect any feature from any page — not just from the profile. Every patient-facing screen includes a lightweight, consistent feature selector affordance (a "Customize" icon in the app bar and/or long-press on widgets and tiles) that opens the same feature picker. The entire app then renders strictly based on the user's current selections: enabled features appear in navigation, dashboards, and menus; disabled features disappear everywhere — no grayed-out placeholders, no dead links, no broken states. Toggling a feature takes effect immediately across the whole app, persists to the profile, and never triggers a re-login or a confirmation nag.


Design System


Primary color: Cyan #00A7C8 · Primary dark: #008DA8 · Primary light / accent: #25BEDA
Semantic colors: Success #10B981, Warning #F59E0B, Error #EF4444, Info #00A7C8
Text: Primary #0F172A, Secondary #6B7280, on-primary white
Backgrounds: White primary, #F3F4F6 secondary, white cards, #E5E7EB borders
Dark mode: Background #0B1220, surface #111827, cards #131B2B, borders #1F2A3A, primary light #5AD4E8, text #E5E7EB
Replace any remaining legacy navy (#14366E) accents with the cyan palette
Rounded cards, soft elevation, large tap targets, WCAG AA contrast, dynamic text scaling (elderly patient audience)
i18n: 8 languages (English, Spanish, French, Arabic, Amharic, Hindi, Nepali, Urdu) with RTL variants for Arabic and Urdu


Flow 1 — Landing & Profile Creation (User/Patient)


Landing page (pre-profile): brand hero, "Create your profile" CTA, "Log in" link. No menu, no feature drawer, no feature previews.
Profile creation wizard (multi-step, launched only from the landing page):

Step 1: Account basics (name, email/phone, password, role = patient)
Step 2: Personal & care details (DOB, address with autocomplete, primary care provider, emergency contact)
Step 3: Health baseline (conditions, medications, allergies — optional, skippable)
Step 4: One-time feature setup — a single screen where the user turns on the features they want (Medication Tracker, Virtual Check-In, Fall Detection, Voice Commands, Informed Delivery/USPS Mail Digest, Wearables, Smart Devices, Social Feed, Gamification, Calendar Assistant, Notetaker, Invoice Assistant, File Management). Clearly label: "You can change these anytime in your profile."
Step 5: Confirmation — "Your profile is saved." All entered information persists to the personal profile; the user is never asked again.



Post-creation: user lands on their home dashboard. All subsequent logins go directly to the dashboard with no setup prompts, no feature reminders, no re-consent nags.


Flow 2 — User Profile (Patient) — the feature hub

Design a rich Profile screen for the patient with these sections:


Profile header: avatar (with upload/crop), name, snapshot of key info saved at creation
My Information: everything captured during profile creation (personal details, care provider, emergency contact, health baseline), viewable and editable in place
My Features: the full feature grid/list (all items formerly in the landing-page dropdown). Each feature is a tappable tile that opens the feature, with an enable/disable toggle. This section is visible only to the patient — never to caregivers.
My Care Circle: list of linked caregivers with per-caregiver access summary, plus:

"Add a caregiver" action → invite via QR code or share link (/care-circle/:linkId/invite)
Permission grant sheet: when adding (or editing) a caregiver, the patient selects exactly what the caregiver may see, item by item — e.g., current mood, latest check-in summary, medication adherence status, fall alerts, emergency contact, upcoming visits. Default = nothing shared until the patient checks it.
Per-caregiver edit / suspend / revoke controls



Settings: notifications, reminders & escalation rules, language (8 locales, RTL), theme (light/dark), telemetry/privacy, account deletion


Flow 2b — Per-Page Feature Selection (design as a reusable system)


Feature Picker component: a bottom sheet (mobile) / side panel (web) listing all available features with toggle switches, grouped by category (Health, Safety, AI, Mail, Devices, Social, Documents). Identical component whether opened from the profile's "My Features" section or from any page's Customize affordance — one source of truth.
Contextual quick-toggle: on the dashboard, long-pressing a widget offers "Remove from my app" / "Add features…"; on any feature page, the app-bar Customize icon opens the picker scrolled to that feature's category.
Conditional rendering states to design:

Dashboard with many features enabled vs. a minimal dashboard with only 2–3 enabled (widgets reflow, no empty slots)
Navigation and profile "My Features" grid re-rendered after a toggle (show before/after frames)
The moment of toggling: instant optimistic UI update with a subtle "Added to your app" / "Removed" snackbar and an Undo action — no modal confirmations
First-run minimal state: if the user enabled very few features at setup, the dashboard shows a single tasteful "Add more features" tile (this is the only place discovery is allowed to surface, and it is dismissible permanently)



Dependency handling: if a selected feature depends on another (e.g., USPS Mail Digest requires Gmail connection; Fall Detection requires device permissions), the picker shows an inline one-time setup step at toggle time — never a recurring reminder afterward.
Caregiver exclusion: the Feature Picker, Customize affordances, and all toggle controls exist only in the patient context. Caregiver screens have no customize entry points and render solely from the patient's grants.


Flow 3 — Caregiver Experience (restricted by design)


Caregiver onboarding: account creation + their own profile only. Caregivers cannot browse or enable patient features and never see the patient feature catalog.
Caregiver joins a patient's care circle only via the patient's invite (QR scan or link → invite landing screen /invite/:token with accept/decline, pending, and expired states).
Caregiver home: roster of linked patients shown as snippet cards. Each snippet card displays only the granted items (e.g., mood emoji + latest check-in time + med adherence chip + active alert badge). Ungranted data simply does not render — no locks, no teasers, no "request access" clutter on the card (a single subtle "Ask for access" link is allowed at the card's bottom edge).
Tapping a snippet opens a limited patient detail view composed only of granted modules. Include an empty-state design for "This patient hasn't shared anything with you yet."
Caregiver retains their own work tools where the patient has granted the related visibility: Messages, Calls, Schedule/EVV visit flow, Tasks assigned to them, and Analytics scoped to granted data only.
Design a clear visual distinction between the patient's full profile experience and the caregiver's restricted view (e.g., "Shared with you by [Patient]" header chip on all patient-data screens in the caregiver context).


Feature Screens (unchanged capabilities, new access model)

All features below are reached from the patient's profile → My Features (patient context) or, where granted, appear as read-only/limited modules in the caregiver's snippet view.

1. Auth

Login (email/password + OAuth), password reset flow (request → confirm → new password), Alexa account-linking, OAuth callback state. Returning-user login goes straight to dashboard.

2. Dashboards


Patient home dashboard widgets: Medication Reminders, Notifications panel, Current Mood, Recent Check-In, Primary Care Provider card, alert and offline banners
Caregiver home: snippet-card roster (per Flow 3), suspend/reactivate relationship dialogs, video-call policy toggle (only where granted)


3. Health & Wellness (patient-only unless granted)

Symptoms & Allergies tracker (tabbed, structured input forms, history), Mood & Wellness check-in, Virtual Check-In (question bank, structured answer forms, config sheet, history cards, detail/review page — mobile and web), reusable structured entry form component (typed fields with validation), meal tracking, Medication Tracker.

4. Emergency & Safety

SOS screen with cancel/countdown, Fall Detection alerts (patient view; caregiver view only if granted — alert details with skeleton-motion playback), Emergency QR code.

5. EVV (caregiver work tool)

Dashboard → patient selection → check-in location → visit in progress → checkout → visit complete → success; visit history, corrections, review records, offline sync queue.

6. Scheduling & Tasks

Shift scheduling (week/month/day views, schedule-visit dialog, conflict warnings, audit history sheet), task management (assign, custom, pre-defined templates, recurrence, ICS import, legend editor, filters), Calendar Assistant.

7. Communication

Chat inbox and threads (attachments, offline queue states), video calls (incoming, in-call, post-call telemetry summary), social feed (posts, comments, friends, requests, search).

8. AI Features

AI Assistant chat, Voice Commands (/voice: wake-word listening states, live transcript, intent confirmation, idle/listening/processing/executed/error states), Call & Visit Summaries with Clinical Urgency Banner (routine/elevated/urgent) and typed extracted items, AI Configuration, Notetaker (search, detail, config, live ASR with speaker diarization), Invoice Assistant (dashboard, OCR upload, list, detail, Excel export).

9. USPS Informed Delivery / Mail Digest

Daily mail digest cards, Gmail connect/disconnect (OAuth consent + status states), digest detail. Patient-only; caregiver sees nothing of this unless explicitly granted a digest summary item.

10. Integrations & Devices

Wearables (Fitbit), smart devices, add-device flow, home monitoring, medication management.

11. Analytics & Reports

Caregiver analytics scoped to granted data (vitals/mood trends, sentiment colors), behavioral/participation/competency trend dashboards, patient reports (patient-owned; shareable as a granted item), ADL/IADL and activity logs, behavioral incident screens, audit log — the patient's audit log includes a "who viewed my data" view.

12. Gamification

Patient points/streaks/badges, achievement detail, leaderboard. Caregiver gamification screens remain caregiver-side only.

13. Payments & Subscription

Tier selection, Stripe checkout, native billing, web pay, success/cancel, subscription management.

14. Care Circle Invites (patient-initiated only)

Invite QR/share screen, invite landing/accept with preview card and expired/invalid states, pending-invite state. Pair the accept flow with the patient-side permission grant sheet so access is defined at link time.

15. Documents & Compliance

Home care document digitization (upload/scan, review page with field-level confirm), compliance dashboard + checklist, assessment review workflow. Reached via patient's File Management; caregiver access only where granted.

16. System States

Offline banners and sync-queue UI, empty states (including caregiver "nothing shared yet"), loading skeletons, error states, notification center. No recurring onboarding/consent modals for returning users.

Deliverables

Mobile-first frames (390×844) for both contexts — the patient's full profile-centered experience and the caregiver's restricted snippet experience — light and dark variants for key screens, the permission grant sheet and the Feature Picker (bottom sheet + side panel variants, with toggle, dependency-setup, and undo-snackbar states) as reusable components, a shared component library (buttons, cards, nav, dialogs, bottom sheets, form fields, chips, badges, snippet card), and the color/typography tokens above as Figma variables.