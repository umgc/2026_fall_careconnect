package com.careconnect.controller;

import com.careconnect.exception.AppException;
import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.BedrockSentimentService;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
import com.careconnect.service.CallRecordingService;
import com.careconnect.service.CallSummaryService;
import com.careconnect.service.CallTelemetryService;
import com.careconnect.service.CallTranscriptService;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.ChimeService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.notifications.SnsService;
import com.careconnect.websocket.CallNotificationHandler;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v3/calls")
@Tag(name = "Calls", description = "Video call and sentiment analysis endpoints")
@SecurityRequirement(name = "Bearer Authentication")
public class CallController {

  private static final Logger log = LoggerFactory.getLogger(CallController.class);
  private static final double SILENCE_SPEECH_RATIO_THRESHOLD = 0.04;
  private static final double SILENCE_MIC_LEVEL_THRESHOLD = 0.02;
  private static final double SILENCE_VARIABILITY_THRESHOLD = 0.12;

  /** Maximum number of transcript segments allowed per request. */
  private static final int MAX_TRANSCRIPT_SEGMENTS = 200;

  /** Maximum allowed length for a callId string. */
  private static final int MAX_CALL_ID_LENGTH = 120;

  private static final String EVT_CALL_JOIN = "CALL_JOIN";
  private static final String EVT_CALL_END = "CALL_END";
  private static final String EVT_CALL_LEAVE = "CALL_LEAVE";
  private static final String EVT_CONFERENCE_INVITE = "CONFERENCE_INVITE";
  private static final String EVT_SENTIMENT_TEXT = "SENTIMENT_TEXT";
  private static final String EVT_SENTIMENT_VOICE = "SENTIMENT_VOICE";
  private static final String EVT_SENTIMENT_VIDEO = "SENTIMENT_VIDEO";
  private static final String EVT_SENTIMENT_COMBINED = "SENTIMENT_COMBINED";
  // private static final String EVT_SENTIMENT_FINAL = "SENTIMENT_FINAL";
  private static final String STATUS_SUCCESS = "SUCCESS";
  private static final String STATUS_ERROR = "ERROR";
  private static final String MSG_ACCESS_DENIED = "Access denied";
  private static final String CHANNEL_COMBINED = "COMBINED";
  private static final String CHANNEL_TEXT = "TEXT";
  private static final String CHANNEL_VOICE = "VOICE";
  private static final String CHANNEL_VIDEO = "VIDEO";

  @Autowired
  private ChimeService chimeService;
  @Autowired
  private BedrockSentimentService sentimentService;
  @Autowired
  private CallNotificationHandler callNotificationHandler;
  @Autowired
  private CallTelemetryService callTelemetryService;
  @Autowired
  private CallTranscriptService callTranscriptService;
  @Autowired
  private CallSummaryService callSummaryService;
  @Autowired
  private CallRecordingService callRecordingService;
  @Autowired
  private CaregiverPatientLinkService caregiverPatientLinkService;
  @Autowired
  private FamilyMemberService familyMemberService;
  @Autowired
  private UserRepository userRepository;
  @Autowired
  private SnsService snsService;
  @Autowired
  private Environment environment;

  private User getCurrentUser() {
    final Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
    final String userEmail = authentication.getName();
    return userRepository
        .findByEmail(userEmail)
        .orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated"));
  }

  private void ensurePatientSource(final User currentUser) {
    if (currentUser.getRole() != Role.PATIENT) {
      throw new AppException(
          HttpStatus.FORBIDDEN,
          "Only patient-origin audio/video/text can be analyzed for sentiment");
    }
  }

  private void ensureDevOrLocalMode() {
    String[] activeProfiles = environment.getActiveProfiles();
    if (activeProfiles == null || activeProfiles.length == 0) {
      activeProfiles = environment.getDefaultProfiles();
    }

    for (final String profile : activeProfiles) {
      final String normalized = profile == null ? "" : profile.trim().toLowerCase(Locale.ROOT);
      if ("dev".equals(normalized)
          || "local".equals(normalized)
          || "default".equals(normalized)
          || "test".equals(normalized)) {
        return;
      }
    }

    throw new AppException(
        HttpStatus.FORBIDDEN, "Call telemetry deletion is only available in local/dev mode");
  }

  @PostMapping("/{callId}/join")
  @Operation(summary = "Join or create a Chime meeting for a call")
  /** Handles join-call request. */
  public final ResponseEntity<Map<String, Object>> joinCall(
      @PathVariable final String callId,
      @RequestBody(required = false) final Map<String, Object> body) {
    try {
      final User currentUser = getCurrentUser();
      final boolean meetingAlreadyActive = chimeService.isMeetingActive(callId);
      final Map<String, Object> response = chimeService.joinMeeting(callId, currentUser.getId().toString(),
          currentUser.getRole().name(), getCallUserDisplayName(currentUser));
      final Map<String, Object> contextMetadata = extractCallContextMetadata(body);
      callTelemetryService.recordCallEvent(
          callId,
          EVT_CALL_JOIN,
          currentUser.getId(),
          null,
          STATUS_SUCCESS,
          mergeMetadata(
              Map.of("meetingActive", chimeService.isMeetingActive(callId)), contextMetadata),
          null);
      if (log.isInfoEnabled()) {
        log.info("User {} joined call {}", currentUser.getId(), callId);
      }
      // Auto-start a system-initiated recording when the 2nd participant joins.
      // The recording will be transcribed and deleted from S3 after the call ends.
      if (meetingAlreadyActive) {
        try {
          callRecordingService.startRecording(callId, null);
        } catch (Exception e) {
          if (log.isWarnEnabled()) {
            log.warn("Auto-recording start failed for call {}: {}", callId, e.getMessage());
          }
        }
      }
      return ResponseEntity.ok(response);
    } catch (AppException e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordCallEvent(
          callId, EVT_CALL_JOIN, actorId, null, STATUS_ERROR, Map.of(), e.getMessage());
      throw e;
    } catch (Exception e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordCallEvent(
          callId, EVT_CALL_JOIN, actorId, null, STATUS_ERROR, Map.of(), e.getMessage());
      if (log.isErrorEnabled()) {
        log.error("Failed to join call {}: {}", callId, e.getMessage(), e);
      }
      throw internalServerError("Failed to join call: " + e.getMessage(), e);
    }
  }

  // =========================================================
  // CONFERENCE: eligible invitees + add-participant invite
  // =========================================================

  @GetMapping("/{callId}/eligible-invitees")
  @Operation(summary = "Get care-circle members who can be added to an active call")
  /** Handles get-eligible-invitees request. */
  public final ResponseEntity<List<Map<String, Object>>> getEligibleInvitees(
      @PathVariable final String callId) {
    final User currentUser = getCurrentUser();
    if (currentUser.getRole() != Role.CAREGIVER) {
      throw new AppException(HttpStatus.FORBIDDEN, "Only caregivers can invite participants");
    }
    if (!chimeService.isMeetingActive(callId)) {
      throw new AppException(HttpStatus.GONE, "Call is no longer active");
    }

    final Long patientId = findPatientInCall(callId);
    if (patientId == null) {
      throw new AppException(HttpStatus.NOT_FOUND, "No patient found in this call");
    }

    final Set<Long> currentParticipantIds = resolveActiveParticipantIds(callId);

    final List<Map<String, Object>> eligible = new ArrayList<>();

    caregiverPatientLinkService.getCaregiversByPatient(patientId).stream()
        .filter(link -> !currentParticipantIds.contains(link.caregiverUserId()))
        .filter(link -> !link.caregiverUserId().equals(currentUser.getId()))
        .forEach(
            link -> {
              final Map<String, Object> entry = new LinkedHashMap<>();
              entry.put("userId", link.caregiverUserId());
              entry.put(
                  "name",
                  link.caregiverName() != null ? link.caregiverName() : link.caregiverEmail());
              entry.put("role", "CAREGIVER");
              entry.put("relationship", null);
              eligible.add(entry);
            });

    familyMemberService.getFamilyMembersByPatient(patientId).stream()
        .filter(link -> !currentParticipantIds.contains(link.familyUserId()))
        .forEach(
            link -> {
              final Map<String, Object> entry = new LinkedHashMap<>();
              entry.put("userId", link.familyUserId());
              entry.put(
                  "name",
                  link.familyMemberName() != null
                      ? link.familyMemberName()
                      : link.familyMemberEmail());
              entry.put("role", "FAMILY_MEMBER");
              entry.put("relationship", link.relationship());
              eligible.add(entry);
            });

    return ResponseEntity.ok(eligible);
  }

  @PostMapping("/{callId}/invite")
  @Operation(summary = "Add a care-circle member to an active call")
  /** Handles invite-participant request. */
  public final ResponseEntity<Map<String, Object>> inviteParticipant(
      @PathVariable final String callId, @RequestBody final Map<String, Object> body) {
    final User currentUser = getCurrentUser();
    if (currentUser.getRole() != Role.CAREGIVER) {
      throw new AppException(HttpStatus.FORBIDDEN, "Only caregivers can invite participants");
    }
    if (!chimeService.isMeetingActive(callId)) {
      throw new AppException(HttpStatus.GONE, "Call is no longer active");
    }

    final Long targetUserId = parseUserId(
        body.get("targetUserId") == null ? null : body.get("targetUserId").toString());
    if (targetUserId == null) {
      throw new AppException(HttpStatus.BAD_REQUEST, "targetUserId is required");
    }

    final User target = userRepository
        .findById(targetUserId)
        .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "User not found"));

    if (target.getRole() == Role.PATIENT) {
      throw new AppException(HttpStatus.FORBIDDEN, "Cannot add a patient to an existing call");
    }

    final Long patientId = findPatientInCall(callId);
    if (patientId == null) {
      throw new AppException(HttpStatus.NOT_FOUND, "No patient found in this call");
    }

    final boolean isLinked = target.getRole() == Role.CAREGIVER
        ? caregiverPatientLinkService.hasAccessToPatient(targetUserId, patientId)
        : familyMemberService.hasAccessToPatient(targetUserId, patientId);
    if (!isLinked) {
      throw new AppException(HttpStatus.FORBIDDEN, "User is not in this patient's care circle");
    }

    // Notify only on invite; invitee gets createAttendee on POST /join

    final Map<String, Object> invite = new HashMap<>();
    invite.put("type", "incoming-video-call");
    invite.put("senderId", currentUser.getId());
    invite.put("senderName", getCallUserDisplayName(currentUser));
    invite.put("senderEmail", currentUser.getEmail());
    invite.put("senderRole", currentUser.getRole().name());
    invite.put("callId", callId);
    invite.put("isVideoCall", true);
    invite.put("callType", "conference-invite");
    invite.put("isConferenceInvite", true);
    invite.put("timestamp", System.currentTimeMillis());
    final boolean online = callNotificationHandler.isUserOnline(targetUserId.toString());
    if (online) {
      callNotificationHandler.sendNotificationToUser(targetUserId.toString(), invite);
    } else {
      maybeSendOfflineConferenceInviteSms(currentUser, target, callId);
    }

    callTelemetryService.recordCallEvent(
        callId,
        EVT_CONFERENCE_INVITE,
        currentUser.getId(),
        targetUserId,
        online ? STATUS_SUCCESS : "OFFLINE",
        Map.of("targetRole", target.getRole().name()),
        null);

    if (log.isInfoEnabled()) {
      log.info(
          "Caregiver {} invited {} to call {} (online={})",
          currentUser.getId(),
          targetUserId,
          callId,
          online);
    }
    final String status = online ? "invited" : "offline";
    return ResponseEntity.ok(
        Map.of("status", status, "callId", callId, "targetUserId", targetUserId));
  }

  private Long findPatientInCall(String callId) {
    return callTelemetryService.getTelemetryForCall(callId).stream()
        .filter(e -> "CALL_JOIN".equals(e.getEventType()) && e.getActorUserId() != null)
        .map(e -> userRepository.findById(e.getActorUserId()).orElse(null))
        .filter(u -> u != null && u.getRole() == Role.PATIENT)
        .map(User::getId)
        .findFirst()
        .orElse(null);
  }

  private String getCallUserDisplayName(User user) {
    String name = user.getName();
    if (name != null && !name.trim().isEmpty()) {
      return name.trim();
    }
    return user.getRole().name().charAt(0)
        + user.getRole().name().substring(1).toLowerCase(Locale.ROOT);
  }

  private void maybeSendOfflineConferenceInviteSms(
      final User inviter, final User target, final String callId) {
    final String phone = target.getPhone();
    if (phone == null || phone.isBlank()) {
      return;
    }

    final String inviterName = getCallUserDisplayName(inviter);
    String message = String.format(
        "%s invited you to join a CareConnect video call. Open the app to join. Call ID: %s",
        inviterName, callId);
    if (message.length() > 160) {
      message = message.substring(0, 157) + "...";
    }

    try {
      snsService.publishSms(phone.trim(), message);
      if (log.isInfoEnabled()) {
        log.info(
            "Sent offline conference invite SMS to user {} for call {}",
            target.getId(),
            callId);
      }
    } catch (Exception e) {
      log.warn(
          "Failed to send offline conference invite SMS to user {} for call {}: {}",
          target.getId(),
          callId,
          e.getMessage());
    }
  }

  private Set<Long> resolveActiveParticipantIds(final String callId) {
    final Set<Long> activeParticipantIds = new LinkedHashSet<>();

    callTelemetryService.getTelemetryForCall(callId).stream()
        .filter(event -> event.getOccurredAt() != null)
        .sorted(Comparator.comparing(CallTelemetryEvent::getOccurredAt))
        .forEach(
            event -> {
              final Long actorUserId = event.getActorUserId();
              if (actorUserId == null) {
                return;
              }

              final String eventType = event.getEventType();
              if (EVT_CALL_JOIN.equals(eventType)) {
                activeParticipantIds.add(actorUserId);
              } else if (EVT_CALL_LEAVE.equals(eventType) || EVT_CALL_END.equals(eventType)) {
                activeParticipantIds.remove(actorUserId);
              }
            });

    return activeParticipantIds;
  }

  private Set<Long> resolvePendingInviteeIds(final String callId) {
    final Set<Long> everJoined = new LinkedHashSet<>();
    callTelemetryService.getTelemetryForCall(callId).stream()
        .filter(e -> EVT_CALL_JOIN.equals(e.getEventType()) && e.getActorUserId() != null)
        .forEach(e -> everJoined.add(e.getActorUserId()));

    final Set<Long> pending = new LinkedHashSet<>();
    callTelemetryService.getTelemetryForCall(callId).stream()
        .filter(e -> EVT_CONFERENCE_INVITE.equals(e.getEventType()) && e.getTargetUserId() != null)
        .forEach(
            e -> {
              if (!everJoined.contains(e.getTargetUserId())) {
                pending.add(e.getTargetUserId());
              }
            });
    return pending;
  }

  private Set<Long> resolveNotifyUserIds(final String callId, final Long excludeUserId) {
    final Set<Long> notifyIds = new LinkedHashSet<>(resolveActiveParticipantIds(callId));
    notifyIds.addAll(resolvePendingInviteeIds(callId));
    if (excludeUserId != null) {
      notifyIds.remove(excludeUserId);
    }
    return notifyIds;
  }

  private void mergeParticipantUserIds(
      final Set<Long> target, final Map<String, Object> body) {
    if (body == null || body.isEmpty()) {
      return;
    }
    final Object raw = body.get("participantUserIds");
    if (!(raw instanceof List<?> ids)) {
      return;
    }
    for (final Object id : ids) {
      final Long parsed = parseUserId(id == null ? null : id.toString());
      if (parsed != null) {
        target.add(parsed);
      }
    }
  }

  @PostMapping("/{callId}/end")
  @Operation(summary = "End a Chime meeting and notify all participants")
  /** Handles end-call request. */
  public final ResponseEntity<Map<String, String>> endCall(
      @PathVariable final String callId,
      @RequestParam(required = false) String otherPartyId,
      @RequestBody(required = false) final Map<String, Object> body) {
    try {
      final User currentUser = getCurrentUser();
      if ((otherPartyId == null || otherPartyId.isBlank()) && body != null) {
        final Object otherPartyRaw = body.get("otherPartyId");
        otherPartyId = otherPartyRaw == null ? null : otherPartyRaw.toString();
      }

      final Set<Long> activeParticipantIds = resolveActiveParticipantIds(callId);
      mergeParticipantUserIds(activeParticipantIds, body);
      final Long parsedOtherPartyId = parseUserId(otherPartyId);
      if (parsedOtherPartyId != null && !parsedOtherPartyId.equals(currentUser.getId())) {
        activeParticipantIds.add(parsedOtherPartyId);
      }
      activeParticipantIds.add(currentUser.getId());
      activeParticipantIds.remove(currentUser.getId());
      final boolean shouldEndMeeting = activeParticipantIds.size() <= 1;
      final Map<String, Object> contextMetadata = extractCallContextMetadata(body);

      if (shouldEndMeeting) {
        maybeRecordFinalOverallSentiment(callId, currentUser.getId(), parseUserId(otherPartyId));
        maybeGenerateAndStoreCallSummary(callId, currentUser.getId());
        callRecordingService.stopRecording(callId);
        chimeService.endMeeting(callId);
      }

      if (shouldEndMeeting) {
        final Set<Long> notifyIds = resolveNotifyUserIds(callId, currentUser.getId());
        mergeParticipantUserIds(notifyIds, body);
        if (parsedOtherPartyId != null && !parsedOtherPartyId.equals(currentUser.getId())) {
          notifyIds.add(parsedOtherPartyId);
        }
        notifyIds.stream()
            .map(String::valueOf)
            .forEach(
                participantId -> callNotificationHandler.sendNotificationToUser(
                    participantId,
                    Map.of(
                        "type",
                        "call-ended",
                        "callId",
                        callId,
                        "endedBy",
                        currentUser.getId().toString())));
      } else {
        activeParticipantIds.stream()
            .map(String::valueOf)
            .forEach(
                participantId -> callNotificationHandler.sendNotificationToUser(
                    participantId,
                    Map.of(
                        "type",
                        "participant-left",
                        "callId",
                        callId,
                        "leftBy",
                        currentUser.getId().toString(),
                        "remainingParticipantCount",
                        activeParticipantIds.size())));
      }

      final String eventType = shouldEndMeeting ? EVT_CALL_END : EVT_CALL_LEAVE;
      callTelemetryService.recordCallEvent(
          callId,
          eventType,
          currentUser.getId(),
          parseUserId(otherPartyId),
          STATUS_SUCCESS,
          mergeMetadata(
              Map.of(
                  "endedMeeting",
                  shouldEndMeeting,
                  "remainingParticipantCount",
                  activeParticipantIds.size(),
                  "notifiedOtherParty",
                  otherPartyId != null && !otherPartyId.isBlank()),
              contextMetadata),
          null);
      if (log.isInfoEnabled()) {
        log.info(
            "User {} {} call {} (remainingParticipants={}, endedMeeting={})",
            currentUser.getId(),
            shouldEndMeeting ? "ended" : "left",
            callId,
            activeParticipantIds.size(),
            shouldEndMeeting);
      }
      return ResponseEntity.ok(
          Map.of(
              "status",
              shouldEndMeeting ? "ended" : "left",
              "callId",
              callId,
              "remainingParticipantCount",
              String.valueOf(activeParticipantIds.size())));
    } catch (AppException e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordCallEvent(
          callId,
          EVT_CALL_END,
          actorId,
          parseUserId(otherPartyId),
          STATUS_ERROR,
          Map.of(),
          e.getMessage());
      throw e;
    } catch (Exception e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordCallEvent(
          callId,
          EVT_CALL_END,
          actorId,
          parseUserId(otherPartyId),
          STATUS_ERROR,
          Map.of(),
          e.getMessage());
      if (log.isErrorEnabled()) {
        log.error("Failed to end call {}: {}", callId, e.getMessage(), e);
      }
      throw internalServerError("Failed to end call: " + e.getMessage(), e);
    }
  }

  @PostMapping("/{callId}/sentiment/text")
  @Operation(summary = "Analyze sentiment from a chat message")
  /** Analyzes sentiment from a chat message for the given call. */
  public final ResponseEntity<SentimentResult> analyzeTextSentiment(
      @PathVariable final String callId, @RequestBody final Map<String, String> body) {
    final Map<String, Object> telemetryPayload = sanitizeTelemetryPayload(body);
    try {
      final User currentUser = getCurrentUser();
      ensureSentimentAllowedForCall(currentUser);
      final String text = body.get("text");
      if (text == null || text.isBlank()) {
        throw new AppException(HttpStatus.BAD_REQUEST, "text field is required");
      }
      final SentimentResult result = sentimentService.analyzeText(text, callId);
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_TEXT,
          CHANNEL_TEXT,
          currentUser.getId(),
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          result,
          Map.of(
              "textLength", text.length(),
              "captureMode", body.get("captureMode")),
          STATUS_SUCCESS,
          null);
      broadcastSentimentToCaregivers(
          callId,
          currentUser.getId().toString(),
          body.get("otherPartyId"),
          result,
          body.get("captureMode"));
      return ResponseEntity.ok(result);
    } catch (AppException e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_TEXT,
          CHANNEL_TEXT,
          actorId,
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          null,
          telemetryPayload,
          STATUS_ERROR,
          e.getMessage());
      throw e;
    } catch (Exception e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_TEXT,
          CHANNEL_TEXT,
          actorId,
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          null,
          telemetryPayload,
          STATUS_ERROR,
          e.getMessage());
      if (log.isErrorEnabled()) {
        log.error("Text sentiment failed for call {}: {}", callId, e.getMessage(), e);
      }
      throw internalServerError("Sentiment analysis failed: " + e.getMessage(), e);
    }
  }

  @PostMapping("/{callId}/sentiment/voice")
  @Operation(summary = "Analyze sentiment from an audio clip (base64 encoded)")
  /** Analyzes sentiment from voice/audio metrics for the given call. */
  public final ResponseEntity<SentimentResult> analyzeVoiceSentiment(
      @PathVariable final String callId, @RequestBody final Map<String, String> body) {
    final Map<String, Object> telemetryPayload = sanitizeTelemetryPayload(body);
    try {
      final User currentUser = getCurrentUser();
      ensureSentimentAllowedForCall(currentUser);
      final Long otherPartyUserId = parseUserId(body.get("otherPartyId"));
      final Double averageLevel = parseDouble(body.get("averageLevel"));
      final Double speechRatio = parseDouble(body.get("speechRatio"));
      final Double variability = parseDouble(body.get("variability"));

      if (averageLevel == null || speechRatio == null || variability == null) {
        throw new AppException(
            HttpStatus.BAD_REQUEST,
            "Provide Chime metrics fields: averageLevel, speechRatio, variability");
      }

      if (isSilenceWindow(averageLevel, speechRatio, variability)) {
        final SentimentResult ignored = SentimentResult.neutral("VOICE", callId, "Silence window ignored");
        if (log.isDebugEnabled()) {
          log.debug(
              "Ignoring silence voice metrics callId={} actorUserId={} avgLevel={} speechRatio={}",
              callId,
              currentUser.getId(),
              averageLevel,
              speechRatio);
        }
        broadcastQuietVoiceStateToCaregivers(
            callId,
            currentUser.getId().toString(),
            body.get("otherPartyId"),
            body.get("captureMode"));
        // Do not record/broadcast scored sentiment for ignored silence windows.
        return ResponseEntity.status(HttpStatus.ACCEPTED).body(ignored);
      }

      final SentimentResult result = sentimentService.analyzeVoiceFromChimeMetrics(
          callId, averageLevel, speechRatio, variability);
      if (log.isInfoEnabled()) {
        log.info(
            "Voice sentiment result callId={} actorUserId={} actorRole={} fallback={} label={}"
                + " score={}",
            callId,
            currentUser.getId(),
            currentUser.getRole(),
            result.fallback(),
            result.label(),
            result.score());
      }
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_VOICE,
          CHANNEL_VOICE,
          currentUser.getId(),
          otherPartyUserId,
          body.get("captureMode"),
          result,
          telemetryPayload,
          STATUS_SUCCESS,
          null);
      broadcastSentimentToCaregivers(
          callId,
          currentUser.getId().toString(),
          body.get("otherPartyId"),
          result,
          body.get("captureMode"));

      return ResponseEntity.ok(result);
    } catch (AppException e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_VOICE,
          CHANNEL_VOICE,
          actorId,
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          null,
          telemetryPayload,
          STATUS_ERROR,
          e.getMessage());
      throw e;
    } catch (Exception e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_VOICE,
          CHANNEL_VOICE,
          actorId,
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          null,
          telemetryPayload,
          STATUS_ERROR,
          e.getMessage());
      if (log.isErrorEnabled()) {
        log.error("Voice sentiment failed for call {}: {}", callId, e.getMessage(), e);
      }
      throw internalServerError("Voice sentiment analysis failed: " + e.getMessage(), e);
    }
  }

  private boolean isSilenceWindow(Double averageLevel, Double speechRatio, Double variability) {
    if (averageLevel == null || speechRatio == null || variability == null) {
      return false;
    }
    return speechRatio <= SILENCE_SPEECH_RATIO_THRESHOLD
        && averageLevel <= SILENCE_MIC_LEVEL_THRESHOLD
        && variability <= SILENCE_VARIABILITY_THRESHOLD;
  }

  private void broadcastQuietVoiceStateToCaregivers(
      final String callId,
      final String userId,
      final String otherPartyId,
      final String captureMode) {
    final Map<String, Object> notification = new HashMap<>();
    notification.put("type", "sentiment-channel-state");
    notification.put("callId", callId);
    notification.put("channel", "voice");
    notification.put("muted", false);
    notification.put("status", "QUIET");
    notification.put("notes", "No speech detected in this window.");
    notification.put("timestamp", System.currentTimeMillis());
    if (captureMode != null && !captureMode.isBlank()) {
      notification.put("captureMode", captureMode.trim().toUpperCase(Locale.ROOT));
    }

    sendSentimentToCaregiverIfEligible(userId, notification);
    sendSentimentToCaregiverIfEligible(otherPartyId, notification);
  }

  @PostMapping("/{callId}/sentiment/video")
  @Operation(summary = "Analyze sentiment from a video frame (base64 encoded image)")
  /** Analyzes sentiment from a video frame for the given call. */
  public final ResponseEntity<SentimentResult> analyzeVideoSentiment(
      @PathVariable final String callId, @RequestBody final Map<String, String> body) {
    final Map<String, Object> telemetryPayload = sanitizeTelemetryPayload(body);
    try {
      final User currentUser = getCurrentUser();
      ensureSentimentAllowedForCall(currentUser);
      final String imageBase64 = body.get("imageBase64");
      if (imageBase64 == null || imageBase64.isBlank()) {
        throw new AppException(HttpStatus.BAD_REQUEST, "imageBase64 field is required");
      }
      final String imageFormat = body.getOrDefault("imageFormat", "jpeg");
      final SentimentResult result = sentimentService.analyzeVideoFrame(imageBase64, imageFormat, callId);
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_VIDEO,
          CHANNEL_VIDEO,
          currentUser.getId(),
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          result,
          telemetryPayload,
          STATUS_SUCCESS,
          null);
      broadcastSentimentToCaregivers(
          callId,
          currentUser.getId().toString(),
          body.get("otherPartyId"),
          result,
          body.get("captureMode"));
      return ResponseEntity.ok(result);
    } catch (AppException e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_VIDEO,
          CHANNEL_VIDEO,
          actorId,
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          null,
          telemetryPayload,
          STATUS_ERROR,
          e.getMessage());
      throw e;
    } catch (Exception e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_VIDEO,
          CHANNEL_VIDEO,
          actorId,
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          null,
          telemetryPayload,
          STATUS_ERROR,
          e.getMessage());
      if (log.isErrorEnabled()) {
        log.error("Video sentiment failed for call {}: {}", callId, e.getMessage(), e);
      }
      throw internalServerError("Video sentiment analysis failed: " + e.getMessage(), e);
    }
  }

  @PostMapping("/{callId}/sentiment/combined")
  @Operation(summary = "Get combined sentiment score across all channels")
  /** Returns combined sentiment score across all channels for the given call. */
  public final ResponseEntity<Map<String, Object>> getCombinedSentiment(
      @PathVariable final String callId, @RequestBody final Map<String, String> body) {
    final Map<String, Object> telemetryPayload = sanitizeTelemetryPayload(body);
    try {
      final User currentUser = getCurrentUser();
      ensureSentimentAllowedForCall(currentUser);
      final String text = body.getOrDefault("text", "");
      final String imageBase64 = body.getOrDefault("imageBase64", "");
      final String imageFormat = body.getOrDefault("imageFormat", "jpeg");
      final Double averageLevel = parseDouble(body.get("averageLevel"));
      final Double speechRatio = parseDouble(body.get("speechRatio"));
      final Double variability = parseDouble(body.get("variability"));

      final SentimentResult textResult = text.isBlank() ? null : sentimentService.analyzeText(text, callId);
      final SentimentResult voiceResult = averageLevel == null || speechRatio == null || variability == null
          ? null
          : sentimentService.analyzeVoiceFromChimeMetrics(
              callId, averageLevel, speechRatio, variability);
      final SentimentResult videoResult = imageBase64.isBlank()
          ? null
          : sentimentService.analyzeVideoFrame(imageBase64, imageFormat, callId);
      final Map<String, Object> combined = sentimentService.buildCombinedSentiment(textResult, voiceResult, videoResult,
          callId);
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_COMBINED,
          CHANNEL_COMBINED,
          currentUser.getId(),
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          null,
          sanitizeCombinedTelemetry(combined),
          STATUS_SUCCESS,
          null);
      return ResponseEntity.ok(combined);
    } catch (AppException e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_COMBINED,
          CHANNEL_COMBINED,
          actorId,
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          null,
          telemetryPayload,
          STATUS_ERROR,
          e.getMessage());
      throw e;
    } catch (Exception e) {
      Long actorId = null;
      try {
        actorId = getCurrentUser().getId();
      } catch (Exception ignored) {
      }
      callTelemetryService.recordSentimentEvent(
          callId,
          EVT_SENTIMENT_COMBINED,
          CHANNEL_COMBINED,
          actorId,
          parseUserId(body.get("otherPartyId")),
          body.get("captureMode"),
          null,
          telemetryPayload,
          STATUS_ERROR,
          e.getMessage());
      if (log.isErrorEnabled()) {
        log.error("Combined sentiment failed for call {}: {}", callId, e.getMessage(), e);
      }
      throw internalServerError("Combined sentiment failed: " + e.getMessage(), e);
    }
  }

  @GetMapping("/{callId}/telemetry")
  @Operation(summary = "Get stored call telemetry events")
  /** Returns stored call telemetry events for the given call. */
  public final ResponseEntity<List<CallTelemetryEvent>> getCallTelemetry(
      @PathVariable final String callId) {
    final User currentUser = getCurrentUser();
    final List<CallTelemetryEvent> events = callTelemetryService.getTelemetryForCall(callId);
    final boolean isAdmin = currentUser.getRole() == Role.ADMIN;
    final boolean isParticipant = events.stream()
        .anyMatch(
            e -> currentUser.getId().equals(e.getActorUserId())
                || currentUser.getId().equals(e.getTargetUserId()));
    if (!isAdmin && !events.isEmpty() && !isParticipant) {
      throw new AppException(HttpStatus.FORBIDDEN, MSG_ACCESS_DENIED);
    }
    return ResponseEntity.ok(events);
  }

  @GetMapping("/{callId}/transcription/debug")
  @Operation(summary = "Get Chime transcription debug state for a call")
  /** Returns Chime transcription debug state for the given call. */
  public final ResponseEntity<Map<String, Object>> getTranscriptionDebugStatus(
      @PathVariable final String callId) {
    final User currentUser = getCurrentUser();
    final Map<String, Object> status = new HashMap<>(chimeService.getTranscriptionDebugStatus(callId));
    status.put("requestedByUserId", currentUser.getId());
    status.put("requestedByRole", currentUser.getRole().name());
    return ResponseEntity.ok(status);
  }

  @PostMapping("/{callId}/transcript/segments")
  @Operation(summary = "Persist transcript segments for a call")
  /** Persists transcript segments for the given call. */
  public final ResponseEntity<Map<String, Object>> saveTranscriptSegments(
      @PathVariable final String callId, @RequestBody final Map<String, Object> body) {
    if (callId == null || callId.trim().isEmpty() || callId.length() > MAX_CALL_ID_LENGTH) {
      throw new AppException(HttpStatus.BAD_REQUEST, "Invalid callId");
    }
    final User currentUser = getCurrentUser();
    final boolean isAdmin = currentUser.getRole() == Role.ADMIN;
    if (!isAdmin && !isCallParticipant(callId, currentUser.getId())) {
      throw new AppException(
          HttpStatus.FORBIDDEN, "Only call participants can persist transcript segments");
    }
    final List<CallTranscriptService.TranscriptSegmentInput> segments = extractTranscriptSegments(body);
    if (segments.size() > MAX_TRANSCRIPT_SEGMENTS) {
      throw new AppException(HttpStatus.BAD_REQUEST, "Too many transcript segments in one request");
    }
    final int saved = callTranscriptService.recordSegments(callId, currentUser.getId(), segments);
    if (log.isInfoEnabled()) {
      log.info(
          "Saved {} transcript segments for callId={} by userId={}",
          saved,
          callId,
          currentUser.getId());
    }
    return ResponseEntity.ok(
        Map.of(
            "callId", callId,
            "savedSegments", saved,
            "status", "saved"));
  }

  @GetMapping("/{callId}/summary")
  @Operation(summary = "Get latest stored call summary")
  /** Returns the latest stored call summary for the given call. */
  public final ResponseEntity<Map<String, Object>> getCallSummary(
      @PathVariable final String callId) {
    final User currentUser = getCurrentUser();
    final boolean isAdmin = currentUser.getRole() == Role.ADMIN;
    final boolean inTelemetry = callTelemetryService.getTelemetryForCall(callId).stream()
        .anyMatch(
            e -> currentUser.getId().equals(e.getActorUserId())
                || currentUser.getId().equals(e.getTargetUserId()));
    final boolean inTranscript = callTranscriptService.hasTranscriptAccess(callId, currentUser.getId());

    final Optional<com.careconnect.model.CallSummary> latestEntity = callSummaryService.getLatestSummaryEntity(callId);
    final boolean isSummaryOwner = latestEntity.map(s -> currentUser.getId().equals(s.getGeneratedByUserId()))
        .orElse(false);

    if (!isAdmin && !inTelemetry && !inTranscript && !isSummaryOwner) {
      throw new AppException(HttpStatus.FORBIDDEN, MSG_ACCESS_DENIED);
    }

    // If end-call summary ran before transcript retries landed, regenerate on read.
    if (latestEntity.isPresent()
        && "NO_TRANSCRIPT".equalsIgnoreCase(latestEntity.get().getStatus())
        && callTranscriptService.countSegments(callId) > 0) {
      final Map<String, CallTelemetryEvent> latestByChannel = callTelemetryService.getLatestSentimentByChannel(callId);
      callSummaryService.generateAndStoreSummary(callId, currentUser.getId(), latestByChannel);
    }

    return callSummaryService
        .getLatestSummary(callId)
        .map(ResponseEntity::ok)
        .orElseGet(
            () -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(
                    Map.of(
                        "callId", callId,
                        "status", "NOT_FOUND",
                        "message", "No stored summary found for this call")));
  }

  @GetMapping("/{callId}/transcript/segments")
  @Operation(summary = "Get stored transcript segments for a call")
  /** Returns stored transcript segments for the given call. */
  public final ResponseEntity<List<com.careconnect.model.CallTranscriptSegment>> getTranscriptSegments(
      @PathVariable final String callId) {
    final User currentUser = getCurrentUser();
    final boolean isAdmin = currentUser.getRole() == Role.ADMIN;
    final boolean inTelemetry = callTelemetryService.getTelemetryForCall(callId).stream()
        .anyMatch(
            e -> currentUser.getId().equals(e.getActorUserId())
                || currentUser.getId().equals(e.getTargetUserId()));
    final boolean inTranscript = callTranscriptService.hasTranscriptAccess(callId, currentUser.getId());
    if (!isAdmin && !inTelemetry && !inTranscript) {
      throw new AppException(HttpStatus.FORBIDDEN, MSG_ACCESS_DENIED);
    }
    return ResponseEntity.ok(callTranscriptService.getSegmentsForCall(callId));
  }

  @DeleteMapping("/{callId}/telemetry")
  @Operation(summary = "Delete the full stored call footprint for a call (dev/local only)")
  /**
   * Deletes the full stored call footprint for the given call (dev/local only).
   */
  public final ResponseEntity<Map<String, Object>> deleteCallTelemetry(
      @PathVariable final String callId) {
    ensureDevOrLocalMode();

    final User currentUser = getCurrentUser();
    final long deletedEvents = callTelemetryService.deleteTelemetryForCall(callId);
    final long deletedSummaries = callSummaryService.deleteSummariesForCall(callId);
    final Map<String, Long> transcriptPurge = callTranscriptService.purgeForCall(callId);
    final Map<String, Object> recordingPurge = callRecordingService.purgeRecordingsForCall(callId);

    final long deletedTranscriptSegments = (transcriptPurge.get("deletedTranscriptSegments") == null)
        ? 0L
        : transcriptPurge.get("deletedTranscriptSegments");
    final long deletedTranscriptArchives = (transcriptPurge.get("deletedTranscriptArchives") == null)
        ? 0L
        : transcriptPurge.get("deletedTranscriptArchives");
    final long deletedRecordingRows = recordingPurge.get("deletedDbRows") instanceof Number n ? n.longValue() : 0L;
    final long deletedRecordingObjects = recordingPurge.get("deletedS3Objects") instanceof Number n ? n.longValue()
        : 0L;

    if (log.isWarnEnabled()) {
      log.warn(
          "Deleted call footprint for call {} by user {} (dev/local mode): telemetry={},"
              + " summaries={}, transcriptSegments={}, transcriptArchives={}, recordingRows={},"
              + " recordingObjects={}",
          callId,
          currentUser.getId(),
          deletedEvents,
          deletedSummaries,
          deletedTranscriptSegments,
          deletedTranscriptArchives,
          deletedRecordingRows,
          deletedRecordingObjects);
    }

    final Map<String, Object> response = new LinkedHashMap<>();
    response.put("callId", callId);
    response.put("deletedEvents", deletedEvents);
    response.put("deletedSummaries", deletedSummaries);
    response.put("deletedTranscriptSegments", deletedTranscriptSegments);
    response.put("deletedTranscriptArchives", deletedTranscriptArchives);
    response.put("deletedRecordingRows", deletedRecordingRows);
    response.put("deletedRecordingS3Objects", deletedRecordingObjects);
    response.put("status", "deleted");
    return ResponseEntity.ok(response);
  }

  @DeleteMapping("/patients/{patientUserId}/telemetry")
  @Operation(summary = "Delete the full stored call footprint for a patient call history tile (dev/local only)")
  /**
   * Deletes the full stored call footprint for a patient's call history
   * (dev/local only).
   */
  public final ResponseEntity<Map<String, Object>> deletePatientCallHistory(
      @PathVariable final Long patientUserId) {
    ensureDevOrLocalMode();

    final User currentUser = getCurrentUser();
    final CallTelemetryService.PatientCallHistoryMatch match = callTelemetryService
        .findCallHistoryForPatient(patientUserId);

    long deletedSummaries = 0L;
    long deletedTranscriptSegments = 0L;
    long deletedTranscriptArchives = 0L;
    long deletedRecordingRows = 0L;
    long deletedRecordingObjects = 0L;

    for (final String callId : match.callIds()) {
      deletedSummaries += callSummaryService.deleteSummariesForCall(callId);

      final Map<String, Long> transcriptPurge = callTranscriptService.purgeForCall(callId);
      deletedTranscriptSegments += transcriptPurge.getOrDefault("deletedTranscriptSegments", 0L);
      deletedTranscriptArchives += transcriptPurge.getOrDefault("deletedTranscriptArchives", 0L);

      final Map<String, Object> recordingPurge = callRecordingService.purgeRecordingsForCall(callId);
      if (recordingPurge.get("deletedDbRows") instanceof Number deletedDbRows) {
        deletedRecordingRows += deletedDbRows.longValue();
      }
      if (recordingPurge.get("deletedS3Objects") instanceof Number deletedS3Objects) {
        deletedRecordingObjects += deletedS3Objects.longValue();
      }
    }

    final long deletedEvents = callTelemetryService.deleteTelemetryEvents(match.events());

    if (log.isWarnEnabled()) {
      log.warn(
          "Deleted patient call history for patientUserId {} by user {} (dev/local mode):"
              + " telemetry={}, calls={}, summaries={}, transcriptSegments={},"
              + " transcriptArchives={}, recordingRows={}, recordingObjects={}",
          patientUserId,
          currentUser.getId(),
          deletedEvents,
          match.callIds().size(),
          deletedSummaries,
          deletedTranscriptSegments,
          deletedTranscriptArchives,
          deletedRecordingRows,
          deletedRecordingObjects);
    }

    final Map<String, Object> response = new LinkedHashMap<>();
    response.put("patientUserId", patientUserId);
    response.put("deletedEvents", deletedEvents);
    response.put("deletedCalls", match.callIds().size());
    response.put("deletedSummaries", deletedSummaries);
    response.put("deletedTranscriptSegments", deletedTranscriptSegments);
    response.put("deletedTranscriptArchives", deletedTranscriptArchives);
    response.put("deletedRecordingRows", deletedRecordingRows);
    response.put("deletedRecordingS3Objects", deletedRecordingObjects);
    response.put("status", "deleted");
    return ResponseEntity.ok(response);
  }

  @GetMapping("/telemetry/my")
  @Operation(summary = "Get telemetry for current user participation")
  /**
   * Returns telemetry events for the currently authenticated user's call
   * participation.
   */
  public final ResponseEntity<List<CallTelemetryEvent>> getMyTelemetry() {
    final User currentUser = getCurrentUser();
    return ResponseEntity.ok(callTelemetryService.getTelemetryForUser(currentUser.getId()));
  }

  @GetMapping("/sentiment-history")
  @Operation(summary = "Get longitudinal per-call sentiment summaries for a user")
  /** Returns longitudinal per-call sentiment summaries for the given user. */
  public final ResponseEntity<List<Map<String, Object>>> getSentimentHistory(
      @RequestParam final Long userId) {
    final User currentUser = getCurrentUser();
    if (!canAccessSentimentHistory(currentUser, userId)) {
      throw new AppException(HttpStatus.FORBIDDEN, MSG_ACCESS_DENIED);
    }
    return ResponseEntity.ok(callTelemetryService.getSentimentHistoryForUser(userId));
  }

  private void broadcastSentimentToCaregivers(
      final String callId,
      final String userId,
      final String otherPartyId,
      final SentimentResult result,
      final String captureMode) {
    final Map<String, Object> notification = new HashMap<>();
    notification.put("type", "sentiment-update");
    notification.put("callId", callId);
    notification.put("sentiment", result);
    if (captureMode != null && !captureMode.isBlank()) {
      notification.put("captureMode", captureMode.trim().toUpperCase(Locale.ROOT));
    }

    sendSentimentToCaregiverIfEligible(userId, notification);
    sendSentimentToCaregiverIfEligible(otherPartyId, notification);
  }

  private void sendSentimentToCaregiverIfEligible(
      final String userId, final Map<String, Object> notification) {
    if (userId == null || userId.isBlank()) {
      return;
    }

    try {
      final Long parsedUserId = Long.parseLong(userId);
      userRepository
          .findById(parsedUserId)
          .ifPresent(
              targetUser -> {
                if (targetUser.getRole() == Role.CAREGIVER) {
                  callNotificationHandler.sendNotificationToUser(
                      targetUser.getId().toString(), notification);
                }
              });
    } catch (NumberFormatException ex) {
      if (log.isWarnEnabled()) {
        log.warn("Skipping sentiment recipient with invalid userId: {}", userId);
      }
    }
  }

  private void ensureSentimentAllowedForCall(final User currentUser) {
    ensurePatientSource(currentUser);
    // Care-team calls still allow sentiment analysis when the source is the
    // patient.
    // Non-patient participants are already blocked by ensurePatientSource.
  }

  private AppException internalServerError(final String message, final Exception cause) {
    final AppException exception = new AppException(HttpStatus.INTERNAL_SERVER_ERROR, message);
    exception.initCause(cause);
    return exception;
  }

  private Long parseUserId(final String userId) {
    if (userId == null || userId.isBlank()) {
      return null;
    }
    try {
      return Long.parseLong(userId.trim());
    } catch (NumberFormatException ex) {
      return null;
    }
  }

  private Double parseDouble(final String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    try {
      return Double.parseDouble(value.trim());
    } catch (NumberFormatException ex) {
      return null;
    }
  }

  private Map<String, Object> sanitizeTelemetryPayload(final Map<String, String> body) {
    final Map<String, Object> sanitized = new HashMap<>();
    if (body == null || body.isEmpty()) {
      return sanitized;
    }

    if (body.containsKey("captureMode")) {
      sanitized.put("captureMode", body.get("captureMode"));
    }
    if (body.containsKey("audioFormat")) {
      sanitized.put("audioFormat", body.get("audioFormat"));
    }
    if (body.containsKey("imageFormat")) {
      sanitized.put("imageFormat", body.get("imageFormat"));
    }
    if (body.containsKey("otherPartyId")) {
      sanitized.put("status", "TARGET_PRESENT");
    }
    if (body.containsKey("averageLevel")) {
      sanitized.put("averageLevel", body.get("averageLevel"));
    }
    if (body.containsKey("speechRatio")) {
      sanitized.put("speechRatio", body.get("speechRatio"));
    }
    if (body.containsKey("variability")) {
      sanitized.put("variability", body.get("variability"));
    }

    final String text = body.get("text");
    if (text != null) {
      sanitized.put("textLength", text.length());
    }

    return sanitized;
  }

  private Map<String, Object> sanitizeCombinedTelemetry(final Map<String, Object> combined) {
    if (combined == null || combined.isEmpty()) {
      return Map.of();
    }

    final Object overallRaw = combined.get("overall");
    if (!(overallRaw instanceof Map<?, ?> overallMap)) {
      return Map.of();
    }

    final Map<String, Object> safe = new HashMap<>();
    final Object score = overallMap.get("score");
    final Object label = overallMap.get("label");
    if (score != null) {
      safe.put("overallScore", score);
    }
    if (label != null) {
      safe.put("overallLabel", label.toString());
    }
    final Object timestamp = combined.get("timestamp");
    if (timestamp != null) {
      safe.put("timestamp", timestamp);
    }

    for (final String debugKey : List.of(
        "dbgTs", "dbgVs", "dbgIs", "dbgTw", "dbgVw", "dbgIw", "dbgTc", "dbgVc", "dbgIc",
        "dbgCf")) {
      final Object debugValue = combined.get(debugKey);
      if (debugValue != null) {
        safe.put(debugKey, debugValue);
      }
    }

    return safe;
  }

  private void maybeRecordFinalOverallSentiment(
      final String callId, final Long actorUserId, final Long targetUserId) {
    try {
      final Map<String, CallTelemetryEvent> latestByChannel = callTelemetryService.getLatestSentimentByChannel(callId);
      if (latestByChannel.isEmpty()) {
        return;
      }

      final Map<String, SentimentResult> channelResults = new LinkedHashMap<>();
      for (final Map.Entry<String, CallTelemetryEvent> entry : latestByChannel.entrySet()) {
        final CallTelemetryEvent event = entry.getValue();
        if (event == null || event.getSentimentScore() == null) {
          continue;
        }
        final String channel = entry.getKey().trim().toUpperCase(Locale.ROOT);
        channelResults.put(
            channel,
            new SentimentResult(
                event.getSentimentScore(),
                event.getSentimentLabel() == null ? "ANXIOUS" : event.getSentimentLabel(),
                event.getSentimentNotes() == null ? "" : event.getSentimentNotes(),
                channel,
                callId,
                event.getAnalysisTimestamp() == null
                    ? System.currentTimeMillis()
                    : event.getAnalysisTimestamp(),
                false));
      }

      if (channelResults.isEmpty()) {
        return;
      }

      SentimentResult finalResult = sentimentService.analyzeFinalOverallSentiment(callId, channelResults);
      callTelemetryService.recordSentimentEvent(
          callId,
          "SENTIMENT_FINAL",
          "COMBINED",
          actorUserId,
          targetUserId,
          "END_CALL",
          finalResult,
          Map.of(
              "overallScore", finalResult.score(),
              "overallLabel", finalResult.label(),
              "status", "FINAL_END_CALL"),
          "SUCCESS",
          null);
    } catch (Exception ex) {
      if (log.isWarnEnabled()) {
        log.warn(
            "Final end-call sentiment analysis skipped for callId {}: {}", callId, ex.getMessage());
      }
    }
  }

  private Map<String, Object> extractCallContextMetadata(Map<String, Object> body) {
    if (body == null || body.isEmpty()) {
      return Map.of();
    }

    Map<String, Object> metadata = new LinkedHashMap<>();
    String callKind = asString(body.get("callKind"));
    if (callKind != null) {
      metadata.put("callKind", callKind.toUpperCase(Locale.ROOT));
    }

    Object rawContextIds = body.get("contextPatientUserIds");
    List<Long> contextPatientUserIds = new ArrayList<>();
    if (rawContextIds instanceof List<?> list) {
      for (Object item : list) {
        Long parsed = asLong(item);
        if (parsed != null && parsed > 0L && !contextPatientUserIds.contains(parsed)) {
          contextPatientUserIds.add(parsed);
        }
      }
    }

    if (contextPatientUserIds.isEmpty()) {
      Long singleContext = asLong(body.get("contextPatientUserId"));
      if (singleContext != null && singleContext > 0L) {
        contextPatientUserIds.add(singleContext);
      }
    }

    if (!contextPatientUserIds.isEmpty()) {
      metadata.put("contextPatientUserIds", contextPatientUserIds);
      metadata.put("contextPatientUserId", contextPatientUserIds.get(0));
    }

    return metadata;
  }

  private Map<String, Object> mergeMetadata(Map<String, Object> base, Map<String, Object> extras) {
    if ((base == null || base.isEmpty()) && (extras == null || extras.isEmpty())) {
      return Map.of();
    }
    if (extras == null || extras.isEmpty()) {
      return base == null ? Map.of() : base;
    }

    Map<String, Object> merged = new LinkedHashMap<>();
    if (base != null && !base.isEmpty()) {
      merged.putAll(base);
    }
    merged.putAll(extras);
    return merged;
  }

  private void maybeGenerateAndStoreCallSummary(String callId, Long actorUserId) {
    try {
      Map<String, CallTelemetryEvent> latestByChannel = callTelemetryService.getLatestSentimentByChannel(callId);
      callSummaryService.generateAndStoreSummary(callId, actorUserId, latestByChannel);
    } catch (Exception ex) {
      if (log.isWarnEnabled()) {
        log.warn("Call summary generation skipped for callId {}: {}", callId, ex.getMessage());
      }
    }
  }

  private List<CallTranscriptService.TranscriptSegmentInput> extractTranscriptSegments(
      Map<String, Object> body) {
    if (body == null || body.isEmpty()) {
      return List.of();
    }

    List<CallTranscriptService.TranscriptSegmentInput> segments = new ArrayList<>();
    Object rawSegments = body.get("segments");
    if (rawSegments instanceof List<?> segmentList) {
      for (Object rawSegment : segmentList) {
        if (!(rawSegment instanceof Map<?, ?> map)) {
          continue;
        }
        segments.add(toTranscriptInput(map));
      }
      return segments;
    }

    segments.add(
        new CallTranscriptService.TranscriptSegmentInput(
            asString(body.get("speakerLabel")),
            asString(body.get("text")),
            asLong(body.get("startMs")),
            asLong(body.get("endMs")),
            asString(body.get("source"))));
    return segments;
  }

  private CallTranscriptService.TranscriptSegmentInput toTranscriptInput(Map<?, ?> rawSegment) {
    return new CallTranscriptService.TranscriptSegmentInput(
        asString(rawSegment.get("speakerLabel")),
        asString(rawSegment.get("text")),
        asLong(rawSegment.get("startMs")),
        asLong(rawSegment.get("endMs")),
        asString(rawSegment.get("source")));
  }

  private String asString(Object value) {
    if (value == null) {
      return null;
    }
    String text = value.toString().trim();
    return text.isEmpty() ? null : text;
  }

  private Long asLong(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof Number n) {
      return n.longValue();
    }
    try {
      return Long.parseLong(value.toString().trim());
    } catch (NumberFormatException ignored) {
      return null;
    }
  }

  private boolean isCallParticipant(String callId, Long userId) {
    if (callId == null || callId.isBlank() || userId == null) {
      return false;
    }
    return callTelemetryService.getTelemetryForCall(callId).stream()
        .anyMatch(e -> userId.equals(e.getActorUserId()) || userId.equals(e.getTargetUserId()));
  }

  private boolean canAccessSentimentHistory(User currentUser, Long requestedUserId) {
    if (currentUser == null || requestedUserId == null) {
      return false;
    }
    if (currentUser.getRole() == Role.ADMIN) {
      return true;
    }
    if (currentUser.getId().equals(requestedUserId)) {
      return true;
    }
    return currentUser.getRole() == Role.CAREGIVER
        && caregiverPatientLinkService.hasAccessToPatient(currentUser.getId(), requestedUserId);
  }

  // ================================================================
  // RECORDING ENDPOINTS
  // ================================================================

  @PostMapping("/{callId}/recording/start")
  @Operation(summary = "Start recording a call via AWS Chime Media Capture Pipeline")
  public ResponseEntity<Map<String, Object>> startRecording(@PathVariable String callId) {
    User currentUser = getCurrentUser();
    Map<String, Object> result = callRecordingService.startRecording(callId, currentUser.getId());
    callTelemetryService.recordCallEvent(
        callId,
        "RECORDING_START",
        currentUser.getId(),
        null,
        result.getOrDefault("status", "UNKNOWN").toString(),
        Map.of(
            "recordingEnabled",
            !result.containsKey("message") || !"DISABLED".equals(result.get("status"))),
        result.containsKey("message") ? result.get("message").toString() : null);
    return ResponseEntity.ok(result);
  }

  @PostMapping("/{callId}/recording/stop")
  @Operation(summary = "Stop the active recording pipeline for a call")
  public ResponseEntity<Map<String, Object>> stopRecording(@PathVariable String callId) {
    User currentUser = getCurrentUser();
    Map<String, Object> result = callRecordingService.stopRecording(callId);
    callTelemetryService.recordCallEvent(
        callId,
        "RECORDING_STOP",
        currentUser.getId(),
        null,
        result.getOrDefault("status", "UNKNOWN").toString(),
        Map.of(),
        null);
    return ResponseEntity.ok(result);
  }

  @GetMapping("/{callId}/recording")
  @Operation(summary = "Get recording status and metadata for a call")
  public ResponseEntity<Map<String, Object>> getRecordingStatus(@PathVariable String callId) {
    User currentUser = getCurrentUser();
    boolean isAdmin = currentUser.getRole() == Role.ADMIN;
    boolean isParticipant = isCallParticipant(callId, currentUser.getId());
    boolean isCaregiver = currentUser.getRole() == Role.CAREGIVER;
    if (!isAdmin && !isParticipant && !isCaregiver) {
      throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
    }
    return ResponseEntity.ok(callRecordingService.getRecordingStatus(callId));
  }

  @GetMapping("/{callId}/recording/playback-url")
  @Operation(summary = "Get a presigned S3 URL for recording playback (expires in 15 minutes)")
  public ResponseEntity<Map<String, Object>> getRecordingPlaybackUrl(@PathVariable String callId) {
    User currentUser = getCurrentUser();
    boolean isAdmin = currentUser.getRole() == Role.ADMIN;
    boolean isCaregiver = currentUser.getRole() == Role.CAREGIVER;
    boolean isParticipant = isCallParticipant(callId, currentUser.getId());
    if (!isAdmin && !isCaregiver && !isParticipant) {
      throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
    }
    callTelemetryService.recordCallEvent(
        callId,
        "RECORDING_PLAYBACK_URL_GENERATED",
        currentUser.getId(),
        null,
        "SUCCESS",
        Map.of("requestedByRole", currentUser.getRole().name()),
        null);
    return ResponseEntity.ok(callRecordingService.generatePlaybackUrl(callId));
  }

  @GetMapping("/recordings")
  @Operation(summary = "List all call recordings (admin and caregiver only)")
  public ResponseEntity<List<Map<String, Object>>> listRecordings(
      @RequestParam(required = false) Long userId) {
    User currentUser = getCurrentUser();
    boolean isAdmin = currentUser.getRole() == Role.ADMIN;
    boolean isCaregiver = currentUser.getRole() == Role.CAREGIVER;
    if (!isAdmin && !isCaregiver) {
      throw new AppException(
          HttpStatus.FORBIDDEN, "Only admins and caregivers can list recordings");
    }
    List<Map<String, Object>> recordings;
    if (userId != null) {
      recordings = callRecordingService.getRecordingsByUser(userId);
    } else if (isAdmin) {
      recordings = callRecordingService.getAllRecordings();
    } else {
      // Caregiver sees only recordings they initiated
      recordings = callRecordingService.getRecordingsByUser(currentUser.getId());
    }
    return ResponseEntity.ok(recordings);
  }

  @PostMapping("/{callId}/recording/cleanup-raw")
  @Operation(summary = "Delete raw recording artifacts after the stitched video is available (dev/local only)")
  public ResponseEntity<Map<String, Object>> cleanupRawRecordingArtifacts(
      @PathVariable String callId) {
    ensureDevOrLocalMode();
    getCurrentUser();
    return ResponseEntity.ok(callRecordingService.cleanupRawArtifactsForCall(callId));
  }

  @DeleteMapping("/recordings")
  @Operation(summary = "Purge ALL recordings from S3 and DB (dev/local only - for test cleanup)")
  public ResponseEntity<Map<String, Object>> purgeAllRecordings() {
    ensureDevOrLocalMode();
    User currentUser = getCurrentUser();
    if (log.isWarnEnabled()) {
      log.warn("Recording purge requested by user {} (dev/local mode)", currentUser.getId());
    }
    Map<String, Object> result = callRecordingService.purgeAllRecordings();
    return ResponseEntity.ok(result);
  }
}
