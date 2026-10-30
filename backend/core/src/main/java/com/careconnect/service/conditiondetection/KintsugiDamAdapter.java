package com.careconnect.service.conditiondetection;

import com.careconnect.model.CallAttendee;
import com.careconnect.model.CallRecording;
import com.careconnect.model.conditiondetection.ConditionDetectionContext;
import com.careconnect.model.conditiondetection.ConditionFinding;
import com.careconnect.model.conditiondetection.ConditionInputKind;
import com.careconnect.model.conditiondetection.ConditionName;
import com.careconnect.model.conditiondetection.ConditionSkipReason;
import com.careconnect.repository.CallAttendeeRepository;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.service.AttendeeAudioWindows;
import com.careconnect.service.KvsArchivedMediaExportService;
import com.careconnect.service.KvsAudioClip;
import com.careconnect.service.KvsAudioTranscodeService;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Phase 1: depression and anxiety screening from the patient's voice with the open-source
 * KintsugiHealth/dam model, served by the localhost inference sidecar.
 *
 * <p>The patient's audio is re-exported from KVS here rather than reused from transcription,
 * whose per-attendee WAVs are deleted as PHI before transcription completes. Audio only ever
 * exists as local temp files for the duration of {@link #analyze}.</p>
 */
@Slf4j
@Component
@Order(1)
@ConditionalOnProperty(
        name = "careconnect.condition-detection.dam.enabled",
        havingValue = "true",
        matchIfMissing = true)
public class KintsugiDamAdapter implements ConditionModelAdapter {

    static final String MODEL_ID = "kintsugi-dam-3.1";

    /** DAM checkpoint plus the published inference thresholds the sidecar applies. */
    static final String CONFIG_VERSION = "dam3.1:published-thresholds-v1";

    static final int DAM_SAMPLE_RATE = 16000;

    /** Re-check a recording that is still finalizing after this many seconds. */
    static final long FINALIZING_DELAY_SECONDS = 60L;

    /** Re-check a sidecar that is restarting or still loading the model after this long. */
    static final long SIDECAR_WAIT_SECONDS = 120L;

    private static final List<String> DEPRESSION_LABELS = List.of("NONE", "MILD_TO_MODERATE", "SEVERE");
    private static final List<String> ANXIETY_LABELS = List.of("NONE", "MILD", "MODERATE", "SEVERE");

    private final DamSidecarClient sidecar;
    private final KvsArchivedMediaExportService kvsExport;
    private final KvsAudioTranscodeService transcoder;
    private final CallRecordingRepository recordingRepository;
    private final CallAttendeeRepository attendeeRepository;
    private final Duration audioMaxAge;

    public KintsugiDamAdapter(
            final DamSidecarClient sidecar,
            final KvsArchivedMediaExportService kvsExport,
            final KvsAudioTranscodeService transcoder,
            final CallRecordingRepository recordingRepository,
            final CallAttendeeRepository attendeeRepository,
            @Value("${careconnect.condition-detection.audio-max-age-hours:20}")
            final long audioMaxAgeHours) {
        this.sidecar = sidecar;
        this.kvsExport = kvsExport;
        this.transcoder = transcoder;
        this.recordingRepository = recordingRepository;
        this.attendeeRepository = attendeeRepository;
        this.audioMaxAge = Duration.ofHours(audioMaxAgeHours);
    }

    @Override
    public String modelId() {
        return MODEL_ID;
    }

    @Override
    public String displayName() {
        return "Voice biomarker screening (Kintsugi DAM)";
    }

    @Override
    public Set<ConditionName> supportedConditions() {
        return Set.of(ConditionName.DEPRESSION, ConditionName.ANXIETY);
    }

    @Override
    public ConditionInputKind inputKind() {
        return ConditionInputKind.PATIENT_AUDIO;
    }

    @Override
    public String configVersion() {
        return CONFIG_VERSION;
    }

    @Override
    public AdapterOutcome analyze(final ConditionDetectionContext context) throws Exception {
        if (context.recordingId() == null) {
            return new AdapterOutcome.Skipped(ConditionSkipReason.NO_RECORDING);
        }
        final CallRecording recording = recordingRepository.findById(context.recordingId()).orElse(null);
        if (recording == null || recording.getStartedAt() == null) {
            return new AdapterOutcome.Skipped(ConditionSkipReason.NO_RECORDING);
        }
        if (recording.getEndedAt() == null) {
            // Recording is still being finalized; KVS ingest has not stopped yet.
            return new AdapterOutcome.Deferred(FINALIZING_DELAY_SECONDS);
        }
        final LocalDateTime now = LocalDateTime.now(ZoneOffset.UTC);
        if (Duration.between(recording.getEndedAt(), now).compareTo(audioMaxAge) > 0) {
            return new AdapterOutcome.Skipped(ConditionSkipReason.AUDIO_EXPIRED);
        }
        if (!sidecar.isReady()) {
            // Restarting or still loading: wait without spending an attempt. If it never comes
            // back, the audio-age check above ends the run as AUDIO_EXPIRED.
            return new AdapterOutcome.Deferred(SIDECAR_WAIT_SECONDS);
        }

        final List<KvsAudioClip> clips = new ArrayList<>();
        Path wav = null;
        try {
            for (final AttendeeAudioWindows.Window window : patientWindows(context, recording)) {
                final KvsAudioClip clip = exportWindow(window);
                if (clip != null) {
                    clips.add(clip);
                }
            }
            if (clips.isEmpty()) {
                return new AdapterOutcome.Skipped(ConditionSkipReason.NO_PATIENT_AUDIO);
            }
            wav = transcoder.toMonoWav(clips, DAM_SAMPLE_RATE);
            return toOutcome(sidecar.analyze(wav));
        } finally {
            for (final KvsAudioClip clip : clips) {
                deleteQuietly(clip.file());
            }
            deleteQuietly(wav);
        }
    }

    /**
     * The patient's own attendee rows (one per Chime join) as consecutive windows inside the
     * recording. KVS pool streams are reused across calls, so each row's join/leave bounds what is
     * read, and rejoins never overlap, so no speech is scored twice.
     */
    private List<AttendeeAudioWindows.Window> patientWindows(
            final ConditionDetectionContext context, final CallRecording recording) {
        final List<CallAttendee> rows = attendeeRepository.findByCallId(context.callId()).stream()
                .filter(a -> context.patientUserId().equals(a.getUserId()))
                .filter(a -> a.getKvsStreamArn() != null && !a.getKvsStreamArn().isBlank())
                .toList();
        return AttendeeAudioWindows.forUser(rows, recording.getStartedAt(), recording.getEndedAt());
    }

    /** Exports one window; null when its stream has no audio there. */
    private KvsAudioClip exportWindow(final AttendeeAudioWindows.Window window) throws Exception {
        final CallAttendee row = window.attendee();
        try {
            return kvsExport.exportAttendeeRange(
                    row.getKvsStreamArn(), window.fromInstant(), window.toInstant());
        } catch (IllegalStateException noAudio) {
            // No fragments for this join (or KVS unavailable); other joins may still have audio.
            if (log.isInfoEnabled()) {
                log.info("No KVS audio for patient attendee row {} of call {}",
                        row.getId(), row.getCallId());
            }
            return null;
        }
    }

    static AdapterOutcome toOutcome(final DamSidecarClient.DamResult result) {
        return switch (result.status()) {
            case DamSidecarClient.STATUS_OK -> new AdapterOutcome.Completed(
                    List.of(
                            finding(ConditionName.DEPRESSION, result.depression(), DEPRESSION_LABELS),
                            finding(ConditionName.ANXIETY, result.anxiety(), ANXIETY_LABELS)),
                    result.speechSeconds());
            case DamSidecarClient.STATUS_INSUFFICIENT_SPEECH -> new AdapterOutcome.Skipped(
                    ConditionSkipReason.INSUFFICIENT_SPEECH, result.speechSeconds());
            case DamSidecarClient.STATUS_INVALID_AUDIO -> new AdapterOutcome.Skipped(
                    ConditionSkipReason.NO_PATIENT_AUDIO);
            default -> throw new IllegalStateException(
                    "Unexpected DAM sidecar status " + result.status());
        };
    }

    private static ConditionFinding finding(
            final ConditionName condition,
            final DamSidecarClient.DamScore score,
            final List<String> labels) {
        if (score == null || score.level() == null
                || score.level() < 0 || score.level() >= labels.size()) {
            throw new IllegalStateException("DAM sidecar returned no valid level for " + condition);
        }
        return new ConditionFinding(
                condition, score.level(), labels.get(score.level()), score.raw(), null);
    }

    private static void deleteQuietly(final Path path) {
        if (path == null) {
            return;
        }
        try {
            Files.deleteIfExists(path);
        } catch (Exception e) {
            if (log.isWarnEnabled()) {
                log.warn("Could not delete condition-detection temp audio {}", path.getFileName());
            }
        }
    }
}
