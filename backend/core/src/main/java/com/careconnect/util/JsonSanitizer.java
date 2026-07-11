package com.careconnect.util;

/**
 * Extracts the first balanced JSON object from raw LLM output that may be
 * wrapped in prose or markdown. Shared by the invoice and home-care document
 * extraction pipelines.
 */
public final class JsonSanitizer {

    private JsonSanitizer() {}

    public static String extractFirstJsonObject(String s) {
        if (s == null) return null;

        String t = s.trim();
        int start = t.indexOf('{');
        if (start < 0) return null;

        int depth = 0;
        for (int i = start; i < t.length(); i++) {
            if (t.charAt(i) == '{') depth++;
            else if (t.charAt(i) == '}') {
                depth--;
                if (depth == 0) return t.substring(start, i + 1);
            }
        }
        return null;
    }
}
