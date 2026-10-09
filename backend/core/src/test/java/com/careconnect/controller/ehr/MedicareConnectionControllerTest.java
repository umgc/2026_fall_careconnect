package com.careconnect.controller.ehr;

import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareConnectionService.ConnectionStatus;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/** The Medicare connection status the app's connect tile reads, in live and mock mode. */
class MedicareConnectionControllerTest {

    private static final String EMAIL = "patient@example.test";
    private static final Authentication SIGNED_IN = new UsernamePasswordAuthenticationToken(EMAIL, null, List.of());

    private MedicareConnectionService connections;
    private UserRepository users;
    private MedicareProperties properties;
    private MedicareConnectionController controller;

    @BeforeEach
    void setUp() {
        connections = mock(MedicareConnectionService.class);
        users = mock(UserRepository.class);
        properties = new MedicareProperties();
        controller = new MedicareConnectionController(connections, users, properties, "http://localhost:3000");
    }

    private void mode(final String mode) {
        ReflectionTestUtils.setField(properties, "mode", mode);
    }

    @Test
    @DisplayName("live mode: status is the signed-in patient's real link state")
    void liveModeReportsTheRealLink() {
        mode(MedicareProperties.MODE_LIVE);
        final User user = User.builder().id(6L).email(EMAIL).build();
        when(users.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(connections.patientIdFor(user)).thenReturn(Optional.of(2L));
        final ConnectionStatus linked = new ConnectionStatus(true, "LINKED", LocalDateTime.of(2026, 10, 1, 9, 0));
        when(connections.status(2L)).thenReturn(linked);

        assertThat(controller.status("medicare", SIGNED_IN).getBody()).isEqualTo(linked);
    }

    @Test
    @DisplayName("live mode: a user with no patient record is not linked")
    void liveModeWithoutPatientIsUnlinked() {
        mode(MedicareProperties.MODE_LIVE);
        when(users.findByEmail(EMAIL)).thenReturn(Optional.empty());

        assertThat(controller.status("medicare", SIGNED_IN).getBody())
                .isEqualTo(new ConnectionStatus(false, "UNLINKED", null));
    }

    @Test
    @DisplayName("mock mode: every signed-in user is reported linked, matching the fixture reads, without looking up a link")
    void mockModeReportsLinked() {
        mode(MedicareProperties.MODE_MOCK);

        assertThat(controller.status("medicare", SIGNED_IN).getBody())
                .isEqualTo(new ConnectionStatus(true, "LINKED", null));
        verifyNoInteractions(connections, users);
    }

    @Test
    @DisplayName("mock mode: another source is still 404")
    void mockModeOtherSourceIsNotFound() {
        mode(MedicareProperties.MODE_MOCK);

        assertThatThrownBy(() -> controller.status("athena", SIGNED_IN)).isInstanceOf(AppException.class);
    }
}
