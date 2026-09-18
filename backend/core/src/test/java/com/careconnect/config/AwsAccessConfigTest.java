package com.careconnect.config;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.textract.TextractClient;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link AwsAccessConfig}.
 * <p>
 * AwsAccessConfig is a Spring {@code @Configuration} class that creates AWS SDK client
 * beans (S3, SSM, Textract) and a credentials provider used throughout the application.
 * <p>
 * Rather than loading the full Spring context (which would attempt real AWS calls), these
 * tests instantiate {@code AwsAccessConfig} directly and set the {@code aws.region} system
 * property to satisfy {@code DefaultAwsRegionProviderChain} — the chain that the SDK uses
 * to resolve the active region at runtime. The property is cleared in {@code tearDown} to
 * avoid leaking state into other tests.
 */
class AwsAccessConfigTest {

    private AwsAccessConfig config;

    @BeforeEach
    void setUp() throws Exception {
        // Set the region system property so DefaultAwsRegionProviderChain can resolve it
        // without hitting EC2 metadata or environment variables that may not exist in CI.
        System.setProperty("aws.region", "us-east-1");
        config = new AwsAccessConfig();
        // Simulate Spring @Value injection for the awsRegion field
        ReflectionTestUtils.setField(config, "awsRegion", "us-east-1");
    }

    @AfterEach
    void tearDown() throws Exception {
        // Always clean up the system property so it does not affect other test classes.
        System.clearProperty("aws.region");
    }

    @Test
    void defaultAwsRegion_ReturnsRegion() throws Exception {
        // Verifies that the region bean resolves to the value set in the system property.
        final Region region = config.defaultAwsRegion();
        assertNotNull(region);
        assertEquals("us-east-1", region.id());
    }

    @Test
    void awsCredentialsProvider_IsCreated() throws Exception {
        // Verifies that a DefaultCredentialsProvider can be constructed; it does not
        // actually resolve credentials until the first API call is made.
        final DefaultCredentialsProvider provider = config.awsCredentialsProvider();
        assertNotNull(provider);
    }

    @Test
    void s3Client_IsCreatedSuccessfully() throws Exception {
        // Verifies that the S3Client bean is created without throwing.
        // Client creation is lightweight — it does not open a network connection.
        final S3Client s3Client = config.s3Client();
        assertNotNull(s3Client);
    }

    @Test
    void ssmClient_IsCreatedSuccessfully() throws Exception {
        // Verifies that the SsmClient bean is created using the credentials provider bean.
        // The credentials provider is passed explicitly, matching the Spring wiring.
        final DefaultCredentialsProvider provider = config.awsCredentialsProvider();
        final SsmClient ssmClient = config.ssmClient(provider);
        assertNotNull(ssmClient);
    }

    @Test
    void textractClient_IsCreatedSuccessfully() throws Exception {
        // Verifies that the TextractClient bean is created without throwing.
        final TextractClient textractClient = config.textractClient();
        assertNotNull(textractClient);
    }

    @Test
    void allBeansCanBeCreatedTogether() throws Exception {
        // Integration-style check: all five beans are instantiated in the order Spring
        // would wire them to confirm there are no dependency conflicts between them.
        final Region region = config.defaultAwsRegion();
        final DefaultCredentialsProvider provider = config.awsCredentialsProvider();
        final S3Client s3 = config.s3Client();
        final SsmClient ssm = config.ssmClient(provider);
        final TextractClient textract = config.textractClient();

        assertNotNull(region);
        assertNotNull(provider);
        assertNotNull(s3);
        assertNotNull(ssm);
        assertNotNull(textract);
    }
}
