package com.careconnect.service;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

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
     * Transcodes the clip's window to a temporary mono 48 kHz WAV file.
     */
    public Path toWav(final KvsAudioClip clip) throws Exception {
        // singletonList, not List.of: a null clip must reach toMonoWav's IllegalArgumentException.
        return toMonoWav(Collections.singletonList(clip), TRANSCRIBE_SAMPLE_RATE);
    }

    /**
     * Trims each clip to its window, then concatenates them, in order, into a single temporary mono
     * WAV at {@code sampleRate}. Several clips occur when an attendee rejoined mid-call.
     */
    public Path toMonoWav(final List<KvsAudioClip> clips, final int sampleRate) throws Exception {
        if (clips == null || clips.isEmpty()) {
            throw new IllegalArgumentException("No raw KVS media files to transcode");
        }
        for (final KvsAudioClip clip : clips) {
            if (clip == null || clip.file() == null || !Files.exists(clip.file())) {
                throw new IllegalArgumentException("Raw KVS media file does not exist");
            }
        }
        final Path output = Files.createTempFile("careconnect-kvs-", ".wav");
        final Process process =
                new ProcessBuilder(buildCommand(clips, sampleRate, output))
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

    List<String> buildCommand(final List<KvsAudioClip> clips, final int sampleRate, final Path output) {
        final List<String> command = new ArrayList<>(
                List.of(ffmpegPath, "-y", "-hide_banner", "-loglevel", "warning"));
        for (final KvsAudioClip clip : clips) {
            command.add("-i");
            command.add(clip.file().toString());
        }
        // Per clip: rebase to 0 (position 0 = first exported fragment), cut to the window, rebase
        // again, then normalize, because concat requires matching rate and layout. Trimming before
        // concat keeps padding audio (possibly another call's, on a reused stream) out of the WAV.
        final StringBuilder graph = new StringBuilder();
        for (int i = 0; i < clips.size(); i++) {
            graph.append('[').append(i).append(":a]asetpts=PTS-STARTPTS,atrim=start=")
                    .append(seconds(clips.get(i).trimStartMs()))
                    .append(":end=").append(seconds(clips.get(i).trimEndMs()))
                    .append(",asetpts=PTS-STARTPTS,aresample=").append(sampleRate)
                    .append(",aformat=channel_layouts=mono[a").append(i).append("];");
        }
        for (int i = 0; i < clips.size(); i++) {
            graph.append("[a").append(i).append(']');
        }
        graph.append("concat=n=").append(clips.size()).append(":v=0:a=1[out]");
        command.addAll(List.of("-filter_complex", graph.toString(), "-map", "[out]"));
        command.addAll(List.of(
                "-acodec", "pcm_s16le",
                "-ar", Integer.toString(sampleRate),
                "-ac", "1",
                output.toString()));
        return command;
    }

    private static String seconds(final long millis) {
        return String.format(Locale.ROOT, "%.3f", millis / 1000.0);
    }
}
