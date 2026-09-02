package com.careconnect.config;

import com.stripe.Stripe;

import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;

@Configuration
@ConditionalOnProperty(name = "careconnect.stripe.enabled", havingValue = "true", matchIfMissing = true)
public class StripeConfig {

    @Value("${stripe.secret-key:}")
    private String secretKey;

    @PostConstruct
    public void init() {
        if (secretKey.isBlank()) {
            // System.out.println("Stripe secret key not set – payments disabled");
        } else {
            Stripe.apiKey = secretKey;
            // System.out.println("Stripe key loaded");
        }
    }
}