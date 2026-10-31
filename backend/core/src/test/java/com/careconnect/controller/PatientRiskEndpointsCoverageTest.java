package com.careconnect.controller;

import com.careconnect.dto.FlagRiskRequestDto;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.PatientRisk;
import com.careconnect.model.RiskType;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.PatientRiskRepository;
import com.careconnect.repository.RiskTypeRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.service.PatientRiskService;
import com.careconnect.service.PatientService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Drives the patient risk endpoints of {@link PatientController} through a real
 * {@link PatientRiskService} backed by mocked repositories.
 */
class PatientRiskEndpointsCoverageTest {

    private PatientController controller;
    private PatientRiskRepository riskRepo;
    private User caller;
    private Patient patient;
    private RiskType fall;
    private FamilyMemberService familyMemberService;

    @BeforeEach
    void setUp() {
        riskRepo = mock(PatientRiskRepository.class);
        RiskTypeRepository typeRepo = mock(RiskTypeRepository.class);
        PatientRepository patientRepo = mock(PatientRepository.class);
        UserRepository userRepo = mock(UserRepository.class);
        PatientService patientService = mock(PatientService.class);
        CaregiverPatientLinkService linkService = mock(CaregiverPatientLinkService.class);
        familyMemberService = mock(FamilyMemberService.class);
        PatientRiskService riskService = new PatientRiskService(riskRepo, typeRepo, patientRepo, userRepo);

        caller = User.builder().id(10L).email("cg@example.test").role(Role.CAREGIVER).build();
        patient = new Patient();
        patient.setId(1L);
        patient.setUser(User.builder().id(20L).build());
        fall = RiskType.builder().id(3L).name("Fall").build();

        when(userRepo.findByEmail("cg@example.test")).thenReturn(Optional.of(caller));
        when(userRepo.findById(10L)).thenReturn(Optional.of(caller));
        when(patientService.getPatientById(1L)).thenReturn(patient);
        when(patientRepo.findById(1L)).thenReturn(Optional.of(patient));
        when(typeRepo.findById(3L)).thenReturn(Optional.of(fall));
        when(typeRepo.findAllByOrderByNameAsc()).thenReturn(List.of(fall));
        when(linkService.hasAccessToPatient(10L, 20L)).thenReturn(true);
        when(riskRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        controller = new PatientController();
        ReflectionTestUtils.setField(controller, "patientService", patientService);
        ReflectionTestUtils.setField(controller, "familyMemberService", familyMemberService);
        ReflectionTestUtils.setField(controller, "caregiverPatientLinkService", linkService);
        ReflectionTestUtils.setField(controller, "userRepository", userRepo);
        ReflectionTestUtils.setField(controller, "patientRiskService", riskService);
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("cg@example.test", null, List.of()));
        assertThat(riskService.getAllRiskTypes()).hasSize(1);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private PatientRisk risk(long id, Patient owner) {
        return PatientRisk.builder().id(id).patient(owner).riskType(fall).flaggedBy(caller)
                .flaggedAt(Instant.now()).build();
    }

    @Test
    void caregiverListsFlagsAndUnflagsRisks() {
        when(riskRepo.findByPatientIdOrderByFlaggedAtDesc(1L)).thenReturn(List.of(risk(7L, patient)));
        assertThat(controller.getPatientRisks(1L).getBody()).hasSize(1);

        FlagRiskRequestDto body = new FlagRiskRequestDto();
        body.setRiskTypeId(3L);
        assertThat(controller.flagPatientRisk(1L, body).getStatusCode().value()).isEqualTo(201);
        when(riskRepo.existsByPatientIdAndRiskTypeId(1L, 3L)).thenReturn(true);
        assertThatThrownBy(() -> controller.flagPatientRisk(1L, body)).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> controller.flagPatientRisk(1L, new FlagRiskRequestDto()))
                .isInstanceOf(AppException.class);

        when(riskRepo.findById(7L)).thenReturn(Optional.of(risk(7L, patient)));
        assertThat(controller.unflagPatientRisk(1L, 7L).getStatusCode().value()).isEqualTo(204);
        Patient other = new Patient();
        other.setId(2L);
        when(riskRepo.findById(8L)).thenReturn(Optional.of(risk(8L, other)));
        assertThatThrownBy(() -> controller.unflagPatientRisk(1L, 8L)).isInstanceOf(AppException.class);
        assertThatThrownBy(() -> controller.unflagPatientRisk(1L, 9L)).isInstanceOf(AppException.class);
    }

    @Test
    void familyMembersAndOtherRolesAreRestricted() {
        caller.setRole(Role.FAMILY_MEMBER);
        assertThatThrownBy(() -> controller.flagPatientRisk(1L, new FlagRiskRequestDto()))
                .isInstanceOf(AppException.class);
        assertThatThrownBy(() -> controller.unflagPatientRisk(1L, 7L)).isInstanceOf(AppException.class);
        when(familyMemberService.hasAccessToPatient(10L, 20L)).thenReturn(false);
        assertThatThrownBy(() -> controller.getPatientRisks(1L)).isInstanceOf(AppException.class);

        caller.setRole(Role.ADMIN);
        when(riskRepo.findByPatientIdOrderByFlaggedAtDesc(1L)).thenReturn(List.of());
        assertThat(controller.getPatientRisks(1L).getBody()).isEmpty();
    }
}
