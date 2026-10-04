# Help content verification

Reviewed: October 3, 2026. Scope: the eight existing bundled articles, platform
differences, and a record of source material and outstanding verification.

This is the narrowed Step 6. It does not claim a new end-to-end audit of every
instruction. Step 4 included workflow source inspection; this review adds the
platform distinctions below. Automated Help widget checks are separate from
testing dose updates, messages, check-in submission, or reset emails against a
live backend. No physical mobile-device or browser workflow check was performed.

## Source material

- [SUPPORT.md](../../SUPPORT.md): password-reset FAQ and support context.
- [User Guide](../guides/USER_GUIDE.md): dashboard/navigation (4.4), calendars
  (4.5.3), mood/check-ins (4.6.3 and 4.8.3), messaging (4.8.1), password reset
  (4.1.4), EVV scheduling (4.13.2), and offline queues (5.2).
- [Windows preview instructions](../../scripts/WINDOWS_PREVIEW.md) and
  [launcher](../../scripts/run-windows-preview.ps1): disabled integrations and
  offline-write behavior.
- Current frontend source, listed per article below, is the reference for
  implementation-specific statements. The older User Guide is context, not
  proof that a described workflow exists in the current app. It was not copied
  wholesale into Help.

## Platform distinctions recorded in Help

| Area | Windows preview | Mobile apps | Web |
| --- | --- | --- | --- |
| Help reading, topics, and search | Bundled content; no backend, database, or disabled preview plugin needed. | Uses the same bundled catalog. | Catalog is bundled with the loaded app; starting/reloading the website can still require connectivity. Browser offline reload behavior has not been verified. |
| Offline saving and replay | Disabled by the preview launcher. Writes cannot be queued for later replay. This does not disable offline Help reading. | The Windows preview restrictions do not establish mobile availability; offline workflows need separate device verification. | Do not assume offline Help implies offline server operations. Browser persistence behavior needs separate verification. |
| Text-to-speech | The preview omits the native TTS integration. | Depends on the mobile build and device support; not checked on a physical device. | Browser capabilities differ from native integrations; not checked in a browser. |
| GPS | The preview omits the native location integration. | Requires a supported device and appropriate permissions; not checked on a physical device. | Browser location support and permissions differ; not checked in a browser. |
| Native permission integration | The preview omits the native permission-handler integration. This does not imply all operating-system permissions or other plugins are disabled. | Device permissions and supported plugins determine availability. | Browser permissions are a different mechanism. |
| Daily Check-In | The native mood-and-notes screen's Submit Check-In displays a mock confirmation; it does not save/send those responses. | The shared native screen has the same mock callback. | The `/virtual-checkin` web entry can open a pending questionnaire answer form with server submission. Patient bottom navigation currently imports the native-style screen directly, so the entry point matters. Neither web entry was exercised in a browser during this review. |

The broad distinctions are visible in **Reading Help articles**, reachable
through Getting Started and a related link from the main Getting started guide.
The medication article additionally explains that Windows preview dose updates
need connectivity. The check-in article preserves the native mock limitation
and distinguishes it from the web questionnaire flow.

## Article-by-article record

"Source checked" means code inspection, not a successful live workflow.
Windows preview refresh and Help widget tests establish that the Help code loads
and renders; they do not establish that every described server operation works.

All frontend paths below are relative to `frontend/lib/`.

| Article ID | Source material / implementation references | Platforms checked | Remaining unverified instructions |
| --- | --- | --- | --- |
| `getting-started-with-careconnect` | User Guide 4.4.1/4.4.3 as context; `config/navigation/bottom_nav_config.dart`, `widgets/menu/menu_page.dart`, `pages/settings_page.dart`, and Patient dashboard source. | Shared navigation source inspected for native platforms; web navigation import reviewed. Help rendering covered by widget tests. | Full Patient sign-in/navigation on Windows, mobile, and web; account-link/data troubleshooting against a live account. |
| `viewing-medications-and-recording-a-dose` | User Guide 4.4.1 as dashboard context; `features/health/medication-tracker/pages/medication-tracker.dart`, `features/dashboard/patient_dashboard/widgets/medication_reminder_widget.dart`, Patient dashboard/service source; Windows preview launcher. | Shared medication source inspected in Step 4; Windows offline-preview behavior source checked in Step 6. | Actual dose persistence, reminder refresh, backend failures, and behavior on each platform. No offline dose success is promised for the Windows preview. |
| `completing-a-daily-check-in` | User Guide 4.6.3/4.8.3 as context; `features/health/virtual_check_in/presentation/pages/patient_check_in_page.dart`, `patient_check_in_page_entry.dart`, `patient_check_in_page_web.dart`, `patient_check_in_detail_page.dart`, and bottom navigation configuration. | Windows/mobile shared native mock callback inspected; web conditional entry and answer-form submission source inspected. | Runtime questionnaire loading/submission and return navigation in a browser, alternate entry points, native camera availability, and mobile device permissions. Native mood/notes submission remains a mock. |
| `viewing-appointments` | User Guide 4.5.3/4.13.2 as context; `features/dashboard/patient_dashboard/pages/patient_dashboard.dart` upcoming EVV section and loading code. | Shared dashboard source inspected in Step 4. | Live scheduled visits, date/time presentation, refresh behavior and connection errors on Windows/mobile/web. |
| `messaging-your-caregiver` | User Guide 4.8.1 as context; `features/social/presentation/pages/chat_inbox_screen.dart`, `my_friend_screen.dart`, and `chat_room_screen.dart`. | Shared inbox/contact/send/retry source inspected in Step 4. | Caregiver linking, messaging availability, successful delivery, failed-send/retry, and platform-specific keyboard behavior in actual conversations. |
| `resetting-your-password` | SUPPORT password FAQ; User Guide 4.1.4 as context; `features/auth/presentation/pages/login_page.dart`, `reset_password_screen.dart`, and password-reset flow source. | Shared sign-in/reset-request source inspected in Step 4. | Email delivery, expired/replaced reset links, password change, and subsequent login on Windows/mobile/web. SMS delivery or a specific expiry duration is not promised by this article. |
| `opening-help` | `pages/settings_page.dart`, `config/router/app_router.dart`, and bundled Help content. User Guide 4.4.3 is historical navigation context. | Settings placement source checked; Help home/article navigation covered by local widget tests. | Full Settings-to-Help navigation on each platform with actual account/provider state; reserved for Step 9. |
| `reading-help` | Bundled Help catalog/screens, Windows preview instructions/launcher, native/web check-in sources; User Guide 5.2 as offline context. | Local article rendering, related navigation, and large-text layouts covered by widgets; preview/plugin differences source checked. | Physically disconnected Windows/mobile access, browser first-load/reload behavior, and real assistive-technology checks on each platform. |

## Verification boundaries and future updates

- Help contains no new network request or native dependency. A local widget test
  is evidence for Help rendering/navigation, not a disconnected-device test.
- Tests check keyboard traversal and activation, semantic labels/button roles,
  live result announcements, light/dark themes, and narrow layouts. A real
  screen-reader session remains a Step 9 device check.
- Screen labels use app localization. Article/category content is English;
  untranslated UI labels currently fall back to English. Preserve stable IDs
  when implementing translated catalogs.
- When checking a live instruction, record the date, platform/build, entry point,
  observed result, and unresolved issues in the relevant row. Record preview
  checks separately from a normal Windows build.
- Review the native check-in explanation when real mood/notes submission is
  implemented. Do not remove it based only on the web form's submission code.
