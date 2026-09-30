package com.careconnect.service;

import com.careconnect.model.Plan;
import com.careconnect.repository.PlanRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Initializes required data (Plans/Tiers) on application startup if they don't exist
 */
@Component
public class DataInitializer implements CommandLineRunner {

    private static final Logger logger = LoggerFactory.getLogger(DataInitializer.class);

    @Autowired
    private PlanRepository planRepository;

    @Override
    public void run(String... args) throws Exception {
        logger.info("Initializing application data...");
        initializePlans();
    }

    private void initializePlans() {
        // Check if plans already exist
        if (planRepository.count() > 0) {
            logger.info("Plans already exist. Skipping initialization.");
            return;
        }

        logger.info("Creating default subscription plans...");

        // Create Free Plan (ID 1)
        Plan freePlan = Plan.builder()
                .code("plan_free")
                .name("Free Plan")
                .priceCents(0)
                .billingPeriod("MONTH")
                .isActive(true)
                .build();
        planRepository.save(freePlan);
        logger.info("Created Free Plan with ID: {}", freePlan.getId());

        // Create Standard Monthly Plan (ID 2)
        Plan standardPlan = Plan.builder()
                .code("plan_standard_monthly")
                .name("Standard Monthly")
                .priceCents(999)  // $9.99
                .billingPeriod("MONTH")
                .isActive(true)
                .build();
        planRepository.save(standardPlan);
        logger.info("Created Standard Monthly plan with ID: {}", standardPlan.getId());

        // Create Premium Monthly Plan (ID 3)
        Plan premiumPlan = Plan.builder()
                .code("plan_premium_monthly")
                .name("Premium Monthly")
                .priceCents(2999)  // $29.99
                .billingPeriod("MONTH")
                .isActive(true)
                .build();
        planRepository.save(premiumPlan);
        logger.info("Created Premium Monthly plan with ID: {}", premiumPlan.getId());

        logger.info("Plans initialized successfully!");
    }
}
