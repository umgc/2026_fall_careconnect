# Digital Assessment Schema (Ticket #83)

The question catalog now supports versioned form templates and section metadata so assessments can evolve without breaking historical check-ins.

## Schema fields

`questions` now includes:
- `form_key` (string): stable template identifier (example: `virtual-checkin`, `comprehensive-assessment`)
- `form_version` (int): increment when you publish a new template revision
- `section_key` (string): logical group inside the form
- `field_key` (string): stable machine key for analytics and downstream mapping
- `score_weight` (decimal, optional): contribution weight for scoring models

`check_in_questions` snapshots now include matching `*_snapshot` metadata fields, so each check-in preserves the exact form definition used at creation time.

## Querying templates via existing API

Use the existing endpoint with optional filters:

`GET /api/questions?active=true&formKey=comprehensive-assessment&formVersion=1`

If `formKey`/`formVersion` are omitted, the endpoint returns all forms (still ordered by form + section + ordinal).

## Adding a new template safely

1. Insert new `questions` rows with a **new `form_version`** (or new `form_key`).
2. Keep existing rows active until no clients depend on them.
3. Use stable `field_key` values so analytics and integrations remain durable across wording updates.
4. Create check-ins from one form/version at a time; mixed form versions in one check-in are rejected.
