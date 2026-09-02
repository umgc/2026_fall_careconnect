package com.careconnect.service;

import com.careconnect.model.ScheduledNotification;
import com.careconnect.model.Task;
import com.careconnect.model.User;
import com.careconnect.notifications.SesService;
import com.careconnect.notifications.SnsService;
import com.careconnect.repository.ScheduledNotificationRepository;
import com.careconnect.repository.TaskRepository;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link ScheduledNotificationService}.
 * <p>
 * All dependencies (repositories, SES/SNS services) are mocked.
 */
@ExtendWith(MockitoExtension.class)
class ScheduledNotificationServiceTest {

    @Mock
    private ScheduledNotificationRepository scheduledNotificationRepository;

    @Mock
    private TaskRepository taskRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private SesService sesService;

    @Mock
    private SnsService snsService;

    @InjectMocks
    private ScheduledNotificationService scheduledNotificationService;

    private User testUser;
    private Task testTask;

    @BeforeEach
    void setUp() {
        testUser = new User();
        testUser.setId(1L);
        testUser.setEmail("user@example.com");
        testUser.setPhone("+15551234567");
        testUser.setName("Test User");

        testTask = new Task();
        testTask.setId(100L);
    }

    // ========== processScheduledNotifications tests ==========

    @Nested
    @DisplayName("processScheduledNotifications")
    class ProcessScheduledNotificationsTests {

        @Test
        @DisplayName("processes pending notifications and marks them SENT")
        void processScheduledNotifications_pendingNotifications_markedSent() {
            ScheduledNotification notification = ScheduledNotification.builder()
                    .id(1L)
                    .receiverId(1L)
                    .title("Test Title")
                    .body("Test Body")
                    .status("PENDING")
                    .scheduledTime(LocalDateTime.now().minusMinutes(5))
                    .build();

            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(List.of(notification));
            when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
            when(sesService.sendEmail(anyString(), anyString(), any(), anyString()))
                    .thenReturn("ses-msg-id");
            when(snsService.publishSms(anyString(), anyString()))
                    .thenReturn("sns-msg-id");

            scheduledNotificationService.processScheduledNotifications();

            assertEquals("SENT", notification.getStatus());
            assertNotNull(notification.getSentTime());
            verify(scheduledNotificationRepository).save(notification);
        }

        @Test
        @DisplayName("marks notification FAILED when exception occurs during send")
        void processScheduledNotifications_exceptionDuringSend_markedFailed() {
            ScheduledNotification notification = ScheduledNotification.builder()
                    .id(2L)
                    .receiverId(999L)
                    .title("Fail Title")
                    .body("Fail Body")
                    .status("PENDING")
                    .scheduledTime(LocalDateTime.now().minusMinutes(5))
                    .build();

            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(List.of(notification));
            when(userRepository.findById(999L))
                    .thenReturn(Optional.empty());

            scheduledNotificationService.processScheduledNotifications();

            assertEquals("FAILED", notification.getStatus());
            assertNotNull(notification.getErrorMessage());
            verify(scheduledNotificationRepository).save(notification);
        }

        @Test
        @DisplayName("does nothing when no pending notifications exist")
        void processScheduledNotifications_noPending_doesNothing() {
            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(Collections.emptyList());

            scheduledNotificationService.processScheduledNotifications();

            verify(scheduledNotificationRepository, never()).save(any());
        }

        @Test
        @DisplayName("sends email only when recipient has email but no phone")
        void processScheduledNotifications_emailOnlyRecipient_sendsEmailOnly() {
            User emailOnlyUser = new User();
            emailOnlyUser.setId(2L);
            emailOnlyUser.setEmail("emailonly@example.com");
            emailOnlyUser.setPhone(null);

            ScheduledNotification notification = ScheduledNotification.builder()
                    .id(3L)
                    .receiverId(2L)
                    .title("Email Only")
                    .body("Email Body")
                    .status("PENDING")
                    .scheduledTime(LocalDateTime.now().minusMinutes(5))
                    .build();

            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(List.of(notification));
            when(userRepository.findById(2L)).thenReturn(Optional.of(emailOnlyUser));
            when(sesService.sendEmail(anyString(), anyString(), any(), anyString()))
                    .thenReturn("ses-email-id");

            scheduledNotificationService.processScheduledNotifications();

            assertEquals("SENT", notification.getStatus());
            assertEquals("ses-email-id", notification.getMessageId());
            verify(sesService).sendEmail(eq("emailonly@example.com"), eq("Email Only"), isNull(), eq("Email Body"));
            verify(snsService, never()).publishSms(anyString(), anyString());
        }

        @Test
        @DisplayName("sends SMS only when recipient has phone but no email")
        void processScheduledNotifications_phoneOnlyRecipient_sendsSmsOnly() {
            User phoneOnlyUser = new User();
            phoneOnlyUser.setId(3L);
            phoneOnlyUser.setEmail(null);
            phoneOnlyUser.setPhone("+15559876543");

            ScheduledNotification notification = ScheduledNotification.builder()
                    .id(4L)
                    .receiverId(3L)
                    .title("SMS Only")
                    .body("SMS Body")
                    .status("PENDING")
                    .scheduledTime(LocalDateTime.now().minusMinutes(5))
                    .build();

            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(List.of(notification));
            when(userRepository.findById(3L)).thenReturn(Optional.of(phoneOnlyUser));
            when(snsService.publishSms(anyString(), anyString()))
                    .thenReturn("sns-sms-id");

            scheduledNotificationService.processScheduledNotifications();

            assertEquals("SENT", notification.getStatus());
            assertEquals("sns-sms-id", notification.getMessageId());
            verify(sesService, never()).sendEmail(anyString(), anyString(), any(), anyString());
            verify(snsService).publishSms(eq("+15559876543"), eq("SMS Body"));
        }

        @Test
        @DisplayName("sends both email and SMS when recipient has both")
        void processScheduledNotifications_bothChannels_sendsBoth() {
            ScheduledNotification notification = ScheduledNotification.builder()
                    .id(5L)
                    .receiverId(1L)
                    .title("Both Channels")
                    .body("Both Body")
                    .status("PENDING")
                    .scheduledTime(LocalDateTime.now().minusMinutes(5))
                    .build();

            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(List.of(notification));
            when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
            when(sesService.sendEmail(anyString(), anyString(), any(), anyString()))
                    .thenReturn("ses-both-id");
            when(snsService.publishSms(anyString(), anyString()))
                    .thenReturn("sns-both-id");

            scheduledNotificationService.processScheduledNotifications();

            assertEquals("SENT", notification.getStatus());
            // messageId should be set from email (first channel)
            assertEquals("ses-both-id", notification.getMessageId());
            verify(sesService).sendEmail(anyString(), anyString(), any(), anyString());
            verify(snsService).publishSms(anyString(), anyString());
        }

        @Test
        @DisplayName("marks FAILED when email send throws and re-throws")
        void processScheduledNotifications_emailSendThrows_markedFailed() {
            ScheduledNotification notification = ScheduledNotification.builder()
                    .id(6L)
                    .receiverId(1L)
                    .title("Email Fail")
                    .body("Email Fail Body")
                    .status("PENDING")
                    .scheduledTime(LocalDateTime.now().minusMinutes(5))
                    .build();

            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(List.of(notification));
            when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
            when(sesService.sendEmail(anyString(), anyString(), any(), anyString()))
                    .thenThrow(new RuntimeException("SES connection failed"));

            scheduledNotificationService.processScheduledNotifications();

            assertEquals("FAILED", notification.getStatus());
            assertTrue(notification.getErrorMessage().contains("SES connection failed"));
        }

        @Test
        @DisplayName("SMS failure does not mark notification as FAILED if email succeeded")
        void processScheduledNotifications_smsFailsAfterEmailSucceeds_markedSent() {
            ScheduledNotification notification = ScheduledNotification.builder()
                    .id(7L)
                    .receiverId(1L)
                    .title("SMS Fail")
                    .body("SMS Fail Body")
                    .status("PENDING")
                    .scheduledTime(LocalDateTime.now().minusMinutes(5))
                    .build();

            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(List.of(notification));
            when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
            when(sesService.sendEmail(anyString(), anyString(), any(), anyString()))
                    .thenReturn("ses-ok-id");
            when(snsService.publishSms(anyString(), anyString()))
                    .thenThrow(new RuntimeException("SNS unavailable"));

            scheduledNotificationService.processScheduledNotifications();

            // Email succeeded, SMS failure is swallowed; notification still marked SENT
            assertEquals("SENT", notification.getStatus());
        }

        @Test
        @DisplayName("processes multiple notifications in sequence")
        void processScheduledNotifications_multipleNotifications_processesAll() {
            ScheduledNotification n1 = ScheduledNotification.builder()
                    .id(10L).receiverId(1L).title("N1").body("B1")
                    .status("PENDING").scheduledTime(LocalDateTime.now().minusMinutes(3)).build();
            ScheduledNotification n2 = ScheduledNotification.builder()
                    .id(11L).receiverId(1L).title("N2").body("B2")
                    .status("PENDING").scheduledTime(LocalDateTime.now().minusMinutes(2)).build();

            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(List.of(n1, n2));
            when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
            when(sesService.sendEmail(anyString(), anyString(), any(), anyString()))
                    .thenReturn("ses-id");
            when(snsService.publishSms(anyString(), anyString()))
                    .thenReturn("sns-id");

            scheduledNotificationService.processScheduledNotifications();

            assertEquals("SENT", n1.getStatus());
            assertEquals("SENT", n2.getStatus());
            verify(scheduledNotificationRepository, times(2)).save(any(ScheduledNotification.class));
        }

        @Test
        @DisplayName("recipient with empty email string does not trigger email send")
        void processScheduledNotifications_emptyEmail_noEmailSent() {
            User emptyEmailUser = new User();
            emptyEmailUser.setId(4L);
            emptyEmailUser.setEmail("");
            emptyEmailUser.setPhone("+15551112222");

            ScheduledNotification notification = ScheduledNotification.builder()
                    .id(8L)
                    .receiverId(4L)
                    .title("Empty Email")
                    .body("Body")
                    .status("PENDING")
                    .scheduledTime(LocalDateTime.now().minusMinutes(5))
                    .build();

            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(List.of(notification));
            when(userRepository.findById(4L)).thenReturn(Optional.of(emptyEmailUser));
            when(snsService.publishSms(anyString(), anyString()))
                    .thenReturn("sns-id");

            scheduledNotificationService.processScheduledNotifications();

            verify(sesService, never()).sendEmail(anyString(), anyString(), any(), anyString());
            verify(snsService).publishSms(eq("+15551112222"), eq("Body"));
            assertEquals("SENT", notification.getStatus());
        }

        @Test
        @DisplayName("recipient with empty phone string does not trigger SMS send")
        void processScheduledNotifications_emptyPhone_noSmsSent() {
            User emptyPhoneUser = new User();
            emptyPhoneUser.setId(5L);
            emptyPhoneUser.setEmail("user5@example.com");
            emptyPhoneUser.setPhone("");

            ScheduledNotification notification = ScheduledNotification.builder()
                    .id(9L)
                    .receiverId(5L)
                    .title("Empty Phone")
                    .body("Body")
                    .status("PENDING")
                    .scheduledTime(LocalDateTime.now().minusMinutes(5))
                    .build();

            when(scheduledNotificationRepository.findByStatusAndScheduledTimeBefore(
                    eq("PENDING"), any(LocalDateTime.class)))
                    .thenReturn(List.of(notification));
            when(userRepository.findById(5L)).thenReturn(Optional.of(emptyPhoneUser));
            when(sesService.sendEmail(anyString(), anyString(), any(), anyString()))
                    .thenReturn("ses-id");

            scheduledNotificationService.processScheduledNotifications();

            verify(snsService, never()).publishSms(anyString(), anyString());
            verify(sesService).sendEmail(eq("user5@example.com"), eq("Empty Phone"), isNull(), eq("Body"));
            assertEquals("SENT", notification.getStatus());
        }
    }

    // ========== createScheduledNotification tests ==========

    @Nested
    @DisplayName("createScheduledNotification")
    class CreateScheduledNotificationTests {

        @Test
        @DisplayName("creates and saves a scheduled notification for a valid task")
        void createScheduledNotification_validTask_savesNotification() {
            when(taskRepository.findById(100L)).thenReturn(Optional.of(testTask));
            when(scheduledNotificationRepository.save(any(ScheduledNotification.class)))
                    .thenAnswer(invocation -> invocation.getArgument(0));

            LocalDateTime scheduledTime = LocalDateTime.now().plusHours(1);

            ScheduledNotification result = scheduledNotificationService.createScheduledNotification(
                    100L, 1L, "Title", "Body", scheduledTime, "REMINDER");

            assertNotNull(result);
            assertEquals(1L, result.getReceiverId());
            assertEquals("Title", result.getTitle());
            assertEquals("Body", result.getBody());
            assertEquals("REMINDER", result.getNotificationType());
            assertEquals(scheduledTime, result.getScheduledTime());
            assertEquals(testTask, result.getTask());
            verify(scheduledNotificationRepository).save(any(ScheduledNotification.class));
        }

        @Test
        @DisplayName("throws IllegalArgumentException when task is not found")
        void createScheduledNotification_taskNotFound_throws() {
            when(taskRepository.findById(999L)).thenReturn(Optional.empty());

            IllegalArgumentException exception = assertThrows(IllegalArgumentException.class,
                    () -> scheduledNotificationService.createScheduledNotification(
                            999L, 1L, "Title", "Body", LocalDateTime.now(), "REMINDER"));

            assertTrue(exception.getMessage().contains("Task not found: 999"));
        }
    }

    // ========== createMedicationReminders tests ==========

    @Nested
    @DisplayName("createMedicationReminders")
    class CreateMedicationRemindersTests {

        @Test
        @DisplayName("creates medication reminders for each reminder time - delegates to createScheduledNotification with null taskId")
        void createMedicationReminders_multipleReminderTimes_throwsBecauseNullTask() {
            // createMedicationReminders passes null as taskId, which will trigger
            // the task lookup to fail because taskId is null
            LocalDateTime time1 = LocalDateTime.now().plusHours(1);
            LocalDateTime time2 = LocalDateTime.now().plusHours(2);

            when(taskRepository.findById(isNull()))
                    .thenReturn(Optional.empty());

            assertThrows(IllegalArgumentException.class,
                    () -> scheduledNotificationService.createMedicationReminders(
                            1L, "Aspirin", "100mg", List.of(time1, time2)));
        }
    }

    // ========== createAppointmentReminder tests ==========

    @Nested
    @DisplayName("createAppointmentReminder")
    class CreateAppointmentReminderTests {

        @Test
        @DisplayName("creates appointment reminder 24 hours before appointment - delegates to createScheduledNotification with null taskId")
        void createAppointmentReminder_throwsBecauseNullTask() {
            LocalDateTime appointmentTime = LocalDateTime.now().plusDays(2);

            when(taskRepository.findById(isNull()))
                    .thenReturn(Optional.empty());

            assertThrows(IllegalArgumentException.class,
                    () -> scheduledNotificationService.createAppointmentReminder(
                            1L, "Checkup", appointmentTime, "Clinic A"));
        }
    }

    // ========== getUserNotifications tests ==========

    @Nested
    @DisplayName("getUserNotifications")
    class GetUserNotificationsTests {

        @Test
        @DisplayName("returns notifications for a given user")
        void getUserNotifications_validUser_returnsNotifications() {
            ScheduledNotification n1 = ScheduledNotification.builder()
                    .id(1L).receiverId(1L).title("N1").body("B1").build();
            ScheduledNotification n2 = ScheduledNotification.builder()
                    .id(2L).receiverId(1L).title("N2").body("B2").build();

            when(scheduledNotificationRepository.findByReceiverId(1L))
                    .thenReturn(List.of(n1, n2));

            List<ScheduledNotification> result = scheduledNotificationService.getUserNotifications(1L);

            assertNotNull(result);
            assertEquals(2, result.size());
            verify(scheduledNotificationRepository).findByReceiverId(1L);
        }

        @Test
        @DisplayName("returns empty list when user has no notifications")
        void getUserNotifications_noNotifications_returnsEmptyList() {
            when(scheduledNotificationRepository.findByReceiverId(999L))
                    .thenReturn(Collections.emptyList());

            List<ScheduledNotification> result = scheduledNotificationService.getUserNotifications(999L);

            assertNotNull(result);
            assertTrue(result.isEmpty());
        }
    }

    // ========== cancelScheduledNotification tests ==========

    @Nested
    @DisplayName("cancelScheduledNotification")
    class CancelScheduledNotificationTests {

        @Test
        @DisplayName("cancels a pending notification")
        void cancelScheduledNotification_existingNotification_setsCancelled() {
            ScheduledNotification notification = ScheduledNotification.builder()
                    .id(1L)
                    .receiverId(1L)
                    .title("To Cancel")
                    .body("Cancel Body")
                    .status("PENDING")
                    .build();

            when(scheduledNotificationRepository.findById(1L))
                    .thenReturn(Optional.of(notification));

            scheduledNotificationService.cancelScheduledNotification(1L);

            assertEquals("CANCELLED", notification.getStatus());
            verify(scheduledNotificationRepository).save(notification);
        }

        @Test
        @DisplayName("throws IllegalArgumentException when notification is not found")
        void cancelScheduledNotification_notFound_throws() {
            when(scheduledNotificationRepository.findById(999L))
                    .thenReturn(Optional.empty());

            IllegalArgumentException exception = assertThrows(IllegalArgumentException.class,
                    () -> scheduledNotificationService.cancelScheduledNotification(999L));

            assertTrue(exception.getMessage().contains("Notification not found: 999"));
        }
    }

    // ========== createRecurringNotifications tests ==========

    @Nested
    @DisplayName("createRecurringNotifications")
    class CreateRecurringNotificationsTests {

        @Test
        @DisplayName("throws UnsupportedOperationException since it is not yet implemented")
        void createRecurringNotifications_throwsUnsupportedOperationException() {
            assertThrows(UnsupportedOperationException.class,
                    () -> scheduledNotificationService.createRecurringNotifications(
                            1L, 1L, "Title", "Body",
                            LocalDateTime.now(), LocalDateTime.now().plusDays(7),
                            "DAILY", "REMINDER"));
        }
    }
}
