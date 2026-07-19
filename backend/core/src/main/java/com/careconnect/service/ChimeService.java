package com.careconnect.service;

import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.repository.CallSessionRepository;
import lombok.extern.slf4j.Slf4j;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import software.amazon.awssdk.services.chimesdkmeetings.ChimeSdkMeetingsClient;
import software.amazon.awssdk.services.chimesdkmeetings.model.Attendee;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateAttendeeRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateAttendeeResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateMeetingResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.DeleteAttendeeRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.DeleteMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.EngineTranscribeSettings;
import software.amazon.awssdk.services.chimesdkmeetings.model.GetMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.ListAttendeesRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.ListAttendeesResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.Meeting;
import software.amazon.awssdk.services.chimesdkmeetings.model.StartMeetingTranscriptionRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.StartMeetingTranscriptionResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.TranscriptionConfiguration;

import java.util.HashMap;
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
    private final CallSessionRepository callSessionRepository;
    private final CallParticipantRepository callParticipantRepository;
    private final TransactionTemplate transactionTemplate;

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

    /** Per attendee locks prevent duplicate local requests while the durable lock coordinates nodes. */
    private final Map<String, Object> attendeeCreationLocks = new ConcurrentHashMap<>();

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

    /** Lease window for durable attendee-creation ownership (covers slow AWS list/create). */
    private static final long ATTENDEE_CLAIM_LEASE_SECONDS = 120L;

    @Autowired
    public ChimeService(
            @Autowired(required = false) final ChimeSdkMeetingsClient chimeSdkMeetingsClient,
            final CallSessionRepository callSessionRepository,
            final CallParticipantRepository callParticipantRepository,
            final PlatformTransactionManager transactionManager,
            @Value("${careconnect.aws.enabled:true}") final boolean awsEnabled,
            @Value("${careconnect.chime.transcription.enabled:true}") final boolean transcriptionEnabled,
            @Value("${careconnect.chime.transcription.language-code:en-US}")
                final String transcriptionLanguageCode,
            @Value("${careconnect.chime.transcription.region:us-east-1}")
                final String transcriptionRegion) {
        this.chimeSdkMeetingsClient = chimeSdkMeetingsClient;
        this.callSessionRepository = callSessionRepository;
        this.callParticipantRepository = callParticipantRepository;
        this.transactionTemplate = transactionManager == null
                ? null
                : new TransactionTemplate(transactionManager);
        this.awsEnabled = awsEnabled;
        this.transcriptionEnabled = transcriptionEnabled;
        this.transcriptionLanguageCode = transcriptionLanguageCode;
        this.transcriptionRegion = transcriptionRegion;
    }

    /** Compatibility constructor for isolated unit tests. */
    ChimeService(
            final ChimeSdkMeetingsClient chimeSdkMeetingsClient,
            final boolean awsEnabled,
            final boolean transcriptionEnabled,
            final String transcriptionLanguageCode,
            final String transcriptionRegion) {
        this(
                chimeSdkMeetingsClient,
                null,
                null,
                null,
                awsEnabled,
                transcriptionEnabled,
                transcriptionLanguageCode,
                transcriptionRegion);
    }

    /** Compatibility constructor used by multi-node unit tests. */
    ChimeService(
            final ChimeSdkMeetingsClient chimeSdkMeetingsClient,
            final CallSessionRepository callSessionRepository,
            final boolean awsEnabled,
            final boolean transcriptionEnabled,
            final String transcriptionLanguageCode,
            final String transcriptionRegion) {
        this(
                chimeSdkMeetingsClient,
                callSessionRepository,
                null,
                null,
                awsEnabled,
                transcriptionEnabled,
                transcriptionLanguageCode,
                transcriptionRegion);
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
        requireJoinableSession(callId);

        // This cache is an optimization only. The durable session and AWS's
        // deterministic idempotency token coordinate concurrent callers/nodes.
        if (activeMeetings.containsKey(callId)) {
            log.info("Meeting already exists for callId: {}", callId);
            return buildMeetingResponse(activeMeetings.get(callId));
        }

        final Meeting durableMeeting = hydrateDurableMeeting(callId);
        if (durableMeeting != null) {
            activeMeetings.put(callId, durableMeeting);
            return buildMeetingResponse(durableMeeting);
        }

        if (!isAwsChimeAvailable()) {
            final Meeting localMeeting = Meeting.builder()
                    .meetingId("local-" + deterministicToken(callId))
                    .externalMeetingId(callId)
                    .mediaRegion(DEFAULT_MEDIA_REGION)
                    .build();
            if (!persistMeetingId(callId, localMeeting.meetingId())) {
                compensateCreatedMeeting(callId, localMeeting.meetingId());
                throw new IllegalStateException("Call became non-joinable while creating meeting");
            }
            activeMeetings.put(callId, localMeeting);
            log.warn("AWS Chime unavailable/disabled; created local mock meeting for callId: {}",
                    callId);
            return buildMeetingResponse(localMeeting);
        }

        try {
            final CreateMeetingRequest request = CreateMeetingRequest.builder()
                    .clientRequestToken(deterministicToken(callId))
                    .mediaRegion(DEFAULT_MEDIA_REGION)
                    .externalMeetingId(callId)
                    .build();

            final CreateMeetingResponse response = chimeSdkMeetingsClient.createMeeting(request);
            final Meeting meeting = response.meeting();

            if (!persistMeetingId(callId, meeting.meetingId())) {
                compensateCreatedMeeting(callId, meeting.meetingId());
                throw new IllegalStateException("Call became non-joinable while creating meeting");
            }
            // Store only as a local response/credential optimization.
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
     * <p>Durable claim/finalize transactions never wrap AWS list/create calls.
     *
     * @param callId the unique call identifier
     * @param userId the user to add as an attendee
     * @return attendee credentials map
     */
    public Map<String, Object> createAttendee(
            final String callId,
            final String userId,
            final String role,
            final String displayName) {
        log.info("Creating Chime attendee for userId: {} in callId: {}", userId, callId);
        // role/displayName retained for public join signature compatibility; never embedded in Chime IDs.
        final String attendeeKey = callId + "\u0000" + userId;
        final Object localLock = attendeeCreationLocks.computeIfAbsent(
                attendeeKey, ignored -> new Object());
        synchronized (localLock) {
            try {
                return createAttendeeCoordinated(callId, userId);
            } finally {
                attendeeCreationLocks.remove(attendeeKey, localLock);
            }
        }
    }

    private Map<String, Object> createAttendeeCoordinated(
            final String callId,
            final String userId) {
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

        final String externalUserId = toOpaqueChimeExternalUserId(callId, userId);
        final AttendeeClaim claim = claimAttendeeCreation(callId, userId, externalUserId);
        if (claim != null && claim.existingCredentials() != null) {
            cacheAttendeeCredentials(callId, userId, claim.existingCredentials());
            return claim.existingCredentials();
        }

        if (!isAwsChimeAvailable()) {
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
            return finalizeOrCompensate(
                    callId, userId, claim, meeting.meetingId(), credentials, false);
        }

        try {
            // AWS list/create intentionally runs outside any DB row-lock transaction.
            final Attendee existing = findAttendee(meeting.meetingId(), externalUserId);
            final Attendee attendee;
            final boolean createdHere;
            if (existing != null) {
                attendee = existing;
                createdHere = false;
            } else {
                final CreateAttendeeRequest request = CreateAttendeeRequest.builder()
                        .meetingId(meeting.meetingId())
                        .externalUserId(externalUserId)
                        .build();
                final CreateAttendeeResponse response = chimeSdkMeetingsClient.createAttendee(request);
                attendee = response.attendee();
                createdHere = true;
            }

            if (log.isInfoEnabled()) {
                log.info("Chime attendee ready: {} for userId: {}", attendee.attendeeId(), userId);
            }

            ensureMeetingTranscriptionStarted(callId, meeting, "createAttendee");

            final Map<String, Object> credentials = buildAttendeeCredentials(meeting, attendee);
            return finalizeOrCompensate(
                    callId, userId, claim, meeting.meetingId(), credentials, createdHere);
        } catch (Exception e) {
            if (claim != null && claim.claimToken() != null) {
                releaseAttendeeClaim(callId, userId, claim.claimToken());
            }
            log.error("Failed to create attendee for userId: {} in callId: {}", userId, callId, e);
            throw new RuntimeException("Failed to join video call: " + e.getMessage(), e);
        }
    }

    private record AttendeeClaim(
            Long sessionId,
            Long userId,
            UUID claimToken,
            Map<String, Object> existingCredentials) {
    }

    private AttendeeClaim claimAttendeeCreation(
            final String callId, final String userId, final String externalUserId) {
        if (callSessionRepository == null
                || callParticipantRepository == null
                || transactionTemplate == null) {
            requireJoinableWithoutLock(callId);
            return null;
        }
        return transactionTemplate.execute(status -> {
            final CallSession locked = callSessionRepository.findByCallIdForLifecycle(callId)
                    .orElseThrow(() -> new IllegalStateException("Call session does not exist"));
            if (!isJoinableStatus(locked.getStatus())) {
                throw new IllegalStateException("Call is no longer joinable");
            }
            final Long parsedUserId = Long.parseLong(userId);
            final CallParticipant participant = callParticipantRepository
                    .findByCallSessionIdAndUserId(locked.getId(), parsedUserId)
                    .orElseThrow(() -> new IllegalStateException(
                            "User is not a durable call participant"));
            if (participant.getChimeAttendeeId() != null
                    && participant.getChimeJoinToken() != null) {
                final Meeting meeting = activeMeetings.get(callId);
                final Map<String, Object> existing = buildPersistedCredentials(meeting, participant);
                return new AttendeeClaim(locked.getId(), parsedUserId, null, existing);
            }
            final UUID claimToken = UUID.randomUUID();
            final LocalDateTime now = LocalDateTime.now(ZoneOffset.UTC);
            final LocalDateTime until = now.plusSeconds(ATTENDEE_CLAIM_LEASE_SECONDS);
            final int claimed = callParticipantRepository.claimAttendeeCreation(
                    locked.getId(),
                    parsedUserId,
                    claimToken,
                    until,
                    externalUserId,
                    now);
            if (claimed == 1) {
                return new AttendeeClaim(locked.getId(), parsedUserId, claimToken, null);
            }
            final CallParticipant refreshed = callParticipantRepository
                    .findByCallSessionIdAndUserId(locked.getId(), parsedUserId)
                    .orElseThrow(() -> new IllegalStateException(
                            "User is not a durable call participant"));
            if (refreshed.getChimeAttendeeId() != null && refreshed.getChimeJoinToken() != null) {
                final Meeting meeting = activeMeetings.get(callId);
                return new AttendeeClaim(
                        locked.getId(),
                        parsedUserId,
                        null,
                        buildPersistedCredentials(meeting, refreshed));
            }
            throw new IllegalStateException("Attendee creation is already in progress");
        });
    }

    private Map<String, Object> buildPersistedCredentials(
            final Meeting meeting, final CallParticipant participant) {
        if (meeting == null) {
            return Map.of(
                    "meetingId", "",
                    "externalMeetingId", "",
                    "mediaRegion", DEFAULT_MEDIA_REGION,
                    "mediaPlacement", Map.of(
                            "audioHostUrl", "",
                            "audioFallbackUrl", "",
                            "screenDataUrl", "",
                            "screenSharingUrl", "",
                            "screenViewingUrl", "",
                            "signalingUrl", "",
                            "turnControlUrl", "",
                            "eventIngestionUrl", ""),
                    "attendeeId", participant.getChimeAttendeeId(),
                    "externalUserId", participant.getChimeExternalUserId(),
                    "joinToken", participant.getChimeJoinToken());
        }
        final String eventIngestionUrl = meeting.mediaPlacement() != null
                && meeting.mediaPlacement().eventIngestionUrl() != null
                ? meeting.mediaPlacement().eventIngestionUrl() : "";
        final Map<String, Object> mediaPlacement = meeting.mediaPlacement() == null
                ? Map.of(
                    "audioHostUrl", "",
                    "audioFallbackUrl", "",
                    "screenDataUrl", "",
                    "screenSharingUrl", "",
                    "screenViewingUrl", "",
                    "signalingUrl", "",
                    "turnControlUrl", "",
                    "eventIngestionUrl", "")
                : Map.of(
                    "audioHostUrl", meeting.mediaPlacement().audioHostUrl(),
                    "audioFallbackUrl", meeting.mediaPlacement().audioFallbackUrl(),
                    "screenDataUrl", meeting.mediaPlacement().screenDataUrl(),
                    "screenSharingUrl", meeting.mediaPlacement().screenSharingUrl(),
                    "screenViewingUrl", meeting.mediaPlacement().screenViewingUrl(),
                    "signalingUrl", meeting.mediaPlacement().signalingUrl(),
                    "turnControlUrl", meeting.mediaPlacement().turnControlUrl(),
                    "eventIngestionUrl", eventIngestionUrl);
        return Map.of(
                "meetingId", meeting.meetingId(),
                "externalMeetingId", meeting.externalMeetingId(),
                "mediaRegion", meeting.mediaRegion() == null
                        ? DEFAULT_MEDIA_REGION : meeting.mediaRegion(),
                "mediaPlacement", mediaPlacement,
                "attendeeId", participant.getChimeAttendeeId(),
                "externalUserId",
                        participant.getChimeExternalUserId() == null
                                ? "" : participant.getChimeExternalUserId(),
                "joinToken", participant.getChimeJoinToken());
    }

    private Map<String, Object> finalizeOrCompensate(
            final String callId,
            final String userId,
            final AttendeeClaim claim,
            final String meetingId,
            final Map<String, Object> credentials,
            final boolean createdHere) {
        if (claim == null || claim.claimToken() == null
                || callParticipantRepository == null
                || transactionTemplate == null) {
            cacheAttendeeCredentials(callId, userId, credentials);
            return credentials;
        }
        final Integer finalized = transactionTemplate.execute(status ->
                callParticipantRepository.finalizeAttendeeCreation(
                        claim.sessionId(),
                        claim.userId(),
                        claim.claimToken(),
                        String.valueOf(credentials.get("externalUserId")),
                        String.valueOf(credentials.get("attendeeId")),
                        String.valueOf(credentials.get("joinToken"))));
        if (finalized != null && finalized == 1) {
            cacheAttendeeCredentials(callId, userId, credentials);
            return credentials;
        }
        // Lost ownership after AWS create. Only delete an attendee we created when it is
        // not the durable winner's id (a peer may have listed+finalized the same AWS attendee).
        releaseAttendeeClaim(callId, userId, claim.claimToken());
        final CallParticipant winner = callParticipantRepository
                .findByCallSessionIdAndUserId(claim.sessionId(), claim.userId())
                .orElse(null);
        final String createdAttendeeId = String.valueOf(credentials.get("attendeeId"));
        if (createdHere) {
            final boolean winnerOwnsCreated = winner != null
                    && createdAttendeeId.equals(winner.getChimeAttendeeId());
            if (!winnerOwnsCreated) {
                compensateCreatedAttendee(meetingId, createdAttendeeId);
            }
        }
        if (winner != null
                && winner.getChimeAttendeeId() != null
                && winner.getChimeJoinToken() != null) {
            final Map<String, Object> existing =
                    buildPersistedCredentials(activeMeetings.get(callId), winner);
            cacheAttendeeCredentials(callId, userId, existing);
            return existing;
        }
        throw new IllegalStateException("Attendee creation is already in progress");
    }

    private void releaseAttendeeClaim(
            final String callId, final String userId, final UUID claimToken) {
        if (callParticipantRepository == null
                || transactionTemplate == null
                || claimToken == null
                || callSessionRepository == null) {
            return;
        }
        transactionTemplate.executeWithoutResult(status -> {
            final CallSession session = callSessionRepository.findByCallId(callId).orElse(null);
            if (session == null) {
                return;
            }
            callParticipantRepository.releaseAttendeeClaim(
                    session.getId(), Long.parseLong(userId), claimToken);
        });
    }

    private void compensateCreatedAttendee(final String meetingId, final String attendeeId) {
        if (!isAwsChimeAvailable() || meetingId == null || attendeeId == null) {
            return;
        }
        try {
            chimeSdkMeetingsClient.deleteAttendee(
                    DeleteAttendeeRequest.builder()
                            .meetingId(meetingId)
                            .attendeeId(attendeeId)
                            .build());
        } catch (Exception e) {
            log.error(
                    "Failed to compensate Chime attendee {} in meeting {}",
                    attendeeId,
                    meetingId,
                    e);
        }
    }

    private void requireJoinableWithoutLock(final String callId) {
        if (callSessionRepository == null) {
            return;
        }
        final CallSession session = callSessionRepository.findByCallId(callId)
                .orElseThrow(() -> new IllegalStateException("Call session does not exist"));
        if (!isJoinableStatus(session.getStatus())) {
            throw new IllegalStateException("Call is no longer joinable");
        }
    }

    private Attendee findAttendee(final String meetingId, final String externalUserId) {
        String nextToken = null;
        do {
            final ListAttendeesRequest.Builder request =
                    ListAttendeesRequest.builder().meetingId(meetingId);
            if (nextToken != null) {
                request.nextToken(nextToken);
            }
            final ListAttendeesResponse response =
                    chimeSdkMeetingsClient.listAttendees(request.build());
            if (response == null) {
                return null;
            }
            final Attendee existing = response.attendees().stream()
                    .filter(attendee -> externalUserId.equals(attendee.externalUserId()))
                    .findFirst()
                    .orElse(null);
            if (existing != null) {
                return existing;
            }
            nextToken = response.nextToken();
        } while (nextToken != null && !nextToken.isBlank());
        return null;
    }

    private Map<String, Object> buildAttendeeCredentials(
            final Meeting meeting, final Attendee attendee) {
        final String mediaRegion = meeting.mediaRegion() == null
                ? DEFAULT_MEDIA_REGION : meeting.mediaRegion();
        final String eventIngestionUrl = meeting.mediaPlacement() != null
                && meeting.mediaPlacement().eventIngestionUrl() != null
                ? meeting.mediaPlacement().eventIngestionUrl() : "";
        final Map<String, Object> mediaPlacement = meeting.mediaPlacement() == null
                ? Map.of(
                    "audioHostUrl", "",
                    "audioFallbackUrl", "",
                    "screenDataUrl", "",
                    "screenSharingUrl", "",
                    "screenViewingUrl", "",
                    "signalingUrl", "",
                    "turnControlUrl", "",
                    "eventIngestionUrl", "")
                : Map.of(
                    "audioHostUrl", meeting.mediaPlacement().audioHostUrl(),
                    "audioFallbackUrl", meeting.mediaPlacement().audioFallbackUrl(),
                    "screenDataUrl", meeting.mediaPlacement().screenDataUrl(),
                    "screenSharingUrl", meeting.mediaPlacement().screenSharingUrl(),
                    "screenViewingUrl", meeting.mediaPlacement().screenViewingUrl(),
                    "signalingUrl", meeting.mediaPlacement().signalingUrl(),
                    "turnControlUrl", meeting.mediaPlacement().turnControlUrl(),
                    "eventIngestionUrl", eventIngestionUrl);
        return Map.of(
            "meetingId",         meeting.meetingId(),
            "externalMeetingId", meeting.externalMeetingId(),
            "mediaRegion",       mediaRegion,
            "mediaPlacement",    mediaPlacement,
            "attendeeId",     attendee.attendeeId(),
            "externalUserId", attendee.externalUserId(),
            "joinToken",      attendee.joinToken()
        );
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
    public Map<String, Object> joinMeeting(
            final String callId,
            final String userId,
            final String role,
            final String displayName) {
        // Always resolve via createMeeting. AWS returns the same meeting for the
        // deterministic token, which hydrates a node that has no local cache.
        createMeeting(callId);
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
        final String durableMeetingId = meeting == null ? getDurableMeetingId(callId) : meeting.meetingId();
        if (durableMeetingId == null) {
            recordTranscriptionAttempt(callId, "endMeeting", "MEETING_ENDED", "no-active-meeting");
            log.warn("No active meeting found for callId: {} — may have already ended", callId);
            return;
        }

        transcriptionLastMeetingId.put(callId, durableMeetingId);
        recordTranscriptionAttempt(
                callId, "endMeeting", "MEETING_ENDED", "meetingId=" + durableMeetingId);

        if (!isAwsChimeAvailable()) {
            log.info("Ended local mock meeting for callId: {}", callId);
            return;
        }

        try {
            final DeleteMeetingRequest request = DeleteMeetingRequest.builder()
                    .meetingId(durableMeetingId)
                    .build();

            chimeSdkMeetingsClient.deleteMeeting(request);
            if (log.isInfoEnabled()) {
                log.info("Chime meeting deleted: {} for callId: {}", durableMeetingId, callId);
            }

        } catch (software.amazon.awssdk.services.chimesdkmeetings.model.ChimeSdkMeetingsException e) {
            if (e.statusCode() == 404) {
                log.info("Chime meeting {} was already absent", durableMeetingId);
                return;
            }
            throw new RuntimeException("Retryable failure deleting Chime meeting", e);
        } catch (Exception e) {
            throw new RuntimeException("Retryable failure deleting Chime meeting", e);
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
        if (callSessionRepository != null) {
            return callSessionRepository.findByCallId(callId)
                    .filter(s -> CallSessionService.SESSION_ACTIVE.equals(s.getStatus()))
                    .map(CallSession::getChimeMeetingId)
                    .filter(id -> !id.isBlank())
                    .isPresent();
        }
        return activeMeetings.containsKey(callId);
    }

    /**
     * Returns the Chime meeting ID for the given callId, or null if none.
     *
     * @param callId the unique call identifier
     * @return Chime meeting ID or null
     */
    public final String getMeetingId(final String callId) {
        final String durable = getDurableMeetingId(callId);
        if (durable != null) {
            return durable;
        }
        final Meeting meeting = activeMeetings.get(callId);
        return meeting == null ? null : meeting.meetingId();
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
                ? meeting.meetingId()
                : (getDurableMeetingId(callId) != null
                    ? getDurableMeetingId(callId)
                    : transcriptionLastMeetingId.get(callId));

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

    private String deterministicToken(final String callId) {
        return UUID.nameUUIDFromBytes(
                ("careconnect-chime:" + callId).getBytes(StandardCharsets.UTF_8)).toString();
    }

    private boolean persistMeetingId(final String callId, final String meetingId) {
        if (callSessionRepository == null) {
            return true;
        }
        final int updated = callSessionRepository.persistMeetingIdIfAbsent(
                callId,
                meetingId,
                CallSessionService.SESSION_CREATED,
                CallSessionService.SESSION_ACTIVE);
        if (updated == 1) {
            return true;
        }
        final CallSession session = callSessionRepository.findByCallId(callId).orElse(null);
        if (session == null || !isJoinableStatus(session.getStatus())) {
            if (session != null
                    && CallSessionService.SESSION_TERMINATING.equals(session.getStatus())) {
                callSessionRepository.attachMeetingToTermination(
                        callId, meetingId, CallSessionService.SESSION_TERMINATING);
            }
            return false;
        }
        final String persisted = session.getChimeMeetingId();
        if (persisted != null && !persisted.equals(meetingId)) {
            throw new IllegalStateException("Call session is already bound to another Chime meeting");
        }
        return meetingId.equals(persisted);
    }

    private String getDurableMeetingId(final String callId) {
        if (callSessionRepository == null) {
            return null;
        }
        return callSessionRepository.findByCallId(callId)
                .map(CallSession::getChimeMeetingId)
                .filter(id -> !id.isBlank())
                .orElse(null);
    }

    private Meeting hydrateDurableMeeting(final String callId) {
        final String meetingId = getDurableMeetingId(callId);
        if (meetingId == null || !isAwsChimeAvailable()) {
            return null;
        }
        try {
            return chimeSdkMeetingsClient.getMeeting(
                    GetMeetingRequest.builder().meetingId(meetingId).build()).meeting();
        } catch (software.amazon.awssdk.services.chimesdkmeetings.model.ChimeSdkMeetingsException e) {
            if (e.statusCode() == 404) {
                callSessionRepository.clearMeetingId(callId, meetingId);
                return null;
            }
            throw new RuntimeException("Failed to probe durable Chime meeting", e);
        }
    }

    private void requireJoinableSession(final String callId) {
        if (callSessionRepository == null) {
            return;
        }
        final CallSession session = callSessionRepository.findByCallId(callId)
                .orElseThrow(() -> new IllegalStateException("Call session does not exist"));
        if (!isJoinableStatus(session.getStatus())) {
            throw new IllegalStateException("Call is no longer joinable");
        }
    }

    private boolean isJoinableStatus(final String status) {
        return CallSessionService.SESSION_CREATED.equals(status)
                || CallSessionService.SESSION_ACTIVE.equals(status);
    }

    private void compensateCreatedMeeting(final String callId, final String meetingId) {
        activeMeetings.remove(callId);
        attendeeCredentials.remove(callId);
        if (!isAwsChimeAvailable()) {
            return;
        }
        try {
            chimeSdkMeetingsClient.deleteMeeting(
                    DeleteMeetingRequest.builder().meetingId(meetingId).build());
        } catch (software.amazon.awssdk.services.chimesdkmeetings.model.ChimeSdkMeetingsException e) {
            if (e.statusCode() != 404) {
                log.error(
                        "Failed to compensate Chime meeting {} after call {} lost join race",
                        meetingId,
                        callId,
                        e);
            }
        } catch (RuntimeException e) {
            log.error(
                    "Failed to compensate Chime meeting {} after call {} lost join race",
                    meetingId,
                    callId,
                    e);
        }
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

    /**
     * Builds a durable opaque Chime externalUserId with no names, roles, or raw user IDs.
     */
    String toOpaqueChimeExternalUserId(final String callId, final String userId) {
        final String material = "careconnect-attendee:"
                + (callId == null ? "" : callId)
                + ":"
                + (userId == null ? "" : userId);
        final String opaque = UUID.nameUUIDFromBytes(material.getBytes(StandardCharsets.UTF_8))
                .toString();
        return opaque.length() > CHIME_USER_ID_MAX_LENGTH
                ? opaque.substring(0, CHIME_USER_ID_MAX_LENGTH)
                : opaque;
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
