package com.careconnect.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.chimesdkmeetings.ChimeSdkMeetingsClient;
import software.amazon.awssdk.services.chimesdkmeetings.model.Attendee;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateAttendeeRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateAttendeeResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateMeetingResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.DeleteMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.EngineTranscribeSettings;
import software.amazon.awssdk.services.chimesdkmeetings.model.Meeting;
import software.amazon.awssdk.services.chimesdkmeetings.model.StartMeetingTranscriptionRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.StartMeetingTranscriptionResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.TranscriptionConfiguration;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * ChimeService — manages AWS Chime SDK video call meetings.
 *
 * Flow:
 *   1. Caller sends call invitation via WebSocket (CallNotificationHandler)
 *   2. Recipient accepts — frontend calls POST /api/v3/calls/{callId}/meeting
 *   3. This service creates a Chime meeting and adds both users as attendees
 *   4. Both users receive meeting credentials and join via Jitsi/Chime SDK in Flutter
 *   5. When call ends, DELETE /api/v3/calls/{callId}/meeting cleans up
 */
@Slf4j
@Service
public class ChimeService {

    /** AWS Chime SDK meetings client. */
    private final ChimeSdkMeetingsClient chimeSdkMeetingsClient;

    /** Whether AWS integration is enabled. */
    private final boolean awsEnabled;

    /** Whether Chime transcription is enabled. */
    private final boolean transcriptionEnabled;

    /** BCP-47 language code for transcription. */
    private final String transcriptionLanguageCode;

    /** AWS region for the transcription service. */
    private final String transcriptionRegion;

    // In-memory store of active meetings: callId -> Meeting
    // On ECS single-instance this is sufficient — no distributed cache needed

    /** Active meetings keyed by callId. */
    private final Map<String, Meeting> activeMeetings = new ConcurrentHashMap<>();

    /** Cached join credentials per callId and userId (L5a idempotent re-join). */
    private final Map<String, Map<String, Map<String, Object>>> attendeeCredentials =
            new ConcurrentHashMap<>();

    /** Tracks whether transcription has been started for each callId. */
    private final Map<String, Boolean> transcriptionStarted = new ConcurrentHashMap<>();

    /** Last source that attempted transcription for each callId. */
    private final Map<String, String> transcriptionLastSource = new ConcurrentHashMap<>();

    /** Timestamp of last transcription attempt for each callId. */
    private final Map<String, Long> transcriptionLastAttemptAtMs = new ConcurrentHashMap<>();

    /** Last transcription status recorded for each callId. */
    private final Map<String, String> transcriptionLastStatus = new ConcurrentHashMap<>();

    /** Last transcription detail message for each callId. */
    private final Map<String, String> transcriptionLastDetail = new ConcurrentHashMap<>();

    /** Last Chime meeting ID used for transcription per callId. */
    private final Map<String, String> transcriptionLastMeetingId = new ConcurrentHashMap<>();

    /** Source of last successful transcription start per callId. */
    private final Map<String, String> transcriptionLastStartSource = new ConcurrentHashMap<>();

    /** Timestamp of last successful transcription start per callId. */
    private final Map<String, Long> transcriptionLastStartAtMs = new ConcurrentHashMap<>();

    /** Status of last transcription start attempt per callId. */
    private final Map<String, String> transcriptionLastStartStatus = new ConcurrentHashMap<>();

    /** Detail message of last transcription start attempt per callId. */
    private final Map<String, String> transcriptionLastStartDetail = new ConcurrentHashMap<>();

    /** Local-mock media region used when AWS is unavailable. */
    private static final String DEFAULT_MEDIA_REGION = "us-east-1";

    /** Maximum length for a Chime external user ID. */
    private static final int CHIME_USER_ID_MAX_LENGTH = 64;

    /** Minimum length for a Chime external user ID. */
    private static final int CHIME_USER_ID_MIN_LENGTH = 2;

    @Autowired
    public ChimeService(
            @Autowired(required = false) final ChimeSdkMeetingsClient chimeSdkMeetingsClient,
            @Value("${careconnect.aws.enabled:true}") final boolean awsEnabled,
            @Value("${careconnect.chime.transcription.enabled:true}") final boolean transcriptionEnabled,
            @Value("${careconnect.chime.transcription.language-code:en-US}")
                final String transcriptionLanguageCode,
            @Value("${careconnect.chime.transcription.region:us-east-1}")
                final String transcriptionRegion) {
        this.chimeSdkMeetingsClient = chimeSdkMeetingsClient;
        this.awsEnabled = awsEnabled;
        this.transcriptionEnabled = transcriptionEnabled;
        this.transcriptionLanguageCode = transcriptionLanguageCode;
        this.transcriptionRegion = transcriptionRegion;
    }

    // ================================================================
    // CREATE MEETING
    // Called when a call is accepted — creates the Chime meeting room
    // ================================================================

    /**
     * Creates a new Chime meeting for the given callId.
     * Returns the meeting details needed by both parties to join.
     *
     * @param callId the unique call identifier
     * @return meeting details map
     */
    public final Map<String, Object> createMeeting(final String callId) {
        log.info("Creating Chime meeting for callId: {}", callId);

        // Check if meeting already exists (e.g. both parties called this simultaneously)
        if (activeMeetings.containsKey(callId)) {
            log.info("Meeting already exists for callId: {}", callId);
            return buildMeetingResponse(activeMeetings.get(callId));
        }

        if (!isAwsChimeAvailable()) {
            final Meeting localMeeting = Meeting.builder()
                    .meetingId("local-" + UUID.randomUUID())
                    .externalMeetingId(callId)
                    .mediaRegion(DEFAULT_MEDIA_REGION)
                    .build();
            activeMeetings.put(callId, localMeeting);
            log.warn("AWS Chime unavailable/disabled; created local mock meeting for callId: {}",
                    callId);
            return buildMeetingResponse(localMeeting);
        }

        try {
            final CreateMeetingRequest request = CreateMeetingRequest.builder()
                    .clientRequestToken(UUID.randomUUID().toString())
                    .mediaRegion(DEFAULT_MEDIA_REGION)
                    .externalMeetingId(callId)
                    .build();

            final CreateMeetingResponse response = chimeSdkMeetingsClient.createMeeting(request);
            final Meeting meeting = response.meeting();

            // Store for later attendee creation and cleanup
            activeMeetings.put(callId, meeting);
            transcriptionLastMeetingId.put(callId, meeting.meetingId());

            ensureMeetingTranscriptionStarted(callId, meeting, "createMeeting");

            if (log.isInfoEnabled()) {
                log.info("Chime meeting created: {} for callId: {}", meeting.meetingId(), callId);
            }
            return buildMeetingResponse(meeting);

        } catch (Exception e) {
            log.error("Failed to create Chime meeting for callId: {}", callId, e);
            throw new RuntimeException("Failed to create video call meeting: " + e.getMessage(), e);
        }
    }

    // ================================================================
    // CREATE ATTENDEE
    // Called for each user joining the meeting — returns join credentials
    // ================================================================

    /**
     * Adds a user to an existing Chime meeting.
     * Must be called for both the caller and the recipient.
     * Returns the attendee credentials the Flutter app needs to join.
     *
     * @param callId the unique call identifier
     * @param userId the user to add as an attendee
     * @return attendee credentials map
     */
    public final Map<String, Object> createAttendee(final String callId, final String userId, final String role, final String displayName) {
        log.info("Creating Chime attendee for userId: {} in callId: {}", userId, callId);

        final Meeting meeting = activeMeetings.get(callId);
        if (meeting == null) {
            throw new RuntimeException("No active meeting found for callId: " + callId
                + ". Create the meeting first.");
        }

        final Map<String, Object> cached = getCachedAttendeeCredentials(callId, userId);
        if (cached != null) {
            if (log.isInfoEnabled()) {
                log.info("Returning cached Chime attendee credentials for userId: {} in callId: {}",
                        userId, callId);
            }
            return cached;
        }

        if (!isAwsChimeAvailable()) {
            final String externalUserId = toChimeExternalUserId(userId, role, displayName);
            final String mediaRegion = meeting.mediaRegion() == null
                    ? DEFAULT_MEDIA_REGION : meeting.mediaRegion();
            final Map<String, Object> credentials = Map.of(
                "meetingId",         meeting.meetingId(),
                "externalMeetingId", meeting.externalMeetingId(),
                "mediaRegion",       mediaRegion,
                "mediaPlacement",    Map.of(
                    "audioHostUrl",      "",
                    "audioFallbackUrl",  "",
                    "screenDataUrl",     "",
                    "screenSharingUrl",  "",
                    "screenViewingUrl",  "",
                    "signalingUrl",      "",
                    "turnControlUrl",    "",
                    "eventIngestionUrl", ""
                ),
                "attendeeId",      "local-attendee-" + UUID.randomUUID(),
                "externalUserId",  externalUserId,
                "joinToken",       "local-join-token-" + UUID.randomUUID()
            );
            cacheAttendeeCredentials(callId, userId, credentials);
            return credentials;
        }

        try {
            final String externalUserId = toChimeExternalUserId(userId, role, displayName);
            final CreateAttendeeRequest request = CreateAttendeeRequest.builder()
                    .meetingId(meeting.meetingId())
                    .externalUserId(externalUserId)
                    .build();

            final CreateAttendeeResponse response = chimeSdkMeetingsClient.createAttendee(request);
            final Attendee attendee = response.attendee();

            if (log.isInfoEnabled()) {
                log.info("Chime attendee created: {} for userId: {}", attendee.attendeeId(), userId);
            }

            // Retry transcription startup after attendee creation in case createMeeting
            // happened before media signaling was fully ready.
            ensureMeetingTranscriptionStarted(callId, meeting, "createAttendee");

            final String eventIngestionUrl = meeting.mediaPlacement().eventIngestionUrl() != null
                    ? meeting.mediaPlacement().eventIngestionUrl() : "";

            // Return everything Flutter needs to join the meeting
            final Map<String, Object> credentials = Map.of(
                "meetingId",         meeting.meetingId(),
                "externalMeetingId", meeting.externalMeetingId(),
                "mediaRegion",       meeting.mediaRegion(),
                "mediaPlacement",    Map.of(
                    "audioHostUrl",      meeting.mediaPlacement().audioHostUrl(),
                    "audioFallbackUrl",  meeting.mediaPlacement().audioFallbackUrl(),
                    "screenDataUrl",     meeting.mediaPlacement().screenDataUrl(),
                    "screenSharingUrl",  meeting.mediaPlacement().screenSharingUrl(),
                    "screenViewingUrl",  meeting.mediaPlacement().screenViewingUrl(),
                    "signalingUrl",      meeting.mediaPlacement().signalingUrl(),
                    "turnControlUrl",    meeting.mediaPlacement().turnControlUrl(),
                    "eventIngestionUrl", eventIngestionUrl
                ),
                "attendeeId",     attendee.attendeeId(),
                "externalUserId", attendee.externalUserId(),
                "joinToken",      attendee.joinToken()
            );
            cacheAttendeeCredentials(callId, userId, credentials);
            return credentials;

        } catch (Exception e) {
            log.error("Failed to create attendee for userId: {} in callId: {}", userId, callId, e);
            throw new RuntimeException("Failed to join video call: " + e.getMessage(), e);
        }
    }

    // ================================================================
    // JOIN MEETING (convenience method)
    // Creates meeting if needed, then creates attendee — one call from Flutter
    // ================================================================

    /**
     * Convenience method — creates the meeting (if not already created)
     * and immediately adds the user as an attendee.
     *
     * Flutter calls this once per user when a call is accepted.
     *
     * @param callId the unique call identifier
     * @param userId the user joining the meeting
     * @return attendee credentials map
     */
    public final Map<String, Object> joinMeeting(final String callId, final String userId, final String role, final String displayName) {
        // Ensure meeting exists
        if (!activeMeetings.containsKey(callId)) {
            createMeeting(callId);
        }
        final Map<String, Object> cached = getCachedAttendeeCredentials(callId, userId);
        if (cached != null) {
            if (log.isInfoEnabled()) {
                log.info("Returning cached join credentials for userId: {} in callId: {}", userId, callId);
            }
            return cached;
        }
        // Add user as attendee and return join credentials
        return createAttendee(callId, userId, role, displayName);
    }

    // ================================================================
    // END MEETING
    // Called when either party hangs up
    // ================================================================

    /**
     * Deletes the Chime meeting and cleans up local state.
     * Called automatically when either party sends end-call via WebSocket.
     *
     * @param callId the unique call identifier
     */
    public final void endMeeting(final String callId) {
        log.info("Ending Chime meeting for callId: {}", callId);

        attendeeCredentials.remove(callId);

        final Meeting meeting = activeMeetings.remove(callId);
        if (meeting == null) {
            recordTranscriptionAttempt(callId, "endMeeting", "MEETING_ENDED", "no-active-meeting");
            log.warn("No active meeting found for callId: {} — may have already ended", callId);
            return;
        }

        transcriptionLastMeetingId.put(callId, meeting.meetingId());
        recordTranscriptionAttempt(
                callId, "endMeeting", "MEETING_ENDED", "meetingId=" + meeting.meetingId());

        if (!isAwsChimeAvailable()) {
            log.info("Ended local mock meeting for callId: {}", callId);
            return;
        }

        try {
            final DeleteMeetingRequest request = DeleteMeetingRequest.builder()
                    .meetingId(meeting.meetingId())
                    .build();

            chimeSdkMeetingsClient.deleteMeeting(request);
            if (log.isInfoEnabled()) {
                log.info("Chime meeting deleted: {} for callId: {}", meeting.meetingId(), callId);
            }

        } catch (Exception e) {
            // Log but don't throw — if Chime already cleaned it up, that's fine
            if (log.isWarnEnabled()) {
                log.warn("Could not delete Chime meeting {} — may have already expired: {}",
                    meeting.meetingId(), e.getMessage());
            }
        }
    }

    // ================================================================
    // GET MEETING INFO
    // Used by sentiment service to confirm meeting is still active
    // ================================================================

    /**
     * Returns whether a meeting is currently active for the given callId.
     *
     * @param callId the unique call identifier
     * @return true if a meeting is active
     */
    public final boolean isMeetingActive(final String callId) {
        return activeMeetings.containsKey(callId);
    }

    /**
     * Returns the Chime meeting ID for the given callId, or null if none.
     *
     * @param callId the unique call identifier
     * @return Chime meeting ID or null
     */
    public final String getMeetingId(final String callId) {
        final Meeting meeting = activeMeetings.get(callId);
        return meeting != null ? meeting.meetingId() : null;
    }

    /**
     * Returns a debug status map for the transcription state of a call.
     *
     * @param callId the unique call identifier
     * @return debug status map
     */
    public final Map<String, Object> getTranscriptionDebugStatus(final String callId) {
        final Map<String, Object> out = new HashMap<>();
        final Meeting meeting = activeMeetings.get(callId);
        final String meetingId = meeting != null
                ? meeting.meetingId() : transcriptionLastMeetingId.get(callId);

        out.put("callId", callId);
        out.put("meetingActive", meeting != null);
        out.put("meetingId", meetingId);
        out.put("awsEnabled", awsEnabled);
        out.put("transcriptionEnabled", transcriptionEnabled);
        out.put("transcriptionStarted", Boolean.TRUE.equals(transcriptionStarted.get(callId)));
        out.put("transcriptionLanguageCode", transcriptionLanguageCode);
        out.put("transcriptionRegion", transcriptionRegion);
        out.put("lastAttemptSource", transcriptionLastSource.get(callId));
        out.put("lastAttemptAtMs", transcriptionLastAttemptAtMs.get(callId));
        out.put("lastStatus", transcriptionLastStatus.get(callId));
        out.put("lastDetail", transcriptionLastDetail.get(callId));
        out.put("lastStartSource", transcriptionLastStartSource.get(callId));
        out.put("lastStartAtMs", transcriptionLastStartAtMs.get(callId));
        out.put("lastStartStatus", transcriptionLastStartStatus.get(callId));
        out.put("lastStartDetail", transcriptionLastStartDetail.get(callId));

        if (meetingId != null && !meetingId.isBlank()) {
            final String liveStatus = queryMeetingTranscriptionStatusSummary(meetingId);
            if (liveStatus != null && !liveStatus.isBlank()) {
                out.put("liveStatusProbe", liveStatus);
            }
        }

        return out;
    }

    // ================================================================
    // PRIVATE HELPERS
    // ================================================================

    private Map<String, Object> getCachedAttendeeCredentials(final String callId, final String userId) {
        final Map<String, Map<String, Object>> perCall = attendeeCredentials.get(callId);
        return perCall != null ? perCall.get(userId) : null;
    }

    private void cacheAttendeeCredentials(
            final String callId, final String userId, final Map<String, Object> credentials) {
        attendeeCredentials.computeIfAbsent(callId, k -> new ConcurrentHashMap<>()).put(userId, credentials);
    }

    private Map<String, Object> buildMeetingResponse(final Meeting meeting) {
        return Map.of(
            "meetingId",         meeting.meetingId(),
            "externalMeetingId", meeting.externalMeetingId(),
            "mediaRegion",       meeting.mediaRegion()
        );
    }

    private String toChimeExternalUserId(final String userId, final String role, final String displayName) {
        // Sanitize the numeric/string user-id portion
        String normalizedId = userId == null ? "u0" : userId.trim();
        if (normalizedId.isEmpty()) {
            normalizedId = "u0";
        }
        normalizedId = normalizedId.replaceAll("[^A-Za-z0-9_-]", "_");
        if (normalizedId.length() < CHIME_USER_ID_MIN_LENGTH) {
            normalizedId = "u" + normalizedId;
        }

        // Build a name segment encoded as "First-LAST" (hyphen-delimited, no spaces).
        // Transcript events carry externalUserId back to the frontend, so the Flutter
        // client can decode it into a human-readable label like "John DOE".
        final String nameSeg = buildNameSegment(displayName);
        final String safeRole = role != null
                ? role.trim().toUpperCase(Locale.ROOT).replaceAll("[^A-Z0-9]", "")
                : "";

        final String combined;
        if (!safeRole.isEmpty() && !nameSeg.isEmpty()) {
            combined = safeRole + "_" + nameSeg + "_" + normalizedId;
        } else if (!safeRole.isEmpty()) {
            combined = safeRole + "_" + normalizedId;
        } else {
            combined = normalizedId;
        }

        return combined.length() > CHIME_USER_ID_MAX_LENGTH
                ? combined.substring(0, CHIME_USER_ID_MAX_LENGTH)
                : combined;
    }

    /**
     * Builds a hyphen-delimited name segment for embedding in externalUserId.
     * "John Doe" → "John-DOE"; "John" → "John"; null/blank → ""
     */
    private String buildNameSegment(final String displayName) {
        if (displayName == null || displayName.isBlank()) {
            return "";
        }
        final String[] parts = displayName.trim().split("\\s+");
        if (parts.length == 0) {
            return "";
        }
        // Keep only alphanumeric chars per part; first name title-case, last name upper-case
        final String firstName = parts[0].replaceAll("[^A-Za-z0-9]", "");
        if (firstName.isEmpty()) {
            return "";
        }
        final String firstCased = firstName.substring(0, 1).toUpperCase(Locale.ROOT)
                + (firstName.length() > 1 ? firstName.substring(1).toLowerCase(Locale.ROOT) : "");
        if (parts.length == 1) {
            return firstCased;
        }
        final String lastName = parts[parts.length - 1].replaceAll("[^A-Za-z0-9]", "").toUpperCase(Locale.ROOT);
        return lastName.isEmpty() ? firstCased : firstCased + "-" + lastName;
    }

    private boolean isAwsChimeAvailable() {
        return awsEnabled && chimeSdkMeetingsClient != null;
    }

    private void ensureMeetingTranscriptionStarted(
            final String callId, final Meeting meeting, final String source) {
        if (!transcriptionEnabled || !isAwsChimeAvailable()) {
            final String reason = !transcriptionEnabled
                    ? "transcription.disabled" : "aws.chime.unavailable";
            recordTranscriptionAttempt(callId, source, "SKIPPED", reason);
            return;
        }

        if (Boolean.TRUE.equals(transcriptionStarted.get(callId))) {
            recordTranscriptionAttempt(callId, source, "ALREADY_STARTED", null);
            logMeetingTranscriptionStatus(callId, meeting.meetingId(), source + ":already-started");
            return;
        }

        try {
            final StartMeetingTranscriptionRequest request =
                    StartMeetingTranscriptionRequest.builder()
                    .meetingId(meeting.meetingId())
                    .transcriptionConfiguration(
                            TranscriptionConfiguration.builder()
                                    .engineTranscribeSettings(
                                            EngineTranscribeSettings.builder()
                                                    .languageCode(transcriptionLanguageCode)
                                                    .region(transcriptionRegion)
                                                    .build())
                                    .build())
                    .build();

            final StartMeetingTranscriptionResponse response =
                    chimeSdkMeetingsClient.startMeetingTranscription(request);
            final String responseSummary = response == null ? "null" : response.toString();
            transcriptionStarted.put(callId, true);
            recordTranscriptionAttempt(callId, source, "STARTED", responseSummary);
            recordTranscriptionStartAttempt(callId, source, "STARTED", responseSummary);
            if (log.isInfoEnabled()) {
                log.info(
                    "Started Chime transcription for callId={} meetingId={} "
                        + "language={} region={} source={} response={}",
                    callId,
                    meeting.meetingId(),
                    transcriptionLanguageCode,
                    transcriptionRegion,
                    source,
                    responseSummary);
            }
            logMeetingTranscriptionStatus(callId, meeting.meetingId(), source + ":post-start");
        } catch (Exception e) {
            final String detail = e.getClass().getSimpleName() + ": " + e.getMessage();
            recordTranscriptionAttempt(callId, source, "START_FAILED", detail);
            recordTranscriptionStartAttempt(callId, source, "START_FAILED", detail);
            if (log.isWarnEnabled()) {
                log.warn(
                    "Could not start Chime transcription for callId={} meetingId={} source={}: {}. "
                        + "Verify Chime StartMeetingTranscription permission and "
                        + "Transcribe service-linked role.",
                    callId,
                    meeting.meetingId(),
                    source,
                    detail);
            }
        }
    }

    private void recordTranscriptionAttempt(
            final String callId, final String source,
            final String status, final String detail) {
        transcriptionLastSource.put(callId, source);
        transcriptionLastAttemptAtMs.put(callId, System.currentTimeMillis());
        transcriptionLastStatus.put(callId, status);
        if (detail == null || detail.isBlank()) {
            transcriptionLastDetail.remove(callId);
        } else {
            transcriptionLastDetail.put(callId, detail);
        }
    }

    private void recordTranscriptionStartAttempt(
            final String callId, final String source,
            final String status, final String detail) {
        transcriptionLastStartSource.put(callId, source);
        transcriptionLastStartAtMs.put(callId, System.currentTimeMillis());
        transcriptionLastStartStatus.put(callId, status);
        if (detail == null || detail.isBlank()) {
            transcriptionLastStartDetail.remove(callId);
        } else {
            transcriptionLastStartDetail.put(callId, detail);
        }
    }

    private void logMeetingTranscriptionStatus(
            final String callId, final String meetingId, final String source) {
        final String summary = queryMeetingTranscriptionStatusSummary(meetingId);
        if (summary == null) {
            return;
        }

        recordTranscriptionAttempt(callId, source, "STATUS_PROBE", summary);
        log.info(
                "Chime transcription status callId={} meetingId={} source={} response={}",
                callId,
                meetingId,
                source,
                summary);
    }

    private String queryMeetingTranscriptionStatusSummary(final String meetingId) {
        try {
            // Some AWS SDK versions do not expose getMeetingTranscription APIs.
            // Use reflection so this code remains compatible across versions.
            final Class<?> requestClass = Class.forName(
                "software.amazon.awssdk.services.chimesdkmeetings.model"
                    + ".GetMeetingTranscriptionRequest");
            final Object requestBuilder = requestClass.getMethod("builder").invoke(null);
            requestBuilder.getClass()
                    .getMethod("meetingId", String.class)
                    .invoke(requestBuilder, meetingId);
            final Object request = requestBuilder.getClass()
                    .getMethod("build").invoke(requestBuilder);

            final Object statusResponse = chimeSdkMeetingsClient
                    .getClass()
                    .getMethod("getMeetingTranscription", requestClass)
                    .invoke(chimeSdkMeetingsClient, request);

            return String.valueOf(statusResponse);
        } catch (ClassNotFoundException notSupportedBySdk) {
            return "STATUS_API_UNAVAILABLE_IN_SDK";
        } catch (Exception statusErr) {
            return "STATUS_QUERY_FAILED: " + statusErr.getMessage();
        }
    }

}
