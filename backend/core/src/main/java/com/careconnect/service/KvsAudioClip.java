package com.careconnect.service;

import java.nio.file.Path;

/**
 * Raw media exported from one attendee's KVS stream, plus the slice of it that belongs to the
 * requested window. The export fetches extra fragments on each side (clock skew, fragment
 * boundaries); pool streams are reused across calls, so only {@code [trimStartMs, trimEndMs)},
 * measured from the start of the file, may be decoded.
 *
 * @param file temporary raw media file (WebM/MKV)
 * @param trimStartMs where the requested window starts in the file
 * @param trimEndMs where the requested window ends in the file
 */
public record KvsAudioClip(Path file, long trimStartMs, long trimEndMs) {

    /** Validates the slice. */
    public KvsAudioClip {
        if (trimStartMs < 0 || trimEndMs <= trimStartMs) {
            throw new IllegalArgumentException(
                    "Invalid KVS clip window start=" + trimStartMs + " end=" + trimEndMs);
        }
    }
}
