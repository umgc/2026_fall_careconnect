package com.careconnect.config;

import com.careconnect.model.Question;
import com.careconnect.model.QuestionType;
import com.careconnect.repository.QuestionRepository;
import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * Initializes default Virtual Check-In questions on application startup.
 * Questions are only created if the questions table is empty.
 * <p>
 * Based on V31__Virtual_Check_In_Questions.sql migration.
 */
@Slf4j
@Component
public class QuestionInitializer {

    @Autowired
    private QuestionRepository questionRepository;

    @PostConstruct
    public void initQuestions() {
        try {
            // Only seed questions if the table is empty
            long existingCount = questionRepository.count();
            if (existingCount > 0) {
                log.info("Questions table already contains {} questions. Skipping initialization.", existingCount);
                return;
            }

            log.info("🔄 Initializing Virtual Check-In questions...");

            // Seed all questions from V31 migration
            createQuestion("Did you take all of your prescribed medications today?", QuestionType.YES_NO, true, 1);
            createQuestion("Have you missed any doses in the past 24 hours?", QuestionType.YES_NO, true, 2);
            createQuestion("I feel comfortable managing my medications without help.", QuestionType.TRUE_FALSE, false, 3);
            createQuestion("On a scale of 0-10, how would you rate your current level of pain?", QuestionType.NUMBER, true, 4);
            createQuestion("On a scale of 0-10, how would you rate your overall mood today?", QuestionType.NUMBER, true, 5);
            createQuestion("Did you sleep well last night?", QuestionType.YES_NO, false, 6);
            createQuestion("Have you eaten at least two meals today?", QuestionType.YES_NO, false, 7);
            createQuestion("I have experienced dizziness or lightheadedness today.", QuestionType.TRUE_FALSE, false, 8);
            createQuestion("Have you had any difficulty breathing or chest discomfort?", QuestionType.YES_NO, true, 9);
            createQuestion("Do you currently feel safe and comfortable at home?", QuestionType.YES_NO, true, 10);
            createQuestion("Please describe any new symptoms or concerns you've noticed.", QuestionType.TEXT, false, 11);
            createQuestion("Is there anything specific you'd like to talk to your caregiver about?", QuestionType.TEXT, false, 12);
            createQuestion("How are you feeling emotionally today?", QuestionType.TEXT, false, 13);
            createQuestion("How much energy do you feel you have right now (0 = none, 10 = full of energy)?", QuestionType.NUMBER, false, 14);
            createQuestion("Have you experienced any side effects from your medication today?", QuestionType.YES_NO, true, 15);

            long finalCount = questionRepository.count();
            log.info("✅ Successfully initialized {} Virtual Check-In questions", finalCount);

        } catch (Exception e) {
            // Log the error but don't fail application startup
            log.error("❌ Failed to initialize questions: {}", e.getMessage(), e);
        }
    }

    private void createQuestion(String prompt, QuestionType type, boolean required, int ordinal) {
        try {
            Question question = Question.builder()
                    .prompt(prompt)
                    .type(type)
                    .required(required)
                    .active(true)
                    .ordinal(ordinal)
                    .build();

            questionRepository.save(question);
            log.debug("Created question: {}", prompt.substring(0, Math.min(50, prompt.length())) + "...");

        } catch (Exception e) {
            // Log the error but continue with other questions
            log.error("Failed to create question '{}': {}", prompt, e.getMessage());
        }
    }
}