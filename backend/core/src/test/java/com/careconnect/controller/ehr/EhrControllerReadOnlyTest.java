package com.careconnect.controller.ehr;

import static org.assertj.core.api.Assertions.assertThat;

import java.lang.reflect.Method;
import java.lang.reflect.Parameter;
import java.util.Arrays;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;

/**
 * CR-2 (#305) requires shared records to be read-only on the server, not just in the app. Anyone
 * reading another patient's Medicare data (a caregiver today, a share recipient once the access
 * policy admits them) reaches it only through {@link EhrController}'s {@code patientId} endpoints,
 * so those must stay GET-only. This fails if a write endpoint that takes a {@code patientId} is
 * ever added there, so the change gets a deliberate review.
 */
@DisplayName("EhrController read-only for other patients' data")
class EhrControllerReadOnlyTest {

    private static boolean takesPatientId(final Method method) {
        return Arrays.stream(method.getParameters())
                .map((Parameter p) -> p.getAnnotation(RequestParam.class))
                .anyMatch(rp -> rp != null
                        && ("patientId".equals(rp.value()) || "patientId".equals(rp.name())
                        || rp.value().isEmpty() && rp.name().isEmpty()));
    }

    private static boolean isWrite(final Method method) {
        if (method.isAnnotationPresent(PostMapping.class) || method.isAnnotationPresent(PutMapping.class)
                || method.isAnnotationPresent(PatchMapping.class)
                || method.isAnnotationPresent(DeleteMapping.class)) {
            return true;
        }
        final RequestMapping rm = method.getAnnotation(RequestMapping.class);
        return rm != null && (rm.method().length == 0 || Arrays.stream(rm.method())
                .anyMatch(m -> !"GET".equals(m.name())));
    }

    @Test
    @DisplayName("TC-CONSENT-076 CR-2: every EhrController endpoint that takes a patientId is GET-only")
    void patientIdEndpointsAreGetOnly() {
        final List<Method> patientIdEndpoints = Arrays.stream(EhrController.class.getDeclaredMethods())
                .filter(EhrControllerReadOnlyTest::takesPatientId)
                .toList();

        assertThat(patientIdEndpoints).isNotEmpty();
        assertThat(patientIdEndpoints).allMatch(m -> m.isAnnotationPresent(GetMapping.class));
        assertThat(patientIdEndpoints).noneMatch(EhrControllerReadOnlyTest::isWrite);
    }
}
