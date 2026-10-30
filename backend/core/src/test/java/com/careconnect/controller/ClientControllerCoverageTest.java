package com.careconnect.controller;

import com.careconnect.exception.AppException;
import com.careconnect.model.ActivityLog;
import com.careconnect.model.BehavioralIncident;
import com.careconnect.model.Caregiver;
import com.careconnect.model.ClientEvent;
import com.careconnect.model.IncidentReport;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.ActivityLogRepository;
import com.careconnect.repository.BehavioralIncidentRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.ClientEventRepository;
import com.careconnect.repository.IncidentReportRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.service.PatientService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class ClientControllerCoverageTest {

    @Mock private PatientService patientService;
    @Mock private UserRepository userRepository;
    @Mock private CaregiverPatientLinkService caregiverPatientLinkService;
    @Mock private FamilyMemberService familyMemberService;
    @Mock private CaregiverRepository caregiverRepository;
    @Mock private BehavioralIncidentRepository behavioralIncidentRepository;
    @Mock private IncidentReportRepository incidentReportRepository;
    @Mock private ClientEventRepository clientEventRepository;
    @Mock private ActivityLogRepository activityLogRepository;
    @InjectMocks private ClientController controller;

    private User caller;
    private final LocalDate monday = LocalDate.now().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));

    @BeforeEach
    void setUp() {
        caller = User.builder().id(10L).email("me@example.test").role(Role.ADMIN).build();
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("me@example.test", null, List.of()));
        when(userRepository.findByEmail("me@example.test")).thenReturn(Optional.of(caller));
        Patient patient = new Patient();
        patient.setId(1L);
        patient.setUser(User.builder().id(20L).build());
        when(patientService.getPatientById(1L)).thenReturn(patient);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private LocalDateTime weeksAgo(int w) {
        return monday.minusWeeks(w).atTime(10, 0);
    }

    private ActivityLog log(int weeksAgo, int score, String name) {
        return ActivityLog.builder().clientId(1L).activityId((long) Math.abs(name.hashCode() % 50))
                .activityName(name).caregiverUserId(10L).competencyScore(score).createdAt(weeksAgo(weeksAgo)).build();
    }

    @Test
    void accessValidationAcrossRoles() {
        caller.setRole(Role.PATIENT);
        assertThatThrownBy(() -> controller.putActivityConfig(1L, 2L, Map.of())).isInstanceOf(AppException.class);
        caller.setId(20L);
        assertThat(controller.putActivityConfig(1L, 2L, Map.of()).getStatusCode().value()).isEqualTo(200);

        caller.setRole(Role.CAREGIVER);
        when(caregiverPatientLinkService.hasAccessToPatient(anyLong(), anyLong())).thenReturn(false);
        assertThatThrownBy(() -> controller.putActivityConfig(1L, 2L, Map.of())).isInstanceOf(AppException.class);

        caller.setRole(Role.FAMILY_MEMBER);
        when(familyMemberService.hasAccessToPatient(anyLong(), anyLong())).thenReturn(false);
        assertThatThrownBy(() -> controller.putActivityConfig(1L, 2L, Map.of())).isInstanceOf(AppException.class);
        when(familyMemberService.hasAccessToPatient(anyLong(), anyLong())).thenReturn(true);
        assertThat(controller.postActivityIcon(1L, 2L, new MockMultipartFile("file", new byte[]{1}))
                .getBody()).containsEntry("iconUrl", "/placeholder-icon");
    }

    @Test
    void auditLogIncludesEveryRecordType() {
        when(activityLogRepository.findByClientIdOrderByCreatedAtDesc(eq(1L), any()))
                .thenReturn(List.of(log(0, 3, "Bathing")));
        when(behavioralIncidentRepository.findByClientIdOrderByOccurredAtDesc(1L)).thenReturn(List.of(
                BehavioralIncident.builder().createdBy(11L).observedBehavior("pacing").createdAt(weeksAgo(0)).build()));
        when(incidentReportRepository.findByClientIdOrderByOccurredAtDesc(1L)).thenReturn(List.of(
                IncidentReport.builder().createdBy(12L).incidentType(IncidentReport.IncidentType.FALL)
                        .location("kitchen").createdAt(weeksAgo(0)).build(),
                IncidentReport.builder().createdBy(12L).createdAt(weeksAgo(20)).build()));
        when(clientEventRepository.findByClientIdOrderByTappedAtDesc(1L)).thenReturn(List.of(
                ClientEvent.builder().caregiverId(5L).activityId(3L).createdAt(weeksAgo(0)).build(),
                ClientEvent.builder().caregiverId(6L).activityId(3L).createdAt(null).build()));
        Caregiver cg = new Caregiver();
        cg.setId(5L);
        cg.setUser(User.builder().id(13L).email("cg@example.test").build());
        Caregiver noUser = new Caregiver();
        noUser.setId(6L);
        when(caregiverRepository.findAllById(any())).thenReturn(List.of(cg, noUser));
        when(userRepository.findAllById(any())).thenReturn(List.of(
                User.builder().id(10L).name("Admin").build(), cg.getUser()));

        assertThat(controller.getAuditLog(1L, monday.minusWeeks(4), LocalDate.now(), null).getBody()).hasSize(4);
        assertThat(controller.getAuditLog(1L, null, null, "client_event").getBody()).hasSize(1);
    }

    @Test
    void competencyTrendsComputeStatus() {
        List<ActivityLog> improving = new ArrayList<>();
        for (int w = 0; w < 4; w++) {
            improving.add(log(w, w < 2 ? 5 : 1, "Bathing"));
            improving.add(log(w, w < 2 ? 5 : 1, ""));
        }
        when(activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(eq(1L), any(), any()))
                .thenReturn(improving);
        assertThat(controller.getCompetencyTrends(1L, LocalDate.now(), monday.minusWeeks(6)).getBody().getStatus())
                .isEqualTo("IMPROVING");

        List<ActivityLog> declining = new ArrayList<>();
        for (int w = 0; w < 4; w++) {
            declining.add(log(w, w < 2 ? 1 : 5, "Bathing"));
        }
        when(activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(eq(1L), any(), any()))
                .thenReturn(declining);
        assertThat(controller.getCompetencyTrends(1L, null, null).getBody().getStatus()).isEqualTo("DECLINING");

        List<ActivityLog> stable = new ArrayList<>();
        for (int w = 0; w < 4; w++) {
            stable.add(log(w, 3, "Bathing"));
        }
        when(activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(eq(1L), any(), any()))
                .thenReturn(stable);
        assertThat(controller.getCompetencyTrends(1L, null, null).getBody().getStatus()).isEqualTo("STABLE");
    }

    private List<BehavioralIncident> incidents(int[] perWeek) {
        List<BehavioralIncident> list = new ArrayList<>();
        for (int w = 0; w < perWeek.length; w++) {
            for (int i = 0; i < perWeek[w]; i++) {
                list.add(BehavioralIncident.builder().observedBehavior("pacing and yelling loudly")
                        .occurredAt(weeksAgo(w)).build());
            }
        }
        return list;
    }

    @Test
    void behavioralTrendsComputeDirection() {
        when(behavioralIncidentRepository.findByClientIdAndOccurredAtBetweenOrderByOccurredAtAsc(eq(1L), any(), any()))
                .thenReturn(incidents(new int[]{3, 3, 1, 1}))
                .thenReturn(incidents(new int[]{1, 1, 3, 3}))
                .thenReturn(incidents(new int[]{1, 1, 1, 1}));
        assertThat(controller.getBehavioralTrends(1L, LocalDate.now(), monday.minusWeeks(6)).getBody().getTrend())
                .isEqualTo("UP");
        assertThat(controller.getBehavioralTrends(1L, null, null).getBody().getTrend()).isEqualTo("DOWN");
        assertThat(controller.getBehavioralTrends(1L, null, null).getBody().getTrend()).isEqualTo("STABLE");
    }

    private List<ActivityLog> participation(int[] perWeek) {
        List<ActivityLog> list = new ArrayList<>();
        String[] names = {"Bathing", "Laundry", "Juggling", ""};
        for (int w = 0; w < perWeek.length; w++) {
            for (int i = 0; i < perWeek[w]; i++) {
                list.add(log(w, 3, names[i % names.length]));
            }
        }
        return list;
    }

    @Test
    void participationComputesStatus() {
        when(activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(eq(1L), any(), any()))
                .thenReturn(participation(new int[]{5, 5, 1, 1}))
                .thenReturn(participation(new int[]{1, 1, 5, 5}))
                .thenReturn(participation(new int[]{2, 2, 2, 2}));
        assertThat(controller.getParticipation(1L, LocalDate.now(), monday.minusWeeks(6)).getBody()).isNotNull();
        assertThat(controller.getParticipation(1L, null, null).getBody()).isNotNull();
        assertThat(controller.getParticipation(1L, null, null).getBody()).isNotNull();
    }

    @Test
    void createIncidentReportValidatesAndSaves() {
        Caregiver cg = new Caregiver();
        cg.setId(5L);
        when(caregiverRepository.findByUserId(10L)).thenReturn(Optional.of(cg));
        when(incidentReportRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        Map<String, Object> body = new HashMap<>();
        body.put("incident_type", "fall");
        body.put("occurred_at", "not-a-date");
        body.put("location", "hall");
        body.put("outcome", "ok");
        assertThatThrownBy(() -> controller.createIncidentReport(1L, body)).isInstanceOf(AppException.class);
        body.put("occurred_at", "2026-05-01T10:00:00");
        body.put("trigger_notes", "wet floor");
        List<String> actions = new ArrayList<>();
        actions.add("called nurse");
        actions.add(" ");
        actions.add(null);
        body.put("actions_taken", actions);
        assertThat(controller.createIncidentReport(1L, body).getStatusCode().value()).isEqualTo(201);
    }
}
