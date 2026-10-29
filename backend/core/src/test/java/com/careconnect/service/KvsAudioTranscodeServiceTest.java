package com.careconnect.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;
import org.mockito.MockedConstruction;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockConstruction;
import static org.mockito.Mockito.when;

class KvsAudioTranscodeServiceTest {

    /** An existing executable; input validation tests never start it. */
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

        final Process process = mock(Process.class);
        when(process.getInputStream()).thenReturn(new ByteArrayInputStream(
                "invalid audio fixture".getBytes(StandardCharsets.UTF_8)));
        when(process.waitFor()).thenReturn(17);
        final AtomicReference<Path> output = new AtomicReference<>();

        // Control the exit and output instead of depending on another executable's diagnostics.
        try (MockedConstruction<ProcessBuilder> builders = mockConstruction(ProcessBuilder.class,
                (builder, context) -> {
                    final String[] command = (String[]) context.arguments().get(0);
                    assertThat(command).containsSubsequence("-i", raw.toString());
                    output.set(Path.of(command[command.length - 1]));
                    when(builder.redirectErrorStream(true)).thenReturn(builder);
                    when(builder.start()).thenReturn(process);
                })) {
            assertThatThrownBy(() -> serviceWith("ffmpeg-test").toWav(raw))
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
