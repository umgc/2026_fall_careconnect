# SWEN 670 work log — Patient/Appointment mapping and TDD addendum

Start (UTC): 2026-09-17T06:02:55.794000+00:00
End (UTC): 2026-09-17T06:19:32.315930+00:00
Elapsed: 996.5 seconds (16.61 minutes).

Work performed: Read current project/template instructions and the prior Milestone 2 TDD and ST plan. Inspected CareConnect Patient, address, gender, task and schedule models. Reviewed the shared EHR branch candidate at 75b5f755 and Team C base snapshots. Compared the field map with HL7 FHIR R4 and Oracle Health docs. Read synthetic Patient and Appointment resources from the public sandbox. Confirmed that date-only appointment search failed and a bounded UTC-time search passed. Wrote a 22-rule field map, 10 proposed tests, four proposed TDD decisions, schema gaps, WBS links and owner next steps. No repository source changes, commits, pushes, merges, team messages or secure sign-in.

Files created:
- TeamC_Patient_Appointment_Mapping_2026-09-17.docx — SHA-256 ec6aa74b0edda505298308c9a5c45cb0e8cf4ef4381ccff76e46913345a7a5bc
- TeamC_TDD_Patient_Appointment_Addendum_2026-09-17.docx — SHA-256 6b2103bc94732644235faa5ebc3601e7a67530ec047fb59e9f98a017604909cb

Validation: Mapping has 10 pages; addendum has 9. Rendered and visually reviewed all pages, including revised pages. Checked table rows, headings, contents page numbers and source hyperlinks. Preserved template sections/styles/media/footers and existing relationships; appended source links. Checked DOCX ZIP integrity and exact-copy hashes after saving. No CareConnect unit, database, CI or secure-flow tests were run. Drafts await team review. TOC page caches match the rendered files; Word field refresh is enabled on open.

Source evidence (public synthetic sandbox; no token):
- {"url": "https://fhir-open.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d/Appointment/4822366", "status": 200, "at": "2026-09-17T06:07:49.905056+00:00", "sha256": "3f7bb9290509a6646ab5edccb295a52673ffa5cf036329dcbf76f2e11ed1c800", "type": "Appointment", "id": "4822366"}
- {"url": "https://fhir-open.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d/Patient/12724066", "status": 200, "at": "2026-09-17T06:07:51.162649+00:00", "sha256": "d8d6a14e7c302481d2a5ad889e97d27f208ba233c6ca7e1d40284c654731b2b2", "type": "Patient", "id": "12724066"}
- {"url": "https://fhir-open.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d/Appointment?patient=12724066&date=ge2020-01-23&date=lt2020-01-24&_count=10", "error": "HTTP Error 400: Bad Request"}
- {"url": "https://fhir-open.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d/Appointment?patient=12724066&date=ge2020-01-23&date=lt2020-01-24&_count=10", "status": 400, "at": "2026-09-17T06:08:27.350082+00:00", "sha256": "5eb52c6fd727f78f337a4a09487740f3a6de56d661e7283103aaf2e29b5bccda", "type": "OperationOutcome", "entry_count": 0}
- {"url": "https://fhir-open.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d/Appointment?patient=12724066&date=ge2020-01-23T00%3A00%3A00Z&date=lt2020-01-24T00%3A00%3A00Z&_count=10", "status": 200, "at": "2026-09-17T06:08:27.926211+00:00", "sha256": "27931cbefd2768f36e0c2d1e914874e5f75a127c4c88d187ae0f915c15ff9998", "type": "Bundle", "entry_count": 1}

Project instruction path used: /Volumes/TerenceB/SWEN670/sandbox/CODEX_TEMPLATE3/Prompts folder/Prompt.md. The exact output destination follows the user project instruction. Existing input, repository and deliverable files were preserved.
