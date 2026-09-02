package com.careconnect.controller;

import com.careconnect.model.FriendRequest;
import com.careconnect.model.Friendship;
import com.careconnect.model.User;
import com.careconnect.repository.FriendRequestRepository;
import com.careconnect.repository.FriendshipRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.GamificationService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class FriendControllerTest {

    private static final Long FROM_USER_ID = 1L;
    private static final Long TO_USER_ID = 2L;
    private static final Long REQUEST_ID = 10L;
    @Mock
    private GamificationService gamificationService;
    @Mock
    private FriendRequestRepository friendRequestRepo;
    @Mock
    private UserRepository userRepo;
    @Mock
    private FriendshipRepository friendshipRepository;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @InjectMocks
    private FriendController controller;

    private FriendRequest makePendingRequest(Long id, Long from, Long to) {
        final FriendRequest r = new FriendRequest();
        r.setId(id);
        r.setFromUserId(from);
        r.setToUserId(to);
        r.setStatus("pending");
        r.setCreatedAt(new Date());
        return r;
    }

    private User makeUser(Long id, String name, String email) {
        final User u = new User();
        u.setId(id);
        u.setName(name);
        u.setEmail(email);
        return u;
    }

    // ─── sendFriendRequest ────────────────────────────────────────────────────

    @Test
    void sendFriendRequest_alreadyExists_returnsConflict() throws Exception {
        when(friendRequestRepo.existsByFromUserIdAndToUserId(FROM_USER_ID, TO_USER_ID)).thenReturn(true);

        final Map<String, Long> payload = Map.of("fromUserId", FROM_USER_ID, "toUserId", TO_USER_ID);
        final ResponseEntity<?> response = controller.sendFriendRequest(payload);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(response.getBody()).isEqualTo("Friend request already sent.");
        verify(friendRequestRepo, never()).save(any());
    }

    @Test
    void sendFriendRequest_new_savesAndReturnsCreated() throws Exception {
        when(friendRequestRepo.existsByFromUserIdAndToUserId(FROM_USER_ID, TO_USER_ID)).thenReturn(false);
        final FriendRequest saved = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        when(friendRequestRepo.save(any(FriendRequest.class))).thenReturn(saved);

        final Map<String, Long> payload = Map.of("fromUserId", FROM_USER_ID, "toUserId", TO_USER_ID);
        final ResponseEntity<?> response = controller.sendFriendRequest(payload);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(response.getBody()).isEqualTo("Friend request sent.");
        verify(friendRequestRepo).save(argThat(r ->
                FROM_USER_ID.equals(r.getFromUserId())
                        && TO_USER_ID.equals(r.getToUserId())
                        && "pending".equals(r.getStatus())
                        && r.getCreatedAt() != null
        ));
    }

    // ─── getPendingRequests ───────────────────────────────────────────────────

    @Test
    void getPendingRequests_noRequests_returnsEmptyList() throws Exception {
        when(friendRequestRepo.findByToUserIdAndStatus(TO_USER_ID, "pending")).thenReturn(List.of());

        final ResponseEntity<List<Map<String, Object>>> response = controller.getPendingRequests(TO_USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    @Test
    void getPendingRequests_withRequest_userFound_includesNameAndEmail() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        when(friendRequestRepo.findByToUserIdAndStatus(TO_USER_ID, "pending")).thenReturn(List.of(req));
        final User sender = makeUser(FROM_USER_ID, "Alice", "alice@example.com");
        when(userRepo.findById(FROM_USER_ID)).thenReturn(Optional.of(sender));

        final ResponseEntity<List<Map<String, Object>>> response = controller.getPendingRequests(TO_USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
        final Map<String, Object> entry = response.getBody().get(0);
        assertThat(entry.get("id")).isEqualTo(REQUEST_ID);
        assertThat(entry.get("fromUserId")).isEqualTo(FROM_USER_ID);
        assertThat(entry.get("toUserId")).isEqualTo(TO_USER_ID);
        assertThat(entry.get("status")).isEqualTo("pending");
        assertThat(entry.get("from_username")).isEqualTo("Alice");
        assertThat(entry.get("from_email")).isEqualTo("alice@example.com");
    }

    @Test
    void getPendingRequests_withRequest_userNotFound_noNameEmail() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        when(friendRequestRepo.findByToUserIdAndStatus(TO_USER_ID, "pending")).thenReturn(List.of(req));
        when(userRepo.findById(FROM_USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<List<Map<String, Object>>> response = controller.getPendingRequests(TO_USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
        final Map<String, Object> entry = response.getBody().get(0);
        assertThat(entry).doesNotContainKey("from_username");
        assertThat(entry).doesNotContainKey("from_email");
    }

    // ─── acceptFriendRequest ──────────────────────────────────────────────────

    @Test
    void acceptFriendRequest_notFound_returnsNotFound() throws Exception {
        when(friendRequestRepo.findById(REQUEST_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.acceptFriendRequest(Map.of("requestId", REQUEST_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(response.getBody()).isEqualTo("Request not found");
    }

    @Test
    void acceptFriendRequest_alreadyHandled_returnsConflict() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        req.setStatus("accepted");
        when(friendRequestRepo.findById(REQUEST_ID)).thenReturn(Optional.of(req));

        final ResponseEntity<?> response = controller.acceptFriendRequest(Map.of("requestId", REQUEST_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(response.getBody()).isEqualTo("Request already handled");
    }

    @Test
    void acceptFriendRequest_fromUserNotFound_returnsBadRequest() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        when(friendRequestRepo.findById(REQUEST_ID)).thenReturn(Optional.of(req));
        when(friendRequestRepo.save(any())).thenReturn(req);
        when(userRepo.findById(FROM_USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.acceptFriendRequest(Map.of("requestId", REQUEST_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody()).isEqualTo("User not found");
    }

    @Test
    void acceptFriendRequest_toUserNotFound_returnsBadRequest() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        when(friendRequestRepo.findById(REQUEST_ID)).thenReturn(Optional.of(req));
        when(friendRequestRepo.save(any())).thenReturn(req);
        when(userRepo.findById(FROM_USER_ID)).thenReturn(Optional.of(makeUser(FROM_USER_ID, "Alice", "a@test.com")));
        when(userRepo.findById(TO_USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.acceptFriendRequest(Map.of("requestId", REQUEST_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody()).isEqualTo("User not found");
    }

    @Test
    void acceptFriendRequest_firstFriend_unlocksAchievement() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        when(friendRequestRepo.findById(REQUEST_ID)).thenReturn(Optional.of(req));
        when(friendRequestRepo.save(any())).thenReturn(req);

        final User fromUser = makeUser(FROM_USER_ID, "Alice", "a@test.com");
        final User toUser = makeUser(TO_USER_ID, "Bob", "b@test.com");
        when(userRepo.findById(FROM_USER_ID)).thenReturn(Optional.of(fromUser));
        when(userRepo.findById(TO_USER_ID)).thenReturn(Optional.of(toUser));
        when(friendshipRepository.save(any(Friendship.class))).thenReturn(
                Friendship.builder().user1(fromUser).user2(toUser).status("CONFIRMED").build()
        );
        when(friendshipRepository.countByUserId(FROM_USER_ID)).thenReturn(1L);

        final ResponseEntity<?> response = controller.acceptFriendRequest(Map.of("requestId", REQUEST_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo("Friend request accepted and friendship created");
        verify(gamificationService).unlockAchievement(FROM_USER_ID, "Added First Friend", 50);
        verify(friendshipRepository).save(argThat(f ->
                "CONFIRMED".equals(f.getStatus())
                        && fromUser.equals(f.getUser1())
                        && toUser.equals(f.getUser2())
        ));
    }

    @Test
    void acceptFriendRequest_notFirstFriend_noAchievement() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        when(friendRequestRepo.findById(REQUEST_ID)).thenReturn(Optional.of(req));
        when(friendRequestRepo.save(any())).thenReturn(req);

        final User fromUser = makeUser(FROM_USER_ID, "Alice", "a@test.com");
        final User toUser = makeUser(TO_USER_ID, "Bob", "b@test.com");
        when(userRepo.findById(FROM_USER_ID)).thenReturn(Optional.of(fromUser));
        when(userRepo.findById(TO_USER_ID)).thenReturn(Optional.of(toUser));
        when(friendshipRepository.save(any(Friendship.class))).thenReturn(
                Friendship.builder().user1(fromUser).user2(toUser).status("CONFIRMED").build()
        );
        when(friendshipRepository.countByUserId(FROM_USER_ID)).thenReturn(5L);

        final ResponseEntity<?> response = controller.acceptFriendRequest(Map.of("requestId", REQUEST_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(gamificationService, never()).unlockAchievement(any(), any(), anyInt());
    }

    // ─── rejectFriendRequest ──────────────────────────────────────────────────

    @Test
    void rejectFriendRequest_notFound_returnsNotFound() throws Exception {
        when(friendRequestRepo.findById(REQUEST_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.rejectFriendRequest(Map.of("requestId", REQUEST_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(response.getBody()).isEqualTo("Request not found");
    }

    @Test
    void rejectFriendRequest_alreadyHandled_returnsConflict() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        req.setStatus("rejected");
        when(friendRequestRepo.findById(REQUEST_ID)).thenReturn(Optional.of(req));

        final ResponseEntity<?> response = controller.rejectFriendRequest(Map.of("requestId", REQUEST_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(response.getBody()).isEqualTo("Request already handled");
    }

    @Test
    void rejectFriendRequest_success_savesRejectedStatusAndReturnsOk() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        when(friendRequestRepo.findById(REQUEST_ID)).thenReturn(Optional.of(req));
        when(friendRequestRepo.save(any())).thenReturn(req);

        final ResponseEntity<?> response = controller.rejectFriendRequest(Map.of("requestId", REQUEST_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo("Friend request rejected");
        verify(friendRequestRepo).save(argThat(r -> "rejected".equals(r.getStatus())));
    }

    // ─── getFriends ───────────────────────────────────────────────────────────

    @Test
    void getFriends_noAcceptedRequests_returnsEmpty() throws Exception {
        when(friendRequestRepo.findByStatus("accepted")).thenReturn(List.of());

        final ResponseEntity<List<Map<String, Object>>> response = controller.getFriends(FROM_USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    @Test
    void getFriends_userIsFromUser_returnsPeer() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        req.setStatus("accepted");
        when(friendRequestRepo.findByStatus("accepted")).thenReturn(List.of(req));
        final User peer = makeUser(TO_USER_ID, "Bob", "bob@test.com");
        when(userRepo.findById(TO_USER_ID)).thenReturn(Optional.of(peer));

        final ResponseEntity<List<Map<String, Object>>> response = controller.getFriends(FROM_USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
        final Map<String, Object> friend = response.getBody().get(0);
        assertThat(friend.get("id")).isEqualTo(TO_USER_ID);
        assertThat(friend.get("name")).isEqualTo("Bob");
        assertThat(friend.get("email")).isEqualTo("bob@test.com");
    }

    @Test
    void getFriends_userIsToUser_returnsPeer() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        req.setStatus("accepted");
        when(friendRequestRepo.findByStatus("accepted")).thenReturn(List.of(req));
        final User peer = makeUser(FROM_USER_ID, "Alice", "alice@test.com");
        when(userRepo.findById(FROM_USER_ID)).thenReturn(Optional.of(peer));

        final ResponseEntity<List<Map<String, Object>>> response = controller.getFriends(TO_USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).get("name")).isEqualTo("Alice");
    }

    @Test
    void getFriends_peerNotFoundInRepo_skipsEntry() throws Exception {
        final FriendRequest req = makePendingRequest(REQUEST_ID, FROM_USER_ID, TO_USER_ID);
        req.setStatus("accepted");
        when(friendRequestRepo.findByStatus("accepted")).thenReturn(List.of(req));
        when(userRepo.findById(TO_USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<List<Map<String, Object>>> response = controller.getFriends(FROM_USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    @Test
    void getFriends_requestUnrelatedToUser_notIncluded() throws Exception {
        final Long otherUser1 = 99L;
        final Long otherUser2 = 100L;
        final FriendRequest req = makePendingRequest(REQUEST_ID, otherUser1, otherUser2);
        req.setStatus("accepted");
        when(friendRequestRepo.findByStatus("accepted")).thenReturn(List.of(req));

        final ResponseEntity<List<Map<String, Object>>> response = controller.getFriends(FROM_USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
        verify(userRepo, never()).findById(any());
    }
}
