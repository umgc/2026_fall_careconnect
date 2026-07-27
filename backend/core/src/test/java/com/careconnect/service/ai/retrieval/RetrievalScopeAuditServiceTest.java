package com.careconnect.service.ai.retrieval;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

class RetrievalScopeAuditServiceTest {

    private final RetrievalScopeAuditService auditService = new RetrievalScopeAuditService();
    private ListAppender<ILoggingEvent> logAppender;
    private Logger logger;

    @BeforeEach
    void attachLogAppender() {
        logger = (Logger) LoggerFactory.getLogger(RetrievalScopeAuditService.class);
        logAppender = new ListAppender<>();
        logAppender.setContext(logger.getLoggerContext());
        logAppender.start();
        logger.setLevel(Level.WARN);
        logger.addAppender(logAppender);
        logger.setAdditive(false);
    }

    @AfterEach
    void detachLogAppender() {
        if (logger != null && logAppender != null) {
            logger.detachAppender(logAppender);
            logger.setAdditive(true);
        }
    }

    @Test
    @DisplayName("logScopeDenied returns audit id and does not throw")
    void logScopeDeniedReturnsAuditId() {
        User caller = User.builder()
                .id(5L)
                .email("patient@test.com")
                .role(Role.PATIENT)
                .build();

        assertThatCode(() -> {
            var auditId = auditService.logScopeDenied(
                    caller,
                    42L,
                    ScopeDenialReason.PATIENT_OUT_OF_SCOPE,
                    "Patient 42 is out of scope");

            assertThat(auditId).isNotNull();
        }).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("logScopeDenied tolerates null caller")
    void logScopeDeniedToleratesNullCaller() {
        assertThat(auditService.logScopeDenied(
                null,
                99L,
                ScopeDenialReason.PATIENT_NOT_FOUND,
                "Patient 99 not found")).isNotNull();
    }

    @Test
    @DisplayName("logScopeDenied emits structured audit fields")
    void logScopeDeniedEmitsStructuredFields() {
        User caller = User.builder()
                .id(5L)
                .email("patient@test.com")
                .role(Role.PATIENT)
                .build();

        var auditId = auditService.logScopeDenied(
                caller,
                42L,
                ScopeDenialReason.PATIENT_OUT_OF_SCOPE,
                "Patient 42 is out of scope");

        assertThat(logAppender.list).hasSize(1);
        String message = logAppender.list.get(0).getFormattedMessage();
        assertThat(message)
                .contains("eventType=SCOPE_DENIED")
                .contains("auditId=" + auditId)
                .contains("callerUserId=5")
                .contains("patientId=42")
                .contains("denialReason=PATIENT_OUT_OF_SCOPE")
                .contains("deliveryStatus=WITHHELD")
                .contains("retrievalPerformed=false")
                .doesNotContain("patient@test.com")
                .doesNotContain("Patient 42 is out of scope");
    }
}
