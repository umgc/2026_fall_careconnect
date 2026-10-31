package com.careconnect.controller;

import com.careconnect.dto.StmlRecallRequest;
import com.careconnect.dto.StmlSearchRequest;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.StmlCheckInService;
import com.careconnect.service.StmlRecallService;
import com.careconnect.service.StmlSearchService;
import com.careconnect.service.StmlService;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.reset;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class StmlControllerCoverageTest {

    @Mock private StmlService stmlService;
    @Mock private StmlRecallService stmlRecallService;
    @Mock private StmlCheckInService stmlCheckInService;
    @Mock private StmlSearchService stmlSearchService;
    @Mock private RetrievalScopeService retrievalScopeService;
    @Mock private UserRepository userRepository;
    @InjectMocks private StmlController controller;

    private final User caller = User.builder().id(5L).email("c@example.test").role(Role.CAREGIVER).build();

    @BeforeEach
    void auth() {
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("c@example.test", null, List.of()));
        org.mockito.Mockito.when(userRepository.findByEmail("c@example.test")).thenReturn(Optional.of(caller));
    }

    @AfterEach
    void clear() {
        SecurityContextHolder.clearContext();
    }

    private void callAll(int expected) {
        assertThat(controller.getDailyBrief(1L).getStatusCode().value()).isEqualTo(expected);
        assertThat(controller.recall(1L, new StmlRecallRequest()).getStatusCode().value()).isEqualTo(expected);
        assertThat(controller.getCheckInView(1L, 5L).getStatusCode().value()).isEqualTo(expected);
        assertThat(controller.search(1L, new StmlSearchRequest()).getStatusCode().value()).isEqualTo(expected);
    }

    @Test
    void endpointsReturnOkWhenScopeAllows() {
        callAll(200);
        assertThat(controller.getCheckInView(1L, 99L).getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void endpointsMapForbiddenScope() throws Exception {
        doThrow(ForbiddenScopeException.unsupportedRole(Role.CAREGIVER, 5L, "no", null))
                .when(retrievalScopeService).resolveRetrievalScope(any(User.class), anyLong());
        callAll(403);
    }

    @Test
    void endpointsMapUnauthorized() throws Exception {
        reset(retrievalScopeService);
        doThrow(new UnauthorizedException("no"))
                .when(retrievalScopeService).resolveRetrievalScope(any(User.class), anyLong());
        callAll(401);
    }
}
