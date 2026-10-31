# Approved glossary search aliases

This records the approved alias map for all 75 starting glossary terms.
The implemented catalog lives in
`frontend/lib/features/help/data/bundled_glossary_content.dart`. Edit that Dart
catalog for future content changes; this document records the original review.
Aliases that match the display term or another alias after normalization are
removed automatically. These phrases do not establish feature availability
on every platform.

Aliases include alternative names, abbreviations, plural forms, and common
phrases readers might search for. Some are examples or task phrases rather
than exact dictionary synonyms. They help readers find the relevant definition;
the definition and linked article must explain the actual app behavior.

## Reader accessibility

Design for readers who may struggle with reading, memory, attention, or
unfamiliar language. Put everyday phrases and short questions first in each
alias list; retain technical variants as secondary search matches.

- Write the first definition sentence in simple words, usually 8-15 words.
  Add one short example when it helps. Explain unfamiliar words immediately.
- Aim for roughly a fourth- to sixth-grade reading level, with human review.
  A reading-level score alone does not prove that an explanation is clear.
- Use one idea per sentence. Prefer direct wording such as "The app has no
  internet connection" to "Network connectivity is unavailable."
- Present the everyday meaning alongside a technical label when useful:
  "Save while offline (Offline Persistence)" or "Read aloud (Text-to-speech)."
- Support the words people type when confused, including "What is EVV?",
  "Who can see my account?", and "Why can't I use the camera?" Exact question
  aliases are starting examples; eventual search should handle filler words
  and punctuation without losing meaningful words such as "no" or "not."
- Use visible text labels with icons. Definitions should not require hover,
  recognition of an icon, or knowledge of an abbreviation.
- Keep the interface calm and predictable, with clear headings and generous
  spacing. Check understanding with representative readers when possible.
- Medical terms still need accurate wording. Avoid defining allergy as
  intolerance, or treating dose and dosage as interchangeable just to simplify.

Example first sentences:

| Term | Proposed plain-language opening |
| --- | --- |
| Questionnaire | A list of questions for you to answer. |
| Offline | Your device is not connected to the internet. |
| Permissions | Your choice to let the app use things like your camera. |
| Cache | Temporary information the app keeps to help pages load faster. |
| Text-to-speech | A tool that reads written words aloud. |

Check these examples against the final definitions and app behavior before
publishing. Question aliases help find an explanation; they do not replace
troubleshooting instructions in related articles.

## People and accounts

| Glossary term | Search aliases |
| --- | --- |
| Patient | person getting care; what is a patient; patients; patient user; care recipient; person receiving care |
| Caregiver | person helping with care; who is my caregiver; caregivers; care giver; carer; caregiving user; person providing care |
| Administrator | person who manages the app; what is an admin; admin; admins; system administrator; app administrator; administrator user |
| User role | what I can do in the app; what is my role; role; roles; account role; user type; account type; access role |
| Account | my account; what is an account; accounts; user account; app account; CareConnect account |
| Profile | my personal details; what is my profile; profiles; my profile; user profile; account profile; profile details; personal details |
| Sign in | get into my account; how do I log in; login; log in; log on; logon; signing in; access my account |
| Sign out | leave my account; how do I log out; logout; log out; log off; logoff; signing out |

## Access and privacy

| Glossary term | Search aliases |
| --- | --- |
| Password | my password; what is a password; passwords; account password; login password; sign-in password |
| Password reset link | forgot my password; how do I reset my password; reset link; password recovery link; email reset link; password reset email; reset password email; forgot password link |
| Account access | who can see my account; who can use my account; access to an account; account authorization; account access rights; access rights; who can access my account |
| Permissions | let the app use my device; what does allow access mean; permission; app permissions; device permissions; browser permissions; permission settings; allow access |
| Privacy | who can see my information; is my information private; data privacy; personal information privacy; privacy settings; information privacy; privacy of my information |
| Session | being signed in; what is a session; sessions; login session; sign-in session; signed-in session; active session |
| Linked account | accounts connected together; what is a linked account; linked accounts; connected account; account link; account linking; caregiver account link; patient account link |

## Check-ins and health information

| Glossary term | Search aliases |
| --- | --- |
| Daily Check-In | my daily update; what is a daily check in; daily check in; daily checkin; daily update; daily health update; daily mood check-in |
| Virtual Check-In | check in using the app; what is a virtual check in; virtual check in; virtual checkin; remote check-in; remote care check-in; online check-in |
| Questionnaire | questions to answer; what is a questionnaire; questionnaires; questions; question form; question set; questionnaire form; survey |
| Assigned questionnaire | questions I was given; what are my assigned questions; assigned questionnaires; assigned questions; assigned form; questionnaire assignment; assigned survey; questions from my caregiver |
| Mood | how I feel emotionally; what is mood; moods; feelings; emotional state; mood rating |
| Symptom | how my body feels; what is a symptom; symptoms; health symptom; reported symptom; symptom entry; symptom record |
| Allergy | my allergies; what is an allergy; allergies; known allergy; reported allergy; allergy entry; allergy record |
| Care notes | notes about my care; what are care notes; care note; patient notes; health notes; notes about care; care observations |

## Medications

| Glossary term | Search aliases |
| --- | --- |
| Medication | my medicine; what does medication mean; medications; medicine; medicines; med; meds; medication name |
| Medication Tracker | my medicine list; where are my medicines; medicine tracker; med tracker; meds tracker; medication list; medicine list; my medications |
| Dose | one dose of medicine; what is a dose; doses; medication dose; medicine dose; single dose; one dose |
| Dosage | medicine instructions; what does dosage mean; dosages; medication dosage; medicine dosage; dosing instructions; dosage instructions; prescribed amount |
| Schedule | when things happen; what is a schedule; schedules; timetable; scheduled times; timing; care schedule; medication schedule |
| Medication reminder | medicine reminder; remind me about my medicine; medication reminders; med reminder; pill reminder; dose reminder; medication alert |
| Mark Taken | I took my medicine; how do I mark medicine as taken; mark as taken; mark dose taken; record a taken dose; log a taken dose; took my medicine; medicine taken |

## Visits and care coordination

| Glossary term | Search aliases |
| --- | --- |
| Appointment | my appointment; what is an appointment; appointments; care appointment; booked appointment; scheduled appointment; appointment booking |
| Scheduled visit | my next care visit; what is a scheduled visit; scheduled visits; planned visit; scheduled care visit; upcoming visit; planned care visit |
| EVV | checking a care visit; what is EVV; electronic visit verification; visit verification; electronic care visit verification; EVV visit; EVV appointment |
| Calendar Assistant | help with my calendar; what is the calendar assistant; calendar helper; calendar tool; appointment calendar; care calendar; calendar assistance |
| Patient List | list of people receiving care; where is my patient list; list of patients; patients list; patient directory; my patients; patient roster |
| Patient Report | a report about a patient; what is a patient report; patient reports; report about a patient; patient summary; patient information report; care report |
| Shift | time someone works; what is a shift; shifts; work shift; caregiver shift; assigned shift; shift assignment; work period |

## Messages and calls

| Glossary term | Search aliases |
| --- | --- |
| Conversation | my chat; what is a conversation; conversations; chat; chat thread; message thread; messaging thread; chat history |
| Contacts | people I can contact; where are my contacts; contact; contact list; contact directory; people list; saved contacts |
| Message | send someone a message; what is a message; messages; chat message; written message; message text; send a message |
| Attachment | a file added to a message; what is an attachment; attachments; attached file; file attachment; message attachment; attached document; attached image |
| Audio call | talk without video; what is an audio call; audio calls; voice call; voice calling; audio calling; call without video |
| Video call | talk and see each other; what is a video call; video calls; video calling; video chat; video conversation; call with video |
| Retry | try again; what does retry mean; attempt again; retry action; retry sending; resend; send again |

## Connections and stored information

| Glossary term | Search aliases |
| --- | --- |
| Online | connected to the internet; what does online mean; internet connected; online connection; internet available; network connected |
| Offline | no internet; why am I offline; disconnected; without internet; no network connection; connection lost; internet unavailable |
| Offline Persistence | save without internet; what is offline persistence; offline storage; offline saving; save offline; local persistence; local saving; offline saving and replay |
| Synchronization | send saved changes; what does sync mean; sync; syncing; synchronize; synchronise; synchronizing; synchronising; data sync |
| Pending update | a change waiting to be sent; what does pending mean; pending updates; unsent update; queued change; unsynced change; waiting to sync; awaiting synchronization |
| Refresh | load the page again; what does refresh mean; refresh data; reload; reload data; load again; update the view; refresh the screen |
| Cache | temporary app information; what is cache; app cache; cached data; temporary app data; cached files; temporary stored information |

## Devices and accessibility tools

| Glossary term | Search aliases |
| --- | --- |
| Wearable | a device I wear; what is a wearable; wearables; wearable device; fitness tracker; activity tracker; smartwatch; smart watch |
| Smart device | a connected device; what is a smart device; smart devices; connected device; connected devices; smart home device; smart appliance |
| Pairing | connect my device; what does pairing mean; pair a device; device pairing; pair devices; link a device; connect a device; device connection |
| Location access | let the app use my location; why does the app ask for my location; location permission; location permissions; allow location; access my location; location settings |
| GPS | finding my location; what is GPS; global positioning system; GPS location; GPS positioning; satellite positioning |
| Camera access | let the app use my camera; why can't I use the camera; camera permission; camera permissions; allow camera; access the camera; camera settings |
| Microphone access | let the app use my microphone; why can't I use the microphone; microphone permission; microphone permissions; mic access; mic permission; allow microphone; microphone settings |
| Text-to-speech | read words aloud; can the app read to me; text to speech; TTS; read aloud; reading aloud; spoken text; speech output |

## App tools

| Glossary term | Search aliases |
| --- | --- |
| AI Assistant | AI helper; what is the AI assistant; artificial intelligence assistant; digital assistant; AI chatbot; AI chat assistant |
| Notetaker Assistant | help taking notes; what is the notetaker assistant; note taker assistant; note-taking assistant; notetaking assistant; notetaker; notes assistant; note-taking helper |
| Daily Brief | a summary of my day; what is the daily brief; daily briefing; daily summary; today's brief; todays brief; day summary; morning brief |
| File Management | my files and documents; where are my files; file manager; manage files; files; documents; document management; file storage |
| Invoice Assistant | help with bills; what is the invoice assistant; invoice helper; invoice tool; billing assistant; billing helper; invoicing; invoices |
| Social Feed | posts and updates; what is the social feed; activity feed; community feed; social updates; social activity; feed |
| Gamification | points and rewards; what does gamification mean; reward system; points system; points and badges; progress rewards; game elements |
| Achievement | something I earned; what is an achievement; achievements; badge; badges; milestone; milestones; earned badge |

## Appearance and navigation

| Glossary term | Search aliases |
| --- | --- |
| Light mode | light screen colors; what is light mode; light theme; light appearance; day mode; bright theme |
| Dark mode | dark screen colors; what is dark mode; dark theme; dark appearance; night mode; darker theme |
| Text size | make words bigger; how do I change text size; font size; larger text; bigger text; text scaling; text zoom; smaller text |
| Screen reader | a tool that speaks what is on screen; what is a screen reader; screen readers; screen-reading software; screen reading; screen-reading tool; spoken interface |
| Keyboard navigation | use the keyboard to move around; can I use the app without a mouse; keyboard controls; keyboard access; navigate with a keyboard; Tab navigation; Tab order; keyboard shortcuts |
| Browse Topics | find help by subject; what does browse topics mean; topics; Help topics; browse Help; Help categories; topic list; topic browsing |
| Related articles | more help about this subject; what are related articles; related guides; related Help; more guides; suggested articles; see also; related reading |
| Back to top | go to the start of this article; how do I get back to the top; return to top; scroll to top; jump to top; go to top; article beginning; beginning of the article |

## Search behavior and maintenance rules

1. Normalize case, surrounding whitespace, repeated spaces, and common
   punctuation variants. Case-only variants should not require stored aliases.
   Preserve meaningful word boundaries: `login` and `log in` should both match.
2. Search the primary term, aliases, and definition. Give exact primary-term
   matches priority over alias or definition matches. For example, searching
   `Patient` should place Patient before Patient List or Patient Report.
3. Keep aliases with their glossary entry. Article references use permanent
   term IDs, so alias changes need no edits to individual articles.
4. Shared phrases may return multiple entries. Do not reject cross-entry
   overlap automatically; rank the more specific match first where possible.
5. Remove duplicate aliases within an entry after normalization, including
   aliases that normalize to the display term itself. Several readable forms
   above deliberately show how people may type a hyphenated term; the eventual
   normalization rules may make storing some of them unnecessary.
6. Do not generate every imaginable misspelling. Add typo tolerance through
   search behavior later if needed, rather than maintaining hundreds of errors.
7. Verify feature names and task phrases against the actual app before
   publication. A search alias does not establish device compatibility,
   successful saving, message delivery, or a supported workflow.

## Concepts that must remain distinct

- Patient, Caregiver, and Administrator are separate roles. Family member,
  clinician, nurse, and doctor should not silently become aliases for a role.
- Symptoms, allergies, intolerances, and side effects are not interchangeable.
- Dose and dosage should have their own definitions; do not map the bare word
  `dose` to Dosage as an alias.
- Daily Check-In and Virtual Check-In may describe different entry points or
  behavior. Do not make their full display names aliases for one another.
- Privacy is broader than a security setting. Passwords, PINs, passcodes, and
  one-time verification codes are not automatically interchangeable.
- Offline Persistence and Cache are different concepts. Synchronization,
  refreshing a view, and a pending update also need separate explanations.
- App messages and SMS are different mechanisms. Do not use bare `SMS` as an
  alias for Message without a dedicated explanation.
- Text-to-speech and screen readers are different accessibility tools.
  Product-specific names such as VoiceOver or TalkBack can be added when the
  glossary explains those tools accurately and the supported-device review
  has been completed.
- Audio calls and video calls should not be merged with appointments or
  questionnaires under broad aliases such as `virtual visit`.

Examples such as smartwatch, badge, and attached image are discovery aliases.
Their definitions must explain the category without promising that every
example, device, or file format is supported by CareConnect.
