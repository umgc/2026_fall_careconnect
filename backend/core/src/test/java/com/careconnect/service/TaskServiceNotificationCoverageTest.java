package com.careconnect.service;

import com.careconnect.dto.TaskDto;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.Task;
import com.careconnect.model.User;
import com.careconnect.notifications.SesService;
import com.careconnect.notifications.SnsService;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.TaskRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class TaskServiceNotificationCoverageTest {

    @Mock private TaskRepository taskRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private SesService sesService;
    @Mock private SnsService snsService;
    @InjectMocks private TaskService taskService;

    private Patient patient;

    @BeforeEach
    void setUp() {
        patient = Patient.builder().id(1L)
                .user(User.builder().id(2L).name("Pat").email("pat@example.test").phone("+15550100").build())
                .build();
        when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(taskRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
    }

    private static TaskDto appointment() {
        return TaskDto.builder().name("Dentist").description("Main St").date("2026-11-01")
                .timeOfDay("09:00").taskType("Appointment").build();
    }

    @Test
    void createAppointmentSendsEmailAndSms() {
        Task saved = taskService.createTask(1L, appointment());
        assertThat(saved.getName()).isEqualTo("Dentist");
        verify(sesService).sendAppointmentReminder(anyString(), anyString(), anyString(), anyString(), anyString());
        verify(snsService).sendAppointmentReminderSms(anyString(), anyString(), anyString(), anyString());
    }

    @Test
    void createAppointmentToleratesChannelFailuresAndDemoContacts() {
        ReflectionTestUtils.setField(taskService, "demoNotificationEmail", "demo@example.test");
        ReflectionTestUtils.setField(taskService, "demoNotificationPhone", "+15550199");
        doThrow(new RuntimeException("ses")).when(sesService)
                .sendAppointmentReminder(any(), any(), any(), any(), any());
        doThrow(new RuntimeException("sns")).when(snsService)
                .sendAppointmentReminderSms(any(), any(), any(), any());
        TaskDto dto = appointment();
        dto.setDescription(null);
        assertThat(taskService.createTask(1L, dto)).isNotNull();
    }

    @Test
    void createAppointmentWithoutContactsSkipsNotification() {
        patient.setUser(User.builder().id(2L).build());
        assertThat(taskService.createTask(1L, appointment())).isNotNull();
        patient.setUser(null);
        assertThat(taskService.createTask(1L, appointment())).isNotNull();
    }

    @Test
    void createTaskWrapsSaveFailure() {
        when(taskRepository.save(any())).thenThrow(new RuntimeException("db"));
        assertThatThrownBy(() -> taskService.createTask(1L, appointment())).isInstanceOf(AppException.class);
    }

    @Test
    void previewBuildsNotificationPayload() {
        when(sesService.buildAppointmentReminderSubject()).thenReturn("subj");
        Map<String, Object> preview = taskService.previewTaskNotification(1L, appointment());
        assertThat(preview).containsEntry("mode", "preview");
        @SuppressWarnings("unchecked")
        Map<String, Object> notif = (Map<String, Object>) preview.get("notificationPreview");
        assertThat(notif).containsEntry("willSendEmail", true);

        patient.setUser(User.builder().build());
        assertThat(taskService.previewTaskNotification(1L, appointment())).isNotNull();
        assertThatThrownBy(() -> taskService.previewTaskNotification(9L, appointment()))
                .isInstanceOf(AppException.class);
    }
}
