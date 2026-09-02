package com.careconnect.service;

import com.careconnect.model.Patient;
import com.careconnect.model.Task;
import com.careconnect.dto.TaskDto;
import com.careconnect.exception.AppException;
import com.careconnect.notifications.SesService;
import com.careconnect.notifications.SnsService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.transaction.annotation.Transactional;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.careconnect.repository.*;

import org.springframework.http.HttpStatus;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Service
@Transactional
public class TaskService {

    private static final Logger log = LoggerFactory.getLogger(TaskService.class);

    @Autowired
    private TaskRepository taskRepository;

    @Autowired
    private PatientRepository patientRepository;

    @Autowired
    private SesService sesService;

    @Autowired
    private SnsService snsService;

    @Value("${demo.notifications.email:}")
    private String demoNotificationEmail;

    @Value("${demo.notifications.phone:}")
    private String demoNotificationPhone;

    public Task getTaskById(Long taskId) {
        return taskRepository.findById(taskId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Task not found"));
    }

    public List<Task> getTasksByPatient(Long patientId) {
        Optional<List<Task>> tasksOpt = taskRepository.findByPatientId(patientId);
        return tasksOpt.orElseGet(ArrayList::new);
    }

    public Task createTask(Long patientId, TaskDto task) {
        // Get the patient and ensure it exists
        Patient patient = patientRepository.findById(patientId).orElseThrow(
                () -> new AppException(HttpStatus.NOT_FOUND, "Patient not found")
        );
        System.out.println("Creating task for patient: " + patient.getId());
        System.out.println("Task details: " + task);
        Task newTask = Task.builder()
                .name(task.getName())
                .description(task.getDescription())
                .date(task.getDate())
                .timeOfDay(task.getTimeOfDay())
                .isCompleted(task.isCompleted())
                .frequency(task.getFrequency())
                .taskInterval(task.getInterval())
                .doCount(task.getCount())
                .daysOfWeek(task.getDaysOfWeek())
                .taskType(task.getTaskType())
                .patient(patient)
                .build();
        System.out.println("New task created: " + newTask);
        try {
            Task savedTask = taskRepository.save(newTask);

            // Trigger notifications if this is an appointment
            if ("Appointment".equalsIgnoreCase(savedTask.getTaskType())) {
                sendAppointmentNotification(savedTask, patient);
            }

            return savedTask;
        } catch (Exception e) {
            throw new AppException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Failed to create task: " + e.getMessage());
        }
    }

    public Map<String, Object> previewTaskNotification(Long patientId, TaskDto task) {
        Patient patient = patientRepository.findById(patientId).orElseThrow(
                () -> new AppException(HttpStatus.NOT_FOUND, "Patient not found")
        );

        Map<String, Object> response = new LinkedHashMap<>();
        Map<String, Object> appointment = new LinkedHashMap<>();
        appointment.put("patientId", patientId);
        appointment.put("name", task.getName());
        appointment.put("description", task.getDescription());
        appointment.put("date", task.getDate());
        appointment.put("timeOfDay", task.getTimeOfDay());
        appointment.put("taskType", task.getTaskType());

        String dateTime = task.getDate() + " at " + task.getTimeOfDay();
        String emailAddress = resolveNotificationEmail(patient);
        String phoneNumber = resolveNotificationPhone(patient);

        Map<String, Object> notificationPreview = new LinkedHashMap<>();
        notificationPreview.put("emailRecipient", emailAddress);
        notificationPreview.put("smsRecipient", phoneNumber);
        notificationPreview.put("emailSubject", sesService.buildAppointmentReminderSubject());
        notificationPreview.put("emailHtmlBody", sesService.buildAppointmentReminderHtmlBody(dateTime));
        notificationPreview.put("emailTextBody", sesService.buildAppointmentReminderTextBody(dateTime));
        notificationPreview.put("smsBody", snsService.buildAppointmentReminderSmsMessage(dateTime));
        notificationPreview.put("willSendEmail", emailAddress != null && !emailAddress.isBlank());
        notificationPreview.put("willSendSms", phoneNumber != null && !phoneNumber.isBlank());

        response.put("appointment", appointment);
        response.put("notificationPreview", notificationPreview);
        response.put("mode", "preview");
        return response;
    }

    public Task updateTask(Long taskId, TaskDto task) {
        Task existingTask = getTaskById(taskId);
        // Update fields as necessary
        existingTask.setName(task.getName());
        existingTask.setDescription(task.getDescription());
        existingTask.setDate(task.getDate());
        existingTask.setTimeOfDay(task.getTimeOfDay());
        existingTask.setCompleted(task.isCompleted());
        existingTask.setTaskType(task.getTaskType());
        existingTask.setFrequency(task.getFrequency());
        existingTask.setTaskInterval(task.getInterval());
        existingTask.setDoCount(task.getCount());
        existingTask.setDaysOfWeek(task.getDaysOfWeek());

        // Save the updated task
        return taskRepository.save(existingTask);
    }

    public boolean deleteTask(Long taskId) {
        Task task = getTaskById(taskId);
        taskRepository.delete(task);
        return true;
    }

    public boolean existsById(Long taskId) {
        return taskRepository.findById(taskId).isPresent();
    }

    public List<Task> getAllTasks() {
        List<Task> tasks = taskRepository.findAll();
        if (tasks.isEmpty()) {
            throw new AppException(HttpStatus.NOT_FOUND, "No tasks found");
        }
        return tasks;
    }

    /**
     * Send appointment notifications via email and SMS to the patient
     */
    private void sendAppointmentNotification(Task appointment, Patient patient) {
        try {
            String appointmentType = appointment.getName();
            String dateTime = appointment.getDate() + " at " + appointment.getTimeOfDay();
            String location = appointment.getDescription() != null ? appointment.getDescription() : "TBD";

            String recipientName = resolveRecipientName(patient);
            String emailAddress = resolveNotificationEmail(patient);
            String phoneNumber = resolveNotificationPhone(patient);

            if (emailAddress != null && !emailAddress.isBlank()) {
                try {
                    sesService.sendAppointmentReminder(
                            emailAddress,
                            recipientName,
                            appointmentType,
                            dateTime,
                            location
                    );
                    log.info("Appointment confirmation email sent to {}", emailAddress);
                } catch (Exception e) {
                    log.error("Failed to send appointment email: {}", e.getMessage());
                }
            }

            if (phoneNumber != null && !phoneNumber.isBlank()) {
                try {
                    snsService.sendAppointmentReminderSms(
                            phoneNumber,
                            recipientName,
                            appointmentType,
                            dateTime
                    );
                    log.info("Appointment confirmation SMS sent to {}", phoneNumber);
                } catch (Exception e) {
                    log.error("Failed to send appointment SMS: {}", e.getMessage());
                }
            }

            if ((emailAddress == null || emailAddress.isBlank()) && (phoneNumber == null || phoneNumber.isBlank())) {
                log.warn("Appointment notification skipped for task {} because no patient or demo contact details are configured", appointment.getId());
            }
        } catch (Exception e) {
            log.error("Error sending appointment notification: {}", e.getMessage(), e);
        }
    }

    private String resolveNotificationEmail(Patient patient) {
        if (demoNotificationEmail != null && !demoNotificationEmail.isBlank()) {
            return demoNotificationEmail;
        }
        if (patient.getUser() != null && patient.getUser().getEmail() != null && !patient.getUser().getEmail().isBlank()) {
            return patient.getUser().getEmail();
        }
        return null;
    }

    private String resolveNotificationPhone(Patient patient) {
        if (demoNotificationPhone != null && !demoNotificationPhone.isBlank()) {
            return demoNotificationPhone;
        }
        if (patient.getUser() != null && patient.getUser().getPhone() != null && !patient.getUser().getPhone().isBlank()) {
            return patient.getUser().getPhone();
        }
        return null;
    }

    private String resolveRecipientName(Patient patient) {
        if (patient.getUser() != null && patient.getUser().getName() != null && !patient.getUser().getName().isBlank()) {
            return patient.getUser().getName();
        }
        return "Patient";
    }

    // Additional methods for TaskService can be added here
}
