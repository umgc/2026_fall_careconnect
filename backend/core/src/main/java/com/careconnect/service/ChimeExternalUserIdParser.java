package com.careconnect.service;

/** Parses legacy {@code ROLE_…_userId} Chime externalUserIds and detects pipeline-internal ids.

 * <p>Production attendees use opaque UUIDs from {@code ChimeService#toOpaqueChimeExternalUserId};
 * those must be resolved via {@code call_participants.chime_external_user_id}, not this parser.
 */
final class ChimeExternalUserIdParser {

    private ChimeExternalUserIdParser() {}

    static boolean isPipelineInternal(final String externalUserId) {
        return externalUserId != null && externalUserId.startsWith("aws:");
    }

    /** True when the id looks like a UUID (opaque attendee id), not {@code ROLE_…_userId}. */
    static boolean isOpaqueExternalUserId(final String externalUserId) {
        if (externalUserId == null || externalUserId.isBlank() || isPipelineInternal(externalUserId)) {
            return false;
        }
        // UUID form: 8-4-4-4-12 hex with hyphens (optionally truncated to Chime max length).
        final String trimmed = externalUserId.trim();
        if (trimmed.length() < 32) {
            return false;
        }
        int hyphens = 0;
        for (int i = 0; i < trimmed.length(); i++) {
            final char c = trimmed.charAt(i);
            if (c == '-') {
                hyphens++;
            } else if (Character.digit(c, 16) < 0) {
                return false;
            }
        }
        return hyphens >= 4 || trimmed.length() == 32;
    }

    /**
     * Legacy {@code ROLE_display_userId} parser only. Returns null for opaque UUIDs and
     * pipeline-internal ids.
     */
    static Long parseUserId(final String externalUserId) {
        if (externalUserId == null
                || externalUserId.isBlank()
                || isPipelineInternal(externalUserId)
                || isOpaqueExternalUserId(externalUserId)) {
            return null;
        }
        final int lastUnderscore = externalUserId.lastIndexOf('_');
        if (lastUnderscore < 0 || lastUnderscore >= externalUserId.length() - 1) {
            return null;
        }
        try {
            return Long.parseLong(externalUserId.substring(lastUnderscore + 1));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** Legacy role prefix parser. Returns {@code UNKNOWN} for opaque / pipeline ids. */
    static String parseRole(final String externalUserId) {
        if (externalUserId == null
                || externalUserId.isBlank()
                || isPipelineInternal(externalUserId)
                || isOpaqueExternalUserId(externalUserId)) {
            return "UNKNOWN";
        }
        final int firstUnderscore = externalUserId.indexOf('_');
        if (firstUnderscore <= 0) {
            return "UNKNOWN";
        }
        return externalUserId.substring(0, firstUnderscore);
    }
}
