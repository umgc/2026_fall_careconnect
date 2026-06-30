package com.careconnect.service;

import java.nio.charset.StandardCharsets;
import java.util.Collection;
import java.util.Optional;

/** Reads Chime media-stream MKV fragment bytes for {@code meetingId} / {@code attendeeId} tags. */
final class KvsFragmentMetadataReader {

    private KvsFragmentMetadataReader() {}

    /**
     * Returns the attendee id when the fragment payload contains both the meeting id and one of
     * the expected attendee ids (UTF-8 tag values in MKV).
     */
    static Optional<String> matchAttendeeId(
            final byte[] fragmentBytes,
            final String meetingId,
            final Collection<String> attendeeIds) {
        if (fragmentBytes == null
                || fragmentBytes.length == 0
                || meetingId == null
                || meetingId.isBlank()
                || attendeeIds == null
                || attendeeIds.isEmpty()) {
            return Optional.empty();
        }
        if (!containsMeetingId(fragmentBytes, meetingId)) {
            return Optional.empty();
        }
        for (final String attendeeId : attendeeIds) {
            if (attendeeId != null
                    && !attendeeId.isBlank()
                    && containsUtf8(fragmentBytes, attendeeId)) {
                return Optional.of(attendeeId);
            }
        }
        return Optional.empty();
    }

    static boolean containsMeetingId(final byte[] fragmentBytes, final String meetingId) {
        if (fragmentBytes == null
                || fragmentBytes.length == 0
                || meetingId == null
                || meetingId.isBlank()) {
            return false;
        }
        if (containsUtf8(fragmentBytes, meetingId)) {
            return true;
        }
        final String compact = meetingId.replace("-", "");
        return !compact.equals(meetingId) && containsUtf8(fragmentBytes, compact);
    }

    private static boolean containsUtf8(final byte[] haystack, final String needle) {
        final byte[] needleBytes = needle.getBytes(StandardCharsets.UTF_8);
        if (needleBytes.length == 0 || haystack.length < needleBytes.length) {
            return false;
        }
        outer:
        for (int i = 0; i <= haystack.length - needleBytes.length; i++) {
            for (int j = 0; j < needleBytes.length; j++) {
                if (haystack[i + j] != needleBytes[j]) {
                    continue outer;
                }
            }
            return true;
        }
        return false;
    }
}
