package com.careconnect.websocket;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.service.CallSessionService;
import com.careconnect.service.CallRecordingService;
import com.careconnect.service.ChimeService;
import com.careconnect.service.CallTelemetryService;
import com.careconnect.service.CaregiverPatientLinkService;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

/** Handles websocket notifications related to call signaling and sentiment channel updates. */
@Component
public class CallNotificationHandler extends TextWebSocketHandler {

  private static final org.slf4j.Logger log =
      org.slf4j.LoggerFactory.getLogger(CallNotificationHandler.class);

  /** Repository used to look up users during websocket interactions. */
  private final UserRepository userRepository;

  /** JWT provider used to authenticate websocket sessions. */
  private final JwtTokenProvider jwtTokenProvider;

  /** Telemetry service used to record websocket call events. */
  private final CallTelemetryService callTelemetryService;

  /** Service used to verify caregiver-patient link permissions. */
  private final CaregiverPatientLinkService caregiverPatientLinkService;
  private final CallSessionService callSessionService;
  private final CallRecordingService callRecordingService;
  private final ChimeService chimeService;

  /** JSON mapper used to serialize websocket payloads. */
  private final ObjectMapper objectMapper;

  /** Store active connections: userId -> WebSocketSession. */
  private final Map<String, WebSocketSession> userSessions = new ConcurrentHashMap<>();

  /** Store user info for sessions: sessionId -> User. */
  private final Map<String, User> sessionUsers = new ConcurrentHashMap<>();

  /**
   * Creates the websocket notification handler with its required collaborators.
   *
   * @param userRepository repository used to look up users
   * @param jwtTokenProvider JWT provider used to validate websocket auth tokens
   * @param callTelemetryService telemetry service used to record websocket events
   * @param caregiverPatientLinkService service used to enforce caregiver-patient call access
   */
  @Autowired
  public CallNotificationHandler(
      final UserRepository userRepository,
      final JwtTokenProvider jwtTokenProvider,
      final CallTelemetryService callTelemetryService,
      final CaregiverPatientLinkService caregiverPatientLinkService,
      final CallSessionService callSessionService,
      final CallRecordingService callRecordingService,
      final ChimeService chimeService) {
    this.userRepository = userRepository;
    this.jwtTokenProvider = jwtTokenProvider;
    this.callTelemetryService = callTelemetryService;
    this.caregiverPatientLinkService = caregiverPatientLinkService;
    this.callSessionService = callSessionService;
    this.callRecordingService = callRecordingService;
    this.chimeService = chimeService;
    this.objectMapper = new ObjectMapper();
  }

  /** Compatibility constructor for isolated unit tests. */
  CallNotificationHandler(
      final UserRepository userRepository,
      final JwtTokenProvider jwtTokenProvider,
      final CallTelemetryService callTelemetryService,
      final CaregiverPatientLinkService caregiverPatientLinkService) {
    this(
        userRepository,
        jwtTokenProvider,
        callTelemetryService,
        caregiverPatientLinkService,
        null,
        null,
        null);
  }

  private String getUserDisplayName(final User user, final String preferredName) {
    if (preferredName != null) {
      final String trimmed = preferredName.trim();
      if (!trimmed.isEmpty() && !looksLikeEmail(trimmed)) {
        return trimmed;
      }
    }
    if (user.getName() != null && !user.getName().isEmpty()) {
      return user.getName();
    }
    if (user.getRole() != null) {
      final String roleName = user.getRole().name().toLowerCase(Locale.ROOT);
      return Character.toUpperCase(roleName.charAt(0)) + roleName.substring(1);
    }
    return "Participant";
  }

  private String getUserDisplayName(final User user) {
    return getUserDisplayName(user, null);
  }

  private boolean looksLikeEmail(final String value) {
    return value.contains("@") && value.contains(".");
  }

  @Override
  public void afterConnectionEstablished(final WebSocketSession session) throws Exception {
    log.info("WebSocket connection established: {}", session.getId());

    final Map<String, Object> response =
        Map.of(
            "type", "connection-established",
            "message", "Connected to CareConnect call service",
            "sessionId", session.getId());
    session.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));
  }

  @Override
  protected void handleTextMessage(final WebSocketSession session, final TextMessage message)
      throws Exception {
    String type = "unknown";
    Map<String, Object> payload = Map.of();
    try {
      payload =
          objectMapper.readValue(
              message.getPayload(), new TypeReference<Map<String, Object>>() {});
      type = String.valueOf(payload.getOrDefault("type", "unknown"));

      log.info("Received WebSocket message: {} from session: {}", type, session.getId());

      switch (type) {
        case "authenticate":
          handleAuthentication(session, payload);
          break;
        case "join-user-room":
          handleUserJoin(session, payload);
          break;
        case "send-video-call-invitation":
          handleCallInvitation(session, payload);
          break;
        case "send-sms-notification":
          handleSmsNotification(session, payload);
          break;
        case "accept-call":
          handleCallAccept(session, payload);
          break;
        case "decline-call":
          handleCallDecline(session, payload);
          break;
        case "end-call":
          handleCallEnd(session, payload);
          break;
        case "heartbeat":
          handleHeartbeat(session, payload);
          break;
        case "sentiment-channel-state":
          handleSentimentChannelState(session, payload);
          break;
        default:
          log.warn("Unknown message type: {}", type);
          sendErrorMessage(session, "Unknown message type: " + type);
          break;
      }

      recordTelemetry(type, session, payload, "SUCCESS", null);
    } catch (Exception e) {
      recordTelemetry(type, session, payload, "ERROR", e.getMessage());
      log.error("Error handling WebSocket message from session {}", session.getId(), e);
      sendErrorMessage(session, "Error processing message: " + e.getMessage());
    }
  }

  private void recordTelemetry(
      final String type,
      final WebSocketSession session,
      final Map<String, Object> payload,
      final String status,
      final String errorMessage) {
    final User actor = sessionUsers.get(session.getId());
    final Long actorUserId = actor != null ? actor.getId() : null;
    final Long targetUserId = resolveTargetUserId(payload);
    final String eventType = "WS_" + type.replace('-', '_').toUpperCase(Locale.ROOT);
    final String callId =
        payload.get("callId") == null ? null : String.valueOf(payload.get("callId"));

    try {
      if (callId != null && !callId.isBlank() && actorUserId != null
          && callSessionService != null) {
        callSessionService.requireParticipant(callId, actorUserId);
      }
      callTelemetryService.recordWebSocketEvent(
          callId,
          eventType,
          actorUserId,
          targetUserId,
          payload,
          status,
          errorMessage);
    } catch (RuntimeException ex) {
      log.error(
          "WebSocket telemetry recording failed for type={} sessionId={}",
          type,
          session.getId(),
          ex);
    }
  }

  private Long resolveTargetUserId(final Map<String, Object> payload) {
    Long targetUserId = parseLong(payload.get("recipientId"));
    if (targetUserId == null) {
      targetUserId = parseLong(payload.get("senderId"));
    }
    if (targetUserId == null) {
      targetUserId = parseLong(payload.get("otherPartyId"));
    }
    return targetUserId;
  }

  private void sendJsonMessage(final WebSocketSession session, final Map<String, Object> payload)
      throws Exception {
    session.sendMessage(new TextMessage(objectMapper.writeValueAsString(payload)));
  }

  private Map<String, Object> errorResponse(final String type, final String message) {
    final Map<String, Object> response = new HashMap<>();
    response.put("type", type);
    response.put("message", message);
    return response;
  }

  private Long parseLong(final Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof Number number) {
      return number.longValue();
    }
    try {
      return Long.parseLong(value.toString());
    } catch (NumberFormatException ignored) {
      return null;
    }
  }

  private void handleAuthentication(
      final WebSocketSession session, final Map<String, Object> payload) throws Exception {
    final String token = (String) payload.get("token");

    if (token == null || !jwtTokenProvider.validateToken(token)) {
      sendJsonMessage(
          session,
          Map.of("type", "authentication-failed", "message", "Invalid or missing token"));
      session.close(CloseStatus.NOT_ACCEPTABLE.withReason("Authentication failed"));
      return;
    }

    final String userEmail = jwtTokenProvider.getEmailFromToken(token);
    final User user = userRepository.findByEmail(userEmail).orElse(null);

    if (user == null) {
      sendJsonMessage(
          session,
          Map.of("type", "authentication-failed", "message", "User not found"));
      session.close(CloseStatus.NOT_ACCEPTABLE.withReason("User not found"));
      return;
    }

    userSessions.put(user.getId().toString(), session);
    sessionUsers.put(session.getId(), user);

    sendJsonMessage(
        session,
        Map.of(
            "type", "authentication-success",
            "userId", user.getId(),
            "userEmail", user.getEmail(),
            "userRole", user.getRole().name()));

    log.debug("User authenticated userId={} role={}", user.getId(), user.getRole());
  }

  private void handleUserJoin(final WebSocketSession session, final Map<String, Object> payload)
      throws Exception {
    final User user = sessionUsers.get(session.getId());
    if (user == null) {
      sendErrorMessage(session, "User not authenticated");
      return;
    }

    final String userId = user.getId().toString();
    final String userRole = user.getRole().name();

    userSessions.put(userId, session);

    log.debug("User joined room userId={} role={}", user.getId(), userRole);

    sendJsonMessage(
        session,
        Map.of(
            "type", "user-joined",
            "userId", userId,
            "userEmail", user.getEmail(),
            "userRole", userRole,
            "joinedAt", System.currentTimeMillis()));
  }

  private void handleCallInvitation(
      final WebSocketSession session, final Map<String, Object> payload) throws Exception {
    final User sender = sessionUsers.get(session.getId());
    if (sender == null) {
      sendErrorMessage(session, "User not authenticated");
      return;
    }

    String recipientId = String.valueOf(payload.get("recipientId"));
    final String callId = (String) payload.get("callId");
    final Boolean isVideoCall = (Boolean) payload.getOrDefault("isVideoCall", true);
    final String callType = (String) payload.getOrDefault("callType", "general");
    final String callerName =
        payload.get("callerName") == null ? null : String.valueOf(payload.get("callerName"));
    if (callSessionService != null) {
      callSessionService.requireActiveParticipant(callId, sender.getId());
      recipientId = callSessionService.requirePendingInvitationRecipient(
          callId, sender.getId(), parseLong(recipientId)).toString();
    }

    final User recipient = userRepository.findById(Long.parseLong(recipientId)).orElse(null);
    if (recipient == null) {
      sendErrorMessage(session, "Recipient not found");
      return;
    }

    if (sender.getRole() == com.careconnect.security.Role.PATIENT
        && recipient.getRole() == com.careconnect.security.Role.PATIENT) {
      sendJsonMessage(
          session,
          Map.of(
              "type", "call-invitation-failed",
              "callId", callId,
              "reason", "Patient-to-patient calls are not permitted",
              "recipientId", recipientId,
              "recipientRole", recipient.getRole().name(),
              "recipientName", getUserDisplayName(recipient)));
      return;
    }

    if (sender.getRole() == com.careconnect.security.Role.PATIENT
        && recipient.getRole() == com.careconnect.security.Role.CAREGIVER) {
      final boolean linked =
          caregiverPatientLinkService.hasAccessToPatient(recipient.getId(), sender.getId());
      if (!linked) {
        sendJsonMessage(
            session,
            Map.of(
                "type", "call-invitation-failed",
                "callId", callId,
                "reason", "No active caregiver-patient link",
                "recipientId", recipientId,
                "recipientRole", recipient.getRole().name(),
                "recipientName", getUserDisplayName(recipient)));
        return;
      }

      final boolean patientCallsEnabled =
          caregiverPatientLinkService.isPatientVideoCallsEnabled(
              recipient.getId(), sender.getId());
      if (!patientCallsEnabled) {
        sendJsonMessage(
            session,
            Map.of(
                "type", "call-invitation-failed",
                "callId", callId,
                "reason", "Caregiver disabled patient-initiated calls",
                "recipientId", recipientId,
                "recipientRole", recipient.getRole().name(),
                "recipientName", getUserDisplayName(recipient)));
        return;
      }
    }

    final WebSocketSession recipientSession = userSessions.get(recipientId);

    if (recipientSession != null && recipientSession.isOpen()) {
      final Map<String, Object> callNotification = new HashMap<>();
      callNotification.put("type", "incoming-video-call");
      callNotification.put("senderId", sender.getId());
      callNotification.put("senderName", getUserDisplayName(sender, callerName));
      callNotification.put("senderRole", sender.getRole().name());
      callNotification.put("callId", callId);
      callNotification.put("isVideoCall", isVideoCall);
      callNotification.put("callType", callType);
      callNotification.put(
          "callKind",
          payload.getOrDefault(
              "callKind",
              "care-team".equalsIgnoreCase(callType) ? "CARE_TEAM" : "GENERAL"));
      if (callSessionService != null) {
        final com.careconnect.model.CallSession durable = callSessionService.requireSession(callId);
        callNotification.put(
            "contextPatientUserIds",
            java.util.List.of(callSessionService.requirePatientUserId(durable)));
        if (durable.getScheduledVisitId() != null) {
          callNotification.put("scheduledVisitId", durable.getScheduledVisitId());
        }
      }
      callNotification.put("timestamp", System.currentTimeMillis());

      recipientSession.sendMessage(
          new TextMessage(objectMapper.writeValueAsString(callNotification)));

      sendJsonMessage(
          session,
          Map.of(
              "type", "call-invitation-sent",
              "callId", callId,
              "recipientId", recipientId,
              "recipientRole", recipient.getRole().name(),
              "recipientName", getUserDisplayName(recipient),
              "status", "delivered"));

      log.debug("Call invitation sent senderId={} recipientId={}", sender.getId(), recipient.getId());
    } else {
      sendJsonMessage(
          session,
          Map.of(
              "type", "call-invitation-failed",
              "callId", callId,
              "reason", "Recipient not online",
              "recipientId", recipientId,
              "recipientRole", recipient.getRole().name(),
              "recipientName", getUserDisplayName(recipient)));

      log.debug("Call invitation failed recipientId={} not online", recipient.getId());
    }
  }

  private void handleSmsNotification(
      final WebSocketSession session, final Map<String, Object> payload) throws Exception {
    final User sender = sessionUsers.get(session.getId());
    if (sender == null) {
      sendErrorMessage(session, "User not authenticated");
      return;
    }

    final String recipientId = (String) payload.get("recipientId");
    final String message = (String) payload.get("message");
    final String messageType = (String) payload.getOrDefault("messageType", "general");

    final User recipient = userRepository.findById(Long.parseLong(recipientId)).orElse(null);
    if (recipient == null) {
      sendErrorMessage(session, "Recipient not found");
      return;
    }

    final WebSocketSession recipientSession = userSessions.get(recipientId);

    if (recipientSession != null && recipientSession.isOpen()) {
      final Map<String, Object> smsNotification =
          Map.of(
              "type", "incoming-sms",
              "senderId", sender.getId(),
              "senderName", getUserDisplayName(sender),
              "senderRole", sender.getRole().name(),
              "message", message,
              "messageType", messageType,
              "timestamp", System.currentTimeMillis());

      recipientSession.sendMessage(
          new TextMessage(objectMapper.writeValueAsString(smsNotification)));

      sendJsonMessage(
          session,
          Map.of(
              "type", "sms-sent",
              "recipientId", recipientId,
              "recipientName", getUserDisplayName(recipient),
              "status", "delivered"));

      log.debug("SMS notification sent senderId={} recipientId={}", sender.getId(), recipient.getId());
    } else {
      sendJsonMessage(
          session,
          Map.of(
              "type", "sms-failed",
              "reason", "Recipient not online",
              "recipientId", recipientId));

      log.debug("SMS notification failed recipientId={} not online", recipient.getId());
    }
  }

  private void handleCallAccept(final WebSocketSession session, final Map<String, Object> payload)
      throws Exception {
    final User user = sessionUsers.get(session.getId());
    if (user == null) {
      sendErrorMessage(session, "User not authenticated");
      return;
    }

    final String callId = (String) payload.get("callId");
    if (callSessionService != null) {
      callSessionService.requireJoinAuthorized(callId, user.getId());
    }

    final java.util.List<Long> recipients = callSessionService == null
        ? java.util.List.of(parseLong(payload.get("senderId")))
        : callSessionService.getOtherParticipantUserIds(callId, user.getId());
    for (final Long recipientId : recipients) {
      if (recipientId == null) continue;
      final WebSocketSession senderSession = userSessions.get(recipientId.toString());
      if (senderSession == null || !senderSession.isOpen()) continue;
      final Map<String, Object> response =
          Map.of(
              "type", "call-answered",
              "callId", callId,
              "answeredBy", user.getId(),
              "answeredByName", getUserDisplayName(user),
              "timestamp", System.currentTimeMillis());
      senderSession.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));

      log.debug("Call {} accepted by userId={}", callId, user.getId());
    }
  }

  private void handleCallDecline(final WebSocketSession session, final Map<String, Object> payload)
      throws Exception {
    final User user = sessionUsers.get(session.getId());
    if (user == null) {
      sendErrorMessage(session, "User not authenticated");
      return;
    }

    final String callId = (String) payload.get("callId");
    final String reason = (String) payload.getOrDefault("reason", "declined");
    final java.util.List<Long> recipients;
    if (callSessionService != null) {
      final CallSessionService.DeclineResult decline =
          callSessionService.declineInvitation(callId, user.getId());
      recipients = decline.notifyUserIds();
      if (decline.terminationOwner()) {
        try {
          if (callRecordingService != null) {
            callRecordingService.stopRecording(callId);
          }
          if (chimeService != null) {
            chimeService.endMeeting(callId);
          }
          callSessionService.completeTermination(callId);
        } catch (RuntimeException cleanupFailure) {
          log.error("Declined call cleanup failed for callId={}", callId, cleanupFailure);
        }
      }
    } else {
      recipients = java.util.List.of(parseLong(payload.get("senderId")));
    }

    for (final Long recipientId : recipients) {
      if (recipientId == null) continue;
      final WebSocketSession senderSession = userSessions.get(recipientId.toString());
      if (senderSession == null || !senderSession.isOpen()) continue;
      final Map<String, Object> response =
          Map.of(
              "type", "call-declined",
              "callId", callId,
              "declinedBy", user.getId(),
              "declinedByName", getUserDisplayName(user),
              "reason", reason,
              "timestamp", System.currentTimeMillis());
      senderSession.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));

      log.debug("Call {} declined by userId={}", callId, user.getId());
    }
  }

  private void handleCallEnd(final WebSocketSession session, final Map<String, Object> payload)
      throws Exception {
    final User user = sessionUsers.get(session.getId());
    if (user == null) {
      sendErrorMessage(session, "User not authenticated");
      return;
    }

    final String callId = (String) payload.get("callId");

    log.warn(
        "Ignoring legacy websocket end-call for call {} from user {}",
        callId,
        user.getId());
  }

  @SuppressWarnings("unused")
  private void handleHeartbeat(
      final WebSocketSession session, final Map<String, Object> payload) throws Exception {
    sendJsonMessage(
        session,
        Map.of("type", "heartbeat-response", "timestamp", System.currentTimeMillis()));
  }

  private void handleSentimentChannelState(
      final WebSocketSession session, final Map<String, Object> payload) throws Exception {
    final User user = sessionUsers.get(session.getId());
    if (user == null) {
      sendErrorMessage(session, "User not authenticated");
      return;
    }

    final String channel =
        payload.get("channel") == null
            ? ""
            : String.valueOf(payload.get("channel")).trim().toLowerCase(Locale.ROOT);
    if (!("text".equals(channel) || "voice".equals(channel) || "video".equals(channel))) {
      sendErrorMessage(session, "Invalid channel: " + channel);
      return;
    }

    final String callId =
        payload.get("callId") == null ? "" : String.valueOf(payload.get("callId"));
    final String otherPartyId =
        payload.get("otherPartyId") == null
            ? ""
            : String.valueOf(payload.get("otherPartyId"));
    final boolean muted =
        Boolean.parseBoolean(String.valueOf(payload.getOrDefault("muted", false)));
    final String captureMode =
        payload.get("captureMode") == null ? null : String.valueOf(payload.get("captureMode"));
    if (callSessionService != null) {
      callSessionService.requireActiveParticipant(callId, user.getId());
    }

    if (callSessionService == null && otherPartyId.isBlank()) {
      sendErrorMessage(session, "otherPartyId is required");
      return;
    }

    final java.util.Set<String> recipientIds = new java.util.LinkedHashSet<>();
    if (callSessionService != null) {
      callSessionService.getJoinedParticipants(callId).stream()
          .map(participant -> participant.getUserId().toString())
          .filter(id -> !id.equals(user.getId().toString()))
          .forEach(recipientIds::add);
    } else {
      recipientIds.add(otherPartyId);
    }
    for (final String recipientId : recipientIds) {
      final WebSocketSession otherSession = userSessions.get(recipientId);
      if (otherSession == null || !otherSession.isOpen()) {
        continue;
      }
      final Map<String, Object> response = new HashMap<>();
      response.put("type", "sentiment-channel-state");
      response.put("callId", callId);
      response.put("channel", channel);
      response.put("muted", muted);
      response.put("status", muted ? "MUTED" : "AWAITING");
      response.put(
          "notes",
          muted ? "Channel Muted" : "Awaiting " + channel + " sentiment sample.");
      response.put("changedBy", user.getId());
      response.put("changedByName", getUserDisplayName(user));
      if (captureMode != null && !captureMode.isBlank()) {
        response.put("captureMode", captureMode);
      }
      response.put("timestamp", System.currentTimeMillis());

      otherSession.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));
    }
  }

  private void sendErrorMessage(final WebSocketSession session, final String errorMessage) {
    try {
      final Map<String, Object> error =
          Map.of(
              "type", "error",
              "message", errorMessage,
              "timestamp", System.currentTimeMillis());
      session.sendMessage(new TextMessage(objectMapper.writeValueAsString(error)));
    } catch (Exception e) {
      log.error("Failed to send error message to session {}", session.getId(), e);
    }
  }

  @Override
  public void afterConnectionClosed(final WebSocketSession session, final CloseStatus status)
      throws Exception {
    final User user = sessionUsers.remove(session.getId());
    if (user != null) {
      userSessions.remove(user.getId().toString());
      log.debug(
          "WebSocket connection closed for userId={} status={}", user.getId(), status);
    } else {
      log.info("WebSocket connection closed: {} - Status: {}", session.getId(), status);
    }
  }

  @Override
  public void handleTransportError(final WebSocketSession session, final Throwable exception)
      throws Exception {
    final User user = sessionUsers.get(session.getId());
    final Long userId = user != null ? user.getId() : null;
    log.error(
        "WebSocket transport error userId={} session={}", userId, session.getId());
    if (log.isDebugEnabled()) {
      log.debug("WebSocket transport diagnostic", exception);
    }
  }

  /**
   * Returns whether the given user identifier has an active open websocket session.
   *
   * @param userId user identifier to check
   * @return {@code true} if the user has an open session
   */
  public boolean isUserOnline(final String userId) {
    final WebSocketSession session = userSessions.get(userId);
    return session != null && session.isOpen();
  }

  /**
   * Sends a websocket notification to a connected user when their session is online.
   *
   * @param userId recipient user identifier
   * @param notification notification payload to send
   */
  public void sendNotificationToUser(
      final String userId, final Map<String, Object> notification) {
    final WebSocketSession session = userSessions.get(userId);
    if (session != null && session.isOpen()) {
      try {
        session.sendMessage(new TextMessage(objectMapper.writeValueAsString(notification)));
        log.info("Notification sent to user {}: {}", userId, notification.get("type"));
      } catch (Exception e) {
        log.error("Failed to send notification to user {}", userId, e);
      }
    } else {
      log.warn(
          "User {} not connected for notification: {}", userId, notification.get("type"));
    }
  }

  /**
   * Returns the currently connected users keyed by user identifier.
   *
   * @return online user identifier to email mapping
   */
  public Map<String, String> getOnlineUsers() {
    final Map<String, String> onlineUsers = new ConcurrentHashMap<>();
    sessionUsers
        .values()
        .forEach(user -> onlineUsers.put(user.getId().toString(), user.getEmail()));
    return onlineUsers;
  }

  /**
   * Sends a call invitation payload from an external service to a connected user.
   *
   * @param recipientId recipient user identifier
   * @param invitationData invitation payload to forward
   */
  public void sendCallInvitation(
      final String recipientId, final Map<String, Object> invitationData) {
    sendNotificationToUser(recipientId, invitationData);
  }

  /**
   * Sends an SMS-style notification payload from an external service to a connected user.
   *
   * @param recipientId recipient user identifier
   * @param smsData SMS notification payload to forward
   */
  @SuppressWarnings("checkstyle:AbbreviationAsWordInName")
  public void sendSMSNotification(final String recipientId, final Map<String, Object> smsData) {
    sendNotificationToUser(recipientId, smsData);
  }
}
