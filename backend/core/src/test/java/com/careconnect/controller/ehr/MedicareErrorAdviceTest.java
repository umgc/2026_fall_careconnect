package com.careconnect.controller.ehr;

import ca.uhn.fhir.rest.server.exceptions.AuthenticationException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareConnectionService.MedicareNotConnectedException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.support.StaticListableBeanFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.context.SecurityContextImpl;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * ERR-MCR-05 for the Medicare reads (FR-MCR-09): 409, never 401 (which would sign the app out), and a
 * token Blue Button rejects marks the link Unlinked.
 */
class MedicareErrorAdviceTest {

    private static final String EMAIL = "patient@example.test";

    private MedicareConnectionService connections;
    private UserRepository users;
    private MedicareErrorAdvice advice;

    @BeforeEach
    void setUp() {
        connections = mock(MedicareConnectionService.class);
        users = mock(UserRepository.class);
        advice = new MedicareErrorAdvice(provider(MedicareConnectionService.class, connections),
                provider(UserRepository.class, users));
        SecurityContextHolder.clearContext();
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    private static <T> ObjectProvider<T> provider(final Class<T> type, final T bean) {
        final StaticListableBeanFactory beans = new StaticListableBeanFactory();
        if (bean != null) {
            beans.addBean(type.getSimpleName(), bean);
        }
        return beans.getBeanProvider(type);
    }

    private static void signIn() {
        SecurityContextHolder.setContext(new SecurityContextImpl(
                new UsernamePasswordAuthenticationToken(EMAIL, null, List.of())));
    }

    private static void assertErrMcr05(final ResponseEntity<Map<String, Object>> response) {
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(response.getBody())
                .containsEntry("error", "ERR-MCR-05")
                .containsEntry("message", MedicareConnectionService.ERR_MCR_05_MESSAGE)
                .containsEntry("connected", false);
    }

    @Test
    @DisplayName("no working link is ERR-MCR-05 as 409, and nothing is changed")
    void notConnectedIs409() {
        assertErrMcr05(advice.notConnected(new MedicareNotConnectedException()));
        verifyNoInteractions(connections, users);
    }

    @Test
    @DisplayName("a token Blue Button rejects marks the signed-in patient's link Unlinked, then answers ERR-MCR-05")
    void rejectedTokenMarksLinkUnlinked() {
        signIn();
        final User user = User.builder().id(6L).email(EMAIL).build();
        when(users.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(connections.patientIdFor(user)).thenReturn(Optional.of(2L));

        assertErrMcr05(advice.tokenRejected(new AuthenticationException("401 from Blue Button")));
        verify(connections).markTokenRejected(2L);
    }

    @Test
    @DisplayName("a signed-in user with no patient record still gets ERR-MCR-05, and no link is touched")
    void rejectedTokenWithoutPatientTouchesNothing() {
        signIn();
        final User user = User.builder().id(6L).email(EMAIL).build();
        when(users.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(connections.patientIdFor(user)).thenReturn(Optional.empty());

        assertErrMcr05(advice.tokenRejected(new AuthenticationException("401")));
        verify(connections, never()).markTokenRejected(org.mockito.ArgumentMatchers.any());
    }

    @Test
    @DisplayName("with nobody signed in, a rejected token is still ERR-MCR-05 and no lookup is made")
    void rejectedTokenWithoutSignIn() {
        assertErrMcr05(advice.tokenRejected(new AuthenticationException("401")));
        verifyNoInteractions(connections, users);
    }

    @Test
    @DisplayName("in a context without the Medicare beans (a @WebMvcTest slice) the advice still answers instead of failing")
    void worksWithoutBeans() {
        signIn();
        final MedicareErrorAdvice bare = new MedicareErrorAdvice(
                provider(MedicareConnectionService.class, null), provider(UserRepository.class, null));

        assertErrMcr05(bare.tokenRejected(new AuthenticationException("401")));
    }
}
