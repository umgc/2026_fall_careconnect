package com.careconnect.service;

import java.nio.file.Files;
import java.nio.file.Path;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Converts raw KVS WebM/AAC attendee fragments to WAV/PCM for AWS Transcribe.
 */
@Service
public class KvsAudioTranscodeService {

    @Value("${careconnect.kvs.ffmpeg-path:ffmpeg}")
    private String ffmpegPath;

    /**
     * Transcodes the raw KVS artifact to a temporary mono 48 kHz WAV file.
     */
    public Path toWav(final Path rawMediaPath) throws Exception {
        if (rawMediaPath == null || !Files.exists(rawMediaPath)) {
            throw new IllegalArgumentException("Raw KVS media file does not exist");
        }
        final Path output = Files.createTempFile("careconnect-kvs-", ".wav");
        final Process process =
                new ProcessBuilder(
                        ffmpegPath,
                        "-y",
                        "-hide_banner",
                        "-loglevel",
                        "warning",
                        "-i",
                        rawMediaPath.toString(),
                        "-vn",
                        "-acodec",
                        "pcm_s16le",
                        "-ar",
                        "48000",
                        "-ac",
                        "1",
                        output.toString())
                        .redirectErrorStream(true)
                        .start();
        final String outputText = new String(process.getInputStream().readAllBytes());
        final int exitCode = process.waitFor();
        if (exitCode != 0) {
            Files.deleteIfExists(output);
            throw new IllegalStateException(
                    "ffmpeg KVS audio transcode failed with exitCode=" + exitCode + ": " + outputText);
        }
        return output;
    }
}
