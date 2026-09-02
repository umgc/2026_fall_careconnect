package com.careconnect.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/uploads/**")
                .addResourceLocations("file:C:/Users/bompl/Documents/uploads/");
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        // CORS Configuration
        registry.addMapping("/**")
                .allowedOriginPatterns(
                        "http://localhost:50030",
                        "http://localhost:3000",
                        "https://care-connect-develop.d26kqsucj1bwc1.amplifyapp.com",
                        "https://isabel-santiagolewis.github.io" // ALEXA TESTING: FOR TESTING ONLY OF MOCK ALEXA LOGIN PAGE
                )
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS") // OPTIONS REQUIRED FOR ALEXA LOGIN FUNCTIONALITY
                .allowedHeaders("*") // * REQUIRED FOR ALEXA LOGIN FUNCTIONALITY
                .allowCredentials(true);  // Allow credentials (cookies)
    }
}
