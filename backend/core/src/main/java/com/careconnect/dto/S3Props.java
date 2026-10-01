package com.careconnect.dto;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Data
@Component
@ConfigurationProperties(prefix = "aws.s3")
public class S3Props {
    private String bucket;
    private String region = "us-east-1";
    private String accessKey;
    private String secretKey;
    private String baseUrl;
}