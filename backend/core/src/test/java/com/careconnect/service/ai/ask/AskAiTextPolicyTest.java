package com.careconnect.service.ai.ask;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class AskAiTextPolicyTest {

    @Test
    @DisplayName("normalize treats null as empty")
    void normalize_nullIsEmpty() {
        assertThat(AskAiTextPolicy.normalize(null)).isEmpty();
    }

    @Test
    @DisplayName("normalize strips bidi controls and replaces other ISO controls")
    void normalize_stripsBidiAndControls() {
        final String raw = "Hello\u200E\u0001world\n\tok";
        final String normalized = AskAiTextPolicy.normalize(raw);
        assertThat(normalized).doesNotContain("\u200E");
        assertThat(normalized).contains("Hello");
        assertThat(normalized).contains("world");
        assertThat(normalized).contains("\n");
        assertThat(normalized).contains("\t");
    }

    @Test
    @DisplayName("truncateGraphemes returns empty for blank or non-positive limits")
    void truncateGraphemes_emptyCases() {
        assertThat(AskAiTextPolicy.truncateGraphemes(null, 5)).isEmpty();
        assertThat(AskAiTextPolicy.truncateGraphemes("abc", 0)).isEmpty();
        assertThat(AskAiTextPolicy.truncateGraphemes("abc", -1)).isEmpty();
    }

    @Test
    @DisplayName("truncateGraphemes keeps full string when under limit")
    void truncateGraphemes_underLimit() {
        assertThat(AskAiTextPolicy.truncateGraphemes("hi", 10)).isEqualTo("hi");
    }

    @Test
    @DisplayName("truncateGraphemes cuts to max graphemes")
    void truncateGraphemes_cuts() {
        assertThat(AskAiTextPolicy.truncateGraphemes("abcdef", 3)).isEqualTo("abc");
    }

    @Test
    @DisplayName("containsBidiControl detects directional marks")
    void containsBidiControl_detects() {
        assertThat(AskAiTextPolicy.containsBidiControl(null)).isFalse();
        assertThat(AskAiTextPolicy.containsBidiControl("plain")).isFalse();
        assertThat(AskAiTextPolicy.containsBidiControl("x\u202E")).isTrue();
    }
}
