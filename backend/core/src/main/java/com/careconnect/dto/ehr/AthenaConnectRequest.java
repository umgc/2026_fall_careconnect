package com.careconnect.dto.ehr;

/**
 * Body of {@code POST /api/athena/connect}.
 *
 * <p>With 2-legged OAuth athena never asks the patient anything, so this flag is the only record that
 * the patient agreed to import. It must be sent as {@code true}, after the client has shown the
 * consent text; an empty or false body is refused rather than read as agreement.
 *
 * @param consent the patient agreed to import their athenahealth records
 */
public record AthenaConnectRequest(Boolean consent) {
}
