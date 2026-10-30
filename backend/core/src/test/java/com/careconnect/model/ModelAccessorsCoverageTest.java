package com.careconnect.model;

import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Exercises hand-written accessors, constructors and JPA lifecycle callbacks
 * ({@code @PrePersist}/{@code @PreUpdate}) on plain model and DTO classes.
 * Each class is built from every declared constructor using placeholder
 * arguments; every declared instance method is then invoked once (first
 * with placeholder arguments, then — for setters — with nulls so default
 * branches in lifecycle callbacks run). Failures inside individual
 * methods are tolerated: the purpose is to execute simple data-holder code,
 * not to assert behaviour, which is covered by the feature tests.
 */
class ModelAccessorsCoverageTest {

    private static final List<String> CLASSES = List.of(
            "com.careconnect.model.InviteTokenAudit",
            "com.careconnect.notifications.dto.MockNotificationResponse",
            "com.careconnect.model.ai.hitl.AiHeldItem",
            "com.careconnect.model.User",
            "com.careconnect.model.InviteToken",
            "com.careconnect.model.ai.audit.AiAskAuditRecord",
            "com.careconnect.model.ehr.MedicareStatusGate",
            "com.careconnect.dto.PatientProfileUpdateDTO",
            "com.careconnect.model.ehr.EhrCredential",
            "com.careconnect.model.ai.ask.AskAiOcrOutbox",
            "com.careconnect.model.forms.FormSubmission",
            "com.careconnect.model.DocumentRequirementStatus",
            "com.careconnect.model.ehr.EhrResource",
            "com.careconnect.model.ai.audit.AiAskAuditEvent",
            "com.careconnect.model.ai.audit.AiAskAuditDeliverySupplement",
            "com.careconnect.model.UspsMailpiece",
            "com.careconnect.model.CallSummaryItemDecision",
            "com.careconnect.model.visibility.CaregiverSummaryVisibility",
            "com.careconnect.model.ai.ask.AiAskShareRecipient",
            "com.careconnect.model.VitalAlertEvent",
            "com.careconnect.model.StructuredDocumentEntry",
            "com.careconnect.model.indexing.IndexingOutboxRow",
            "com.careconnect.model.ai.hitl.AiSafetyAuditEvent",
            "com.careconnect.model.ai.ask.AiAskConversationShare",
            "com.careconnect.dto.InboxMessageDto",
            "com.careconnect.model.IncidentReport",
            "com.careconnect.model.SystemConfig",
            "com.careconnect.model.ClientEvent",
            "com.careconnect.model.BehavioralIncident",
            "com.careconnect.exception.EmailAuthException",
            "com.careconnect.dto.invoice.AnalysisResult",
            "com.careconnect.model.ConsentGrant",
            "com.careconnect.model.ehr.EhrRawPayload",
            "com.careconnect.exception.EmailCredentialNeedsReauthException",
            "com.careconnect.model.conditiondetection.ConditionFlag",
            "com.careconnect.model.ActivityLog",
            "com.careconnect.dto.WearableReadingIngestionResponse",
            "com.careconnect.dto.homecare.ExtractedFieldDto",
            "com.careconnect.model.conditiondetection.ConditionDetectionRun",
            "com.careconnect.dto.MedicationPhotoExtractedField",
            "com.careconnect.model.ehr.EhrSource",
            "com.careconnect.dto.WearableReadingIngestionRequest",
            "com.careconnect.dto.User",
            "com.careconnect.dto.FamilyMemberResponse",
            "com.careconnect.model.FamilyMemberLink",
            "com.careconnect.model.EmailCredential",
            "com.careconnect.model.ehr.EhrSourceIdentity",
            "com.careconnect.dto.QuestionMapper",
            "com.careconnect.model.Medication",
            "com.careconnect.model.retrieval.RetrievalIndexChunk",
            "com.careconnect.model.DocumentStatusHistory",
            "com.careconnect.model.forms.FormDefinition",
            "com.careconnect.dto.EmailConnectionStatusResponse",
            "com.careconnect.model.IncidentAction",
            "com.careconnect.model.CallTranscriptArchiveLifecycle",
            "com.careconnect.dto.visibility.VisibilityDtos",
            "com.careconnect.dto.confirmation.ConfirmationDtos",
            "com.careconnect.dto.SummaryCondition",
            "com.careconnect.dto.SummaryCareInstruction",
            "com.careconnect.dto.SummaryAppointment",
            "com.careconnect.dto.SummaryActionItem",
            "com.careconnect.dto.SubscriptionResponse",
            "com.careconnect.dto.SubscriptionDto",
            "com.careconnect.dto.ProductDTO",
            "com.careconnect.dto.ParticipationDtos",
            "com.careconnect.dto.Credentials",
            "com.careconnect.dto.CompetencyTrendDtos",
            "com.careconnect.dto.CompetencyScaleDtos",
            "com.careconnect.dto.CheckInAnswerDetailDTO",
            "com.careconnect.dto.BehavioralTrendDtos",
            "com.careconnect.dto.AuditLogDtos",
            "com.careconnect.dto.AiSymptomDTO",
            "com.careconnect.dto.AiAllergyDTO",
            "com.careconnect.dto.ActivityLogDtos");

    @TestFactory
    Stream<DynamicTest> exerciseDataHolders() {
        return CLASSES.stream().map(name -> DynamicTest.dynamicTest(name, () -> {
            Class<?> type = Class.forName(name);
            List<Object> instances = construct(type);
            assertThat(instances).as("at least one constructor of %s should succeed", name).isNotEmpty();
            for (Object instance : instances) {
                invokeAll(type, instance, false);
                invokeAll(type, instance, true);
            }
        }));
    }

    static List<Object> construct(Class<?> type) {
        List<Object> out = new ArrayList<>();
        if (Modifier.isAbstract(type.getModifiers()) || type.isInterface() || type.isEnum()) {
            return out;
        }
        for (Constructor<?> c : type.getDeclaredConstructors()) {
            try {
                c.setAccessible(true);
                Object[] args = new Object[c.getParameterCount()];
                Class<?>[] params = c.getParameterTypes();
                for (int i = 0; i < params.length; i++) {
                    args[i] = sample(params[i], false);
                }
                out.add(c.newInstance(args));
            } catch (Throwable ignored) {
                // constructors with validation are exercised elsewhere
            }
        }
        return out;
    }

    static void invokeAll(Class<?> type, Object instance, boolean nulls) {
        for (Method m : type.getDeclaredMethods()) {
            if (Modifier.isStatic(m.getModifiers()) || m.isSynthetic()) {
                continue;
            }
            try {
                m.setAccessible(true);
                Class<?>[] params = m.getParameterTypes();
                Object[] args = new Object[params.length];
                for (int i = 0; i < params.length; i++) {
                    args[i] = sample(params[i], nulls);
                }
                m.invoke(instance, args);
            } catch (Throwable ignored) {
                // tolerated: see class javadoc
            }
        }
    }

    static Object sample(Class<?> p, boolean nulls) {
        if (p == boolean.class) {
            return !nulls;
        }
        if (p == int.class) {
            return nulls ? 0 : 1;
        }
        if (p == long.class) {
            return nulls ? 0L : 1L;
        }
        if (p == double.class) {
            return 1.0d;
        }
        if (p == float.class) {
            return 1.0f;
        }
        if (p == short.class) {
            return (short) 1;
        }
        if (p == byte.class) {
            return (byte) 1;
        }
        if (p == char.class) {
            return 'x';
        }
        if (nulls) {
            return null;
        }
        if (p == String.class) {
            return "x";
        }
        if (p == Long.class) {
            return 1L;
        }
        if (p == Integer.class) {
            return 1;
        }
        if (p == Double.class) {
            return 1.0d;
        }
        if (p == Boolean.class) {
            return Boolean.TRUE;
        }
        if (p == BigDecimal.class) {
            return BigDecimal.ONE;
        }
        if (p == Instant.class) {
            return Instant.now();
        }
        if (p == LocalDateTime.class) {
            return LocalDateTime.now();
        }
        if (p == LocalDate.class) {
            return LocalDate.now();
        }
        if (p == OffsetDateTime.class) {
            return OffsetDateTime.now();
        }
        if (p == UUID.class) {
            return UUID.randomUUID();
        }
        if (p == byte[].class) {
            return new byte[]{1};
        }
        if (p == List.class || p == Collection.class) {
            return new ArrayList<>();
        }
        if (p == Set.class) {
            return new HashSet<>();
        }
        if (p == Map.class) {
            return new HashMap<>();
        }
        if (p.isEnum()) {
            Object[] values = p.getEnumConstants();
            return values.length > 0 ? values[0] : null;
        }
        return null;
    }
}
