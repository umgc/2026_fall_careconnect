package com.careconnect;


import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;


@SpringBootApplication()
@EnableScheduling
@EnableAsync
public class CareconnectBackendApplication {

    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(CareconnectBackendApplication.class);

        String explicitProfile = System.getProperty("spring.profiles.active");
        if (explicitProfile == null || explicitProfile.isBlank()) {
            explicitProfile = System.getenv("SPRING_PROFILES_ACTIVE");
        }

        if (explicitProfile == null || explicitProfile.isBlank()) {
            String environment = System.getenv("CARECONNECT_ENV");
            if (environment != null && environment.equalsIgnoreCase("prod")) {
                app.setAdditionalProfiles("prod");
            } else {
                app.setAdditionalProfiles("dev");
            }
        }

        app.run(args);

    }
}
