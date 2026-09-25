# Professor Q&A: SWEN 670 progress since Milestone 1
Prepared September 19, 2026. Based on the final four-slide deck and saved September 17 test evidence.

## 1. What was tested?
I tested the part that checks and prepares patient and appointment data for CareConnect. The 57 cases checked valid data and bad inputs. They did not test the full app or a secure hospital connection.

Examples:
- Patient match: reject a record tied to the wrong patient, even if another entry matches.
- Dates and times: reject bad dates, handle time zones, and accept a valid leap day.
- Visit status: keep a cancelled visit cancelled and reject a booked visit without required times.
- Names and birth dates: choose a current name and preserve whether a birth date gives a year, month, or full date.
- Privacy: keep patient values out of error messages and the tool's text summaries.
- Bad input: reject missing patient links, unsafe source addresses, and oversized or deeply nested data.

## 2. How did you test it?
I used automated unit tests. Each test supplies sample data, calls the tool, and compares the result with the expected result. Some tests expect rejection. The saved Java test report shows 57 cases, zero failures, zero errors, and none skipped. Some cases use the same test with different inputs.

## 3. Can you give one simple example?
A cancelled appointment can still list a person who accepted the visit. I tested that the tool keeps the appointment cancelled. I also tested that an appointment for a different patient gets rejected.

## 4. Did you use real patient records?
The automated tests used made-up data. I also checked sample records in Cerner's public test site during the design work. That was separate from the 57 tests and did not prove secure access to live patient records.

## 5. What were the 102 issues you fixed?
They were findings from an automated code checker. They included naming, repeated values, and how the code handles decisions and variables. They were not 102 confirmed software bugs or security flaws. After the fixes, the same rule sets reported zero findings for this new component.

## 6. What did you contribute beyond coding?
I prepared design drafts for Teams A–E and expanded Team C's design and test planning. I wrote rules for patient and appointment data. I also reviewed Team C's progress and language-support gaps, gathered shared-folder links, and checked an upload-access problem. The design drafts still needed team review.

## 7. Why does this work matter?
It gives the team a tested starting point for checking hospital data before adding more features. The patient checks help guard against mixing records. The design and test plans give reviewers clear rules to check. I have not measured time savings or patient outcomes.

## 8. Is the Cerner connection finished?
No. The data tool and its local tests are done. At the slide update, I had submitted the code for team review. Secure sign-in, saving data, and testing the full connection still needed work. Passing these tests does not mean the whole system is ready.

## 9. What is your role in testing and approval?
I provide design input and tests for my component. QA and the Test Lead own the wider test plan and test sign-off. An independent reviewer needs to review my work. My own passing tests do not replace that review.

## 10. What would you do next?
I would work through review feedback, agree on the remaining data rules, and help test the secure connection in the approved test environment. Then the team can check the full path from sign-in to the correct patient data.

## If asked about AI assistance
I used Codex to help draft documents, write code, and run checks. I should be clear about that support and explain the work I understand. The saved results show what was checked; they do not replace my responsibility to learn the code or the team's review.

## Evidence to have ready
- Final deck: Terence_Boyce_SWEN670_Progress_Since_M1_Ready.pptx
- Test source: backend/core/src/test/java/com/careconnect/service/cerner/CernerResourceMapperTest.java
- Saved Maven report: backend/core/target/surefire-reports/TEST-com.careconnect.service.cerner.CernerResourceMapperTest.xml
- Work log: Cerner_PR148_PMD_Fix_Work_Log_2026-09-17.md
- PR: https://github.com/umgc/2026_fall_careconnect/pull/148

These answers describe the evidence behind the slides, not a fresh test run or a new check of PR status.
