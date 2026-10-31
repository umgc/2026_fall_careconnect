package com.careconnect.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;
import org.mockito.MockedConstruction;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockConstruction;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link KvsAudioTranscodeService}: ffmpeg command construction, including the
 * per-clip trim to the attendee window (asserted directly on {@code buildCommand}, no process
 * started), argument validation, and the
 * transcode process paths, where a stand-in executable plays ffmpeg so no real ffmpeg is needed.
 */
class KvsAudioTranscodeServiceTest {

    /** Existing executable used only by input validation tests. */
    private static final String JAVA_BIN =
            Path.of(System.getProperty("java.home"), "bin", "java").toString();

    private KvsAudioTranscodeService serviceWith(final String ffmpegPath) {
        final KvsAudioTranscodeService service = new KvsAudioTranscodeService();
        ReflectionTestUtils.setField(service, "ffmpegPath", ffmpegPath);
        return service;
    }

    /** A whole-file-ish window; the window itself doesn't matter where only the file is under test. */
    private static KvsAudioClip clip(final Path file) {
        return new KvsAudioClip(file, 0L, 60_000L);
    }

    @Test
    void toWav_missingFile_throwsIllegalArgument(@TempDir final Path dir) {
        assertThatThrownBy(() -> serviceWith(JAVA_BIN).toWav(clip(dir.resolve("missing.webm"))))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("does not exist");
    }

    @Test
    void toWav_transcoderFails_throwsWithExitCodeAndOutput(@TempDir final Path dir) throws Exception {
        final Path raw = Files.writeString(dir.resolve("in.webm"), "not audio");

        final Process process = mock(Process.class);
        when(process.getInputStream()).thenReturn(new ByteArrayInputStream(
                "invalid audio fixture".getBytes(StandardCharsets.UTF_8)));
        when(process.waitFor()).thenReturn(17);
        final AtomicReference<Path> output = new AtomicReference<>();

        // Preserve PR #429's portable failure fixture with the current clip/list API.
        try (MockedConstruction<ProcessBuilder> builders = mockConstruction(ProcessBuilder.class,
                (builder, context) -> {
                    final List<?> command = (List<?>) context.arguments().get(0);
                    assertThat(command.indexOf(raw.toString())).isGreaterThan(0);
                    assertThat(command.get(command.indexOf(raw.toString()) - 1)).isEqualTo("-i");
                    output.set(Path.of((String) command.get(command.size() - 1)));
                    when(builder.redirectErrorStream(true)).thenReturn(builder);
                    when(builder.start()).thenReturn(process);
                })) {
            assertThatThrownBy(() -> serviceWith("ffmpeg-test").toWav(clip(raw)))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("exitCode=17")
                    .hasMessageContaining("invalid audio fixture");
            assertThat(builders.constructed()).hasSize(1);
            assertThat(output.get()).doesNotExist();
        }
    }

    @Test
    void toWav_transcoderSucceeds_returnsTempWav(@TempDir final Path dir) throws Exception {
        assumeTrue(canRun("true"), "no `true` executable on this machine");
        final Path raw = Files.writeString(dir.resolve("in.webm"), "audio");

        final Path wav = serviceWith("true").toWav(clip(raw));
        try {
            assertThat(wav).exists();
            assertThat(wav.getFileName().toString()).startsWith("careconnect-kvs-").endsWith(".wav");
        } finally {
            Files.deleteIfExists(wav);
        }
    }

    /**
     * Scenario: the Transcribe path (one clip, 48 kHz). The clip's window (10 s padding before, a
     * 60 s join) must be cut out of the file, so the padding never reaches the WAV.
     */
    @Test
    void buildCommand_singleClip_trimsToWindow() {
        // Arrange: 10 000 ms of padding precedes the window; the window is 60 s long.
        final Path in = Path.of("in.webm");
        final Path out = Path.of("out.wav");

        // Act
        final List<String> command = serviceWith("ffmpeg").buildCommand(
                List.of(new KvsAudioClip(in, 10_000L, 70_000L)), 48000, out);

        // Assert
        assertThat(command).containsExactly(
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "warning",
                "-i", in.toString(),
                "-filter_complex",
                "[0:a]asetpts=PTS-STARTPTS,atrim=start=10.000:end=70.000,asetpts=PTS-STARTPTS,"
                        + "aresample=48000,aformat=channel_layouts=mono[a0];"
                        + "[a0]concat=n=1:v=0:a=1[out]",
                "-map", "[out]",
                "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "1",
                out.toString());
    }

    /**
     * Scenario: a rejoined attendee has two clips; each is trimmed to its own window before they
     * are concatenated, so neither clip's padding ends up between them.
     */
    @Test
    void buildCommand_twoClips_trimsEachBeforeConcat() {
        // Arrange: sub-second offsets check the millisecond formatting.
        final Path a = Path.of("a.webm");
        final Path b = Path.of("b.webm");
        final Path out = Path.of("out.wav");

        // Act
        final List<String> command = serviceWith("ffmpeg").buildCommand(
                List.of(new KvsAudioClip(a, 0L, 30_500L), new KvsAudioClip(b, 9_250L, 40_000L)),
                16000, out);

        // Assert
        assertThat(command).containsExactly(
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "warning",
                "-i", a.toString(), "-i", b.toString(),
                "-filter_complex",
                "[0:a]asetpts=PTS-STARTPTS,atrim=start=0.000:end=30.500,asetpts=PTS-STARTPTS,"
                        + "aresample=16000,aformat=channel_layouts=mono[a0];"
                        + "[1:a]asetpts=PTS-STARTPTS,atrim=start=9.250:end=40.000,asetpts=PTS-STARTPTS,"
                        + "aresample=16000,aformat=channel_layouts=mono[a1];"
                        + "[a0][a1]concat=n=2:v=0:a=1[out]",
                "-map", "[out]",
                "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1",
                out.toString());
    }

    /** Scenario: three clips extend the graph by one chain and the concat count. */
    @Test
    void buildCommand_threeClips_concatCountMatchesInputs() {
        final List<String> command = serviceWith("ffmpeg").buildCommand(
                List.of(clip(Path.of("a")), clip(Path.of("b")), clip(Path.of("c"))),
                16000, Path.of("o.wav"));

        assertThat(String.join(" ", command))
                .contains("[0:a]asetpts").contains("[1:a]asetpts").contains("[2:a]asetpts")
                .contains("[a0][a1][a2]concat=n=3:v=0:a=1[out]");
    }

    /** Scenario: the configured ffmpeg path is the command's first element. */
    @Test
    void buildCommand_usesConfiguredFfmpegPath() {
        assertThat(serviceWith("/opt/ffmpeg/bin/ffmpeg")
                .buildCommand(List.of(clip(Path.of("a"))), 48000, Path.of("o")).get(0))
                .isEqualTo("/opt/ffmpeg/bin/ffmpeg");
    }

    /** Scenario: a null clip is rejected like a missing file, before any temp file is made. */
    @Test
    void toWav_nullClip_throwsIllegalArgument() {
        assertThatThrownBy(() -> serviceWith(JAVA_BIN).toWav(null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("does not exist");
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
                List.of(clip(existing), clip(dir.resolve("missing.webm"))), 16000))
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
