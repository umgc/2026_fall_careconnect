package com.careconnect.dto.ehr;

import com.careconnect.service.ehr.athena.AthenaSyncResult;
import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Connection state for the athenahealth tile, from {@code GET /api/athena/status} and
 * {@code POST /api/athena/connect}.
 *
 * <p>{@code status} uses the shared EHR tile values. athena has no per-user login to expire, so it
 * is never {@code NEEDS_RECONNECT}. {@code reason} explains a {@code NOT_CONNECTED} status as a
 * code for the client to localize, never as display text.
 *
 * @param connected whether athena records can be synced and read
 * @param status    {@value #CONNECTED} or {@value #NOT_CONNECTED}
 * @param reason    why not connected; absent when connected
 * @param sync      the first sync, on a connect that linked the chart; absent otherwise
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record AthenaConnectionResponse(boolean connected, String status, String reason, AthenaSyncResult sync) {

    public static final String CONNECTED = "CONNECTED";
    public static final String NOT_CONNECTED = "NOT_CONNECTED";

    public static AthenaConnectionResponse connected(final AthenaSyncResult sync) {
        return new AthenaConnectionResponse(true, CONNECTED, null, sync);
    }

    public static AthenaConnectionResponse notConnected(final String reason) {
        return new AthenaConnectionResponse(false, NOT_CONNECTED, reason, null);
    }
}
