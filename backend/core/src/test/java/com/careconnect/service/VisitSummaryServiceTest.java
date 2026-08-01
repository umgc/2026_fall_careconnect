package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.model.VisitSummary;
import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.repository.VisitSummaryRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
@DisplayName("VisitSummaryService Tests")
class VisitSummaryServiceTest {

    private static final Long VISIT_ID = 100L;
    private static final Long PATIENT_ID = 42L;
    private static final Long CAREGIVER_USER_ID = 7L;

    @Mock
    private VisitSummaryPersistenceService persistenceService;

    @Mock
    private VisitSummaryRepository visitSummaryRepository;

    @Mock
    private ScheduledVisitRepository scheduledVisitRepository;

    @Mock
    private BedrockSentimentService bedrockSentimentService;

    private VisitSummaryService service;

    @BeforeEach
    void setUp() {
        service = new VisitSummaryService(
                persistenceService,
                visitSummaryRepository,
                scheduledVisitRepository,
                bedrockSentimentService,
                new ObjectMapper());
        lenient().when(bedrockSentimentService.summaryModelConfigVersion())
                .thenReturn("amazon.nova-pro-v1:0:visit-summary-v1");
        lenient().when(bedrockSentimentService.summaryEngine())
                .thenReturn("aws_bedrock:amazon.nova-pro-v1:0");
        lenient().when(persistenceService.persist(any(VisitSummary.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        lenient().when(visitSummaryRepository.findTopByVisitIdOrderByGeneratedAtDesc(anyString()))
                .thenReturn(Optional.empty());
    }

    private ScheduledVisit sampleVisit(final String notes) {
        final ScheduledVisit visit = new ScheduledVisit();
        visit.setId(VISIT_ID);
        visit.setCaregiverId(CAREGIVER_USER_ID);
        visit.setPatientId(PATIENT_ID);
        visit.setServiceType("Medication Management");
        visit.setScheduledDate(LocalDate.of(2026, 7, 24));
        visit.setScheduledTime(LocalTime.of(9, 0));
        visit.setNotes(notes);
        visit.setStatus("Completed");
        return visit;
    }

    @Test
    @DisplayName("throws when visitId is null")
    void generateAndStoreSummary_throwsWhenVisitIdNull() {
        assertThatThrownBy(() -> service.generateAndStoreSummary(null, CAREGIVER_USER_ID))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("throws when visit not found")
    void generateAndStoreSummary_throwsWhenVisitNotFound() {
        when(scheduledVisitRepository.findById(VISIT_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.generateAndStoreSummary(VISIT_ID, CAREGIVER_USER_ID))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Scheduled visit not found");
    }

    @Test
    @DisplayName("stores NO_TRANSCRIPT summary when notes are blank")
    void generateAndStoreSummary_noTranscriptWhenNotesBlank() {
        when(scheduledVisitRepository.findById(VISIT_ID))
                .thenReturn(Optional.of(sampleVisit("  ")));

        final VisitSummary result = service.generateAndStoreSummary(VISIT_ID, CAREGIVER_USER_ID);

        assertThat(result.getStatus()).isEqualTo("NO_TRANSCRIPT");
        assertThat(result.getVisitId()).isEqualTo(String.valueOf(VISIT_ID));
        assertThat(result.getPatientId()).isEqualTo(PATIENT_ID);
        assertThat(result.getCaregiverVisibility()).isEqualTo("on_consent");
        assertThat(result.getSummaryJson()).isEqualTo("{}");
        verify(bedrockSentimentService, org.mockito.Mockito.never())
                .summarizeTranscript(anyString(), anyString(), any());
        verify(persistenceService).persist(result);
    }

    @Test
    @DisplayName("stores SUCCESS summary from Bedrock when notes present")
    void generateAndStoreSummary_successWhenNotesPresent() {
        when(scheduledVisitRepository.findById(VISIT_ID))
                .thenReturn(Optional.of(sampleVisit("Patient tolerated new medication well.")));
        when(bedrockSentimentService.summarizeTranscript(
                eq("visit-" + VISIT_ID), anyString(), eq(Map.of())))
                .thenReturn(Map.of("headline", "Medication visit went well"));

        final VisitSummary result = service.generateAndStoreSummary(VISIT_ID, CAREGIVER_USER_ID);

        assertThat(result.getStatus()).isEqualTo("SUCCESS");
        assertThat(result.getSummaryJson()).contains("Medication visit went well");
        assertThat(result.getSummarizationEngine()).isEqualTo("aws_bedrock:amazon.nova-pro-v1:0");

        final ArgumentCaptor<String> sourceTextCaptor = ArgumentCaptor.forClass(String.class);
        verify(bedrockSentimentService).summarizeTranscript(
                eq("visit-" + VISIT_ID), sourceTextCaptor.capture(), eq(Map.of()));
        assertThat(sourceTextCaptor.getValue())
                .contains("Medication Management")
                .contains("Date: 2026-07-24 09:00")
                .contains("Patient tolerated new medication well.");
    }

    @Test
    @DisplayName("stores ERROR summary when summarization fails")
    void generateAndStoreSummary_errorWhenSummarizationFails() {
        when(scheduledVisitRepository.findById(VISIT_ID))
                .thenReturn(Optional.of(sampleVisit("Some notes")));
        when(bedrockSentimentService.summarizeTranscript(anyString(), anyString(), any()))
                .thenThrow(new ModelInferenceException("bedrock timeout", new RuntimeException()));

        final VisitSummary result = service.generateAndStoreSummary(VISIT_ID, CAREGIVER_USER_ID);

        assertThat(result.getStatus()).isEqualTo("ERROR");
        assertThat(result.getErrorMessage()).isEqualTo("bedrock timeout");
        assertThat(result.getSummaryJson()).isEqualTo("{}");
    }

    @Test
    @DisplayName("returns existing SUCCESS summary without regenerating")
    void generateAndStoreSummary_skipsWhenSuccessExists() {
        final VisitSummary existing = new VisitSummary();
        existing.setId(9L);
        existing.setVisitId(String.valueOf(VISIT_ID));
        existing.setStatus("SUCCESS");
        existing.setSummaryJson("{\"headline\":\"already done\"}");
        when(visitSummaryRepository.findTopByVisitIdOrderByGeneratedAtDesc(String.valueOf(VISIT_ID)))
                .thenReturn(Optional.of(existing));

        final VisitSummary result = service.generateAndStoreSummary(VISIT_ID, CAREGIVER_USER_ID);

        assertThat(result).isSameAs(existing);
        verify(scheduledVisitRepository, org.mockito.Mockito.never()).findById(any());
        verify(persistenceService, org.mockito.Mockito.never()).persist(any());
        verify(bedrockSentimentService, org.mockito.Mockito.never())
                .summarizeTranscript(anyString(), anyString(), any());
    }

    @Test
    @DisplayName("force regenerates even when SUCCESS summary exists")
    void generateAndStoreSummary_forceRegenerates() {
        when(scheduledVisitRepository.findById(VISIT_ID))
                .thenReturn(Optional.of(sampleVisit("Fresh notes")));
        when(bedrockSentimentService.summarizeTranscript(anyString(), anyString(), any()))
                .thenReturn(Map.of("headline", "regenerated"));

        final VisitSummary result =
                service.generateAndStoreSummary(VISIT_ID, CAREGIVER_USER_ID, true);

        assertThat(result.getStatus()).isEqualTo("SUCCESS");
        assertThat(result.getSummaryJson()).contains("regenerated");
        verify(persistenceService).persist(any(VisitSummary.class));
    }
}
