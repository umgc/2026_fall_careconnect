package com.careconnect.controller;

import com.careconnect.model.Comment;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.CommentService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;
import java.util.Optional;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@ExtendWith(MockitoExtension.class)
class CommentControllerTest {

    private MockMvc mockMvc;

    @Mock
    private CommentService commentService;

    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private CommentController controller;

    @BeforeEach
    void setUp() throws Exception {
        mockMvc = MockMvcBuilders
                .standaloneSetup(controller)
                .build();
    }

    @AfterEach
    void tearDown() throws Exception {
        SecurityContextHolder.clearContext();
        /*
         * Ensures no authentication leaks between tests.
         */
    }

    private void mockAuthenticated() throws Exception {
        final Authentication authentication = mock(Authentication.class);
        final SecurityContext securityContext = mock(SecurityContext.class);

        when(authentication.isAuthenticated()).thenReturn(true);
        when(securityContext.getAuthentication()).thenReturn(authentication);

        SecurityContextHolder.setContext(securityContext);
        /*
         * Used for GET endpoint (no email needed).
         */
    }

    private void mockAuthenticatedUser(String email) {
        final Authentication authentication = mock(Authentication.class);
        final SecurityContext securityContext = mock(SecurityContext.class);

        when(authentication.isAuthenticated()).thenReturn(true);
        when(authentication.getName()).thenReturn(email);
        when(securityContext.getAuthentication()).thenReturn(authentication);

        SecurityContextHolder.setContext(securityContext);
        /*
         * Used for POST endpoint (email required).
         */
    }

    @Test
    void getComments_shouldReturnForbidden_whenNotAuthenticated() throws Exception {

        mockMvc.perform(get("/v1/api/comments/post/1"))
                .andExpect(status().isForbidden());
    }

    @Test
    void getComments_shouldReturnComments_whenAuthenticated() throws Exception {

        mockAuthenticated();

        when(commentService.getCommentsForPost(1L))
                .thenReturn(List.of(new Comment()));

        mockMvc.perform(get("/v1/api/comments/post/1"))
                .andExpect(status().isOk());

        verify(commentService).getCommentsForPost(1L);
    }

    @Test
    void addComment_shouldReturnForbidden_whenNotAuthenticated() throws Exception {

        mockMvc.perform(post("/v1/api/comments/post/1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void addComment_shouldReturnForbidden_whenUserNotFound() throws Exception {

        mockAuthenticatedUser("missing@example.com");

        when(userRepository.findByEmail("missing@example.com"))
                .thenReturn(Optional.empty());

        mockMvc.perform(post("/v1/api/comments/post/1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(
                                "{" +
                                        "\"userId\": 1," +
                                        "\"username\": \"test\"," +
                                        "\"content\": \"Hello\"" +
                                        "}"
                        ))
                .andExpect(status().isForbidden());

        verify(userRepository).findByEmail("missing@example.com");
    }

    @Test
    void addComment_shouldReturnForbidden_whenUserIdMismatch() throws Exception {

        mockAuthenticatedUser("user@example.com");

        final User user = new User();
        user.setId(5L);

        when(userRepository.findByEmail("user@example.com"))
                .thenReturn(Optional.of(user));

        mockMvc.perform(post("/v1/api/comments/post/1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(
                                "{" +
                                        "\"userId\": 1," +
                                        "\"username\": \"wrong\"," +
                                        "\"content\": \"Invalid\"" +
                                        "}"
                        ))
                .andExpect(status().isForbidden());

        verify(userRepository).findByEmail("user@example.com");
    }

    @Test
    void addComment_shouldReturnCreated_whenValid() throws Exception {

        mockAuthenticatedUser("user@example.com");

        final User user = new User();
        user.setId(1L);

        final Comment saved = new Comment();
        saved.setId(100L);

        when(userRepository.findByEmail("user@example.com"))
                .thenReturn(Optional.of(user));

        when(commentService.addComment(1L, 1L, "john", "Nice post"))
                .thenReturn(saved);

        mockMvc.perform(post("/v1/api/comments/post/1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(
                                "{" +
                                        "\"userId\": 1," +
                                        "\"username\": \"john\"," +
                                        "\"content\": \"Nice post\"" +
                                        "}"
                        ))
                .andExpect(status().isCreated());

        verify(commentService)
                .addComment(1L, 1L, "john", "Nice post");
    }
}