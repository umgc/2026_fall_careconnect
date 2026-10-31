package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.file.Path;
import org.junit.jupiter.api.Test;

/**
 * Validates {@link KvsAudioClip}'s window check. The window is the only part of an exported KVS
 * file the transcoder may decode, so an empty or inverted one must be rejected when the clip is
 * built rather than producing an empty or padding-only WAV. Pure value object: nothing is mocked.
 */
class KvsAudioClipTest {

    private static final Path FILE = Path.of("export.mkv");

    /** Scenario: the usual export — 10 s of padding precede a 60 s window. */
    @Test
    void validWindow_keepsFileAndOffsets() {
        final KvsAudioClip clip = new KvsAudioClip(FILE, 10_000L, 70_000L);

        assertThat(clip.file()).isEqualTo(FILE);
        assertThat(clip.trimStartMs()).isEqualTo(10_000L);
        assertThat(clip.trimEndMs()).isEqualTo(70_000L);
    }

    /** Scenario: the file starts exactly at the window (no padding found), so the start is 0. */
    @Test
    void windowStartingAtZero_isValid() {
        assertThat(new KvsAudioClip(FILE, 0L, 1L).trimStartMs()).isZero();
    }

    /** Scenario: a zero-length window (start == end) would decode nothing. */
    @Test
    void emptyWindow_isRejected() {
        assertThatThrownBy(() -> new KvsAudioClip(FILE, 5_000L, 5_000L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("start=5000")
                .hasMessageContaining("end=5000");
    }

    /** Scenario: an end before the start (inverted window) is a caller bug. */
    @Test
    void invertedWindow_isRejected() {
        assertThatThrownBy(() -> new KvsAudioClip(FILE, 9_000L, 1_000L))
                .isInstanceOf(IllegalArgumentException.class);
    }

    /** Scenario: a negative start points before the file. */
    @Test
    void negativeStart_isRejected() {
        assertThatThrownBy(() -> new KvsAudioClip(FILE, -1L, 5_000L))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
