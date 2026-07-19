package com.careconnect.controller;

import com.careconnect.exception.AppException;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CallControllerRecordingPolicyTest {

    @Test
    void globalPurge_defaultProfileCannotBeEnabled() {
        final CallController controller = controllerWith(
                new MockEnvironment()
                        .withProperty("careconnect.recording.global-purge-enabled", "true"));

        assertThatThrownBy(() -> invokePurgePolicy(controller))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("explicit enablement");
    }

    @Test
    void globalPurge_devProfileStillRequiresExplicitFlag() {
        final MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles("dev");
        final CallController controller = controllerWith(environment);

        assertThatThrownBy(() -> invokePurgePolicy(controller))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("explicit enablement");
    }

    @Test
    void globalPurge_explicitTestProfileCanPassEnvironmentGate() {
        final MockEnvironment environment = new MockEnvironment()
                .withProperty("careconnect.recording.global-purge-enabled", "true");
        environment.setActiveProfiles("test");
        final CallController controller = controllerWith(environment);

        assertThatCode(() -> invokePurgePolicy(controller)).doesNotThrowAnyException();
    }

    private CallController controllerWith(final MockEnvironment environment) {
        final CallController controller = new CallController();
        ReflectionTestUtils.setField(controller, "environment", environment);
        return controller;
    }

    private void invokePurgePolicy(final CallController controller) {
        ReflectionTestUtils.invokeMethod(controller, "ensureGlobalRecordingPurgeEnabled");
    }
}
