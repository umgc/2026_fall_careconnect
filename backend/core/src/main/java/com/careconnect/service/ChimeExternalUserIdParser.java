package com.careconnect.service;

/** Parses {@link ChimeService#toChimeExternalUserId} values back to app user id and role. */
final class ChimeExternalUserIdParser {

    private ChimeExternalUserIdParser() {}

    static boolean isPipelineInternal(final String externalUserId) {
        return externalUserId != null && externalUserId.startsWith("aws:");
    }

    static Long parseUserId(final String externalUserId) {
        if (externalUserId == null || externalUserId.isBlank() || isPipelineInternal(externalUserId)) {
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

    static String parseRole(final String externalUserId) {
        if (externalUserId == null || externalUserId.isBlank() || isPipelineInternal(externalUserId)) {
            return "UNKNOWN";
        }
        final int firstUnderscore = externalUserId.indexOf('_');
        if (firstUnderscore <= 0) {
            return "UNKNOWN";
        }
        return externalUserId.substring(0, firstUnderscore);
    }
}
