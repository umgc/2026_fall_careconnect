package com.careconnect.service.ai.retrieval;

import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Permission;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.util.EnumSet;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Task 2.1 / WBS 3.2.3 — RetrievalScopeService unit tests (FR-AI-1, REQ-SC-7/8). */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class RetrievalScopeServiceTest {

    private static final Long PATIENT_ENTITY_ID = 42L;
    private static final Long PATIENT_USER_ID = 10L;
    private static final Long OTHER_PATIENT_ENTITY_ID = 99L;

    @Mock
    private PatientRepository patientRepository;

    @Mock
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @Mock
    private FamilyMemberService familyMemberService;

    @Mock
    private RetrievalSourceExclusionProvider sourceExclusionProvider;

    @Mock
    private RetrievalConsentProvider consentProvider;

    @Mock
    private RetrievalScopeAuditService scopeAuditService;

    private RetrievalScopeService service;

    private User patientUser;
    private User caregiverUser;
    private User familyUser;
    private User adminUser;
    private Patient patient;

    @BeforeEach
    void setUp() {
        service = new RetrievalScopeService(
                new AuthorizationService(),
                patientRepository,
                caregiverPatientLinkService,
                familyMemberService,
                sourceExclusionProvider,
                consentProvider,
                scopeAuditService
        );

        patientUser = User.builder()
                .id(PATIENT_USER_ID)
                .email("patient@test.com")
                .role(Role.PATIENT)
                .build();

        caregiverUser = User.builder()
                .id(20L)
                .email("caregiver@test.com")
                .role(Role.CAREGIVER)
                .build();

        familyUser = User.builder()
                .id(30L)
                .email("family@test.com")
                .role(Role.FAMILY_MEMBER)
                .build();

        adminUser = User.builder()
                .id(1L)
                .email("admin@test.com")
                .role(Role.ADMIN)
                .build();

        patient = Patient.builder()
                .id(PATIENT_ENTITY_ID)
                .user(patientUser)
                .build();

        when(sourceExclusionProvider.getExcludedSourceTypes(anyLong())).thenReturn(Set.of());
        when(scopeAuditService.logScopeDenied(any(), anyLong(), any(), any()))
                .thenReturn(UUID.fromString("11111111-1111-1111-1111-111111111111"));
    }

    @Nested
    @DisplayName("PATIENT role")
    class PatientRole {

        @Test
        @DisplayName("resolves scope for own patient with default source types")
        void resolvesOwnPatientScope() throws Exception {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));

            RetrievalScope scope = service.resolveRetrievalScope(patientUser, PATIENT_ENTITY_ID);

            assertThat(scope.callerUserId()).isEqualTo(PATIENT_USER_ID);
            assertThat(scope.callerRole()).isEqualTo(Role.PATIENT);
            assertThat(scope.allowedPatientIds()).containsExactly(PATIENT_ENTITY_ID);
            assertThat(scope.allowedSourceTypes()).contains(RetrievalRecordType.CALL_SUMMARY);
            assertThat(scope.allowedSourceTypes()).doesNotContain(RetrievalRecordType.USPS_MAIL);
            assertThat(scope.consentGranted()).isTrue();
            assertThat(scope.visibilityFilter().permits("on_consent")).isTrue();
        }

        @Test
        @DisplayName("denies access to another patient's records")
        void deniesOtherPatient() {
            Patient otherPatient = Patient.builder()
                    .id(OTHER_PATIENT_ENTITY_ID)
                    .user(User.builder().id(50L).email("other@test.com").role(Role.PATIENT).build())
                    .build();
            when(patientRepository.findById(OTHER_PATIENT_ENTITY_ID)).thenReturn(Optional.of(otherPatient));

            assertThatThrownBy(() -> service.resolveRetrievalScope(patientUser, OTHER_PATIENT_ENTITY_ID))
                    .isInstanceOf(ForbiddenScopeException.class)
                    .hasMessageContaining("out of scope");
        }

        @Test
        @DisplayName("applies REQ-SC-7 source exclusions from patient preferences")
        void appliesSourceExclusions() throws Exception {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));
            when(sourceExclusionProvider.getExcludedSourceTypes(PATIENT_ENTITY_ID))
                    .thenReturn(Set.of(RetrievalRecordType.TRANSCRIPT_SEGMENT));

            RetrievalScope scope = service.resolveRetrievalScope(patientUser, PATIENT_ENTITY_ID);

            assertThat(scope.excludedSourceTypes()).contains(RetrievalRecordType.TRANSCRIPT_SEGMENT);
            assertThat(scope.allowedSourceTypes()).doesNotContain(RetrievalRecordType.TRANSCRIPT_SEGMENT);
        }

        @Test
        @DisplayName("intersects requested source types with permitted set")
        void intersectsRequestedSourceTypes() throws Exception {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));

            RetrievalScope scope = service.resolveRetrievalScope(
                    patientUser,
                    PATIENT_ENTITY_ID,
                    Set.of(RetrievalRecordType.CALL_SUMMARY, RetrievalRecordType.USPS_MAIL));

            assertThat(scope.allowedSourceTypes()).containsExactly(RetrievalRecordType.CALL_SUMMARY);
        }

        @Test
        @DisplayName("throws when requested types leave no permitted sources")
        void throwsWhenRequestedTypesNotPermitted() {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));

            assertThatThrownBy(() -> service.resolveRetrievalScope(
                    patientUser,
                    PATIENT_ENTITY_ID,
                    Set.of(RetrievalRecordType.USPS_MAIL)))
                    .isInstanceOf(ForbiddenScopeException.class)
                    .hasMessageContaining("No permitted source types");
        }

        @Test
        @DisplayName("throws when all source types excluded by REQ-SC-7")
        void throwsWhenAllTypesExcluded() {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));
            when(sourceExclusionProvider.getExcludedSourceTypes(PATIENT_ENTITY_ID))
                    .thenReturn(RetrievalRecordType.defaultsForRole(Role.PATIENT));

            assertThatThrownBy(() -> service.resolveRetrievalScope(patientUser, PATIENT_ENTITY_ID))
                    .isInstanceOf(ForbiddenScopeException.class)
                    .hasMessageContaining("No permitted source types");
        }

        @Test
        @DisplayName("throws when patient entity has no linked user")
        void throwsWhenPatientUserMissing() {
            Patient orphan = Patient.builder().id(PATIENT_ENTITY_ID).user(null).build();
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(orphan));

            assertThatThrownBy(() -> service.resolveRetrievalScope(patientUser, PATIENT_ENTITY_ID))
                    .isInstanceOf(ForbiddenScopeException.class)
                    .hasMessageContaining("not found");
        }
    }

    @Nested
    @DisplayName("CAREGIVER role")
    class CaregiverRole {

        @Test
        @DisplayName("resolves scope when active link exists")
        void resolvesWithActiveLink() throws Exception {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));
            when(caregiverPatientLinkService.hasAccessToPatient(caregiverUser.getId(), PATIENT_USER_ID))
                    .thenReturn(true);
            when(consentProvider.isCaregiverConsentGranted(caregiverUser.getId(), PATIENT_USER_ID))
                    .thenReturn(false);

            RetrievalScope scope = service.resolveRetrievalScope(caregiverUser, PATIENT_ENTITY_ID);

            assertThat(scope.allowedPatientIds()).containsExactly(PATIENT_ENTITY_ID);
            assertThat(scope.allowedSourceTypes()).contains(RetrievalRecordType.USPS_MAIL);
            assertThat(scope.consentGranted()).isFalse();
            assertThat(scope.visibilityFilter().permits("on_consent")).isFalse();
            assertThat(scope.visibilityFilter().permits("auto")).isTrue();
        }

        @Test
        @DisplayName("denies access without active link")
        void deniesWithoutLink() {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));
            when(caregiverPatientLinkService.hasAccessToPatient(caregiverUser.getId(), PATIENT_USER_ID))
                    .thenReturn(false);

            assertThatThrownBy(() -> service.resolveRetrievalScope(caregiverUser, PATIENT_ENTITY_ID))
                    .isInstanceOf(ForbiddenScopeException.class)
                    .hasMessageContaining("out of scope");
        }

        @Test
        @DisplayName("honors REQ-SC-8 consent for on_consent visibility")
        void honorsCaregiverConsent() throws Exception {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));
            when(caregiverPatientLinkService.hasAccessToPatient(caregiverUser.getId(), PATIENT_USER_ID))
                    .thenReturn(true);
            when(consentProvider.isCaregiverConsentGranted(caregiverUser.getId(), PATIENT_USER_ID))
                    .thenReturn(true);

            RetrievalScope scope = service.resolveRetrievalScope(caregiverUser, PATIENT_ENTITY_ID);

            assertThat(scope.consentGranted()).isTrue();
            assertThat(scope.visibilityFilter().permits("on_consent")).isTrue();
        }
    }

    @Nested
    @DisplayName("FAMILY_MEMBER role")
    class FamilyMemberRole {

        @Test
        @DisplayName("denied at USE_AI_FEATURES permission gate today")
        void deniedAtPermissionGate() {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));

            assertThatThrownBy(() -> service.resolveRetrievalScope(familyUser, PATIENT_ENTITY_ID))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("USE_AI_FEATURES");
        }

        @Test
        @DisplayName("resolves read-only subset when linked and permission granted")
        void resolvesReadOnlySubsetWhenPermitted() throws Exception {
            AuthorizationService permissiveAuth = mock(AuthorizationService.class);
            doNothing().when(permissiveAuth).requirePermission(any(User.class), any(Permission.class));

            RetrievalScopeService familyScopeService = new RetrievalScopeService(
                    permissiveAuth,
                    patientRepository,
                    caregiverPatientLinkService,
                    familyMemberService,
                    sourceExclusionProvider,
                    consentProvider,
                    scopeAuditService
            );

            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));
            when(familyMemberService.hasAccessToPatient(familyUser.getId(), PATIENT_USER_ID))
                    .thenReturn(true);

            RetrievalScope scope = familyScopeService.resolveRetrievalScope(familyUser, PATIENT_ENTITY_ID);

            assertThat(scope.allowedSourceTypes()).contains(RetrievalRecordType.CLINICAL_NOTE);
            assertThat(scope.allowedSourceTypes()).doesNotContain(RetrievalRecordType.USPS_MAIL);
            assertThat(scope.consentGranted()).isFalse();
        }

        @Test
        @DisplayName("denies access without link when permission granted")
        void deniesWithoutLinkWhenPermitted() throws Exception {
            AuthorizationService permissiveAuth = mock(AuthorizationService.class);
            doNothing().when(permissiveAuth).requirePermission(any(User.class), any(Permission.class));

            RetrievalScopeService familyScopeService = new RetrievalScopeService(
                    permissiveAuth,
                    patientRepository,
                    caregiverPatientLinkService,
                    familyMemberService,
                    sourceExclusionProvider,
                    consentProvider,
                    scopeAuditService
            );

            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));
            when(familyMemberService.hasAccessToPatient(familyUser.getId(), PATIENT_USER_ID))
                    .thenReturn(false);

            assertThatThrownBy(() -> familyScopeService.resolveRetrievalScope(familyUser, PATIENT_ENTITY_ID))
                    .isInstanceOf(ForbiddenScopeException.class)
                    .hasMessageContaining("out of scope");
        }
    }

    @Nested
    @DisplayName("ADMIN role")
    class AdminRole {

        @Test
        @DisplayName("allows any existing patient with all source types")
        void allowsAnyPatient() throws Exception {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));

            RetrievalScope scope = service.resolveRetrievalScope(adminUser, PATIENT_ENTITY_ID);

            assertThat(scope.allowedSourceTypes()).contains(RetrievalRecordType.USPS_MAIL);
            assertThat(scope.allowedSourceTypes()).containsAll(EnumSet.allOf(RetrievalRecordType.class));
            assertThat(scope.consentGranted()).isTrue();
        }
    }

    @Nested
    @DisplayName("Permission gate")
    class PermissionGate {

        @Test
        @DisplayName("requires USE_AI_FEATURES before scope resolution")
        void requiresUseAiFeatures() {
            assertThatThrownBy(() -> service.resolveRetrievalScope(familyUser, PATIENT_ENTITY_ID))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("USE_AI_FEATURES");
        }

        @Test
        @DisplayName("rejects unauthenticated caller")
        void rejectsNullCaller() {
            assertThatThrownBy(() -> service.resolveRetrievalScope(null, PATIENT_ENTITY_ID))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("not authenticated");
        }
    }

    @Nested
    @DisplayName("Task 2.6 — scope denial audit")
    class ScopeDenialAudit {

        @Test
        @DisplayName("audits and attaches auditId when patient is out of scope")
        void auditsPatientOutOfScope() {
            Patient otherPatient = Patient.builder()
                    .id(OTHER_PATIENT_ENTITY_ID)
                    .user(User.builder().id(50L).email("other@test.com").role(Role.PATIENT).build())
                    .build();
            when(patientRepository.findById(OTHER_PATIENT_ENTITY_ID)).thenReturn(Optional.of(otherPatient));

            assertThatThrownBy(() -> service.resolveRetrievalScope(patientUser, OTHER_PATIENT_ENTITY_ID))
                    .isInstanceOf(ForbiddenScopeException.class)
                    .satisfies(ex -> {
                        ForbiddenScopeException denied = (ForbiddenScopeException) ex;
                        assertThat(denied.getAuditId()).isNotNull();
                        assertThat(denied.getErrorCode()).isEqualTo(ForbiddenScopeException.ERROR_CODE);
                        assertThat(denied.getDenialReason()).isEqualTo(ScopeDenialReason.PATIENT_OUT_OF_SCOPE);
                    });

            verify(scopeAuditService).logScopeDenied(
                    eq(patientUser),
                    eq(OTHER_PATIENT_ENTITY_ID),
                    eq(ScopeDenialReason.PATIENT_OUT_OF_SCOPE),
                    any());
        }

        @Test
        @DisplayName("audits when patient entity is missing")
        void auditsPatientNotFound() {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.resolveRetrievalScope(patientUser, PATIENT_ENTITY_ID))
                    .isInstanceOf(ForbiddenScopeException.class)
                    .satisfies(ex -> assertThat(((ForbiddenScopeException) ex).getDenialReason())
                            .isEqualTo(ScopeDenialReason.PATIENT_NOT_FOUND));

            verify(scopeAuditService).logScopeDenied(
                    eq(patientUser),
                    eq(PATIENT_ENTITY_ID),
                    eq(ScopeDenialReason.PATIENT_NOT_FOUND),
                    any());
        }

        @Test
        @DisplayName("audits when no permitted source types remain")
        void auditsNoPermittedSourceTypes() {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));
            when(sourceExclusionProvider.getExcludedSourceTypes(PATIENT_ENTITY_ID))
                    .thenReturn(RetrievalRecordType.defaultsForRole(Role.PATIENT));

            assertThatThrownBy(() -> service.resolveRetrievalScope(patientUser, PATIENT_ENTITY_ID))
                    .isInstanceOf(ForbiddenScopeException.class)
                    .satisfies(ex -> assertThat(((ForbiddenScopeException) ex).getDenialReason())
                            .isEqualTo(ScopeDenialReason.NO_PERMITTED_SOURCE_TYPES));

            verify(scopeAuditService).logScopeDenied(
                    eq(patientUser),
                    eq(PATIENT_ENTITY_ID),
                    eq(ScopeDenialReason.NO_PERMITTED_SOURCE_TYPES),
                    any());
        }
    }

    @Nested
    @DisplayName("Validation")
    class Validation {

        @Test
        @DisplayName("throws when patient entity is missing")
        void throwsWhenPatientMissing() {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.resolveRetrievalScope(patientUser, PATIENT_ENTITY_ID))
                    .isInstanceOf(ForbiddenScopeException.class)
                    .hasMessageContaining("not found");
        }

        @Test
        @DisplayName("throws when patientId is null")
        void throwsWhenPatientIdNull() {
            assertThatThrownBy(() -> service.resolveRetrievalScope(patientUser, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("patientId");
        }

        @Test
        @DisplayName("assertCanAsk delegates to resolveRetrievalScope")
        void assertCanAskDelegates() throws Exception {
            when(patientRepository.findById(PATIENT_ENTITY_ID)).thenReturn(Optional.of(patient));

            service.assertCanAsk(patientUser, PATIENT_ENTITY_ID, Set.of(RetrievalRecordType.MEDICATION));
        }
    }
}
