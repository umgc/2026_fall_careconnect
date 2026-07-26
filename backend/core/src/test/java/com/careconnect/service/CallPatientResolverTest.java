package com.careconnect.service;

import com.careconnect.model.CallSession;
import com.careconnect.repository.CallSessionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CallPatientResolverTest {

    @Mock
    private CallSessionRepository callSessionRepository;

    private CallPatientResolver resolver;

    @BeforeEach
    void setUp() {
        resolver = new CallPatientResolver(callSessionRepository);
    }

    @Test
    void requirePatientId_usesDurableCallSessionPatientEntityId() {
        final CallSession session = new CallSession();
        session.setPatientId(42L);
        when(callSessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));

        assertThat(resolver.requirePatientId("call-1")).isEqualTo(42L);
    }

    @Test
    void requirePatientId_rejectsMissingSession() {
        when(callSessionRepository.findByCallId("call-1")).thenReturn(Optional.empty());
        assertThatThrownBy(() -> resolver.requirePatientId("call-1"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("authoritative patient");
    }

    @Test
    void requirePatientId_rejectsNullSessionPatient() {
        final CallSession session = new CallSession();
        when(callSessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        assertThatThrownBy(() -> resolver.requirePatientId("call-1"))
                .isInstanceOf(IllegalStateException.class);
    }
}
