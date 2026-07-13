# Invite Security & Permission Hardening Guide

> Issue #81 — companion documentation for the care-circle invite flow (#53, #59, #75, #69).
> Audience: backend reviewers, security reviewers, and milestone sign-off.

This guide documents the safeguards built into the invite-token subsystem and
maps each invite API action to the roles and permissions that gate it.

## 1. Permission Map — Roles x Actions

| Action | Endpoint | Auth | Gate | Allowed roles |
|--------|----------|------|------|---------------|
| Create | POST /v1/api/care-circle/{linkId}/invite | Yes | @RequirePermission(CREATE_TASKS) | ADMIN, CAREGIVER, PATIENT (FAMILY_MEMBER rejected 403) |
| Preview | GET /v1/api/invite/{token} | No (public) | none | anyone holding a token |
| Accept | POST /v1/api/invite/{token}/accept | Yes | authenticated | any authed user; email-scoped invites require email match |
| Revoke | DELETE /v1/api/care-circle/{linkId}/invite/{tokenId} | Yes | @RequirePermission(CREATE_TASKS) | ADMIN, CAREGIVER, PATIENT (cross-link rejected 403) |

Create/Revoke reuse CREATE_TASKS (same gate as existing link creation). Preview
is public because an invitee may have no account yet, but is hardened by a
non-enumerating response (section 4). Accept requires auth to bind a userId.

## 2. Token Lifecycle, Expiration & Revocation

States: PENDING --accept--> ACCEPTED; PENDING --TTL/sweep--> EXPIRED;
PENDING --revoke--> REVOKED. All terminal. A token is usable only while
status == PENDING AND now < expires_at.

Expiration: default TTL 72h, capped at 168h (7 days). A scheduled sweep
(default 15 min) marks overdue PENDING tokens EXPIRED. Lazy expiry: redeem/accept
re-checks the clock so a token lapsed between sweeps is treated as expired.

One-time use: first accept flips to ACCEPTED; further attempts return 409.
One active token per link: creating a second invite while a PENDING one exists
returns 409 — revoke first to rotate.

Revocation is idempotent (revoking a terminal token is a no-op) and scoped
(tokenId must belong to the linkId in the path, else 403). Every revoke is audited.

## 3. Abuse Cases & Mitigations

| Threat | Mitigation |
|--------|------------|
| Brute-force / guessing | 256-bit SecureRandom tokens; lookup prefix only narrows to a row, full token must pass a one-way hash check. |
| Token theft from DB dump | Raw tokens never stored; only a non-secret prefix + one-way BCrypt hash (TokenHashService). |
| Replay | Single-use; post-accept status is ACCEPTED, replay returns 409. Revoked/expired never usable. |
| Expired scan | TTL + sweep + lazy expiry surface EXPIRED and offer REQUEST_NEW. |
| Enumeration | Preview returns the same 200 shape for all token states; only the status field differs, and only after the hash verifies. Unknown and hash-mismatch both collapse to INVALID with null context. |
| Cross-circle redemption | Link resolved from the token itself, not a client path var, so a token only binds its own link. |
| Email hijack | If invited_email is set, accept requires the authed user's email to match (case-insensitive) or 403. |
| Privilege misuse | FAMILY_MEMBER rejected at the controller for create and revoke. |

## 4. Non-Enumerating Responses (issues #59 + #81)

Criterion: API responses do not expose whether a user or care circle exists.

Note: the non-enumerating preview body is delivered by the #59 change to
previewInvite. Until #59 merges, the #53 preview returns clear per-state errors
(404/410). The gating, lifecycle, hashing, and audit safeguards (sections 1-3, 5)
are live as of #53.

The public preview (GET /v1/api/invite/{token}) always returns HTTP 200 with a
stable body: valid (boolean); status (VALID|EXPIRED|REVOKED|ACCEPTED|INVALID);
nextAction (ACCEPT|SIGN_IN|REQUEST_NEW|NONE); and linkId, linkType, inviterName,
patientName, inviteReason, invitedEmail, expiresAt. For any non-valid token all
context fields are null. Unknown and hash-mismatch tokens are indistinguishable
(both INVALID), so the endpoint is not a "does this token exist?" oracle.

The authenticated accept endpoint does return distinct errors (409 used, 410
expired/revoked, 403 email mismatch) — safe because the caller has proven they
hold the real token and are authenticated.

## 5. Auditing

Every lifecycle event writes an immutable row to invite_token_audit:
CREATED (creator + IP), VIEWED (anonymous + IP), ACCEPTED (redeemer + IP),
REVOKED (revoker + IP + reason), EXPIRED (system). Audit writes never break the
business flow. VIEWED is written in a REQUIRES_NEW transaction so a read-only
preview still records access.

## 6. Reviewer Checklist

- [ ] Create/revoke gated by CREATE_TASKS and reject FAMILY_MEMBER.
- [ ] Preview is public and non-enumerating (identical shape, null context).
- [ ] Accept enforces single-use and optional email match.
- [ ] Raw tokens never persisted; only prefix + BCrypt hash.
- [ ] TTL default 72h, capped 7d; sweep + lazy expiry active.
- [ ] One active token per link enforced.
- [ ] Cross-link revoke rejected.
- [ ] All five lifecycle events audited with actor + IP.

## 7. Configuration Reference

| Property | Default | Purpose |
|----------|---------|---------|
| careconnect.invite.base-url | https://app.careconnect.io/invite | Share/QR URL prefix (#69) |
| careconnect.invite.default-ttl-hours | 72 | TTL when request omits ttlHours |
| careconnect.invite.max-ttl-hours | 168 | Hard cap on requested TTL |
| careconnect.invite.sweep-interval-ms | 900000 | Expiry sweep cadence (15 min) |

All overridable via environment variables.
