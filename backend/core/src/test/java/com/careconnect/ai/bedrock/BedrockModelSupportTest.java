package com.careconnect.ai.bedrock;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class BedrockModelSupportTest {

    @Test
    void exactProfileAllowlistRejectsLookalikesAndArbitraryArns() {
        assertThat(BedrockModelSupport.isApprovedModelId(
                "us.anthropic.claude-sonnet-4-20250514-v1:0")).isTrue();
        assertThat(BedrockModelSupport.isApprovedModelId(
                "eu.anthropic.claude-sonnet-4-20250514-v1:0")).isFalse();
        assertThat(BedrockModelSupport.isApprovedModelId(
                "arn:aws:bedrock:us-east-1:123456789012:inference-profile/"
                        + "us.anthropic.claude-sonnet-4-20250514-v1:0")).isFalse();
    }

    @Test
    void unapprovedDefaultDoesNotBecomeFallback() {
        assertThatThrownBy(() -> BedrockModelSupport.resolveModelId(
                null, "us.anthropic.claude-lookalike-v1:0"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
