# Gmail OAuth Setup Guide

This guide walks backend contributors through configuring Gmail OAuth for the CareConnect backend. Follow it when you
need to run the app locally, rotate credentials, or unblock QA.

---

## 1. Create and Configure the Google Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/).
2. Select your existing project or create a new one dedicated to CareConnect.
3. Enable the **Gmail API**:
    - APIs & Services ➜ Library ➜ search for "Gmail API" ➜ Enable.
4. Configure the OAuth consent screen (APIs & Services ➜ OAuth consent screen):
    - User type: **Internal** (if using a Google Workspace org) or **External**.
    - App name, support email, developer contact: fill in as required.
    - Test users: add every Google account that should exercise the flow in non-production. If you plan to test with a
      personal Gmail account, add that address here; Google blocks consent for accounts not on this list while the app
      is in testing.
    - Save.

## 2. Create OAuth Client Credentials

1. APIs & Services ➜ Credentials ➜ **Create Credentials ➜ OAuth client ID**.
2. Application type: **Web application**.
3. Name the client (e.g., `careconnect-local`).
4. Authorized redirect URIs (exact match, no trailing slash):
   ```
   http://localhost:8080/oauth/google/callback
   ```
5. Save. Download the credentials or copy the **Client ID** and **Client secret**.

## 3. Add Secrets to the Backend

1. In `backend/core/.env`, set:
   ```
   GOOGLE_CLIENT_ID=<client id from console>
   GOOGLE_CLIENT_SECRET=<client secret from console>
   GOOGLE_REDIRECT_URI=http://localhost:8080/oauth/google/callback
   GOOGLE_SCOPE=https://www.googleapis.com/auth/gmail.readonly
   ```
   The redirect/scope entries are optional because defaults exist in `application-dev.properties`, but adding them makes
   overrides explicit.
2. The Gmail scope must remain `https://www.googleapis.com/auth/gmail.readonly`. Broader scopes (send/modify) require
   re-verification with Google and are not supported by the current backend flow.
3. Never commit real secrets. `.env` is git-ignored; keep credentials in your password manager.

## 4. Verify Spring Picks Up the Values

The dev profile now pulls values from the environment:

```
google.oauth.client-id=${GOOGLE_CLIENT_ID}
google.oauth.client-secret=${GOOGLE_CLIENT_SECRET}
google.oauth.redirect-uri=${GOOGLE_REDIRECT_URI:http://localhost:8080/oauth/google/callback}
google.oauth.scope=${GOOGLE_SCOPE:https://www.googleapis.com/auth/gmail.readonly}
```

If you prefer not to use `.env`, export the variables in your shell or IDE run configuration instead.

## 5. Rebuild and Restart the Backend

Whenever you change OAuth config, rebuild so the running instance loads the new properties:

```bash
cd backend/core
./mvnw package -DskipTests -P!assembly-zip
java -jar target/careconnect-backend-0.0.1-SNAPSHOT.jar --spring.profiles.active=dev
```

You can also use `./run-dev.sh`, which sources `.env` automatically.

## 6. Quick Smoke Test

The OAuth start endpoint is patient-scoped. `/oauth/google/start` no longer accepts a raw
`userId`; it requires a short-lived, HMAC-signed `startToken` issued by the authenticated connect-url endpoint.

1. Request a connect URL (JWT required). This authorizes the caller against the patient and returns a
   `/oauth/google/start?startToken=...` URL:
   ```bash
   curl -s "http://localhost:8080/v1/api/email-credentials/gmail/connect-url?returnUrl=http://localhost:3000/usps-test" \
     -H "Authorization: Bearer <jwt>"
   ```
   Response:
   ```json
   { "url": "http://localhost:8080/oauth/google/start?startToken=<signed-token>" }
   ```
2. Follow the returned URL to obtain the Google redirect:
   ```bash
   curl -s -D - "http://localhost:8080/oauth/google/start?startToken=<signed-token>" \
     -o /dev/null | grep -i '^Location:'
   ```
3. Confirm the `Location` header shows:
    - `client_id=<your actual client id>`
    - Encoded `redirect_uri` (`http%3A%2F%2Flocalhost...`)
    - Encoded `scope` (`https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fgmail.readonly`)
4. Paste the URL into a browser to verify the Google consent screen appears. If prompted, approve and ensure the app
   captures the callback.

> Notes:
> - The `startToken` is valid for ~2 minutes and is single-purpose (it is rejected if replayed as the callback `state`).
> - `returnUrl` must resolve to an allowed frontend host (`google.oauth.frontend-url`, `frontend.base-url`, any host in
    `google.oauth.allowed-return-hosts`, or localhost). Unknown hosts are rejected.

## 7. Common Errors

| Error text (browser/Google)                                    | Likely cause                                                                                  | Fix                                                                                            |
|----------------------------------------------------------------|-----------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------|
| `redirect_uri_mismatch`                                        | Redirect URI in the request does not match the authorized list.                               | Update Google Cloud credential entry to include `http://localhost:8080/oauth/google/callback`. |
| `invalid_client`                                               | Placeholder client ID/secret or typo.                                                         | Re-copy credentials into `.env`; restart backend.                                              |
| Loop back to `/oauth/google/start` with 400                    | Values are not URL-encoded.                                                                   | Ensure you are running a build after Feb 2025 (controller encodes each parameter).             |
| `/oauth/google/start` returns an error / `Invalid start token` | Calling `/oauth/google/start` directly without a `startToken`, or the token expired (~2 min). | Fetch a fresh URL from `/v1/api/email-credentials/gmail/connect-url` and follow it promptly.   |
| `returnUrl host is not allowed`                                | The `returnUrl` points to a host not on the allowlist.                                        | Use an allowed frontend origin or add it to `google.oauth.allowed-return-hosts`.               |
| `access_denied` after consent                                  | User cancelled or account not in test users list.                                             | Add the account under OAuth consent screen ➜ Test users.                                      |

## 8. Security Notes

- Treat the client secret like any other credential. Use `.env`, 1Password/Bitwarden, and environment variable injection
  in prod—never commit secrets.
- Rotate the secret immediately if it leaks (Credentials ➜ OAuth client ➜ Reset secret).
- Production deployments should use a different OAuth client entry, with production redirect URIs and scopes reviewed by
  security.

---

**Need help?** Post questions in the `#backend` channel with the exact error message and the results of the curl smoke
test above. Providing both speeds up triage.
