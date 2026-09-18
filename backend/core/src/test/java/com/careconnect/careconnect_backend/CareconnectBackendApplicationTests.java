package com.careconnect.careconnect_backend;

import com.careconnect.CareconnectBackendApplication;
import org.junit.jupiter.api.Test;
import org.mockito.MockedConstruction;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

class CareconnectBackendApplicationTests {

    @Test
    void contextLoads() {
        // Verify the application class is properly annotated for Spring Boot
        assertThat(CareconnectBackendApplication.class.getAnnotation(SpringBootApplication.class)).isNotNull();
    }

    @Test
    void main_callsSpringApplicationRun() {
        try (MockedConstruction<SpringApplication> construction =
                     mockConstruction(SpringApplication.class)) {

            CareconnectBackendApplication.main(new String[]{});

            assertThat(construction.constructed()).hasSize(1);
            verify(construction.constructed().get(0)).run(new String[]{});
        }
    }
}
