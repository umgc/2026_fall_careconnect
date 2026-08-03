package com.careconnect.config;

import com.careconnect.service.FormSchemaService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.ApplicationArguments;
import org.springframework.stereotype.Component;

/**
 * Registers the bundled hiring/onboarding form definitions in the database at
 * startup so submissions can reference a persisted {@code form_definitions} row
 * and the active version for each form type is resolvable.
 * <p>
 * Failures are logged but never abort startup — form submission self-heals by
 * syncing on demand if the table is empty.
 */
@Component
public class FormDefinitionInitializer implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(FormDefinitionInitializer.class);

    private final FormSchemaService formSchemaService;

    public FormDefinitionInitializer(FormSchemaService formSchemaService) {
        this.formSchemaService = formSchemaService;
    }

    @Override
    public void run(ApplicationArguments args) {
        try {
            formSchemaService.syncBundledDefinitions();
        } catch (Exception e) {
            log.warn("Could not sync bundled form definitions at startup: {}", e.getMessage());
        }
    }
}
