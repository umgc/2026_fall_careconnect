package com.careconnect.service;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Converts raw KVS WebM/AAC attendee fragments to WAV/PCM for AWS Transcribe.
 */
@Service
public class KvsAudioTranscodeService {

    @Value("${careconnect.kvs.ffmpeg-path:ffmpeg}")
    private String ffmpegPath;

    /** Sample rate used for AWS Transcribe input. */
    public static final int TRANSCRIBE_SAMPLE_RATE = 48000;

    /**
     * Transcodes the raw KVS artifact to a temporary mono 48 kHz WAV file.
     */
    public Path toWav(final Path rawMediaPath) throws Exception {
        // singletonList, not List.of: a null path must reach toMonoWav's IllegalArgumentException.
        return toMonoWav(Collections.singletonList(rawMediaPath), TRANSCRIBE_SAMPLE_RATE);
    }

    /**
     * Transcodes one or more raw KVS artifacts, in order, into a single temporary mono WAV at
     * {@code sampleRate}. Several inputs occur when an attendee rejoined mid-call.
     */
    public Path toMonoWav(final List<Path> rawMediaPaths, final int sampleRate) throws Exception {
        if (rawMediaPaths == null || rawMediaPaths.isEmpty()) {
            throw new IllegalArgumentException("No raw KVS media files to transcode");
        }
        for (final Path raw : rawMediaPaths) {
            if (raw == null || !Files.exists(raw)) {
                throw new IllegalArgumentException("Raw KVS media file does not exist");
            }
        }
        final Path output = Files.createTempFile("careconnect-kvs-", ".wav");
        final Process process =
                new ProcessBuilder(buildCommand(rawMediaPaths, sampleRate, output))
                        .redirectErrorStream(true)
                        .start();
        final String outputText =
                new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        final int exitCode = process.waitFor();
        if (exitCode != 0) {
            Files.deleteIfExists(output);
            throw new IllegalStateException(
                    "ffmpeg KVS audio transcode failed with exitCode=" + exitCode + ": " + outputText);
        }
        return output;
    }

    List<String> buildCommand(final List<Path> inputs, final int sampleRate, final Path output) {
        final List<String> command = new ArrayList<>(
                List.of(ffmpegPath, "-y", "-hide_banner", "-loglevel", "warning"));
        for (final Path input : inputs) {
            command.add("-i");
            command.add(input.toString());
        }
        if (inputs.size() > 1) {
            // Normalize every segment first: concat requires matching rate and layout.
            final StringBuilder graph = new StringBuilder();
            for (int i = 0; i < inputs.size(); i++) {
                graph.append('[').append(i).append(":a]aresample=").append(sampleRate)
                        .append(",aformat=channel_layouts=mono[a").append(i).append("];");
            }
            for (int i = 0; i < inputs.size(); i++) {
                graph.append("[a").append(i).append(']');
            }
            graph.append("concat=n=").append(inputs.size()).append(":v=0:a=1[out]");
            command.addAll(List.of("-filter_complex", graph.toString(), "-map", "[out]"));
        } else {
            command.add("-vn");
        }
        command.addAll(List.of(
                "-acodec", "pcm_s16le",
                "-ar", Integer.toString(sampleRate),
                "-ac", "1",
                output.toString()));
        return command;
    }
}
