package com.careconnect.websocket;

import com.careconnect.model.User;
import java.util.Collection;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.web.socket.WebSocketSession;

/**
 * Thread-safe WebSocket identity map with atomic rebind and identity-fenced close.
 *
 * <p>Each handler owns its own registry instance so call-signaling sessions are not mixed with
 * general CareConnect sessions. Close only removes a user binding when the closed socket is still
 * the registered owner, so a stale close cannot evict a replacement connection.
 */
public final class WebSocketIdentityRegistry {

  private final Map<String, WebSocketSession> userSessions = new ConcurrentHashMap<>();
  private final Map<String, User> sessionUsers = new ConcurrentHashMap<>();
  private final Object authenticationLock = new Object();

  /**
   * Atomically detaches any prior identity for {@code session}, then binds {@code user}.
   *
   * @param session socket being authenticated
   * @param user authenticated user
   */
  public void bind(final WebSocketSession session, final User user) {
    synchronized (authenticationLock) {
      final User prior = sessionUsers.remove(session.getId());
      if (prior != null) {
        userSessions.remove(prior.getId().toString(), session);
      }
      userSessions.put(user.getId().toString(), session);
      sessionUsers.put(session.getId(), user);
    }
  }

  /**
   * Identity-fenced unbind: removes the session user and only clears the user→session mapping when
   * {@code session} is still the registered owner.
   *
   * @param session closed or rebinding socket
   * @return detached user, or {@code null} when the socket was unauthenticated
   */
  public User unbind(final WebSocketSession session) {
    synchronized (authenticationLock) {
      final User user = sessionUsers.remove(session.getId());
      if (user != null) {
        userSessions.remove(user.getId().toString(), session);
      }
      return user;
    }
  }

  public User getUser(final String sessionId) {
    return sessionUsers.get(sessionId);
  }

  public WebSocketSession getSession(final String userId) {
    return userSessions.get(userId);
  }

  public boolean isOnline(final String userId) {
    final WebSocketSession session = userSessions.get(userId);
    return session != null && session.isOpen();
  }

  public int onlineCount() {
    return userSessions.size();
  }

  public Collection<WebSocketSession> sessions() {
    return userSessions.values();
  }

  public Collection<User> users() {
    return sessionUsers.values();
  }

  /**
   * Registers a user identity without a live WebSocket (legacy HTTP undying-session hook).
   *
   * @param userId user identifier
   * @param user user metadata
   */
  public void registerUserWithoutSession(final String userId, final User user) {
    sessionUsers.put(userId, user);
  }
}
