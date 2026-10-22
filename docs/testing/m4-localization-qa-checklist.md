# Milestone 4 Team C Localization QA Checklist

**Owner:** Team C QA Lead (Tiffany Obi)  
**Status:** Working execution template; no row is passing until evidence is recorded  
**Required workflows:** Social Feed, Gamification, USPS Mail Digest, Caregiver Shift Scheduling, and HHAExchange submission

## 1. Execution information

| Field | Value |
|---|---|
| Release-candidate commit | TBD |
| Build/environment | TBD |
| Flutter version | TBD |
| Tested platforms/devices/browsers | TBD |
| Supported locale list | TBD |
| English template/catalog checksum | TBD |
| Tester(s) | TBD |
| Execution date(s) | TBD |

Use `Not Run`, `Pass`, `Fail`, `Blocked`, or `Not Applicable`. Each Pass or Fail must have an evidence or defect reference.

## 2. Catalog and generation checks

| Check ID | Requirement | Check | Owner | Result | Evidence/defect |
|---|---|---|---|---|---|
| M4-L10N-CAT-001 | M4-REQ-10 | Every ARB file parses as valid JSON/ARB. | Frontend + QA | Not Run | TBD |
| M4-L10N-CAT-002 | M4-REQ-10 | Approved locale catalogs contain the required English keys with no unexplained extras. | Frontend + QA | Not Run | TBD |
| M4-L10N-CAT-003 | M4-REQ-10 | Placeholder names, types and metadata match the English template. | Frontend + QA | Not Run | TBD |
| M4-L10N-CAT-004 | M4-REQ-10 | `flutter gen-l10n` succeeds from a clean checkout. | Frontend | Not Run | TBD |
| M4-L10N-CAT-005 | M4-REQ-11 | Changed workflows contain no unintended raw localization keys or user-facing English literals. | Frontend + QA review | Not Run | TBD |
| M4-L10N-CAT-006 | M4-REQ-13 | Sensitive medical, medication, safety, privacy and legal strings have recorded qualified-review status. | QA + qualified reviewer | Not Run | TBD |

## 3. Workflow and locale execution matrix

Add rows for every tested locale/device combination. English and Spanish manual checks are required. At least one approved RTL locale must cover representative patient and caregiver journeys.

| Workflow | Locale | Device/viewport | Scenario IDs | Functional text/states | Overflow/text scale | Accessibility/semantics | RTL/focus/icons | Reviewer | Result | Evidence/defect |
|---|---|---|---|---|---|---|---|---|---|---|
| Social Feed | English | TBD | M4-SC-L10N-002, 005 | Not Run | Not Run | Not Run | N/A | TBD | Not Run | TBD |
| Social Feed | Spanish | TBD | M4-SC-L10N-002-005 | Not Run | Not Run | Not Run | N/A | TBD | Not Run | TBD |
| Social Feed | Arabic or Urdu | TBD | M4-SC-L10N-005-006 | Not Run | Not Run | Not Run | Not Run | TBD | Not Run | TBD |
| Gamification | English | TBD | M4-SC-L10N-002, 004-005 | Not Run | Not Run | Not Run | N/A | TBD | Not Run | TBD |
| Gamification | Spanish | TBD | M4-SC-L10N-002, 004-005 | Not Run | Not Run | Not Run | N/A | TBD | Not Run | TBD |
| Gamification | Arabic or Urdu | TBD | M4-SC-L10N-005-006 | Not Run | Not Run | Not Run | Not Run | TBD | Not Run | TBD |
| USPS Mail Digest | English | TBD | M4-SC-L10N-002, 004-005 | Not Run | Not Run | Not Run | N/A | TBD | Not Run | TBD |
| USPS Mail Digest | Spanish | TBD | M4-SC-L10N-002, 004-005 | Not Run | Not Run | Not Run | N/A | TBD | Not Run | TBD |
| USPS Mail Digest | Arabic or Urdu | TBD | M4-SC-L10N-005-006 | Not Run | Not Run | Not Run | Not Run | TBD | Not Run | TBD |
| Shift Scheduling | English | TBD | M4-SC-L10N-002, 004-005 | Not Run | Not Run | Not Run | N/A | TBD | Not Run | TBD |
| Shift Scheduling | Spanish | TBD | M4-SC-L10N-002, 004-005 | Not Run | Not Run | Not Run | N/A | TBD | Not Run | TBD |
| Shift Scheduling | Arabic or Urdu | TBD | M4-SC-L10N-005-006 | Not Run | Not Run | Not Run | Not Run | TBD | Not Run | TBD |
| HHAExchange submission | English | TBD | M4-SC-L10N-002, 005 | Not Run | Not Run | Not Run | N/A | TBD | Not Run | TBD |
| HHAExchange submission | Spanish | TBD | M4-SC-L10N-002-005 | Not Run | Not Run | Not Run | N/A | TBD | Not Run | TBD |
| HHAExchange submission | Arabic or Urdu | TBD | M4-SC-L10N-005-006 | Not Run | Not Run | Not Run | Not Run | TBD | Not Run | TBD |

## 4. Workflow-specific checks

| Workflow | Minimum states and content to verify | Result | Evidence/defect |
|---|---|---|---|
| Social Feed | Navigation, headings, feed loading/empty/error, create post, comments, search, requests, messages/chat, validation, permissions, tooltips and semantics. | Not Run | TBD |
| Gamification | Dashboard, points, levels, achievements, leaderboard, unnamed/empty/error states, parameters/plurals, notifications and semantics. | Not Run | TBD |
| USPS Mail Digest | Connect/disconnect, digest loading/cache/empty/error/expired connection, dates/counts, details, packages, read aloud, images, links and semantics. | Not Run | TBD |
| Shift Scheduling | Day/week/month views, create/edit, recurrence, validation, conflicts, save/error, locale-aware dates/times, first-day behavior and semantics. | Not Run | TBD |
| HHAExchange submission | Eligibility, selection, payload/download warning, progress, no eligible visits, approved/error states, success/failure and semantics. | Not Run | TBD |

## 5. Locale behavior and accessibility checks

| Check | Expected result | Result | Evidence/defect |
|---|---|---|---|
| Locale selection and persistence | Selected supported locale survives the approved restart/session boundary. | Not Run | TBD |
| Unsupported/stale locale | Application follows the approved fallback without crash or raw keys. | Not Run | TBD |
| Parameters and plurals | Values are substituted in the correct order and plural category. | Not Run | TBD |
| Date/time/number formatting | Locale-sensitive values are correct and consistent with product rules. | Not Run | TBD |
| Text scaling and narrow viewport | Content remains readable; controls remain visible/reachable. | Not Run | TBD |
| Screen-reader labels | Controls, errors, status changes and images have meaningful localized semantics. | Not Run | TBD |
| Keyboard/focus order | Focus follows meaningful reading/task order with visible focus. | Not Run | TBD |
| RTL direction and reading order | Layout direction, alignment and content order are correct. | Not Run | TBD |
| Directional icons | Back/forward/chevrons mirror where meaning is directional; non-directional icons do not. | Not Run | TBD |
| Mixed-direction content | IDs, dates, numbers and source values remain readable in RTL layouts. | Not Run | TBD |

## 6. Qualified translation review record

| Locale | Reviewer/name or role | Qualified scope | Sensitive content reviewed | Date | Disposition | Evidence/open issue |
|---|---|---|---|---|---|---|
| English | TBD | Source copy/product review | Medical, safety, privacy, legal | TBD | Not Run | TBD |
| Spanish | TBD | TBD | Medical, safety, privacy, legal | TBD | Not Run | TBD |
| Arabic or Urdu | TBD | TBD | Medical, safety, privacy, legal | TBD | Not Run | TBD |

## 7. Completion rule

Localization sign-off requires approved catalog parity and generation, passing critical workflow checks, representative accessibility/RTL evidence, and documented qualified review for sensitive copy. Missing qualified review is a blocker, not an automatic QA translation approval.
