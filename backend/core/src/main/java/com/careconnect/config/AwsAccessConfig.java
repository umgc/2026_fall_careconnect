package com.careconnect.config;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.chimesdkmeetings.ChimeSdkMeetingsClient;
import software.amazon.awssdk.services.chimesdkmediapipelines.ChimeSdkMediaPipelinesClient;
import software.amazon.awssdk.services.iam.IamClient;
import software.amazon.awssdk.services.kinesisvideo.KinesisVideoClient;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.textract.TextractClient;
import software.amazon.awssdk.services.transcribe.TranscribeClient;
import org.springframework.beans.factory.annotation.Value;


@Configuration
@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true", matchIfMissing = false)
public class AwsAccessConfig {

    @Value("${aws.region:us-east-1}")
    private String awsRegion;

    @Bean
    public Region defaultAwsRegion() {
        return Region.of(awsRegion);
    }

    @Bean
    public DefaultCredentialsProvider awsCredentialsProvider() {
        return DefaultCredentialsProvider.builder().asyncCredentialUpdateEnabled(true).build();
    }

    @Bean
    public S3Client s3Client() {
        return S3Client.builder()
                .region(defaultAwsRegion())
                .credentialsProvider(awsCredentialsProvider())
                .build();
    }

    @Bean
    public SsmClient ssmClient(DefaultCredentialsProvider credentialsProvider) {
        return SsmClient.builder()
                .credentialsProvider(credentialsProvider)
                .region(defaultAwsRegion())
                .build();
    }

    @Bean
    public TextractClient textractClient() {
        return TextractClient.builder()
                .region(defaultAwsRegion())
                .credentialsProvider(DefaultCredentialsProvider.create())
                .build();
    }

    @Bean
    public ChimeSdkMeetingsClient chimeSdkMeetingsClient() {
        return ChimeSdkMeetingsClient.builder()
                .region(defaultAwsRegion())
                .credentialsProvider(awsCredentialsProvider())
                .build();
    }

    @Bean
    public BedrockRuntimeClient bedrockRuntimeClient() {
        return BedrockRuntimeClient.builder()
                .region(defaultAwsRegion())
                .credentialsProvider(awsCredentialsProvider())
                .build();
    }

    @Bean
    public ChimeSdkMediaPipelinesClient chimeSdkMediaPipelinesClient() {
        return ChimeSdkMediaPipelinesClient.builder()
                .region(defaultAwsRegion())
                .credentialsProvider(awsCredentialsProvider())
                .build();
    }

    @Bean
    public KinesisVideoClient kinesisVideoClient() {
        return KinesisVideoClient.builder()
                .region(defaultAwsRegion())
                .credentialsProvider(awsCredentialsProvider())
                .build();
    }

    @Bean
    public StsClient stsClient() {
        return StsClient.builder()
                .region(defaultAwsRegion())
                .credentialsProvider(awsCredentialsProvider())
                .build();
    }

    @Bean
    public S3Presigner s3Presigner() {
        return S3Presigner.builder()
                .region(defaultAwsRegion())
                .credentialsProvider(awsCredentialsProvider())
                .build();
    }

    @Bean
    public IamClient iamClient() {
        // IAM is a global service — must use us-east-1 regardless of deployment region
        return IamClient.builder()
                .region(Region.US_EAST_1)
                .credentialsProvider(awsCredentialsProvider())
                .build();
    }

    @Bean
    public TranscribeClient transcribeClient() {
        return TranscribeClient.builder()
                .region(defaultAwsRegion())
                .credentialsProvider(awsCredentialsProvider())
                .build();
    }
}
