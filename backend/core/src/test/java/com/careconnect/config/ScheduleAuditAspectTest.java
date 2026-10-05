package com.careconnect.config;

import com.careconnect.model.schedule.ScheduledVisitAudit;
import com.careconnect.repository.schedule.ScheduledVisitAuditRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.aspectj.lang.JoinPoint;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.Collections;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ScheduleAuditAspectTest {

    @Mock
    private ScheduledVisitAuditRepository auditRepository;

    @Mock
    private ObjectMapper objectMapper;

    @Mock
    private JoinPoint joinPoint;

    private ScheduleAuditAspect aspect;

    @BeforeEach
    void setUp() {
        aspect = new ScheduleAuditAspect(auditRepository, objectMapper);
        SecurityContextHolder.clearContext();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private void setAuthenticatedUser(String username) {
        UsernamePasswordAuthenticationToken auth =
                new UsernamePasswordAuthenticationToken(username, null, Collections.emptyList());
        SecurityContextHolder.getContext().setAuthentication(auth);
    }

    @Test
    void auditVisitCreation_withValidResult_savesAuditEntry() throws Exception {
        setAuthenticatedUser("nurse@example.com");
        Object result = createMockScheduledVisitResponse(42L);
        when(objectMapper.writeValueAsString(result)).thenReturn("{\"id\":42}");
        when(auditRepository.save(any(ScheduledVisitAudit.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        aspect.auditVisitCreation(joinPoint, result);

        ArgumentCaptor<ScheduledVisitAudit> captor =
                ArgumentCaptor.forClass(ScheduledVisitAudit.class);
        verify(auditRepository).save(captor.capture());

        ScheduledVisitAudit audit = captor.getValue();
        assertThat(audit.getVisitId()).isEqualTo(42L);
        assertThat(audit.getAction()).isEqualTo("CREATED");
        assertThat(audit.getOldValue()).isNull();
        assertThat(audit.getNewValue()).isEqualTo("{\"id\":42}");
        assertThat(audit.getChangedBy()).isEqualTo("nurse@example.com");
        assertThat(audit.getChangedAt()).isNotNull();
    }

    @Test
    void auditVisitCreation_withNullResult_doesNotSave() {
        aspect.auditVisitCreation(joinPoint, null);

        verify(auditRepository, never()).save(any());
    }

    @Test
    void auditVisitCreation_withNoAuthentication_usesSystem() throws Exception {
        Object result = createMockScheduledVisitResponse(10L);
        when(objectMapper.writeValueAsString(result)).thenReturn("{\"id\":10}");
        when(auditRepository.save(any(ScheduledVisitAudit.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        aspect.auditVisitCreation(joinPoint, result);

        ArgumentCaptor<ScheduledVisitAudit> captor =
                ArgumentCaptor.forClass(ScheduledVisitAudit.class);
        verify(auditRepository).save(captor.capture());
        assertThat(captor.getValue().getChangedBy()).isEqualTo("SYSTEM");
    }

    @Test
    void auditVisitUpdate_doesNotThrow() {
        aspect.auditVisitUpdate(joinPoint);

        // auditVisitUpdate is a fallback that only logs; no repository call expected
        verify(auditRepository, never()).save(any());
    }

    @Test
    void auditVisitDeletion_withLongArg_savesAuditEntry() {
        setAuthenticatedUser("admin@example.com");
        when(joinPoint.getArgs()).thenReturn(new Object[]{99L});
        when(auditRepository.save(any(ScheduledVisitAudit.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        aspect.auditVisitDeletion(joinPoint);

        ArgumentCaptor<ScheduledVisitAudit> captor =
                ArgumentCaptor.forClass(ScheduledVisitAudit.class);
        verify(auditRepository).save(captor.capture());

        ScheduledVisitAudit audit = captor.getValue();
        assertThat(audit.getVisitId()).isEqualTo(99L);
        assertThat(audit.getAction()).isEqualTo("DELETED");
        assertThat(audit.getChangedField()).isEqualTo("full_record");
        assertThat(audit.getOldValue()).isEqualTo("Visit record deleted");
        assertThat(audit.getNewValue()).isEmpty();
        assertThat(audit.getChangedBy()).isEqualTo("admin@example.com");
    }

    @Test
    void auditVisitDeletion_withNonLongArg_doesNotSave() {
        when(joinPoint.getArgs()).thenReturn(new Object[]{"not-a-long"});

        aspect.auditVisitDeletion(joinPoint);

        verify(auditRepository, never()).save(any());
    }

    @Test
    void auditVisitDeletion_withEmptyArgs_doesNotSave() {
        when(joinPoint.getArgs()).thenReturn(new Object[]{});

        aspect.auditVisitDeletion(joinPoint);

        verify(auditRepository, never()).save(any());
    }

    @Test
    void auditStatusChange_withValidArgs_savesAuditEntry() {
        setAuthenticatedUser("doctor@example.com");
        when(joinPoint.getArgs()).thenReturn(new Object[]{5L, "COMPLETED"});
        when(auditRepository.save(any(ScheduledVisitAudit.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        aspect.auditStatusChange(joinPoint, new Object());

        ArgumentCaptor<ScheduledVisitAudit> captor =
                ArgumentCaptor.forClass(ScheduledVisitAudit.class);
        verify(auditRepository).save(captor.capture());

        ScheduledVisitAudit audit = captor.getValue();
        assertThat(audit.getVisitId()).isEqualTo(5L);
        assertThat(audit.getAction()).isEqualTo("UPDATED");
        assertThat(audit.getChangedField()).isEqualTo("status");
        assertThat(audit.getOldValue()).isNull();
        assertThat(audit.getNewValue()).isEqualTo("COMPLETED");
        assertThat(audit.getChangedBy()).isEqualTo("doctor@example.com");
    }

    @Test
    void auditStatusChange_withInsufficientArgs_doesNotSave() {
        when(joinPoint.getArgs()).thenReturn(new Object[]{5L});

        aspect.auditStatusChange(joinPoint, new Object());

        verify(auditRepository, never()).save(any());
    }

    /**
     * Creates a mock object whose class is named "ScheduledVisitResponse" with an "id" field,
     * which is what extractVisitIdFromResult expects via reflection.
     */
    private Object createMockScheduledVisitResponse(Long id) {
        return new ScheduledVisitResponse(id);
    }

    /**
     * Inner class used to simulate ScheduledVisitResponse for reflection-based extraction.
     */
    @SuppressWarnings("unused")
    private static class ScheduledVisitResponse {
        private Long id;

        ScheduledVisitResponse(Long id) {
            this.id = id;
        }
    }
}
