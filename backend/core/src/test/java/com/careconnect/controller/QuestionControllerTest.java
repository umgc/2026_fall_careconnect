package com.careconnect.controller;

import com.careconnect.dto.QuestionDTO;
import com.careconnect.dto.QuestionUpsertDTO;
import com.careconnect.model.QuestionType;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.QuestionService;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(QuestionController.class)
@DisplayName("QuestionController Tests")
class QuestionControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private QuestionService questionService;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    private QuestionDTO sampleQuestion;
    private QuestionDTO activeQuestion;
    private QuestionUpsertDTO upsertPayload;

    @BeforeEach
    void setUp() throws Exception {
        sampleQuestion = new QuestionDTO(1L, "How are you feeling today?", "TEXT", true, false, 1);
        activeQuestion = new QuestionDTO(1L, "How are you feeling today?", "TEXT", true, true, 1);
        upsertPayload = new QuestionUpsertDTO(
                "How are you feeling today?",
                QuestionType.TEXT,
                true,
                1
        );
    }

    @Nested
    @DisplayName("GET /questions")
    class ListQuestions {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns all questions when active filter is missing")
        void returnsAllWhenFilterMissing() throws Exception {
            // Arrange
            when(questionService.listQuestions(null)).thenReturn(List.of(sampleQuestion));

            // Act + Assert
            mockMvc.perform(get("/v1/api/questions"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(1))
                    .andExpect(jsonPath("$[0].prompt").value("How are you feeling today?"))
                    .andExpect(jsonPath("$[0].active").value(false));

            // Assert
            verify(questionService).listQuestions(null);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Passes active=true filter to service")
        void passesActiveTrueFilter() throws Exception {
            // Arrange
            when(questionService.listQuestions(true)).thenReturn(List.of(activeQuestion));

            // Act + Assert
            mockMvc.perform(get("/api/questions").param("active", "true"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].active").value(true));

            // Assert
            verify(questionService).listQuestions(true);
        }
    }

    @Nested
    @DisplayName("GET /questions/{id}")
    class GetOneQuestion {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 200 when question exists")
        void returns200WhenFound() throws Exception {
            // Arrange
            when(questionService.getOne(1L)).thenReturn(Optional.of(sampleQuestion));

            // Act + Assert
            mockMvc.perform(get("/api/questions/1"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(1))
                    .andExpect(jsonPath("$.prompt").value("How are you feeling today?"))
                    .andExpect(jsonPath("$.type").value("TEXT"));

            // Assert
            verify(questionService).getOne(1L);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 404 when question is missing")
        void returns404WhenMissing() throws Exception {
            // Arrange
            when(questionService.getOne(999L)).thenReturn(Optional.empty());

            // Act + Assert
            mockMvc.perform(get("/v1/api/questions/999"))
                    .andExpect(status().isNotFound());

            // Assert
            verify(questionService).getOne(999L);
        }
    }

    @Nested
    @DisplayName("POST /questions")
    class CreateQuestion {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Creates a new question")
        void createsQuestion() throws Exception {
            // Arrange
            when(questionService.create(any(QuestionUpsertDTO.class))).thenReturn(sampleQuestion);

            // Act + Assert
            mockMvc.perform(post("/api/questions")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(upsertPayload)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(1))
                    .andExpect(jsonPath("$.required").value(true))
                    .andExpect(jsonPath("$.ordinal").value(1));

            // Assert
            verify(questionService).create(any(QuestionUpsertDTO.class));
        }
    }

    @Nested
    @DisplayName("PUT /questions/{id}")
    class UpdateQuestion {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns updated question when id exists")
        void returnsUpdatedQuestionWhenFound() throws Exception {
            // Arrange
            final QuestionDTO updated = new QuestionDTO(1L, "Updated prompt", "TEXT", false, true, 2);
            when(questionService.update(eq(1L), any(QuestionUpsertDTO.class)))
                    .thenReturn(Optional.of(updated));

            // Act + Assert
            mockMvc.perform(put("/v1/api/questions/1")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(upsertPayload)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.prompt").value("Updated prompt"))
                    .andExpect(jsonPath("$.required").value(false))
                    .andExpect(jsonPath("$.ordinal").value(2));

            // Assert
            verify(questionService).update(eq(1L), any(QuestionUpsertDTO.class));
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 404 when id does not exist")
        void returns404WhenNotFound() throws Exception {
            // Arrange
            when(questionService.update(eq(404L), any(QuestionUpsertDTO.class)))
                    .thenReturn(Optional.empty());

            // Act + Assert
            mockMvc.perform(put("/api/questions/404")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(upsertPayload)))
                    .andExpect(status().isNotFound());

            // Assert
            verify(questionService).update(eq(404L), any(QuestionUpsertDTO.class));
        }
    }

    @Nested
    @DisplayName("POST /questions – validation")
    class CreateValidation {

        @Test
        @WithMockUser(username = "admin@test.com")
        @DisplayName("Returns 400 when prompt is blank")
        void returns400WhenPromptIsBlank() throws Exception {
            final QuestionUpsertDTO invalid = new QuestionUpsertDTO(
                    "", QuestionType.TEXT, false, 1);

            mockMvc.perform(post("/api/questions")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(invalid)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Validation failed"))
                    .andExpect(jsonPath("$.fields[0]").value("prompt: prompt must not be blank"));

            verifyNoInteractions(questionService);
        }

        @Test
        @WithMockUser(username = "admin@test.com")
        @DisplayName("Returns 400 when type is null")
        void returns400WhenTypeIsNull() throws Exception {
            final String payload = "{\"prompt\":\"How are you?\",\"type\":null,\"required\":false,\"ordinal\":1}";

            mockMvc.perform(post("/api/questions")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(payload))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Validation failed"));

            verifyNoInteractions(questionService);
        }

        @Test
        @WithMockUser(username = "admin@test.com")
        @DisplayName("Returns 400 when ordinal is null")
        void returns400WhenOrdinalIsNull() throws Exception {
            final String payload = "{\"prompt\":\"How are you?\",\"type\":\"TEXT\",\"required\":false,\"ordinal\":null}";

            mockMvc.perform(post("/api/questions")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(payload))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Validation failed"));

            verifyNoInteractions(questionService);
        }

        @Test
        @WithMockUser(username = "admin@test.com")
        @DisplayName("Returns 400 when ordinal is negative")
        void returns400WhenOrdinalIsNegative() throws Exception {
            final QuestionUpsertDTO invalid = new QuestionUpsertDTO(
                    "Some question", QuestionType.TEXT, false, -1);

            mockMvc.perform(post("/api/questions")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(invalid)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Validation failed"))
                    .andExpect(jsonPath("$.fields[0]").value("ordinal: ordinal must be 0 or greater"));

            verifyNoInteractions(questionService);
        }
    }

    @Nested
    @DisplayName("PUT /questions/{id} – validation")
    class UpdateValidation {

        @Test
        @WithMockUser(username = "admin@test.com")
        @DisplayName("Returns 400 when prompt is blank on update")
        void returns400WhenPromptIsBlankOnUpdate() throws Exception {
            final QuestionUpsertDTO invalid = new QuestionUpsertDTO(
                    "   ", QuestionType.YES_NO, true, 0);

            mockMvc.perform(put("/api/questions/1")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(invalid)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Validation failed"));

            verifyNoInteractions(questionService);
        }
    }
    @Nested
    @DisplayName("PATCH /questions/{id}/active")
    class SetActive {

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 200 when setActive succeeds")
        void returns200WhenSetActiveSucceeds() throws Exception {
            // Arrange
            when(questionService.setActive(1L, true)).thenReturn(Optional.of(activeQuestion));

            // Act + Assert
            mockMvc.perform(patch("/api/questions/1/active")
                            .with(csrf())
                            .param("active", "true"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(1))
                    .andExpect(jsonPath("$.active").value(true));

            // Assert
            verify(questionService).setActive(1L, true);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 404 when question does not exist")
        void returns404WhenQuestionMissing() throws Exception {
            // Arrange
            when(questionService.setActive(999L, false)).thenReturn(Optional.empty());

            // Act + Assert
            mockMvc.perform(patch("/v1/api/questions/999/active")
                            .with(csrf())
                            .param("active", "false"))
                    .andExpect(status().isNotFound());

            // Assert
            verify(questionService).setActive(999L, false);
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        @DisplayName("Returns 500 when active query parameter is missing")
        void returns500WhenActiveMissing() throws Exception {
            // Act + Assert
            mockMvc.perform(patch("/api/questions/1/active")
                            .with(csrf()))
                    .andExpect(status().isInternalServerError())
                    .andExpect(jsonPath("$.error").value("An unexpected error occurred"));

            // Assert
            verifyNoInteractions(questionService);
        }
    }
}
