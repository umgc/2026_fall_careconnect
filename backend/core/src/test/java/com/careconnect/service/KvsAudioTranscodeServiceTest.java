package com.careconnect.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class KvsAudioTranscodeServiceTest {

    /** The JVM running this test: exits non-zero on ffmpeg's arguments, on every OS. */
    private static final String JAVA_BIN =
            Path.of(System.getProperty("java.home"), "bin", "java").toString();

    private KvsAudioTranscodeService serviceWith(final String ffmpegPath) {
        final KvsAudioTranscodeService service = new KvsAudioTranscodeService();
        ReflectionTestUtils.setField(service, "ffmpegPath", ffmpegPath);
        return service;
    }

    @Test
    void toWav_nullPath_throwsIllegalArgument() {
        assertThatThrownBy(() -> serviceWith(JAVA_BIN).toWav(null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("does not exist");
    }

    @Test
    void toWav_missingFile_throwsIllegalArgument(@TempDir final Path dir) {
        assertThatThrownBy(() -> serviceWith(JAVA_BIN).toWav(dir.resolve("missing.webm")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("does not exist");
    }

    @Test
    void toWav_transcoderFails_throwsWithExitCodeAndOutput(@TempDir final Path dir) throws Exception {
        final Path raw = Files.writeString(dir.resolve("in.webm"), "not audio");

        // `java -y ...` rejects the unknown option and exits 1, standing in for a failed ffmpeg.
        assertThatThrownBy(() -> serviceWith(JAVA_BIN).toWav(raw))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("exitCode=1")
                .hasMessageContaining("-y");
    }

    @Test
    void toWav_transcoderSucceeds_returnsTempWav(@TempDir final Path dir) throws Exception {
        assumeTrue(canRun("true"), "no `true` executable on this machine");
        final Path raw = Files.writeString(dir.resolve("in.webm"), "audio");

        final Path wav = serviceWith("true").toWav(raw);
        try {
            assertThat(wav).exists();
            assertThat(wav.getFileName().toString()).startsWith("careconnect-kvs-").endsWith(".wav");
        } finally {
            Files.deleteIfExists(wav);
        }
    }

    private static boolean canRun(final String command) {
        try {
            return new ProcessBuilder(command).start().waitFor() == 0;
        } catch (Exception e) {
            return false;
        }
    }
}
