package com.careconnect.client.ehr;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;
import org.junit.jupiter.api.Test;

/** Unit tests for {@link EhrApiClientRegistry}. */
class EhrApiClientRegistryTest {

    @Test
    void resolvesTheClientRegisteredForItsSourceCode() {
        final EhrApiClient athenahealth = stubClient("ATHENAHEALTH");
        final EhrApiClient epic = stubClient("EPIC");
        final EhrApiClientRegistry registry =
                new EhrApiClientRegistry(List.of(athenahealth, epic));

        assertThat(registry.get("ATHENAHEALTH")).isSameAs(athenahealth);
        assertThat(registry.get("EPIC")).isSameAs(epic);
    }

    @Test
    void refusesAnUnregisteredSourceCode() {
        final EhrApiClientRegistry registry =
                new EhrApiClientRegistry(List.of(stubClient("ATHENAHEALTH")));

        assertThatThrownBy(() -> registry.get("MEDICARE"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("MEDICARE");
    }

    @Test
    void failsFastOnTwoAdaptersClaimingTheSameSourceCode() {
        final EhrApiClient first = stubClient("ATHENAHEALTH");
        final EhrApiClient second = stubClient("ATHENAHEALTH");

        assertThatThrownBy(() -> new EhrApiClientRegistry(List.of(first, second)))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("ATHENAHEALTH");
    }

    private static EhrApiClient stubClient(final String sourceCode) {
        return new EhrApiClient() {
            @Override
            public String sourceCode() {
                return sourceCode;
            }

            @Override
            public List<JsonNode> fetchResources(final String resourceType, final String externalPatientId) {
                return List.of();
            }
        };
    }
}
