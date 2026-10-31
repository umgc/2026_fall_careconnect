package com.careconnect.controller.ehr;

import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.ehr.MedicareConnectionService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class MedicareConnectionControllerLinkCoverageTest {

    private MedicareConnectionService connections;
    private MedicareConnectionController controller;
    private final Authentication auth = new UsernamePasswordAuthenticationToken("p@example.test", null, List.of());

    @BeforeEach
    void setUp() {
        connections = mock(MedicareConnectionService.class);
        UserRepository users = mock(UserRepository.class);
        User user = User.builder().id(1L).email("p@example.test").build();
        when(users.findByEmail("p@example.test")).thenReturn(Optional.of(user));
        when(connections.patientIdFor(user)).thenReturn(Optional.of(7L));
        controller = new MedicareConnectionController(connections, users, mock(MedicareProperties.class),
                "http://localhost:3000");
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(new MockHttpServletRequest()));
    }

    @AfterEach
    void tearDown() {
        RequestContextHolder.resetRequestAttributes();
    }

    @Test
    void connectUrlAndDisconnectForPatient() {
        when(connections.startLink(7L)).thenReturn("link-1");
        assertThat(controller.connectUrl("medicare", auth).getBody().get("url")).contains("linkToken=link-1");
        assertThat(controller.disconnect("medicare", auth).getBody()).isNotNull();
        verify(connections).disconnect(7L);
        assertThatThrownBy(() -> controller.connectUrl("medicare", null)).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> controller.disconnect("medicare", null)).isInstanceOf(AppException.class);
    }

    @Test
    void connectRedirectsByLinkState() throws Exception {
        when(connections.pendingLink("expired")).thenReturn(Optional.empty());
        MockHttpServletResponse expired = new MockHttpServletResponse();
        controller.connect("expired", new MockHttpServletRequest(), expired);
        assertThat(expired.getRedirectedUrl()).startsWith("http://localhost:3000");

        when(connections.pendingLink("live")).thenReturn(Optional.of(new EhrPatientCrosswalk()));
        MockHttpServletResponse live = new MockHttpServletResponse();
        controller.connect("live", new MockHttpServletRequest(), live);
        assertThat(live.getRedirectedUrl()).contains("/oauth2/authorization/medicare");
    }
}
