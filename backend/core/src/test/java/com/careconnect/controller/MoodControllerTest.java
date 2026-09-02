package com.careconnect.controller;

import com.careconnect.model.Mood;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.service.MoodService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class MoodControllerTest {

    private static final Long USER_ID = 1L;
    private static final Long CAREGIVER_ID = 10L;
    @Mock
    private MoodService moodService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @Mock
    private UserRepository userRepository;
    @Mock
    private CaregiverPatientLinkService caregiverPatientLinkService;
    @Mock
    private FamilyMemberService familyMemberService;
    @InjectMocks
    private MoodController controller;

    @BeforeEach
    void setUpSecurityContext() {
        final User patient = User.builder()
                .id(USER_ID)
                .email("patient@test.com")
                .role(Role.PATIENT)
                .password("p")
                .status("ACTIVE")
                .build();
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("patient@test.com", null, List.of()));
        lenient().when(userRepository.findByEmail("patient@test.com")).thenReturn(Optional.of(patient));
    }

    private Mood makeMood(Long userId, int score, String label) {
        final Mood m = new Mood(userId, score, label);
        m.setCreatedAt(LocalDateTime.now());
        return m;
    }

    // ─── saveMood ─────────────────────────────────────────────────────────────

    @Test
    void saveMood_returns200_withSavedMood() throws Exception {
        final Mood saved = makeMood(USER_ID, 8, "Happy");
        when(moodService.saveMood(USER_ID, 8, "Happy")).thenReturn(saved);

        final Map<String, Object> payload = Map.of("score", 8, "label", "Happy");
        final ResponseEntity<Mood> response = controller.saveMood(USER_ID, payload);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(saved);
    }

    @Test
    void saveMood_returnsCorrectMoodValues() throws Exception {
        final Mood saved = makeMood(USER_ID, 3, "Sad");
        when(moodService.saveMood(USER_ID, 3, "Sad")).thenReturn(saved);

        final Map<String, Object> payload = Map.of("score", 3, "label", "Sad");
        final ResponseEntity<Mood> response = controller.saveMood(USER_ID, payload);

        assertThat(response.getBody().getScore()).isEqualTo(3);
        assertThat(response.getBody().getLabel()).isEqualTo("Sad");
    }

    // ─── getCaregiverMoodSummaries ────────────────────────────────────────────

    @Test
    void getCaregiverMoodSummaries_allPatientsHaveMoods() throws Exception {
        // The controller hardcodes patientIds = [1, 2, 3]
        final Mood mood1 = makeMood(1L, 7, "Good");
        final Mood mood2 = makeMood(2L, 5, "Neutral");
        final Mood mood3 = makeMood(3L, 9, "Excellent");

        when(moodService.getMoods(1L)).thenReturn(List.of(mood1));
        when(moodService.getMoods(2L)).thenReturn(List.of(mood2));
        when(moodService.getMoods(3L)).thenReturn(List.of(mood3));

        final ResponseEntity<Map<String, Object>> response = controller.getCaregiverMoodSummaries(CAREGIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        final Map<String, Object> body = response.getBody();
        assertThat(body.get("caregiverId")).isEqualTo(CAREGIVER_ID);
        @SuppressWarnings("unchecked") final List<Map<String, Object>> summaries = (List<Map<String, Object>>) body.get("summaries");
        assertThat(summaries).hasSize(3);
        assertThat(summaries.get(0).get("score")).isEqualTo(7);
        assertThat(summaries.get(0).get("label")).isEqualTo("Good");
    }

    @Test
    void getCaregiverMoodSummaries_somePatientsNoMoods() throws Exception {
        // patient 1 has moods, patient 2 and 3 do not
        final Mood mood1 = makeMood(1L, 7, "Good");
        when(moodService.getMoods(1L)).thenReturn(List.of(mood1));
        when(moodService.getMoods(2L)).thenReturn(List.of());
        when(moodService.getMoods(3L)).thenReturn(List.of());

        final ResponseEntity<Map<String, Object>> response = controller.getCaregiverMoodSummaries(CAREGIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked") final List<Map<String, Object>> summaries =
                (List<Map<String, Object>>) response.getBody().get("summaries");
        assertThat(summaries).hasSize(1);
        assertThat(summaries.get(0).get("patientId")).isEqualTo(1L);
    }

    @Test
    void getCaregiverMoodSummaries_noPatientsHaveMoods_emptySummaries() throws Exception {
        when(moodService.getMoods(1L)).thenReturn(List.of());
        when(moodService.getMoods(2L)).thenReturn(List.of());
        when(moodService.getMoods(3L)).thenReturn(List.of());

        final ResponseEntity<Map<String, Object>> response = controller.getCaregiverMoodSummaries(CAREGIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked") final List<Map<String, Object>> summaries =
                (List<Map<String, Object>>) response.getBody().get("summaries");
        assertThat(summaries).isEmpty();
    }

    @Test
    void getCaregiverMoodSummaries_summaryContainsCreatedAt() throws Exception {
        final Mood mood = makeMood(1L, 6, "Okay");
        when(moodService.getMoods(1L)).thenReturn(List.of(mood));
        when(moodService.getMoods(2L)).thenReturn(List.of());
        when(moodService.getMoods(3L)).thenReturn(List.of());

        final ResponseEntity<Map<String, Object>> response = controller.getCaregiverMoodSummaries(CAREGIVER_ID);

        @SuppressWarnings("unchecked") final List<Map<String, Object>> summaries =
                (List<Map<String, Object>>) response.getBody().get("summaries");
        assertThat(summaries.get(0)).containsKey("createdAt");
    }

    // ─── getMoods ─────────────────────────────────────────────────────────────

    @Test
    void getMoods_returns200_withMoodList() throws Exception {
        final List<Mood> moods = List.of(makeMood(USER_ID, 7, "Good"), makeMood(USER_ID, 5, "Okay"));
        when(moodService.getMoods(USER_ID)).thenReturn(moods);

        final ResponseEntity<List<Mood>> response = controller.getMoods(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(moods);
    }

    @Test
    void getMoods_returns200_emptyList() throws Exception {
        when(moodService.getMoods(USER_ID)).thenReturn(List.of());

        final ResponseEntity<List<Mood>> response = controller.getMoods(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }
}
