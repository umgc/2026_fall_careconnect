package com.careconnect.security;

import com.careconnect.controller.AiAllergyController;
import com.careconnect.controller.AiSymptomController;
import com.careconnect.dto.AiAllergyDTO;
import com.careconnect.dto.AiSymptomDTO;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.lang.annotation.Annotation;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

/**
 * Task 2.2 — verifies AI analyze endpoints require USE_AI_FEATURES (not CREATE_TASKS)
 * and that PATIENT role passes the permission gate via PermissionAspect.
 */
@ExtendWith(MockitoExtension.class)
class AiAnalyzeEndpointPermissionTest {

    @Mock
    private UserRepository userRepository;

    private PermissionAspect permissionAspect;

    @BeforeEach
    void setUp() throws Exception {
        permissionAspect = new PermissionAspect();
        setField(permissionAspect, "authorizationService", new AuthorizationService());
        setField(permissionAspect, "userRepository", userRepository);

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("patient@test.com", "token", List.of()));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("AiSymptomController.analyze requires USE_AI_FEATURES")
    void symptomEndpoint_requiresUseAiFeatures() throws NoSuchMethodException {
        RequirePermission annotation = AiSymptomController.class
                .getMethod("analyze", AiSymptomDTO.Request.class)
                .getAnnotation(RequirePermission.class);

        assertThat(annotation).isNotNull();
        assertThat(annotation.value()).isEqualTo(Permission.USE_AI_FEATURES);
    }

    @Test
    @DisplayName("AiAllergyController.analyze requires USE_AI_FEATURES")
    void allergyEndpoint_requiresUseAiFeatures() throws NoSuchMethodException {
        RequirePermission annotation = AiAllergyController.class
                .getMethod("analyze", AiAllergyDTO.Request.class)
                .getAnnotation(RequirePermission.class);

        assertThat(annotation).isNotNull();
        assertThat(annotation.value()).isEqualTo(Permission.USE_AI_FEATURES);
    }

    @Test
    @DisplayName("PATIENT passes PermissionAspect check for USE_AI_FEATURES")
    void patient_passesUseAiFeaturesPermissionCheck() throws UnauthorizedException {
        when(userRepository.findByEmail("patient@test.com")).thenReturn(Optional.of(
                User.builder().id(2L).email("patient@test.com").role(Role.PATIENT).build()));

        assertThatCode(() ->
                permissionAspect.checkPermission(requirePermission(Permission.USE_AI_FEATURES)))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("PATIENT is denied CREATE_TASKS at PermissionAspect (old misconfiguration)")
    void patient_deniedCreateTasksPermissionCheck() {
        when(userRepository.findByEmail("patient@test.com")).thenReturn(Optional.of(
                User.builder().id(2L).email("patient@test.com").role(Role.PATIENT).build()));

        assertThatThrownBy(() ->
                permissionAspect.checkPermission(requirePermission(Permission.CREATE_TASKS)))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessageContaining("Required permission");
    }

    @Test
    @DisplayName("FAMILY_MEMBER is denied USE_AI_FEATURES at PermissionAspect")
    void familyMember_deniedUseAiFeaturesPermissionCheck() {
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("family@test.com", "token", List.of()));
        when(userRepository.findByEmail("family@test.com")).thenReturn(Optional.of(
                User.builder().id(3L).email("family@test.com").role(Role.FAMILY_MEMBER).build()));

        assertThatThrownBy(() ->
                permissionAspect.checkPermission(requirePermission(Permission.USE_AI_FEATURES)))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessageContaining("Required permission");
    }

    private RequirePermission requirePermission(Permission value) {
        return new RequirePermission() {
            @Override
            public Permission value() {
                return value;
            }

            @Override
            public Class<? extends Annotation> annotationType() {
                return RequirePermission.class;
            }
        };
    }

    private static void setField(Object target, String fieldName, Object value) throws Exception {
        var field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }
}
