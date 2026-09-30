package com.careconnect.service;

import com.careconnect.model.ScheduledNotification;
import com.careconnect.model.Task;
import com.careconnect.model.User;
import com.careconnect.notifications.SesService;
import com.careconnect.notifications.SnsService;
import com.careconnect.repository.ScheduledNotificationRepository;
import com.careconnect.repository.TaskRepository;
import com.careconnect.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class ScheduledNotificationService {

    private final ScheduledNotificationRepository scheduledNotificationRepository;
    private final TaskRepository taskRepository;
    private final UserRepository userRepository;
    private final SesService sesService;
    private final SnsService snsService;
    private final Logger log = LoggerFactory.getLogger(ScheduledNotificationService.class);

    /**
     * Process pending scheduled notifications every minute
     */
    @Scheduled(fixedRate = 60000) // Every minute
    @Transactional
    public void processScheduledNotifications() {
        LocalDateTime now = LocalDateTime.now();
        LocalDateTime cutoff = now.plusMinutes(1); // Look ahead 1 minute

        List<ScheduledNotification> pendingNotifications = scheduledNotificationRepository
                .findByStatusAndScheduledTimeBefore("PENDING", cutoff);

        for (ScheduledNotification notification : pendingNotifications) {
            try {
                sendScheduledNotification(notification);
                notification.setStatus("SENT");
                notification.setSentTime(now);
                scheduledNotificationRepository.save(notification);
                log.info("Sent scheduled notification {} to user {}", notification.getId(), notification.getReceiverId());
            } catch (Exception e) {
                log.error("Failed to send scheduled notification {}: {}", notification.getId(), e.getMessage(), e);
                notification.setStatus("FAILED");
                notification.setErrorMessage(e.getMessage());
                scheduledNotificationRepository.save(notification);
            }
        }
    }

    /**
     * Send a scheduled notification
     */
    private void sendScheduledNotification(ScheduledNotification notification) {
        User recipient = userRepository.findById(notification.getReceiverId())
                .orElseThrow(() -> new IllegalArgumentException("Recipient not found: " + notification.getReceiverId()));

        // Send email if recipient has email
        if (recipient.getEmail() != null && !recipient.getEmail().isEmpty()) {
            try {
                String messageId = sesService.sendEmail(
                        recipient.getEmail(),
                        notification.getTitle(),
                        null, // HTML body - could be enhanced
                        notification.getBody()
                );
                notification.setMessageId(messageId);
            } catch (Exception e) {
                log.warn("Failed to send email for scheduled notification {}: {}", notification.getId(), e.getMessage());
                throw e; // Re-throw to mark as failed
            }
        }

        // Send SMS if recipient has phone
        if (recipient.getPhone() != null && !recipient.getPhone().isEmpty()) {
            try {
                String messageId = snsService.publishSms(recipient.getPhone(), notification.getBody());
                if (notification.getMessageId() == null) {
                    notification.setMessageId(messageId);
                }
            } catch (Exception e) {
                log.warn("Failed to send SMS for scheduled notification {}: {}", notification.getId(), e.getMessage());
                // Don't throw here - email might have succeeded
            }
        }
    }

    /**
     * Create a scheduled notification for a task
     */
    @Transactional
    public ScheduledNotification createScheduledNotification(Long taskId, Long receiverId, String title, String body,
                                                             LocalDateTime scheduledTime, String notificationType) {
        Task task = taskRepository.findById(taskId)
                .orElseThrow(() -> new IllegalArgumentException("Task not found: " + taskId));

        ScheduledNotification notification = ScheduledNotification.builder()
                .receiverId(receiverId)
                .title(title)
                .body(body)
                .notificationType(notificationType)
                .scheduledTime(scheduledTime)
                .task(task)
                .build();

        return scheduledNotificationRepository.save(notification);
    }

    /**
     * Create medication reminder notifications
     */
    @Transactional
    public List<ScheduledNotification> createMedicationReminders(Long patientId, String medicationName,
                                                                 String dosage, List<LocalDateTime> reminderTimes) {
        // This would be called when a medication schedule is created
        return reminderTimes.stream()
                .map(time -> createScheduledNotification(
                        null, // No specific task for medication reminders
                        patientId,
                        "Medication Reminder: " + medicationName,
                        String.format("Time to take %s (%s)", medicationName, dosage),
                        time,
                        "MEDICATION_REMINDER"
                ))
                .toList();
    }

    /**
     * Create appointment reminder notifications
     */
    @Transactional
    public ScheduledNotification createAppointmentReminder(Long patientId, String appointmentType,
                                                           LocalDateTime appointmentTime, String location) {
        LocalDateTime reminderTime = appointmentTime.minusHours(24); // 24 hours before

        return createScheduledNotification(
                null, // No specific task
                patientId,
                "Appointment Reminder: " + appointmentType,
                String.format("You have a %s appointment on %s at %s. Location: %s",
                        appointmentType,
                        appointmentTime.toLocalDate(),
                        appointmentTime.toLocalTime(),
                        location),
                reminderTime,
                "APPOINTMENT_REMINDER"
        );
    }

    /**
     * Get notifications for a user
     */
    public List<ScheduledNotification> getUserNotifications(Long userId) {
        return scheduledNotificationRepository.findByReceiverId(userId);
    }

    /**
     * Cancel a scheduled notification
     */
    @Transactional
    public void cancelScheduledNotification(Long notificationId) {
        ScheduledNotification notification = scheduledNotificationRepository.findById(notificationId)
                .orElseThrow(() -> new IllegalArgumentException("Notification not found: " + notificationId));

        notification.setStatus("CANCELLED");
        scheduledNotificationRepository.save(notification);
    }

    /**
     * Future enhancement: Bulk create notifications for recurring events
     * This would be useful for weekly medication reminders, recurring appointments, etc.
     */
    public List<ScheduledNotification> createRecurringNotifications(Long taskId, Long receiverId,
                                                                    String title, String body,
                                                                    LocalDateTime startTime, LocalDateTime endTime,
                                                                    String frequency, String notificationType) {
        // TODO: Implement recurring notification creation
        // Frequency could be "DAILY", "WEEKLY", "MONTHLY", etc.
        throw new UnsupportedOperationException("Recurring notifications not yet implemented");
    }
}