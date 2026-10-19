package com.careconnect.controller;

import com.careconnect.dto.PostWithCommentCountDto;
import com.careconnect.model.Caregiver;
import com.careconnect.model.Patient;
import com.careconnect.model.Post;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.FeedService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
        /*
         * FeedController uses SecurityContextHolder for auth and delegates to FeedService.
         * All dependencies are field-injected (@Autowired), so @InjectMocks uses field injection.
         */
class FeedControllerTest {

    private static final String EMAIL = "user@example.com";
    private static final Long USER_ID = 10L;
    @Mock
    private FeedService feedService;
    @Mock
    private UserRepository userRepository;
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private CaregiverRepository caregiverRepository;
    @Mock
    private Authentication authentication;
    @Mock
    private SecurityContext securityContext;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @InjectMocks
    private FeedController controller;

    @BeforeEach
    void setUpSecurityContext() throws Exception {
        /*
         * getUserFeed, getFriendsFeed, and createPost all resolve the caller
         * via SecurityContextHolder → authentication.getName() (email).
         */
        lenient().when(securityContext.getAuthentication()).thenReturn(authentication);
        SecurityContextHolder.setContext(securityContext);
        lenient().when(authentication.getName()).thenReturn(EMAIL);
    }

    @AfterEach
    void clearSecurityContext() throws Exception {
        SecurityContextHolder.clearContext();
    }

    private User makeUser(Long id, Role role) {
        final User u = new User();
        u.setId(id);
        u.setEmail(EMAIL);
        u.setRole(role);
        return u;
    }

    private Post makeSavedPost() throws Exception {
        final Post p = new Post();
        p.setId(1L);
        p.setUserId(USER_ID);
        p.setContent("Hello World");
        p.setCreatedAt(LocalDateTime.now());
        return p;
    }

    // ── getGlobalFeed() ───────────────────────────────────────────────────────

    @Test
    void getGlobalFeed_returns200_withAllPosts() throws Exception {
        /*
         * No authentication check — delegates directly to feedService.
         * No branches to cover.
         */
        final List<PostWithCommentCountDto> posts = List.of();
        when(feedService.getAllPostsWithCommentCount()).thenReturn(posts);

        final ResponseEntity<?> response = controller.getGlobalFeed();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(posts);
    }

    // ── getUserFeed() ─────────────────────────────────────────────────────────

    @Test
    void getUserFeed_returns403_whenUserNotFound() throws Exception {
        /*
         * Covers: userRepository.findByEmail() returns empty → user == null → 403.
         */
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.getUserFeed(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void getUserFeed_returns403_whenDifferentUserAndNotAdmin() throws Exception {
        /*
         * Covers: user found, user.getId() != userId AND role != ADMIN → 403.
         */
        final User user = makeUser(99L, Role.PATIENT);  // different id, not admin
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));

        final ResponseEntity<?> response = controller.getUserFeed(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void getUserFeed_returns200_whenSameUser() throws Exception {
        /*
         * Covers: user.getId().equals(userId) → condition false → proceeds to service.
         */
        final User user = makeUser(USER_ID, Role.PATIENT);
        final List<Post> posts = List.of();
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(feedService.getPostsByUser(USER_ID)).thenReturn(posts);

        final ResponseEntity<?> response = controller.getUserFeed(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void getUserFeed_returns200_whenAdmin() throws Exception {
        /*
         * Covers: user.getId() != userId but role == ADMIN
         * → !user.getId().equals(userId) && !isAdmin → false → proceeds.
         */
        final User admin = makeUser(99L, Role.ADMIN);  // different id, but admin
        final List<Post> posts = List.of();
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(admin));
        when(feedService.getPostsByUser(USER_ID)).thenReturn(posts);

        final ResponseEntity<?> response = controller.getUserFeed(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    // ── getFriendsFeed() ──────────────────────────────────────────────────────

    @Test
    void getFriendsFeed_returns403_whenUserNotFound() throws Exception {
        /*
         * Covers: userRepository.findByEmail() returns empty → user == null → 403.
         */
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.getFriendsFeed();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void getFriendsFeed_returns200_whenUserFound() throws Exception {
        /*
         * Covers: user found → delegates to feedService.getPostsByUserAndFriends().
         */
        final User user = makeUser(USER_ID, Role.PATIENT);
        final List<PostWithCommentCountDto> posts = List.of();
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(feedService.getPostsByUserAndFriends(USER_ID)).thenReturn(posts);

        final ResponseEntity<?> response = controller.getFriendsFeed();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    // ── createPost() + resolveDisplayName() ──────────────────────────────────

    private Post postDataFor(Long userId) {
        final Post p = new Post();
        p.setUserId(userId);
        p.setContent("Test content");
        return p;
    }

    @Test
    void createPost_returns403_whenUserNotFound() throws Exception {
        /*
         * Covers: userRepository.findByEmail() returns empty → user == null → 403.
         */
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.createPost(postDataFor(USER_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void createPost_returns403_whenUserIdMismatch() throws Exception {
        /*
         * Covers: user.getId() != postData.getUserId() → 403.
         */
        final User user = makeUser(USER_ID, Role.PATIENT);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));

        final Post postData = postDataFor(999L);  // different userId

        final ResponseEntity<?> response = controller.createPost(postData);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void createPost_returns201_withPatientDisplayName_whenPatientFound() throws Exception {
        /*
         * Covers: resolveDisplayName → PATIENT role → patientRepository found
         * → firstName + " " + lastName.
         */
        final User user = makeUser(USER_ID, Role.PATIENT);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(feedService.createPost(USER_ID, "Test content", null)).thenReturn(makeSavedPost());

        final Patient patient = new Patient();
        patient.setFirstName("Alice");
        patient.setLastName("Smith");
        when(patientRepository.findByUserId(USER_ID)).thenReturn(Optional.of(patient));

        final ResponseEntity<?> response = controller.createPost(postDataFor(USER_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        final PostWithCommentCountDto dto = (PostWithCommentCountDto) response.getBody();
        assertThat(dto.getUsername()).isEqualTo("Alice Smith");
    }

    @Test
    void createPost_returns201_withEmailFallback_whenPatientNotFound() throws Exception {
        /*
         * Covers: resolveDisplayName → PATIENT role → patientRepository empty
         * → falls back to user.getEmail().
         */
        final User user = makeUser(USER_ID, Role.PATIENT);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(feedService.createPost(USER_ID, "Test content", null)).thenReturn(makeSavedPost());
        when(patientRepository.findByUserId(USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.createPost(postDataFor(USER_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        final PostWithCommentCountDto dto = (PostWithCommentCountDto) response.getBody();
        assertThat(dto.getUsername()).isEqualTo(EMAIL);
    }

    @Test
    void createPost_returns201_withCaregiverDisplayName_whenCaregiverFound() throws Exception {
        /*
         * Covers: resolveDisplayName → CAREGIVER role → caregiverRepository found
         * → firstName + " " + lastName.
         */
        final User user = makeUser(USER_ID, Role.CAREGIVER);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(feedService.createPost(USER_ID, "Test content", null)).thenReturn(makeSavedPost());

        final Caregiver caregiver = new Caregiver();
        caregiver.setFirstName("Bob");
        caregiver.setLastName("Jones");
        when(caregiverRepository.findByUserId(USER_ID)).thenReturn(Optional.of(caregiver));

        final ResponseEntity<?> response = controller.createPost(postDataFor(USER_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        final PostWithCommentCountDto dto = (PostWithCommentCountDto) response.getBody();
        assertThat(dto.getUsername()).isEqualTo("Bob Jones");
    }

    @Test
    void createPost_returns201_withEmailFallback_whenCaregiverNotFound() throws Exception {
        /*
         * Covers: resolveDisplayName → CAREGIVER role → caregiverRepository empty
         * → falls back to user.getEmail().
         */
        final User user = makeUser(USER_ID, Role.CAREGIVER);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(feedService.createPost(USER_ID, "Test content", null)).thenReturn(makeSavedPost());
        when(caregiverRepository.findByUserId(USER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.createPost(postDataFor(USER_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        final PostWithCommentCountDto dto = (PostWithCommentCountDto) response.getBody();
        assertThat(dto.getUsername()).isEqualTo(EMAIL);
    }

    @Test
    void createPost_returns201_withEmailDisplayName_forOtherRole() throws Exception {
        /*
         * Covers: resolveDisplayName → else branch (ADMIN or FAMILY_MEMBER)
         * → returns user.getEmail() directly.
         */
        final User user = makeUser(USER_ID, Role.ADMIN);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(feedService.createPost(USER_ID, "Test content", null)).thenReturn(makeSavedPost());

        final ResponseEntity<?> response = controller.createPost(postDataFor(USER_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        final PostWithCommentCountDto dto = (PostWithCommentCountDto) response.getBody();
        assertThat(dto.getUsername()).isEqualTo(EMAIL);
    }

    @Test
    void createPost_returns500_whenServiceThrowsException() throws Exception {
        /*
         * Covers: feedService.createPost() throws Exception
         * → caught by catch block → 500 with error message.
         */
        final User user = makeUser(USER_ID, Role.ADMIN);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(feedService.createPost(USER_ID, "Test content", null))
                .thenThrow(new RuntimeException("DB error"));

        final ResponseEntity<?> response = controller.createPost(postDataFor(USER_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        assertThat(response.getBody().toString()).contains("Error creating post");
    }
}
