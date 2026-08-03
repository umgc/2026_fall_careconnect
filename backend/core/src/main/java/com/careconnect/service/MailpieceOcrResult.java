package com.careconnect.service;

/**
 * Sender and optional summary text extracted from a mailpiece image via Textract OCR.
 */
public record MailpieceOcrResult(String sender, String summaryLine) {
}
