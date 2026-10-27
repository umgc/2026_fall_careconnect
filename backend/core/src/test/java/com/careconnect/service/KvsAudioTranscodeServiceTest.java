package com.careconnect.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * Unit tests for {@link KvsAudioTranscodeService}: ffmpeg command construction (asserted
 * directly on {@code buildCommand}, no process started), argument validation, and the
 * transcode process paths, where a stand-in executable plays ffmpeg so no real ffmpeg is needed.
 */
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

    /** Scenario: the Transcribe path (single input, 48 kHz) must be byte-for-byte the legacy command. */
    @Test
    void buildCommand_singleInput_isExactLegacyCommand() {
        // Arrange
        final Path in = Path.of("in.webm");
        final Path out = Path.of("out.wav");

        // Act
        final List<String> command = serviceWith("ffmpeg").buildCommand(List.of(in), 48000, out);

        // Assert
        assertThat(command).containsExactly(
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "warning",
                "-i", in.toString(),
                "-vn", "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "1",
                out.toString());
    }

    /** Scenario: a rejoined attendee has two segments; they are normalized then concatenated. */
    @Test
    void buildCommand_twoInputs_usesConcatFilterGraphAndMapsOutput() {
        // Arrange
        final Path a = Path.of("a.webm");
        final Path b = Path.of("b.webm");
        final Path out = Path.of("out.wav");

        // Act
        final List<String> command = serviceWith("ffmpeg").buildCommand(List.of(a, b), 16000, out);

        // Assert
        assertThat(command).containsExactly(
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "warning",
                "-i", a.toString(), "-i", b.toString(),
                "-filter_complex",
                "[0:a]aresample=16000,aformat=channel_layouts=mono[a0];"
                        + "[1:a]aresample=16000,aformat=channel_layouts=mono[a1];"
                        + "[a0][a1]concat=n=2:v=0:a=1[out]",
                "-map", "[out]",
                "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1",
                out.toString());
        assertThat(command).doesNotContain("-vn");
    }

    /** Scenario: three segments extend the graph by one chain and the concat count. */
    @Test
    void buildCommand_threeInputs_concatCountMatchesInputs() {
        final List<String> command = serviceWith("ffmpeg").buildCommand(
                List.of(Path.of("a"), Path.of("b"), Path.of("c")), 16000, Path.of("o.wav"));

        assertThat(command).contains(
                "[0:a]aresample=16000,aformat=channel_layouts=mono[a0];"
                        + "[1:a]aresample=16000,aformat=channel_layouts=mono[a1];"
                        + "[2:a]aresample=16000,aformat=channel_layouts=mono[a2];"
                        + "[a0][a1][a2]concat=n=3:v=0:a=1[out]");
    }

    /** Scenario: the configured ffmpeg path is the command's first element. */
    @Test
    void buildCommand_usesConfiguredFfmpegPath() {
        assertThat(serviceWith("/opt/ffmpeg/bin/ffmpeg")
                .buildCommand(List.of(Path.of("a")), 48000, Path.of("o")).get(0))
                .isEqualTo("/opt/ffmpeg/bin/ffmpeg");
    }

    /** Scenario: an empty list is a caller bug and must fail before creating any temp file. */
    @Test
    void toMonoWav_emptyList_throwsIllegalArgument() {
        assertThatThrownBy(() -> serviceWith("ffmpeg").toMonoWav(List.of(), 16000))
                .isInstanceOf(IllegalArgumentException.class);
    }

    /** Scenario: null list is treated the same as empty. */
    @Test
    void toMonoWav_nullList_throwsIllegalArgument() {
        assertThatThrownBy(() -> serviceWith("ffmpeg").toMonoWav(null, 16000))
                .isInstanceOf(IllegalArgumentException.class);
    }

    /** Scenario: one input exists, the other does not; the missing one must be rejected. */
    @Test
    void toMonoWav_missingFile_throwsIllegalArgument(@TempDir final Path dir) throws Exception {
        // Arrange
        final Path existing = Files.writeString(dir.resolve("present.webm"), "audio");

        // Act + Assert
        assertThatThrownBy(() -> serviceWith("ffmpeg").toMonoWav(
                List.of(existing, dir.resolve("missing.webm")), 16000))
                .isInstanceOf(IllegalArgumentException.class);
    }

    private static boolean canRun(final String command) {
        try {
            return new ProcessBuilder(command).start().waitFor() == 0;
        } catch (Exception e) {
            return false;
        }
    }
}
