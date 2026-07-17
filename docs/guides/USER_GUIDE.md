# Fall CareConnect 2025 User Guide

University of Maryland Global Campus  
SWEN 670 – Software Engineering Capstone  
Dr. Mir Assadullah  
November 4, 2025

---

## Document Control

### Revision History

| Date       | Version | Description      | Author           |
|------------|---------|------------------|------------------|
| 11/04/2025 | 1.0     | Initial release  | CareConnect Team |

---

## Table of Contents

- [1. Introduction – Purpose, Audience, Document Map](#1-introduction)
  - [1.1 Purpose](#purpose)
  - [1.2 Intended Audience](#intended-audience)
  - [1.3 Project Documents](#project-documents)
  - [1.4 Acronyms, Terms, and Definitions](#acronyms-terms-and-definitions)
- [2. System Capabilities – Platform Overview and Dataflow](#2-system-capabilities)
  - [2.1 Overview](#overview)
  - [2.2 Dataflow](#dataflow)
- [3. Technical Specifications and Requirements – Hardware, Software, Network](#3-technical-specifications-and-requirements)
  - [3.1 Hardware](#hardware)
  - [3.2 Software](#software)
  - [3.3 Network](#network)
- [4. User Guide – Feature Walkthroughs and How-To Scenarios](#4-user-guide)
  - [4.1 Onboarding & Authentication](#onboarding-authentication)
    - [4.1.1 Welcome](#welcome)
    - [4.1.2 User Registration](#user-registration)
    - [4.1.3 Login & Session Management](#login-session-management)
    - [4.1.4 Password Reset & Account Recovery](#password-reset-account-recovery)
    - [4.1.5 Session Timeout & MFA](#session-timeout-mfa)
  - [4.2 Billing & Subscription Management](#billing-subscription-management)
    - [4.2.1 Plan Selection & Activation](#plan-selection-activation)
    - [4.2.2 Payment Methods & Grace Periods](#payment-methods-grace-periods)
    - [4.2.3 Managing Invoices & Receipts](#managing-invoices-receipts)
  - [4.3 User & Role Management](#user-role-management)
    - [4.3.1 Role-Based Access & Permissions](#role-based-access-permissions)
    - [4.3.2 Caregiver Profiles](#caregiver-profiles)
    - [4.3.3 Patient Profiles & Linking](#patient-profiles-linking)
    - [4.3.4 Family & Guest Access](#family-guest-access)
  - [4.4 Dashboards & Menus](#dashboards-menus)
    - [4.4.1 Patient Dashboard](#patient-dashboard)
    - [4.4.2 Caregiver Command Center](#caregiver-command-center)
    - [4.4.3 Global Navigation & Quick Actions](#global-navigation-quick-actions)
  - [4.5 Scheduling, Calendars & Notifications](#scheduling-calendars-notifications)
    - [4.5.1 Task Templates & Custom Scheduling](#task-templates-custom-scheduling)
    - [4.5.2 Caregiver Shift Scheduling](#caregiver-shift-scheduling)
    - [4.5.3 Patient Calendar Assistant](#patient-calendar-assistant)
    - [4.5.4 Notification Channels & Quiet Hours](#notification-channels-quiet-hours)
  - [4.6 Health & Wellness Tracking](#health-wellness-tracking)
    - [4.6.1 Symptom Libraries & Alerts](#symptom-libraries-alerts)
    - [4.6.2 Nutrition & Meal Journaling](#nutrition-meal-journaling)
    - [4.6.3 Mood, Pain, and Virtual Check-Ins](#mood-pain-and-virtual-check-ins)
  - [4.7 AI Integration](#ai-integration)
    - [4.7.1 Ask AI Health Assistant](#ask-ai-health-assistant)
    - [4.7.2 AI Mood Detection During Calls](#ai-mood-detection-during-calls)
    - [4.7.3 Streaming Voice Notes & Diarization](#streaming-voice-notes-diarization)
  - [4.8 Communication & Telehealth](#communication-telehealth)
    - [4.8.1 Messaging & Broadcasts](#messaging-broadcasts)
    - [4.8.2 Voice, Video, & Telehealth Bridge](#voice-video-telehealth-bridge)
    - [4.8.3 Virtual Check-In Rounds](#virtual-check-in-rounds)
    - [4.8.4 Emergency SOS & QR Escalation](#emergency-sos-qr-escalation)
    - [4.8.5 Vial of Life Printable Card](#vial-of-life-printable-card)
  - [4.9 Device & Third-Party Integrations](#device-third-party-integrations)
    - [4.9.1 Wearables & Remote Monitoring](#wearables-remote-monitoring)
    - [4.9.2 Smart Home & Safety Sensors](#smart-home-safety-sensors)
    - [4.9.3 USPS Digest & Informed Delivery](#usps-digest-informed-delivery)
  - [4.10 Files & Media Management](#files-media-management)
  - [4.11 Gamification & Community Engagement](#gamification-community-engagement)
  - [4.12 Analytics & Reporting](#analytics-reporting)
  - [4.13 Electronic Visit Verification (EVV)](#electronic-visit-verification-evv)
    - [4.13.1 Launching the EVV Workspace](#launching-the-evv-workspace)
    - [4.13.2 Scheduling Visits](#scheduling-visits)
    - [4.13.3 Conducting Visits & Capturing Evidence](#conducting-visits-capturing-evidence)
    - [4.13.4 Submitting, Exporting, & Syncing](#submitting-exporting-syncing)
    - [4.13.5 EVV Video Walkthroughs](#evv-video-walkthroughs)
  - [4.14 Invoice & Billing Assistant](#invoice-billing-assistant)
    - [4.14.1 Dashboard KPIs & Trends](#dashboard-kpis-trends)
    - [4.14.2 Uploading Bills & OCR Extraction](#uploading-bills-ocr-extraction)
    - [4.14.3 Reviewing, Editing, and Saving Invoices](#reviewing-editing-and-saving-invoices)
    - [4.14.4 AI Insights, History, & Exports](#ai-insights-history-exports)
    - [4.14.5 Video Walkthrough](#video-walkthrough)
  - [4.15 Clinical Documentation & Note Taking](#clinical-documentation-note-taking)
    - [4.15.1 Real-Time Note Capture](#real-time-note-capture)
    - [4.15.2 Managing Patient Notes](#managing-patient-notes)
    - [4.15.3 Configuring Speech Models](#configuring-speech-models)
    - [4.15.4 Video Walkthroughs](#video-walkthroughs)
  - [4.16 Safety Monitoring & Fall Alerts](#safety-monitoring-fall-alerts)
    - [4.16.1 Understanding Fall Alert Streams](#understanding-fall-alert-streams)
    - [4.16.2 Reviewing Alert Details](#reviewing-alert-details)
    - [4.16.3 Responding & Documenting Outcomes](#responding-documenting-outcomes)
  - [4.17 Postal & Delivery Insights](#postal-delivery-insights)
    - [4.17.1 Connecting Email Sources](#connecting-email-sources)
    - [4.17.2 Navigating the Digest Viewer](#navigating-the-digest-viewer)
    - [4.17.3 Search, Filtering, and Accessibility](#search-filtering-and-accessibility)
    - [4.17.4 USPS Digest Video Walkthrough](#usps-digest-video-walkthrough)
  - [4.18 Localization & Multilingual Experience](#localization-multilingual-experience)
    - [4.18.1 Internationalization Walkthrough](#internationalization-walkthrough)
- [5. Security, Data Management, and General Settings](#5-security-data-management-and-general-settings)
  - [5.1 AI Configuration](#ai-configuration)
  - [5.2 Clear Cache & Offline Queues](#clear-cache-offline-queues)
  - [5.3 Appearance & Personalization](#appearance-personalization)
- [6. Troubleshooting & Support](#6-troubleshooting--support)
  - [6.1 Common Issues and Solutions](#common-issues-and-solutions)
  - [6.2 Contact Support](#contact-support)

---

## 1. Introduction

### 1.1 Purpose
The Fall CareConnect 2025 User Guide offers in-depth instructions for every capability available in the CareConnect ecosystem—from initial onboarding through advanced clinical documentation, electronic visit verification, and invoice automation. The guide blends narrative explanations with procedural steps so that patients, caregivers, administrators, and support staff can confidently navigate the latest feature set documented in SRS v5.3, TDD v4.1, PMP v4.2, and STP v2.1.

### 1.2 Intended Audience
- **Patients and care recipients** who use CareConnect to monitor health, review schedules, and stay connected to their support network.
- **Professional and family caregivers** responsible for executing care plans, documenting visits, and responding to safety events.
- **Clinical administrators and coordinators** who manage billing, EVV compliance, staffing, and analytics.
- **IT support specialists and developers** who maintain integrations, troubleshoot issues, and roll out configuration changes.

### 1.3 Project Documents
Table 1 lists the controlling project documents. Each provides deeper background for topics summarized in this guide.

| Document                     | Version | Date       | Description                                      |
|------------------------------|---------|------------|--------------------------------------------------|
| Project Plan                 | 4.2     | 11/04/2025 | Project charter, scope, milestones               |
| Software Requirements Specification | 5.3 | 11/04/2025 | Functional and non-functional requirements       |
| Technical Design Document    | 4.1     | 11/04/2025 | Architecture diagrams and component designs      |
| Software Test Plan           | 2.1     | 11/04/2025 | Test strategy, test cases, acceptance criteria    |
| Programmer's Guide           | 1.0     | 11/04/2025 | Code structure, development standards             |
| Deployment & Operations Guide| 1.0     | 11/04/2025 | Release process, infrastructure management        |
| User Guide                   | 1.0     | 11/04/2025 | Platform instructions for end users               |

### 1.4 Acronyms, Terms, and Definitions
- **AI** – Artificial Intelligence
- **ASR** – Automatic Speech Recognition
- **EDI** – Electronic Data Interchange
- **EVV** – Electronic Visit Verification
- **HIPAA** – Health Insurance Portability and Accountability Act
- **MFA** – Multi-Factor Authentication
- **OCR** – Optical Character Recognition
- **SOS** – Emergency distress signal
- **USPS** – United States Postal Service

---

## 2. System Capabilities

### 2.1 Overview
CareConnect unifies clinical coordination, remote monitoring, AI-assisted documentation, billing automation, and family engagement in a single, role-aware experience. Fall 2025 highlights include:
- **EVV workspace** with visit scheduling, GPS or address-based check-in/out, compliance-ready EDI exports, and offline synchronization queues.
- **Invoice & Billing Assistant** for high-volume document intake, AI-powered OCR, duplicate detection, collaborative review, and financial KPIs.
- **Streaming voice diarization** that transcribes multi-speaker conversations, tags participants, and stores structured patient notes.
- **Emergency response tooling** featuring an exportable medical QR card, SOS escalation flows, fall-alert skeleton playback, and integration with smart-home sensors.
- **USPS informed delivery digest** pulling mail previews straight from linked email accounts to assist with medication-by-mail tracking and insurance correspondence.
- **Expanded scheduling and calendar utilities** covering caregiver shift planning, patient calendar assistants, and configurable notification windows.

### 2.2 Dataflow
The multi-tier architecture distributes responsibilities across secure services:
1. **Flutter front-end** applications render dashboards, capture sensor data, perform on-device inference (Sherpa ONNX for speech, AI mood detection), and support offline queues.
2. **Backend services** manage authentication, RBAC policies, visit and invoice persistence, AI orchestration, and notification routing over REST and WebSocket channels.
3. **Data stores** encrypt PHI at rest while maintaining immutable audit logs for EVV, invoice edits, and emergency events.
4. **Integration services** connect to payment processors (Stripe, PayPal), wearable APIs, email providers (Gmail for informed delivery), and AI model endpoints.
5. **Notification engine** aggregates push, SMS, email, and in-app alerts, respecting user-defined quiet hours and escalation rules.

---

## 3. Technical Specifications and Requirements

### 3.1 Hardware
- **Mobile devices:** Android 10+ or iOS 13+ with 4 GB RAM, camera, microphone, GPS, and Bluetooth LE for wearables.
- **Desktop/laptop:** Windows 10+, macOS 12+, or Ubuntu 22.04+ with 8 GB RAM, dual-core CPU, webcam, and dedicated storage for downloaded PDFs and audio notes.
- **Peripherals:** Barcode scanners for medication intake, ECG/BP monitors, fall-detection wearables, smart speakers for voice commands, and printers for EVV/Invoice reports.

### 3.2 Software
- **CareConnect app:** Latest production build with access to Sherpa ONNX assets for on-device ASR, OAuth libraries for Google integrations, and share_plus for PDF exports.
- **Browsers:** Chrome 118+, Firefox 119+, Safari 16+, Edge 118+.
- **Mobile permissions:** Camera, microphone, location, file storage, motion sensors, notification access, and calendar integration.
- **Third-party connectors:** Google API credentials for Gmail digest, Stripe/PayPal API keys for billing, and FHIR endpoints for facility EHRs if enabled.

### 3.3 Network
- **Bandwidth:** 10 Mbps down / 5 Mbps up for HD video; 2 Mbps sustained uplink required for ASR streaming.
- **Security:** TLS 1.2+ for all APIs, secure WebSockets for live dashboards, VPN support for enterprise rollouts, and DNS allowlists for wearable providers.
- **Offline tolerance:** EVV and invoice modules queue transactions for later sync; ensure devices have at least 200 MB free storage for cached assets.

---

## 4. User Guide
The following sections describe each feature in operational detail. Screenshots referenced in project documentation will be supplemented with narrated walkthrough videos in upcoming releases.

### 4.1 Onboarding & Authentication

#### 4.1.1 Welcome
1. Launch the CareConnect app (mobile or desktop) or browse to the web portal.
2. Review carousel highlights covering EVV, invoices, AI notes, and safety tools. Tap `Next` to advance or `Skip` to jump to role selection.
3. Select `Get Started` to see the role chooser (Patient, Caregiver, Organization Admin, Family Viewer).
4. Optional: open the `Platform Tour` overlay for a guided walkthrough of new Fall 2025 capabilities.

#### 4.1.2 User Registration
1. Choose your role. Organization administrators may invite additional staff post-registration.
2. Enter personal details (legal name, preferred display name, email, mobile). Caregivers can scan a QR invite from an administrator to pre-fill credentials.
3. Create a strong password (minimum 12 characters). Password strength meters enforce policies documented in the SRS.
4. Select a sign-in method: email/password, SSO (Azure AD, Google Workspace), or SMS one-time passcode for limited-use caregiver kiosks.
5. Accept Terms of Service and Privacy Policy, then submit.
6. Confirm the verification email or SMS. For SSO, the IdP redirect completes activation.

#### 4.1.3 Login & Session Management
1. Enter your credentials on the `Login` screen or choose your SSO provider.
2. Devices remember trusted sessions for 30 days unless policy overrides apply.
3. Idle sessions auto-lock based on role: 10 minutes for caregiver clinical consoles, 30 minutes for family viewers.
4. View active sessions under `Settings > Security` to terminate remote devices if needed.

#### 4.1.4 Password Reset & Account Recovery
1. Tap `Forgot Password?` on the login screen.
2. Provide the registered email address and confirm the reset request.
3. Click the secure link delivered via email/SMS within 15 minutes and set a new password.
4. Administrators can issue temporary access codes for clinicians who cannot access email.
5. For compromised accounts, administrators can force a password reset and revoke tokens in the admin console.

#### 4.1.5 Session Timeout & MFA
1. Enable MFA via authenticator app, SMS, or hardware key under `Settings > Security`.
2. Configure session timeout overrides for shared devices—CareConnect enforces maximums defined in the Deployment Guide (15 minutes for EVV tablets, 5 minutes for kiosk tablets).
3. If MFA fails while offline, use backup codes generated during setup. Store them securely.

### 4.2 Billing & Subscription Management

#### 4.2.1 Plan Selection & Activation
1. Navigate to `Settings > Billing`.
2. Review plan tiers (Patient Essentials, Care Team Pro, Organization Suite) with side-by-side comparisons that highlight EVV capacity, invoice automation, and AI note allocations.
3. Click `Activate` to launch the checkout wizard. Stripe handles cards and ACH; PayPal is available for agencies with existing agreements.
4. Confirm billing contact, business name, tax ID, and auto-renew preferences before finalizing.

#### 4.2.2 Payment Methods & Grace Periods
1. Add or update payment methods under `Manage Payment Methods`.
2. Define a backup method to avoid service interruption. The system cascades to the backup if the primary fails.
3. Failed charges trigger a 7-day grace period. During grace, premium features display warning badges but remain accessible for critical workflows (EVV submission, invoice review).
4. After grace expiration, premium features downgrade while core data remains intact for 60 days pending payment.

#### 4.2.3 Managing Invoices & Receipts
1. Download billing receipts and statements directly from the Billing page.
2. Export histories as CSV for finance reconciliation.
3. Toggle email invoice delivery to route copies to accounting addresses.
4. See Section [4.14](#414-invoice--billing-assistant) for managing clinical invoices within the Invoice Assistant.

### 4.3 User & Role Management

#### 4.3.1 Role-Based Access & Permissions
1. Open `Admin Console > Roles` to view default RBAC templates.
2. Duplicate a role to customize permissions (e.g., allow Caregiver Supervisors to approve EVV corrections while restricting invoice edits).
3. Each toggle controls view/edit/export rights for invoices, EVV, ASR notes, USPS digest, and safety dashboards.
4. All role changes write to the immutable audit log with timestamp, actor, and rationale.

#### 4.3.2 Caregiver Profiles
1. Access `Profile > Caregiver Profile`.
2. Update contact information, licenses, specialties, shift preferences, and language fluency.
3. Upload credential PDFs; the system surfaces expiry alerts 30 days in advance.
4. Link to wearables (step trackers) or smart badges used for fall detection verification.

#### 4.3.3 Patient Profiles & Linking
1. Patients edit demographics, medical history, allergies, and medication lists from `Profile > View Profile`.
2. Caregivers can invite patients via email or secure QR code. Patients scan the QR from their device to accept relationships quickly.
3. Administrators can bulk-upload patient rosters via CSV and assign primary caregivers.
4. Each patient profile shows integrated modules: upcoming EVV visits, invoice balances, fall-alert status, and mail digest snapshots.

#### 4.3.4 Family & Guest Access
1. Patients open `Profile > Family Access` to invite viewers (read-only, wellness summaries, emergency contacts).
2. Invitations send via email with configurable expiry (24 hours, 3 days, 7 days).
3. Family members can elevate to `Care Partner` status upon patient approval, granting permissions to respond to fall alerts and view EVV history.
4. Administrators may revoke access or downgrade roles if misuse is detected.

### 4.4 Dashboards & Menus

#### 4.4.1 Patient Dashboard
1. Displays wellness widgets (mood, pain, vitals), today’s tasks, upcoming EVV visits, outstanding invoices, and USPS mail previews.
2. The `Health Snapshot` combines symptom trends with medication adherence, pulling data from standardized templates.
3. `Financial Summary` shows unpaid invoices and insurance reimbursements awaiting review.
4. Patients can rearrange widgets and pin the `Ask AI` panel for quick guidance.

#### 4.4.2 Caregiver Command Center
1. Caregivers land on a roster with priority flags (overdue EVV visit, negative mood alert, high-risk fall detection).
2. Quick actions on each patient card include `Message`, `Start Video Visit`, `Document Note`, `Invoice Review`, and `Emergency QR`.
3. The top banner highlights shift assignments, offline items pending sync, and broadcast announcements from administrators.
4. Integrated `Invoice Overview` cards display unpaid counts, linking directly to relevant invoice filters.

**Video walkthrough:**  
![Dashboard new features walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/TeamC_CDashboard_NewFeatures.mov)  
[Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/TeamC_CDashboard_NewFeatures.mov)

#### 4.4.3 Global Navigation & Quick Actions
1. The universal hamburger menu exposes modules: Dashboard, EVV, Invoice Assistant, AI Notetaker, Files, Wearables, USPS Digest, Settings, and Help Center.
2. `More` drawers differ by role—patients see wellness and financial tools; caregivers see documentation and scheduling utilities.
3. The floating action button toggles contextually (add task, start note, upload document).

### 4.5 Scheduling, Calendars & Notifications

#### 4.5.1 Task Templates & Custom Scheduling
1. From a patient profile, select `Assign Task`.
2. Choose a template (e.g., Post-Operative Pain Management) to auto-fill instructions, frequencies, and responsible parties.
3. Customize tasks with start/end times, recurrence (daily, weekly, interval), and reminder windows.
4. Save to notify assignees and log the addition in the patient timeline.

#### 4.5.2 Caregiver Shift Scheduling
1. Open `Scheduling > Caregiver Shifts`.
2. Toggle `Recurring Shift` to define weekly patterns or leave disabled for one-time coverage.
3. Select start/end times via the time picker and tap days (S–S) to indicate coverage.
4. Save to publish to the organization calendar. Peers see availability and can request swaps through the messaging channel.

#### 4.5.3 Patient Calendar Assistant
1. Access `Calendar Assistant` from the patient dashboard.
2. View consolidated appointments (EVV visits, telehealth, medication refills, USPS package deliveries).
3. Enable smart suggestions to auto-fill routine events based on historical adherence.
4. Sync with external calendars (Google, Outlook) by authorizing integration; read-only links are available for family.

**Video walkthrough:**  
![Calendar assistant walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/calendar-assistant.mp4)  
[Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/calendar-assistant.mp4)

#### 4.5.4 Notification Channels & Quiet Hours
1. Navigate to `Settings > Notifications`.
2. Enable delivery methods (push, SMS, email) individually for EVV, invoices, ASR note tasks, fall alerts, and USPS digests.
3. Set quiet hours to pause non-critical alerts; critical alerts (SOS, high-impact fall) automatically override.
4. Use `Test Notification` to verify channel health.

### 4.6 Health & Wellness Tracking

#### 4.6.1 Symptom Libraries & Alerts
1. Caregivers assign default symptom libraries (fatigue, nausea, dizziness) or add custom symptoms per patient.
2. Patients respond to symptom prompts triggered via push notifications. Responses populate charts and trigger alerts when thresholds are exceeded.
3. Mood-symptom correlation graphs help clinicians identify interactions between treatments and reported wellness.

#### 4.6.2 Nutrition & Meal Journaling
1. Patients log meals under `Health > Meal Log` with time, ingredients, and portion size.
2. Caregivers configure default questions (hydration status, appetite changes) and attach to patients individually.
3. AI summarization flags nutrition trends and suggests follow-ups inside the caregiver dashboard.

#### 4.6.3 Mood, Pain, and Virtual Check-Ins
1. The `How are you feeling today?` widget captures mood via emojis and optional comments.
2. The pain slider records intensity on a 1–10 scale with clear iconography.
3. Caregivers review results in the `Vital Data` card. Negative moods trigger notifications and auto-suggest a virtual check-in.
4. Virtual check-in histories display clinician, duration, mood outcomes, and summary notes with next scheduled sessions.

### 4.7 AI Integration

#### 4.7.1 Ask AI Health Assistant
1. Tap the blue `Ask AI` button to open the conversational assistant.
2. Type or upload documents (discharge instructions, lab results). AI provides context-aware answers, using on-device summaries when offline.
3. Share responses with caregivers or append them to patient notes for review.

#### 4.7.2 AI Mood Detection During Calls
1. Start a video call from patient or caregiver dashboards.
2. Grant camera and microphone permissions when prompted.
3. During the call, the left panel displays emoji mood assessments derived from facial cues, refreshing every few seconds.
4. Post-call summaries capture mood trends for longitudinal review.

#### 4.7.3 Streaming Voice Notes & Diarization
1. Open `AI Notetaker` or start a note from within a telehealth session.
2. Press `Record` to capture audio. The system uses Sherpa ONNX models to transcribe speech in real time and detect speaker changes.
3. Label speakers (Patient, Caregiver, Specialist) to improve diarization. Add new speaker names on the fly.
4. After recording, review the transcript, remove sensitive segments, and save to the patient chart. Notes can be exported as PDF or shared with supervisors.

### 4.8 Communication & Telehealth

#### 4.8.1 Messaging & Broadcasts
1. Use `Messages` for one-to-one or group chats. Attach photos, documents, or audio snippets.
2. Mark messages as `High Priority` to escalate notifications.
3. Administrators send broadcasts from `Messages > Broadcasts` to disseminate policy updates; recipients acknowledge receipt for audit tracking.

#### 4.8.2 Voice, Video, & Telehealth Bridge
1. Start audio/video calls from patient cards, invoices (for billing disputes), or EVV visit details.
2. Telehealth Bridge integrates third-party providers; join meetings from within CareConnect without switching apps.
3. Screen share (web) or share files mid-call to collaborate on care plans.

#### 4.8.3 Virtual Check-In Rounds
1. Access `Virtual Check-In` from patient dashboards or the navigation drawer.
2. Configure question sets, cadence, and responsible clinicians.
3. During rounds, clinicians document key observations and mark follow-up actions. Completed rounds feed analytics and trigger notifications if critical responses are captured.

#### 4.8.4 Emergency SOS & QR Escalation
1. Activate SOS by pressing and holding the red button for three seconds.
2. Confirm emergency type (medical, safety, other). CareConnect sends GPS, profile, and contact info to responders.
3. Generate an emergency QR card under `Safety > Emergency QR`. Share or print the card; first responders scan to access vital details and contacts.

#### 4.8.5 Vial of Life Printable Card
1. From the Emergency QR screen, tap `Generate Vial of Life PDF` to build a printable summary of vital medical information and emergency contacts.
2. Review the preview to confirm details such as medications, allergies, and primary physician before printing.
3. Use the `Download` or `Share` buttons to distribute the PDF to caregivers, place it on the refrigerator, or store it in emergency kits.
4. Reprint after any profile update so responders always have the latest information.

**Video walkthrough:**  
![Vial of Life walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/vial-of-life.mov)  
[Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/vial-of-life.mov)

### 4.9 Device & Third-Party Integrations

#### 4.9.1 Wearables & Remote Monitoring
1. Open `Integrations > Wearables` to connect Fitbit, Apple Health (iOS), or Health Connect (Android).
2. Authorize data sharing. The semester implementation demonstrates local wearable metric display and status labels for persisted mapping vs placeholder/demo-only metrics.
3. Supported metric/source scope is documented in `docs/spring2026_guides/WEARABLE_METRICS_SOURCE_MATRIX.md`.

#### 4.9.2 Smart Home & Safety Sensors
1. Access `Integrations > Smart Home` to link fall-detection mats, motion sensors, or voice assistants.
2. Map each sensor to a room or patient. Alerts appear in the Fall Alert module with skeletal playback when available.
3. Use automation rules to turn on lights or notify caregivers when movement patterns change unexpectedly.

**Video walkthrough:**  
![Smart devices integration walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/smart-devices-alexa.mp4)  
[Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/smart-devices-alexa.mp4)

#### 4.9.3 USPS Digest & Informed Delivery
See Section [4.17](#417-postal--delivery-insights) for a full walkthrough.

### 4.10 Files & Media Management
1. Navigate to `Files Management` to upload photos, PDFs, scans, or transcribed documents.
2. Categorize uploads (Lab Results, Insurance, Care Plans). Add tags for fast retrieval.
3. Use speech-to-text capture for dictated documents, or enter text manually.
4. Share files with specific team members or generate expiring public links for external specialists.

### 4.11 Gamification & Community Engagement
1. `Achievements` track XP earned from completing tasks, check-ins, and note documentation.
2. Patients opt into leaderboards to compare progress with peers using anonymized identifiers.
3. Daily motivation messages adapt to adherence patterns and wellness logs.
4. The `Community` tab enables social posts, friend requests, and direct messaging among approved contacts.

### 4.12 Analytics & Reporting
1. Open `Analytics` to view adherence rates, EVV completion metrics, invoice payment trends, and fall alert outcomes.
2. Filter by date range, care team, or facility.
3. Export dashboards as PDF or data tables (CSV). Scheduled reports deliver to specified emails weekly or monthly.
4. Toggle `Real-time` vs `Batch` processing depending on operational needs. Real-time streams update dashboards instantly; batch modes process overnight for performance.

### 4.13 Electronic Visit Verification (EVV)

#### 4.13.1 Launching the EVV Workspace
1. Select `EVV` from the caregiver navigation drawer.
2. Summary tiles show Overdue, Ready, Upcoming, and Total Today counts to prioritize action.
3. Toggle between `Today` and `Upcoming` lists; filters allow sorting by patient or service type.

#### 4.13.2 Scheduling Visits
1. Tap `Schedule New Visit`.
2. Complete required fields (Patient, Service Type, Date, Time). Optional inputs include duration, priority, and notes.
3. Save to notify patients and populate the EVV calendar. Conflicts prompt warnings for double-booked caregivers.

#### 4.13.3 Conducting Visits & Capturing Evidence
1. When ready, tap `Start Visit` from the EVV dashboard or patient card.
2. Choose check-in location (patient address or GPS). GPS requires location permissions; address defaults to the patient profile.
3. During the visit, timers track duration. Add mid-visit notes or attach photos for documentation.
4. Tap `Ready to Check Out`, select exit location, review summary, and add final notes.

#### 4.13.4 Submitting, Exporting, & Syncing
1. Submit the visit to finalize and lock timestamps.
2. Generate EDI exports from the visit summary. Save or share files via system share sheets for upload to payer portals.
3. Offline completions queue in `Offline Sync`. When connectivity returns, open the queue and tap `Sync` to upload.
4. Correction requests route to supervisors for approval, maintaining audit compliance.

#### 4.13.5 EVV Video Walkthroughs
- **Mobile caregiver app tour**  
  ![EVV mobile caregiver walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/evv-mobile.mp4)  
  [Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/evv-mobile.mp4)
- **Web console tour**  
  ![EVV web console walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/evv-web.mp4)  
  [Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/evv-web.mp4)

### 4.14 Invoice & Billing Assistant

#### 4.14.1 Dashboard KPIs & Trends
1. Launch `Invoice Assistant` from the drawer.
2. Dashboard widgets display total invoices, total amount, pending payments, overdue counts, and recent activity.
3. Charts visualize payment progress, status breakdown, and monthly trends to highlight bottlenecks.

#### 4.14.2 Uploading Bills & OCR Extraction
1. Choose the `Upload Invoice` tab.
2. Select files from device storage (PNG, JPG, JPEG, PDF) or capture using the camera. Multiple files are supported per session.
3. Review selected files in the `Review Photos` screen—rotate, reorder, or remove before continuing.
4. The system invokes the Invoice OCR + LLM service to extract vendors, services, patient identifiers, amounts, and line items. Offline status is monitored and notifications appear when connectivity resumes.

#### 4.14.3 Reviewing, Editing, and Saving Invoices
1. After extraction, confirm duplicate detection messages. Proceed if the invoice is intentional; otherwise cancel.
2. The detail page organizes content into tabs: `Details`, `Services`, `Payment`, `AI Insights`, and `History`.
3. Enter edit mode to adjust fields, mark services as covered by insurance, or update payment status.
4. Save changes to persist the invoice. The system logs who edited, when, and what changed for auditability.

#### 4.14.4 AI Insights, History, & Exports
1. Review AI-generated summaries that highlight anomalies, missing authorizations, or prior trends.
2. Use `History` to see every revision with timestamps and comments.
3. Download PDFs using `Open PDF` (requires original document link) or export structured data for accounting systems.
4. Configure invoice notifications (overdue reminders, new upload alerts) in `Invoice Settings` within the module.

#### 4.14.5 Video Walkthrough
![Invoice Assistant walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/invoice-assistant.mp4)  
[Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/invoice-assistant.mp4)

### 4.15 Clinical Documentation & Note Taking

#### 4.15.1 Real-Time Note Capture
1. Open `AI Notetaker` or tap `Document Note` during a visit.
2. Start streaming audio; transcripts populate live while diarization labels each speaker.
3. Insert manual annotations or flag key moments for later review.
4. Stop recording to finalize the transcript. Preview, redact sensitive content, and save to the patient record.

#### 4.15.2 Managing Patient Notes
1. Access `Documentation > Patient Notes` to search by patient, date, or clinician.
2. Open a note to view transcript, summary, attachments, and related tasks.
3. Share notes with team members or export to PDF. Revision history tracks edits and approvals.

#### 4.15.3 Configuring Speech Models
1. Navigate to `Settings > AI Configuration`.
2. Select ASR model preferences (on-device Sherpa ONNX vs. cloud transcription) and diarization sensitivity.
3. Manage audio retention policies—choose to keep raw audio locally only, upload encrypted copies, or delete after transcription.

#### 4.15.4 Video Walkthroughs
- **Notetaker overview and setup**  
  ![Notetaker overview walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/notetaker-overview.mp4)  
  [Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/notetaker-overview.mp4)
- **Detailed transcription workflow**  
  ![Notetaker transcription workflow walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/notetaker-workflow.mp4)  
  [Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/notetaker-workflow.mp4)

### 4.16 Safety Monitoring & Fall Alerts

#### 4.16.1 Understanding Fall Alert Streams
1. Open `Safety > Fall Alerts`.
2. The timeline lists recent detections classified by severity, location, and source (wearable, smart home sensor, manual SOS).
3. Skeleton playback visualizes detected falls to help clinicians assess legitimacy.

#### 4.16.2 Reviewing Alert Details
1. Tap an alert to view patient info, captured sensor data, and contextual notes.
2. `Mock Alert Lab` allows training drills—simulate events to practice response workflows.
3. Patients can view a simplified alert history to understand caregiver follow-up.

#### 4.16.3 Responding & Documenting Outcomes
1. Use the `Respond` action to call, message, or initiate a telehealth session with the patient.
2. Document the resolution (assisted recovery, false alarm, escalated to EMS) and assign follow-up tasks.
3. Alerts automatically notify primary caregivers, family contacts (if permitted), and administrators for severe events.

### 4.17 Postal & Delivery Insights

#### 4.17.1 Connecting Email Sources
1. Navigate to `Integrations > USPS Digest` or open the USPS Digest module directly.
2. Authorize access to the Gmail account receiving USPS Informed Delivery emails.
3. CareConnect fetches daily digests and caches images for faster viewing. Offline viewing uses stored thumbnails.

#### 4.17.2 Navigating the Digest Viewer
1. The digest groups mailpieces and packages by delivery date. Select a day from the left rail to view previews.
2. Mailpiece cards show sender, summary, and the scanned envelope image. Tap to enlarge or access action buttons (Track, Redelivery, Dashboard).
3. Packages list tracking numbers with expected delivery dates and quick links to USPS services.

#### 4.17.3 Search, Filtering, and Accessibility
1. Use the search bar to filter by sender or keywords; results update after a short debounce to reduce load.
2. Toggle between grid and list view for accessibility. High-contrast mode and keyboard navigation ensure compliance with ADA guidelines.
3. Download envelope images or share with caregivers responsible for medication-by-mail coordination.

#### 4.17.4 USPS Digest Video Walkthrough
![USPS digest walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/InformedDelivery_USPS.mov)  
[Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/InformedDelivery_USPS.mov)

### 4.18 Localization & Multilingual Experience
CareConnect supports multilingual caregivers and patients through dynamic localization and regional formatting.

#### 4.18.1 Internationalization Walkthrough
1. Open `Settings > Preferences > Language` to switch between supported locales. Text, date/time formats, and numeric separators update instantly.
2. Verify RTL (right-to-left) layouts and translated UI strings using the localization preview panel before rolling changes into production.
3. Combine localization with accessibility settings (text scaling, high contrast) to tailor experiences for diverse users.

![Localization experience walkthrough](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/localization.mp4)  
[Download video](https://github.com/umgc/2025_fall/raw/main/careconnect2025/docs/user-videos/localization.mp4)

---

## 5. Security, Data Management, and General Settings

### 5.1 AI Configuration
1. Open `Settings > AI Configuration`.
2. Select AI providers for Ask AI, invoice extraction, and ASR. Mix on-device and cloud options as permitted by organizational policy.
3. Adjust data minimization settings (strip PHI before cloud processing, anonymize transcripts) and test responses with sample prompts.

### 5.2 Clear Cache & Offline Queues
1. Under `Settings > General`, tap `Clear Cache` to remove temporary files (invoice images, ASR audio, USPS thumbnails).
2. Review the `Offline Queue` to monitor pending EVV submissions, invoice uploads, or note saves awaiting connectivity. Trigger manual sync if needed.

### 5.3 Appearance & Personalization
1. Toggle dark or light mode from the appearance switch in the hamburger menu.
2. Choose accent colors, text scaling, and widget density to match accessibility needs.
3. Configure dashboard layout presets (Clinical Focus, Financial Focus, Safety Focus) to tailor the experience by role.

---

## 6. Troubleshooting & Support

### 6.1 Common Issues and Solutions
- **Cannot log in:** Verify credentials, ensure MFA device is available, and check for admin-issued forced resets. Use backup codes when offline.
- **EVV check-in fails:** Confirm GPS permissions, ensure the patient address is correct, or switch to manual address entry when indoors.
- **Invoice OCR errors:** Re-upload higher-resolution images, ensure full pages are captured, or manually key critical fields before saving.
- **ASR transcript inaccurate:** Calibrate microphone placement, reduce background noise, and retrain speaker profiles in `AI Configuration`.
- **Fall alert false positives:** Adjust sensor sensitivity, review smart home placement, and mark the alert as false to refine future detection.
- **USPS digest empty:** Reauthorize Gmail access, confirm digest emails are arriving, or enable mock data for demonstration mode.
- **Notifications not received:** Review notification settings, confirm quiet hours, and ensure device-level notification permissions are enabled.

### 6.2 Contact Support
1. Open `Settings > Help Center`.
2. Browse knowledge base articles or submit a support ticket with logs and screenshots.
3. Urgent needs (failed EVV submission, SOS malfunction) trigger priority routing via phone or secure chat. Expect acknowledgment within one hour and full response within 24 hours.

---

**Future Enhancements:** The team is preparing guided video tours, interactive checklists, and localized translations to complement this written guide and support diverse learning preferences.
