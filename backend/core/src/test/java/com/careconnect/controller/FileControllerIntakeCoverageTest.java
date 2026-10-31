package com.careconnect.controller;

import com.careconnect.dto.StructuredEntryRequest;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverService;
import com.careconnect.service.FileManagementService;
import com.careconnect.service.PatientService;
import com.careconnect.service.S3StorageService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class FileControllerIntakeCoverageTest {

    @Mock private S3StorageService s3StorageService;
    @Mock private FileManagementService fileManagementService;
    @Mock private UserRepository userRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private MessageRepository messageRepository;
    @Mock private CaregiverService caregiverService;
    @Mock private PatientService patientService;

    private FileController controller;
    private final MockMultipartFile file = new MockMultipartFile("file", "w4.pdf", "application/pdf", new byte[]{1});

    @BeforeEach
    void setUp() {
        controller = new FileController(s3StorageService, fileManagementService, userRepository,
                patientRepository, messageRepository, caregiverService, patientService);
        User caregiver = User.builder().id(3L).email("cg@example.test").role(Role.CAREGIVER).build();
        when(userRepository.findByEmail("cg@example.test")).thenReturn(Optional.of(caregiver));
        when(patientRepository.findById(9L)).thenReturn(Optional.of(new Patient()));
        when(caregiverService.hasAccessToPatient(3L, 9L)).thenReturn(false);
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("cg@example.test", null, List.of()));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void intakeUploadValidationAndAccess() throws Exception {
        assertThat(controller.uploadIntakeDocument(file, null, "not-a-type", null, null, null)
                .getStatusCode().value()).isEqualTo(400);
        assertThat(controller.uploadIntakeDocument(file, "ONBOARDING_FORM", null, null, 1L, 2L)
                .getStatusCode().value()).isEqualTo(400);
        assertThat(controller.uploadIntakeDocument(file, "ONBOARDING_FORM", null, null, 9L, null)
                .getStatusCode().value()).isEqualTo(403);
        when(fileManagementService.uploadFile(any(), anyLong(), anyString(), anyString(), any(), any()))
                .thenThrow(new IllegalArgumentException("too big"))
                .thenThrow(new IllegalStateException("disk"));
        assertThat(controller.uploadIntakeDocument(file, "ONBOARDING_FORM", null, null, null, null)
                .getStatusCode().value()).isEqualTo(400);
        assertThat(controller.uploadIntakeDocument(file, "ONBOARDING_FORM", null, null, null, null)
                .getStatusCode().value()).isEqualTo(500);
    }

    @Test
    void intakeListingsAndStructuredEntryErrorsMapToStatuses() {
        when(fileManagementService.listEmploymentDocumentsForUser(3L, "CAREGIVER")).thenReturn(List.of());
        assertThat(controller.listMyIntakeDocuments().getStatusCode().value()).isEqualTo(200);
        assertThat(controller.listPatientIntakeDocuments(9L).getStatusCode().value()).isEqualTo(403);

        SecurityContextHolder.clearContext();
        assertThat(controller.listMyIntakeDocuments().getStatusCode().value()).isEqualTo(500);
        assertThat(controller.listPatientIntakeDocuments(9L).getStatusCode().value()).isEqualTo(500);
        assertThat(controller.createStructuredEntry(1L, new StructuredEntryRequest()).getStatusCode().value())
                .isEqualTo(500);
        assertThat(controller.getStructuredEntry(1L).getStatusCode().value()).isEqualTo(500);
        assertThat(controller.updateStructuredEntry(1L, new StructuredEntryRequest()).getStatusCode().value())
                .isEqualTo(500);
        assertThat(controller.listPatientStructuredEntries(9L).getStatusCode().value()).isEqualTo(500);
    }
}
