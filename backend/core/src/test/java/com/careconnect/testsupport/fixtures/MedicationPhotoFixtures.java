package com.careconnect.testsupport.fixtures;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;

import software.amazon.awssdk.services.textract.model.Block;
import software.amazon.awssdk.services.textract.model.BlockType;
import software.amazon.awssdk.services.textract.model.DetectDocumentTextResponse;

/**
 * Shared fixtures for the F-01 medication photo capture tests.
 *
 * <p>
 * Everything here is synthetic and deterministic so the tests can run with
 * Textract and the LLM mocked and no live AWS access. The image "bytes" carry a
 * unique marker string so log and error-body assertions can prove that image
 * content never leaves the request (ADR-05, Table 25, section 11.4).
 * </p>
 */
public final class MedicationPhotoFixtures {

    /** Marker embedded in the fake image; must never appear in logs or responses. */
    public static final String IMAGE_MARKER = "IMG-MARKER-7f3c9a21";

    /** Text the mocked OCR "reads"; also must not be echoed into failure logs. */
    public static final String LABEL_LINE_1 = "LISINOPRIL 10 MG";
    public static final String LABEL_LINE_2 = "TAKE ONE TABLET DAILY";

    private MedicationPhotoFixtures() {
        // Utility class
    }

    /** Fake JPEG-ish bytes: a magic number followed by the marker string. */
    public static byte[] imageBytes() {
        final byte[] marker = IMAGE_MARKER.getBytes(StandardCharsets.UTF_8);
        final byte[] out = new byte[marker.length + 3];
        out[0] = (byte) 0xFF;
        out[1] = (byte) 0xD8;
        out[2] = (byte) 0xFF;
        System.arraycopy(marker, 0, out, 3, marker.length);
        return out;
    }

    /** Every textual encoding of the image that a careless log line could emit. */
    public static List<String> imageLeakNeedles() {
        final byte[] bytes = imageBytes();
        return List.of(
                IMAGE_MARKER,
                Base64.getEncoder().encodeToString(bytes),
                Base64.getEncoder().encodeToString(IMAGE_MARKER.getBytes(StandardCharsets.UTF_8)),
                java.util.Arrays.toString(bytes));
    }

    /** Textract response with two LINE blocks (label text) and one WORD block that must be ignored. */
    public static DetectDocumentTextResponse ocrResponse() {
        return DetectDocumentTextResponse.builder().blocks(
                Block.builder().blockType(BlockType.LINE).text(LABEL_LINE_1).build(),
                Block.builder().blockType(BlockType.WORD).text("IGNORED").build(),
                Block.builder().blockType(BlockType.LINE).text(LABEL_LINE_2).build()).build();
    }

    /** Textract response with no LINE text at all. */
    public static DetectDocumentTextResponse emptyOcrResponse() {
        return DetectDocumentTextResponse.builder().blocks(
                Block.builder().blockType(BlockType.WORD).text("x").build()).build();
    }

    /** LLM JSON for a fully mappable label. */
    public static String llmJson(String name, String dosage, String frequency, String type) {
        return "{\"medicationName\":\"" + name + "\",\"dosage\":\"" + dosage
                + "\",\"frequency\":\"" + frequency + "\",\"medicationType\":\"" + type + "\"}";
    }

    public static String fullLlmJson() {
        return llmJson("Lisinopril", "10 mg", "Once daily", "PRESCRIPTION");
    }
}
