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

    @Test
    void sonnet46DirectIdIsNotApprovedWithoutSupportedProfileMapping() {
        final String sonnet46 = "anthropic.claude-sonnet-4-6";

        assertThat(BedrockModelSupport.isApprovedModelId(sonnet46)).isFalse();
        assertThatThrownBy(() -> BedrockModelSupport.resolveModelId(null, sonnet46))
                .isInstanceOf(IllegalArgumentException.class);
        assertThat(BedrockModelSupport.resolveModelId(
                sonnet46, "amazon.nova-lite-v1:0"))
                .isEqualTo("amazon.nova-lite-v1:0");
    }

    @Test
    void supportedClaudeDirectIdsNormalizeToProfiles() {
        assertThat(BedrockModelSupport.resolveModelId(
                null, "anthropic.claude-sonnet-4-5-20250929-v1:0"))
                .isEqualTo("us.anthropic.claude-sonnet-4-5-20250929-v1:0");
    }
}
