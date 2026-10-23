package com.careconnect.integration.cerner;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.NoSuchBeanDefinitionException;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

/** Context-only checks use fake source beans; no database or external API starts. */
@Tag("WBS-4.2.7")
class CernerAllergyControllerConfigurationTest {

    private static final String ENABLED = "careconnect.cerner.allergies.enabled";
    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(CernerAllergyController.class);

    /** Supply both boundary mocks only for tests that need a wired controller. */
    private ApplicationContextRunner withConfiguredDependencies() {
        return runner.withBean(CernerAllergyService.class, () -> mock(CernerAllergyService.class))
                .withBean(CernerAccessPolicy.class, () -> mock(CernerAccessPolicy.class));
    }

    @Test
    @DisplayName("An unconfigured Cerner route is off by default and does not block startup")
    void disabledByDefaultStartsWithoutSourceBeans() {
        runner.run(context -> assertThat(context).hasNotFailed()
                .doesNotHaveBean(CernerAllergyController.class));
    }

    @Test
    @DisplayName("An explicit false setting keeps the route off even when beans exist")
    void disabledExplicitlyDoesNotRegisterController() {
        withConfiguredDependencies().withPropertyValues(ENABLED + "=false")
                .run(context -> assertThat(context).hasNotFailed()
                        .doesNotHaveBean(CernerAllergyController.class));
    }

    @Test
    @DisplayName("An enabled route registers only with its service and policy wired")
    void enabledWithBothBeansRegistersController() {
        withConfiguredDependencies().withPropertyValues(ENABLED + "=true")
                .run(context -> assertThat(context).hasNotFailed()
                        .hasSingleBean(CernerAllergyController.class));
    }

    @Test
    @DisplayName("Enabling without a source service fails clearly rather than returning fake data")
    void enabledWithoutServiceFailsClearly() {
        runner.withPropertyValues(ENABLED + "=true")
                .withBean(CernerAccessPolicy.class, () -> mock(CernerAccessPolicy.class))
                .run(context -> {
                    assertThat(context).hasFailed();
                    assertThat(context.getStartupFailure())
                            .hasRootCauseInstanceOf(NoSuchBeanDefinitionException.class);
                });
    }

    @Test
    @DisplayName("Enabling without an access policy fails rather than bypassing authorization")
    void enabledWithoutPolicyFailsClearly() {
        runner.withPropertyValues(ENABLED + "=true")
                .withBean(CernerAllergyService.class, () -> mock(CernerAllergyService.class))
                .run(context -> {
                    assertThat(context).hasFailed();
                    assertThat(context.getStartupFailure())
                            .hasRootCauseInstanceOf(NoSuchBeanDefinitionException.class);
                });
    }
}
