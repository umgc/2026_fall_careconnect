package com.careconnect.dto;

public record QuestionDTO(Long id, String prompt, String type, boolean required, boolean active, int ordinal) {}
