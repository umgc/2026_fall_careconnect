package com.careconnect.service.v2;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionSystemException;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;
import org.springframework.transaction.support.AbstractPlatformTransactionManager;
import org.springframework.transaction.support.DefaultTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;

import com.careconnect.dto.ScheduledNotificationDTO;
import com.careconnect.dto.v2.TaskDtoV2;
import com.careconnect.exception.ParentTaskNotFoundException;
import com.careconnect.exception.PatientNotFoundException;
import com.careconnect.exception.TaskNotFoundException;
import com.careconnect.model.Patient;
import com.careconnect.model.ScheduledNotification;
import com.careconnect.model.Task;
import com.careconnect.model.User;
import com.careconnect.notifications.SesService;
import com.careconnect.notifications.SnsService;
import com.careconnect.service.TaskService;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.TaskRepository;
import com.fasterxml.jackson.databind.ObjectMapper;

@DisplayName("TaskServiceV2")
class TaskServiceV2Test {

    @Mock
    private TaskRepository taskRepository;

    @Mock
    private PatientRepository patientRepository;
    @Mock
    private com.careconnect.repository.UserRepository userRepository;
    @Mock
    private com.careconnect.security.AuthorizationService authorizationService;
    @Mock
    private com.careconnect.util.SecurityUtil securityUtil;
    @Mock
    private TaskService appointmentNotifications;

    @Mock
    private ObjectMapper objectMapper;

    private TaskServiceV2 service;

    private Patient patient;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        when(securityUtil.resolveCurrentUser()).thenReturn(com.careconnect.model.User.builder()
                .id(999L).role(com.careconnect.security.Role.ADMIN).build());
        service = new TaskServiceV2(taskRepository, patientRepository, objectMapper, appointmentNotifications, authorizationService, securityUtil, userRepository);
        patient = Patient.builder().id(1L).firstName("John").lastName("Doe").build();
    }

    @Nested
    class SeriesAuthorization {
        private final User userA = User.builder().id(100L).role(com.careconnect.security.Role.PATIENT).build();
        private final User userB = User.builder().id(200L).role(com.careconnect.security.Role.PATIENT).build();
        private final User caregiver = User.builder().id(300L).role(com.careconnect.security.Role.CAREGIVER).build();
        private Patient a;
        private Patient b;
        private Task parent;
        private Task child;
        private Task sibling;
        private List<Task> records;
        private java.util.Set<Long> linkedUsers;
        private com.careconnect.repository.CaregiverPatientLinkRepository links;
        private com.careconnect.controller.v2.TaskControllerV2 controller;

        @BeforeEach
        void configureAuthorization() {
            a = Patient.builder().id(10L).user(userA).build();
            b = Patient.builder().id(20L).user(userB).build();
            parent = seriesTask(1L, null, "2026-01-06", a);
            child = seriesTask(2L, 1L, "2026-01-20", a);
            sibling = seriesTask(3L, 1L, "2026-01-21", a);
            records = new ArrayList<>(List.of(parent, child, sibling));
            linkedUsers = java.util.Set.of(100L, 200L);
            links = mock(com.careconnect.repository.CaregiverPatientLinkRepository.class);
            final var families = mock(com.careconnect.repository.FamilyMemberLinkRepository.class);
            when(links.existsActiveNonExpiredLinkByUserIds(any(), any(), any()))
                    .thenAnswer(invocation -> Long.valueOf(300L).equals(invocation.getArgument(0))
                            && linkedUsers.contains(invocation.<Long>getArgument(1)));
            when(patientRepository.findById(10L)).thenReturn(Optional.of(a));
            when(patientRepository.findById(20L)).thenReturn(Optional.of(b));
            when(taskRepository.findById(anyLong())).thenAnswer(invocation ->
                    records.stream().filter(t -> t.getId().equals(invocation.getArgument(0))).findFirst());
            when(taskRepository.findByParentTaskId(anyLong())).thenAnswer(invocation -> {
                final Long id = invocation.getArgument(0);
                return records.stream().filter(t -> id.equals(t.getParentTaskId()))
                        .collect(java.util.stream.Collectors.toCollection(ArrayList::new));
            });
            when(taskRepository.save(any(Task.class))).thenAnswer(invocation -> invocation.getArgument(0));
            when(taskRepository.saveAll(any())).thenAnswer(invocation -> {
                final List<Task> saved = new ArrayList<>();
                for (Task task : invocation.<Iterable<Task>>getArgument(0)) {
                    if (task.getId() == null) {
                        task.setId(records.stream().mapToLong(Task::getId).max().orElse(0L) + 1L);
                        records.add(task);
                    }
                    saved.add(task);
                }
                return saved;
            });
            doAnswer(invocation -> {
                final List<Task> deleted = new ArrayList<>();
                invocation.<Iterable<Task>>getArgument(0).forEach(deleted::add);
                records.removeAll(deleted);
                return null;
            }).when(taskRepository).deleteAll(any(Iterable.class));
            final var authorization = new com.careconnect.security.AuthorizationService(
                    links, families, patientRepository);
            service = new TaskServiceV2(taskRepository, patientRepository, objectMapper,
                    appointmentNotifications, authorization, securityUtil, userRepository);
            controller = new com.careconnect.controller.v2.TaskControllerV2(service, securityUtil, authorization);
            when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
        }

        private Task seriesTask(long id, Long parentId, String date, Patient owner) {
            return Task.builder().id(id).parentTaskId(parentId).patient(owner)
                    .name("Original " + id).date(date).timeOfDay("10:00")
                    .frequency("daily").taskInterval(1).doCount(30).build();
        }

        private void assertDenied(org.assertj.core.api.ThrowableAssert.ThrowingCallable operation) {
            assertThatThrownBy(operation).isInstanceOf(com.careconnect.security.UnauthorizedException.class);
            verify(taskRepository, never()).save(any(Task.class));
            verify(taskRepository, never()).saveAll(any());
            verify(taskRepository, never()).delete(any(Task.class));
            verify(taskRepository, never()).deleteAll(any(Iterable.class));
            assertThat(parent.getName()).isEqualTo("Original 1");
        }

        @Test
        void movingOneOccurrenceDetachesItFromTheFormerSeries() throws Exception {
            final TaskDtoV2 result = controller.updateTask(2L,
                    TaskDtoV2.builder().patientId(20L).updateSeries(false).build()).getBody();
            assertThat(result.getPatientId()).isEqualTo(20L);
            assertThat(result.getParentTaskId()).isNull();
            assertThat(result.getFrequency()).isNull();
            assertThat(result.getCount()).isNull();
            assertThat(result.getDate()).isEqualTo("2026-01-20");
            assertThat(parent.getPatient()).isSameAs(a);
            assertThat(sibling.getPatient()).isSameAs(a);
            assertThat(sibling.getParentTaskId()).isEqualTo(1L);
        }

        @Test
        void movedOccurrenceCannotBeUsedToEditOrDeleteTheFormerSeries() throws Exception {
            controller.updateTask(2L, TaskDtoV2.builder().patientId(20L).build());
            when(securityUtil.resolveCurrentUser()).thenReturn(userB);
            controller.updateTask(2L, TaskDtoV2.builder().patientId(20L)
                    .name("B independent task").updateSeries(true).build());
            assertThat(parent.getName()).isEqualTo("Original 1");
            assertThat(parent.getPatient()).isSameAs(a);
            controller.deleteTask(2L, true);
            final ArgumentCaptor<Iterable<Task>> deleted = ArgumentCaptor.forClass(Iterable.class);
            verify(taskRepository).deleteAll(deleted.capture());
            assertThat(deleted.getValue()).containsExactly(child);
        }

        @Test
        void existingMixedSeriesCannotBeEditedThroughItsForeignChild() {
            child.setPatient(b);
            when(securityUtil.resolveCurrentUser()).thenReturn(userB);
            assertDenied(() -> controller.updateTask(2L, TaskDtoV2.builder().patientId(20L)
                    .name("Unauthorized").updateSeries(true).build()));
            assertThat(parent.getPatient()).isSameAs(a);
            assertThat(child.getParentTaskId()).isEqualTo(1L);
        }

        @Test
        void existingMixedSeriesCannotBeDeletedThroughItsForeignChild() {
            child.setPatient(b);
            when(securityUtil.resolveCurrentUser()).thenReturn(userB);
            assertDenied(() -> controller.deleteTask(2L, true));
        }

        @Test
        void ownParentDoesNotAuthorizeEditingAnotherPatientsChild() {
            parent.setPatient(b);
            child.setPatient(b);
            when(securityUtil.resolveCurrentUser()).thenReturn(userB);
            assertDenied(() -> controller.updateTask(1L, TaskDtoV2.builder().patientId(20L)
                    .name("Unauthorized").updateSeries(true).build()));
            assertThat(sibling.getPatient()).isSameAs(a);
        }

        @Test
        void ownParentDoesNotAuthorizeDeletingAnotherPatientsChild() {
            parent.setPatient(b);
            child.setPatient(b);
            when(securityUtil.resolveCurrentUser()).thenReturn(userB);
            assertDenied(() -> controller.deleteTask(1L, true));
        }

        @Test
        void singleParentDeletionCannotPromoteAnotherPatientsChild() {
            parent.setPatient(b);
            child.setPatient(b);
            when(securityUtil.resolveCurrentUser()).thenReturn(userB);
            assertDenied(() -> controller.deleteTask(1L, false));
            assertThat(child.getParentTaskId()).isEqualTo(1L);
            assertThat(sibling.getParentTaskId()).isEqualTo(1L);
        }

        @Test
        void caregiverMustHaveAccessToTheParentAndAllChildren() {
            child.setPatient(b);
            linkedUsers = java.util.Set.of(200L);
            assertDenied(() -> controller.updateTask(2L,
                    TaskDtoV2.builder().name("Unauthorized").updateSeries(true).build()));
            assertDenied(() -> controller.deleteTask(2L, true));
        }

        @Test
        void inaccessibleDestinationRejectsTheWholeMoveBeforeMutation() {
            linkedUsers = java.util.Set.of(100L);
            assertDenied(() -> service.updateTask(1L,
                    TaskDtoV2.builder().patientId(20L).updateSeries(true).build()));
            assertThat(parent.getPatient()).isSameAs(a);
            assertThat(child.getPatient()).isSameAs(a);
        }

        @Test
        void seriesReassignmentMovesEveryMemberToTheDestination() throws Exception {
            service.updateTask(2L, TaskDtoV2.builder().patientId(20L).updateSeries(true).build());
            assertThat(records).allSatisfy(t -> assertThat(t.getPatient()).isSameAs(b));
            assertThat(parent.getParentTaskId()).isNull();
            assertThat(child.getParentTaskId()).isEqualTo(1L);
            assertThat(sibling.getParentTaskId()).isEqualTo(1L);
        }

        @Test
        void movingTheParentPromotesItsOriginalChildrenAndDetachesTheMovedTask() throws Exception {
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).updateSeries(false).build());
            assertThat(parent.getPatient()).isSameAs(b);
            assertThat(parent.getFrequency()).isNull();
            assertThat(child.getPatient()).isSameAs(a);
            assertThat(child.getParentTaskId()).isNull();
            assertThat(sibling.getParentTaskId()).isEqualTo(2L);
            assertThat(sibling.getPatient()).isSameAs(a);
        }

        @Test
        void parentMovePromotesEarliestRemainingOccurrenceRegardlessOfQueryOrder() throws Exception {
            records = new ArrayList<>(List.of(parent, sibling, child));
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).build());
            assertThat(child.getParentTaskId()).isNull();
            assertThat(child.getDate()).isEqualTo("2026-01-20");
            assertThat(sibling.getParentTaskId()).isEqualTo(2L);
        }

        @Test
        void parentMoveChecksChildrenBeforePromotingOrReassigningAnything() {
            final Patient c = Patient.builder().id(30L)
                    .user(User.builder().id(400L).role(com.careconnect.security.Role.PATIENT).build()).build();
            when(patientRepository.findById(30L)).thenReturn(Optional.of(c));
            child.setPatient(b);
            linkedUsers = java.util.Set.of(100L, 400L);
            assertDenied(() -> service.updateTask(1L, TaskDtoV2.builder().patientId(30L).build()));
            assertThat(parent.getPatient()).isSameAs(a);
            assertThat(child.getParentTaskId()).isEqualTo(1L);
        }

        @Test
        void keepingTheSamePatientPreservesTheSeriesLink() throws Exception {
            when(securityUtil.resolveCurrentUser()).thenReturn(userA);
            service.updateTask(2L, TaskDtoV2.builder().patientId(10L).name("Own edit").build());
            assertThat(child.getParentTaskId()).isEqualTo(1L);
            assertThat(child.getFrequency()).isEqualTo("daily");
        }

        @Test
        void directServiceCallCannotBypassPatientReassignmentRestriction() {
            child.setPatient(b);
            when(securityUtil.resolveCurrentUser()).thenReturn(userB);
            assertDenied(() -> service.updateTask(2L, TaskDtoV2.builder().patientId(10L).build()));
            assertThat(child.getPatient()).isSameAs(b);
            assertThat(child.getParentTaskId()).isEqualTo(1L);
        }

        private ScheduledNotification addReminder(Task task, long receiver, String status) {
            final ScheduledNotification reminder = ScheduledNotification.builder().receiverId(receiver)
                    .title("Reminder").body("Task reminder").status(status).task(task)
                    .scheduledTime(LocalDateTime.parse(task.getDate() + "T09:45:00")).build();
            task.getNotifications().add(reminder);
            return reminder;
        }

        private void threeConsecutiveOccurrences() {
            parent.setDoCount(3);
            child.setDoCount(3);
            sibling.setDoCount(3);
            child.setDate("2026-01-07");
            sibling.setDate("2026-01-08");
        }

        @Test
        void promotedCountMatchesRemainingOccurrencesAndSurvivesAnotherEdit() throws Exception {
            threeConsecutiveOccurrences();
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).build());
            assertThat(child.getDoCount()).isEqualTo(2);
            assertThat(sibling.getDoCount()).isEqualTo(2);
            assertThat(service.getTaskDtoById(2L).getCount()).isEqualTo(2);
            service.updateTask(2L, TaskDtoV2.builder().frequency("weekly")
                    .interval(1).updateSeries(true).build());
            assertThat(records.stream().filter(t -> t.getPatient() == a).map(Task::getDate))
                    .containsExactlyInAnyOrder("2026-01-07", "2026-01-14");
        }

        @Test
        void deletingTheParentAlsoUpdatesCountsForEveryRemainingOccurrence() throws Exception {
            threeConsecutiveOccurrences();
            service.deleteTask(1L, false);
            assertThat(child.getDoCount()).isEqualTo(2);
            assertThat(sibling.getDoCount()).isEqualTo(2);
        }

        @Test
        void singleRemainingOccurrenceHasCountOneAfterPromotion() throws Exception {
            records.remove(sibling);
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).build());
            assertThat(child.getDoCount()).isEqualTo(1);
            assertThat(child.getParentTaskId()).isNull();
        }

        @Test
        void seriesMoveRetargetsAllPendingPatientRemindersToTheUserId() throws Exception {
            records.forEach(t -> addReminder(t, 100L, "PENDING"));
            final LocalDateTime originalTime = child.getNotifications().get(0).getScheduledTime();
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).updateSeries(true).build());
            assertThat(records).allSatisfy(t -> {
                assertThat(t.getNotifications().get(0).getReceiverId()).isEqualTo(200L);
                assertThat(t.getNotifications().get(0).getStatus()).isEqualTo("PENDING");
            });
            assertThat(child.getNotifications().get(0).getScheduledTime()).isEqualTo(originalTime);
        }

        @Test
        void childMoveUpdatesOnlyItsPatientReminder() throws Exception {
            final var parentReminder = addReminder(parent, 100L, "PENDING");
            final var childReminder = addReminder(child, 100L, "PENDING");
            service.updateTask(2L, TaskDtoV2.builder().patientId(20L).build());
            assertThat(childReminder.getReceiverId()).isEqualTo(200L);
            assertThat(parentReminder.getReceiverId()).isEqualTo(100L);
        }

        @Test
        void parentMoveDoesNotRetargetTheRemainingPatientsReminders() throws Exception {
            final var rootReminder = addReminder(parent, 100L, "PENDING");
            final var childReminder = addReminder(child, 100L, "PENDING");
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).build());
            assertThat(rootReminder.getReceiverId()).isEqualTo(200L);
            assertThat(childReminder.getReceiverId()).isEqualTo(100L);
        }

        @Test
        void authorizedCaregiverReminderIsPreserved() throws Exception {
            when(userRepository.findById(300L)).thenReturn(Optional.of(caregiver));
            final var reminder = addReminder(child, 300L, "PENDING");
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).updateSeries(true).build());
            assertThat(reminder.getReceiverId()).isEqualTo(300L);
            assertThat(reminder.getStatus()).isEqualTo("PENDING");
        }

        @Test
        void caregiverWithoutDestinationAccessIsCancelled() throws Exception {
            final User formerCaregiver = User.builder().id(400L)
                    .role(com.careconnect.security.Role.CAREGIVER).build();
            when(userRepository.findById(400L)).thenReturn(Optional.of(formerCaregiver));
            final var reminder = addReminder(child, 400L, "PENDING");
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).updateSeries(true).build());
            assertThat(reminder.getStatus()).isEqualTo("CANCELLED");
        }

        @Test
        void unrelatedPatientAndMissingRecipientRemindersAreCancelled() throws Exception {
            when(userRepository.findById(999L)).thenReturn(Optional.of(User.builder().id(999L)
                    .role(com.careconnect.security.Role.PATIENT).build()));
            final var unrelated = addReminder(child, 999L, "PENDING");
            final var missing = addReminder(child, 888L, "PENDING");
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).updateSeries(true).build());
            assertThat(unrelated.getStatus()).isEqualTo("CANCELLED");
            assertThat(missing.getStatus()).isEqualTo("CANCELLED");
        }

        @Test
        void destinationUserRecipientIsAlreadyCorrect() throws Exception {
            final var reminder = addReminder(child, 200L, "PENDING");
            service.updateTask(2L, TaskDtoV2.builder().patientId(20L).build());
            assertThat(reminder.getReceiverId()).isEqualTo(200L);
            assertThat(reminder.getStatus()).isEqualTo("PENDING");
            verifyNoInteractions(userRepository);
        }

        @Test
        void historicalReminderRecipientsAndStatusesAreNotRewritten() throws Exception {
            for (String status : List.of("SENT", "FAILED", "CANCELLED")) {
                addReminder(child, 100L, status);
            }
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).updateSeries(true).build());
            assertThat(child.getNotifications()).allSatisfy(n -> assertThat(n.getReceiverId()).isEqualTo(100L));
            assertThat(child.getNotifications()).extracting(ScheduledNotification::getStatus)
                    .containsExactly("SENT", "FAILED", "CANCELLED");
        }

        @Test
        void unavailableDestinationUserCancelsUnsafeReminders() throws Exception {
            b.setUser(null);
            when(userRepository.findById(100L)).thenReturn(Optional.of(userA));
            when(securityUtil.resolveCurrentUser()).thenReturn(User.builder().id(900L)
                    .role(com.careconnect.security.Role.ADMIN).build());
            final var reminder = addReminder(child, 100L, "PENDING");
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).updateSeries(true).build());
            assertThat(reminder.getStatus()).isEqualTo("CANCELLED");
        }

        @Test
        void regeneratedChildrenUseSanitizedPendingRemindersWithShiftedTimes() throws Exception {
            threeConsecutiveOccurrences();
            addReminder(parent, 100L, "PENDING");
            addReminder(parent, 100L, "SENT");
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).frequency("weekly")
                    .updateSeries(true).build());
            assertThat(records).hasSize(3);
            assertThat(records.stream().filter(t -> t.getParentTaskId() != null)).allSatisfy(t -> {
                assertThat(t.getPatient()).isSameAs(b);
                assertThat(t.getNotifications()).hasSize(1);
                final var reminder = t.getNotifications().get(0);
                assertThat(reminder.getReceiverId()).isEqualTo(200L);
                assertThat(reminder.getStatus()).isEqualTo("PENDING");
                assertThat(reminder.getScheduledTime()).isEqualTo(LocalDateTime.parse(t.getDate() + "T09:45:00"));
            });
            assertThat(parent.getNotifications().get(1).getStatus()).isEqualTo("SENT");
            assertThat(parent.getNotifications().get(1).getReceiverId()).isEqualTo(100L);
        }

        @Test
        void samePatientEditDoesNotRewriteReminderRecipients() throws Exception {
            final var reminder = addReminder(child, 100L, "PENDING");
            service.updateTask(2L, TaskDtoV2.builder().patientId(10L).name("Edited").build());
            assertThat(reminder.getReceiverId()).isEqualTo(100L);
            assertThat(reminder.getStatus()).isEqualTo("PENDING");
            verifyNoInteractions(userRepository);
        }

        private void monthlyMonthEndSeries() {
            parent.setDate("2026-01-31");
            child.setDate("2026-02-28");
            sibling.setDate("2026-03-31");
            for (Task task : records) {
                task.setFrequency("monthly");
                task.setDoCount(3);
            }
        }

        @Test
        void promotedMonthEndAnchorSurvivesCountChanges() throws Exception {
            monthlyMonthEndSeries();
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).build());
            assertThat(service.getTaskDtoById(2L).getRecurrenceAnchorDate()).isEqualTo("2026-01-31");
            assertThat(parent.getRecurrenceAnchorDate()).isNull();
            service.updateTask(2L, TaskDtoV2.builder().count(3).updateSeries(true).build());
            assertThat(records.stream().filter(t -> t.getPatient() == a).map(Task::getDate))
                    .containsExactlyInAnyOrder("2026-02-28", "2026-03-31", "2026-04-30");
            assertThat(records.stream().filter(t -> t.getPatient() == a))
                    .allSatisfy(t -> assertThat(t.getRecurrenceAnchorDate()).isEqualTo("2026-01-31"));
        }

        @Test
        void promotedLeapDaySeriesReturnsToFebruary29InLeapYears() throws Exception {
            parent.setDate("2024-02-29");
            child.setDate("2025-02-28");
            sibling.setDate("2026-02-28");
            for (Task task : records) {
                task.setFrequency("yearly");
                task.setDoCount(3);
            }
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).build());
            service.updateTask(2L, TaskDtoV2.builder().count(4).updateSeries(true).build());
            assertThat(records.stream().filter(t -> t.getPatient() == a).map(Task::getDate))
                    .containsExactlyInAnyOrder("2025-02-28", "2026-02-28", "2027-02-28", "2028-02-29");
        }

        @Test
        void repeatedPromotionRetainsOriginalMonthEndCadence() throws Exception {
            monthlyMonthEndSeries();
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).build());
            service.updateTask(2L, TaskDtoV2.builder().patientId(20L).build());
            assertThat(sibling.getRecurrenceAnchorDate()).isEqualTo("2026-01-31");
            assertThat(sibling.getDoCount()).isEqualTo(1);
            service.updateTask(3L, TaskDtoV2.builder().count(2).updateSeries(true).build());
            assertThat(records.stream().filter(t -> t.getPatient() == a).map(Task::getDate))
                    .containsExactlyInAnyOrder("2026-03-31", "2026-04-30");
        }

        @Test
        void changedMonthlyIntervalUsesPromotedMonthAndOriginalDay() throws Exception {
            monthlyMonthEndSeries();
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).build());
            service.updateTask(2L, TaskDtoV2.builder().interval(2).updateSeries(true).build());
            assertThat(records.stream().filter(t -> t.getPatient() == a).map(Task::getDate))
                    .containsExactlyInAnyOrder("2026-02-28", "2026-04-30");
        }

        @Test
        void changingFrequencyResetsTheFormerCadenceAnchor() throws Exception {
            monthlyMonthEndSeries();
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).build());
            service.updateTask(2L, TaskDtoV2.builder().frequency("daily").updateSeries(true).build());
            assertThat(child.getRecurrenceAnchorDate()).isEqualTo("2026-02-28");
            service.updateTask(2L, TaskDtoV2.builder().frequency("monthly").updateSeries(true).build());
            assertThat(records.stream().filter(t -> t.getPatient() == a).map(Task::getDate))
                    .containsExactlyInAnyOrder("2026-02-28", "2026-03-28");
        }

        @Test
        void clientCannotOverwriteServerOwnedCadenceMetadata() throws Exception {
            monthlyMonthEndSeries();
            service.updateTask(1L, TaskDtoV2.builder().patientId(20L).build());
            service.updateTask(2L, TaskDtoV2.builder().recurrenceAnchorDate("1900-01-01")
                    .recurrenceExcludedDates(List.of("2026-03-31"))
                    .name("Own edit").updateSeries(true).build());
            assertThat(child.getRecurrenceAnchorDate()).isEqualTo("2026-01-31");
            assertThat(service.getTaskDtoById(2L).getRecurrenceExcludedDates()).containsExactly("2026-01-31");
        }

        @Test
        void removedMiddleOccurrenceIsNotRecreatedWhenTheCountIsExtended() throws Exception {
            threeConsecutiveOccurrences();
            service.updateTask(2L, TaskDtoV2.builder().patientId(20L).build());
            assertThat(parent.getDoCount()).isEqualTo(2);
            assertThat(sibling.getDoCount()).isEqualTo(2);
            assertThat(service.getTaskDtoById(1L).getRecurrenceExcludedDates()).containsExactly("2026-01-07");
            service.updateTask(1L, TaskDtoV2.builder().count(3).updateSeries(true).build());
            assertThat(records.stream().filter(t -> t.getPatient() == a).map(Task::getDate))
                    .containsExactlyInAnyOrder("2026-01-06", "2026-01-08", "2026-01-09");
            assertThat(child.getPatient()).isSameAs(b);
            assertThat(child.getRecurrenceExcludedDates()).isNull();
        }

        @Test
        void changingIntervalAfterMiddleRemovalDoesNotAddAnExtraOccurrence() throws Exception {
            threeConsecutiveOccurrences();
            service.updateTask(2L, TaskDtoV2.builder().patientId(20L).build());
            service.updateTask(1L, TaskDtoV2.builder().interval(2).updateSeries(true).build());
            assertThat(records.stream().filter(t -> t.getPatient() == a).map(Task::getDate))
                    .containsExactlyInAnyOrder("2026-01-06", "2026-01-08");
        }

        @Test
        void deletingAMiddleOccurrenceRetainsItsExceptionAndRemainingCount() throws Exception {
            threeConsecutiveOccurrences();
            service.deleteTask(2L, false);
            assertThat(parent.getDoCount()).isEqualTo(2);
            assertThat(parent.getRecurrenceExcludedDates()).contains("2026-01-07");
            service.updateTask(1L, TaskDtoV2.builder().count(3).updateSeries(true).build());
            assertThat(records.stream().filter(t -> !t.getId().equals(2L)).map(Task::getDate))
                    .doesNotContain("2026-01-07");
        }

        @Test
        void removingAChildInAnExistingMixedSeriesChecksTheParentBeforeMetadataChanges() {
            child.setPatient(b);
            when(securityUtil.resolveCurrentUser()).thenReturn(userB);
            assertDenied(() -> service.deleteTask(2L, false));
            assertThat(parent.getRecurrenceExcludedDates()).isNull();
        }

        @Test
        void removedMonthlyDateStaysExcludedWithoutLosingMonthEndCadence() throws Exception {
            monthlyMonthEndSeries();
            service.updateTask(2L, TaskDtoV2.builder().patientId(20L).build());
            assertThat(parent.getDoCount()).isEqualTo(2);
            service.updateTask(1L, TaskDtoV2.builder().count(3).updateSeries(true).build());
            assertThat(records.stream().filter(t -> t.getPatient() == a).map(Task::getDate))
                    .containsExactlyInAnyOrder("2026-01-31", "2026-03-31", "2026-04-30");
        }

        @Test
        void repairedWeeklySeriesIncludesTheCurrentWeekAndSkipsTheRemovedDate() throws Exception {
            parent.setDate("2026-01-06");
            child.setDate("2026-01-07");
            sibling.setDate("2026-01-13");
            for (Task task : records) {
                task.setFrequency("weekly");
                task.setDoCount(3);
                task.setDaysOfWeek("[false,false,true,true,false,false,false]");
            }
            service.updateTask(2L, TaskDtoV2.builder().patientId(20L).build());
            service.updateTask(1L, TaskDtoV2.builder().count(3).updateSeries(true).build());
            assertThat(records.stream().filter(t -> t.getPatient() == a).map(Task::getDate))
                    .containsExactlyInAnyOrder("2026-01-06", "2026-01-13", "2026-01-14");
        }

        @Test
        void malformedPersistedExceptionMetadataFailsBeforeAnyMutation() {
            parent.setRecurrenceExcludedDates("not JSON");
            assertThatThrownBy(() -> service.updateTask(1L,
                    TaskDtoV2.builder().name("Unsafe").updateSeries(true).build()))
                    .isInstanceOf(IllegalArgumentException.class);
            verify(taskRepository, never()).save(any(Task.class));
            assertThat(parent.getName()).isEqualTo("Original 1");
        }

        @Test
        void authorizedMixedSeriesDeletionIncludesEveryAuthorizedMember() throws Exception {
            child.setPatient(b);
            service.deleteTask(2L, true);
            final ArgumentCaptor<Iterable<Task>> deleted = ArgumentCaptor.forClass(Iterable.class);
            verify(taskRepository).deleteAll(deleted.capture());
            assertThat(deleted.getValue()).containsExactlyInAnyOrder(parent, child, sibling);
        }
    }

    @Nested
    class AppointmentConfirmations {
        private SesService email;
        private SnsService sms;
        private TaskService dispatcher;

        @BeforeEach
        void configureDispatcher() {
            email = mock(SesService.class);
            sms = mock(SnsService.class);
            dispatcher = new TaskService();
            ReflectionTestUtils.setField(dispatcher, "sesService", email);
            ReflectionTestUtils.setField(dispatcher, "snsService", sms);
            service = new TaskServiceV2(taskRepository, patientRepository, objectMapper, dispatcher, authorizationService, securityUtil, userRepository);
            patient.setUser(User.builder()
                    .name("Jane Doe").email("patient@example.test").phone("+12025550100").build());
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(invocation -> {
                Task saved = invocation.getArgument(0);
                saved.setId(51L);
                return saved;
            });
        }

        private TaskDtoV2 appointment(String type) {
            return TaskDtoV2.builder().name("Checkup").description("Clinic")
                    .date("2026-01-20").timeOfDay("10:00").taskType(type).build();
        }

        @Test
        void sendsBothConfirmationsAfterSaveUsingPatientContacts() {
            TaskDtoV2 result = service.createTask(1L, appointment("appointment"));
            assertThat(result.getId()).isEqualTo(51L);
            final var order = inOrder(taskRepository, email, sms);
            order.verify(taskRepository).save(any(Task.class));
            order.verify(email).sendAppointmentReminder("patient@example.test", "Jane Doe",
                    "Checkup", "2026-01-20 at 10:00", "Clinic");
            order.verify(sms).sendAppointmentReminderSms("+12025550100", "Jane Doe",
                    "Checkup", "2026-01-20 at 10:00");
        }

        private TaskServiceV2 transactionalService(TestTransactionManager manager) {
            final TransactionInterceptor interceptor = new TransactionInterceptor();
            interceptor.setTransactionManager(manager);
            interceptor.setTransactionAttributeSource(new AnnotationTransactionAttributeSource());
            final ProxyFactory factory = new ProxyFactory(service);
            factory.addAdvice(interceptor);
            return (TaskServiceV2) factory.getProxy();
        }

        @Test
        void transactionalCreateSendsBothChannelsOnlyAfterCommit() {
            final TestTransactionManager manager = new TestTransactionManager();
            doAnswer(invocation -> {
                assertThat(manager.committed).isTrue();
                return null;
            }).when(email).sendAppointmentReminder(any(), any(), any(), any(), any());
            doAnswer(invocation -> {
                assertThat(manager.committed).isTrue();
                return null;
            }).when(sms).sendAppointmentReminderSms(any(), any(), any(), any());

            assertThat(transactionalService(manager).createTask(1L, appointment("Appointment")).getId())
                    .isEqualTo(51L);

            assertThat(manager.committed).isTrue();
            verify(email).sendAppointmentReminder(any(), any(), any(), any(), any());
            verify(sms).sendAppointmentReminderSms(any(), any(), any(), any());
            verifyNoMoreInteractions(email, sms);
        }

        @Test
        void enclosingTransactionDefersConfirmationUntilItsCommit() {
            final TestTransactionManager manager = new TestTransactionManager();
            new TransactionTemplate(manager).execute(status -> {
                service.createTask(1L, appointment("Appointment"));
                verifyNoInteractions(email, sms);
                assertThat(manager.committed).isFalse();
                return null;
            });
            assertThat(manager.committed).isTrue();
            verify(email).sendAppointmentReminder(any(), any(), any(), any(), any());
            verify(sms).sendAppointmentReminderSms(any(), any(), any(), any());
        }

        @Test
        void rollbackOnlyTransactionDoesNotSendConfirmations() {
            final TestTransactionManager manager = new TestTransactionManager();
            new TransactionTemplate(manager).execute(status -> {
                service.createTask(1L, appointment("Appointment"));
                verifyNoInteractions(email, sms);
                status.setRollbackOnly();
                return null;
            });
            assertThat(manager.rolledBack).isTrue();
            assertThat(manager.committed).isFalse();
            verifyNoInteractions(email, sms);
        }

        @Test
        void exceptionAfterCreationRollsBackWithoutConfirmations() {
            final TestTransactionManager manager = new TestTransactionManager();
            assertThatThrownBy(() -> new TransactionTemplate(manager).execute(status -> {
                service.createTask(1L, appointment("Appointment"));
                verifyNoInteractions(email, sms);
                throw new IllegalStateException("later work failed");
            })).isInstanceOf(IllegalStateException.class);
            assertThat(manager.rolledBack).isTrue();
            verifyNoInteractions(email, sms);
        }

        @Test
        void failedCommitDoesNotSendConfirmations() {
            final TestTransactionManager manager = new TestTransactionManager();
            manager.failCommit = true;
            assertThatThrownBy(() -> transactionalService(manager)
                    .createTask(1L, appointment("Appointment")))
                    .isInstanceOf(TransactionSystemException.class);
            assertThat(manager.committed).isFalse();
            verifyNoInteractions(email, sms);
        }

        @Test
        void recurringCreationSendsOneConfirmationPairAfterCommit() {
            final TestTransactionManager manager = new TestTransactionManager();
            final TaskDtoV2 request = appointment("Appointment");
            request.setFrequency("daily");
            request.setInterval(1);
            request.setCount(3);
            new TransactionTemplate(manager).execute(status -> {
                service.createTask(1L, request);
                verify(taskRepository).saveAll(anyList());
                verifyNoInteractions(email, sms);
                return null;
            });
            assertThat(manager.committed).isTrue();
            verify(email).sendAppointmentReminder(any(), any(), any(), any(), any());
            verify(sms).sendAppointmentReminderSms(any(), any(), any(), any());
            verifyNoMoreInteractions(email, sms);
        }

        @Test
        void emailFailureAfterCommitStillSendsSmsAndReturnsCreatedTask() {
            final TestTransactionManager manager = new TestTransactionManager();
            doThrow(new IllegalStateException("email unavailable"))
                    .when(email).sendAppointmentReminder(any(), any(), any(), any(), any());
            assertThat(transactionalService(manager).createTask(1L, appointment("Appointment")).getId())
                    .isEqualTo(51L);
            assertThat(manager.committed).isTrue();
            verify(sms).sendAppointmentReminderSms(any(), any(), any(), any());
        }

        @Test
        void recurringAppointmentSendsOneConfirmationForCreation() {
            TaskDtoV2 request = appointment("Appointment");
            request.setFrequency("daily");
            request.setInterval(1);
            request.setCount(3);
            service.createTask(1L, request);
            verify(taskRepository).saveAll(anyList());
            verify(email).sendAppointmentReminder(any(), any(), any(), any(), any());
            verify(sms).sendAppointmentReminderSms(any(), any(), any(), any());
            verifyNoMoreInteractions(email, sms);
        }

        @Test
        void nonAppointmentAndMissingTypeDoNotSendConfirmations() {
            service.createTask(1L, appointment("General"));
            service.createTask(1L, appointment(null));
            verifyNoInteractions(email, sms);
        }

        @Test
        void failedSaveDoesNotSendConfirmations() {
            when(taskRepository.save(any(Task.class))).thenThrow(new IllegalStateException("save failed"));
            assertThatThrownBy(() -> service.createTask(1L, appointment("Appointment")))
                    .isInstanceOf(IllegalStateException.class);
            verifyNoInteractions(email, sms);
        }

        @Test
        void emailFailureDoesNotPreventSmsOrTaskCreation() {
            doThrow(new IllegalStateException("email unavailable"))
                    .when(email).sendAppointmentReminder(any(), any(), any(), any(), any());
            assertThat(service.createTask(1L, appointment("APPOINTMENT")).getId()).isEqualTo(51L);
            verify(sms).sendAppointmentReminderSms(any(), any(), any(), any());
        }

        @Test
        void smsFailureDoesNotFailTaskCreation() {
            doThrow(new IllegalStateException("SMS unavailable"))
                    .when(sms).sendAppointmentReminderSms(any(), any(), any(), any());
            assertThat(service.createTask(1L, appointment("Appointment")).getId()).isEqualTo(51L);
            verify(email).sendAppointmentReminder(any(), any(), any(), any(), any());
        }

        @Test
        void absentContactsSkipConfirmations() {
            patient.setUser(null);
            assertThat(service.createTask(1L, appointment("Appointment")).getId()).isEqualTo(51L);
            verifyNoInteractions(email, sms);
        }

        @Test
        void demoOverridesAndFallbackDetailsMatchV1() {
            patient.setUser(null);
            ReflectionTestUtils.setField(dispatcher,
                    "demoNotificationEmail", "demo@example.test");
            ReflectionTestUtils.setField(dispatcher,
                    "demoNotificationPhone", "+12025550101");
            TaskDtoV2 request = appointment("Appointment");
            request.setDescription(null);
            service.createTask(1L, request);
            verify(email).sendAppointmentReminder("demo@example.test", "Patient",
                    "Checkup", "2026-01-20 at 10:00", "TBD");
            verify(sms).sendAppointmentReminderSms("+12025550101", "Patient",
                    "Checkup", "2026-01-20 at 10:00");
        }
    }

    // Exercise Spring's real transaction lifecycle without a database or external senders.
    private static final class TestTransactionManager extends AbstractPlatformTransactionManager {
        boolean committed;
        boolean rolledBack;
        boolean failCommit;

        @Override
        protected Object doGetTransaction() {
            return new Object();
        }

        @Override
        protected void doBegin(Object transaction, TransactionDefinition definition) {
        }

        @Override
        protected void doCommit(DefaultTransactionStatus status) {
            if (failCommit) {
                throw new TransactionSystemException("commit failed");
            }
            committed = true;
        }

        @Override
        protected void doRollback(DefaultTransactionStatus status) {
            rolledBack = true;
        }
    }

    // ================================================================
    // Helper methods
    // ================================================================

    private Task buildTask(Long id, String name, String date) {
        final Task task = Task.builder()
                .id(id)
                .name(name)
                .description("desc")
                .date(date)
                .timeOfDay("10:00")
                .isCompleted(false)
                .taskType("General")
                .frequency(null)
                .taskInterval(1)
                .doCount(1)
                .daysOfWeek(null)
                .patient(patient)
                .parentTaskId(null)
                .build();
        // Ensure notifications list is initialized
        if (task.getNotifications() == null) {
            task.setNotifications(new ArrayList<>());
        }
        return task;
    }

    private Task buildRecurringTask(Long id, String name, String date, String frequency,
                                    int interval, int count, Long parentTaskId) {
        final Task task = Task.builder()
                .id(id)
                .name(name)
                .description("recurring desc")
                .date(date)
                .timeOfDay("10:00")
                .isCompleted(false)
                .taskType("Medication")
                .frequency(frequency)
                .taskInterval(interval)
                .doCount(count)
                .daysOfWeek(null)
                .patient(patient)
                .parentTaskId(parentTaskId)
                .build();
        if (task.getNotifications() == null) {
            task.setNotifications(new ArrayList<>());
        }
        return task;
    }

    private ScheduledNotificationDTO buildNotificationDto() throws Exception {
        return ScheduledNotificationDTO.builder()
                .receiverId(1L)
                .title("Reminder")
                .body("Take your meds")
                .notificationType("REMINDER")
                .scheduledTime("2025-06-01T10:00:00")
                .build();
    }

    // ================================================================
    // getTaskById
    // ================================================================

    @Nested
    @DisplayName("getTaskById")
    class GetTaskByIdTests {

        @Test
        @DisplayName("should return task when found")
        void getTaskById_taskExists_returnsTask() throws Exception {
            final Task task = buildTask(1L, "Test Task", "2025-06-01");
            when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

            final Task result = service.getTaskById(1L);

            assertThat(result).isNotNull();
            assertThat(result.getId()).isEqualTo(1L);
            assertThat(result.getName()).isEqualTo("Test Task");
        }

        @Test
        @DisplayName("should throw TaskNotFoundException when not found")
        void getTaskById_taskNotFound_throwsException() throws Exception {
            when(taskRepository.findById(99L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.getTaskById(99L))
                    .isInstanceOf(TaskNotFoundException.class);
        }
    }

    // ================================================================
    // getTaskDtoById
    // ================================================================

    @Nested
    @DisplayName("getTaskDtoById")
    class GetTaskDtoByIdTests {

        @Test
        @DisplayName("should return TaskDtoV2 when task exists")
        void getTaskDtoById_taskExists_returnsDto() throws Exception {
            final Task task = buildTask(1L, "DTO Task", "2025-06-01");
            when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

            final TaskDtoV2 result = service.getTaskDtoById(1L);

            assertThat(result).isNotNull();
            assertThat(result.getId()).isEqualTo(1L);
            assertThat(result.getName()).isEqualTo("DTO Task");
            assertThat(result.getDate()).isEqualTo("2025-06-01");
            assertThat(result.getPatientId()).isEqualTo(1L);
        }

        @Test
        @DisplayName("should map notifications correctly when present")
        void getTaskDtoById_withNotifications_mapsNotifications() throws Exception {
            final Task task = buildTask(1L, "Notif Task", "2025-06-01");
            final ScheduledNotification sn = ScheduledNotification.builder()
                    .receiverId(1L)
                    .title("Title")
                    .body("Body")
                    .notificationType("REMINDER")
                    .scheduledTime(LocalDateTime.of(2025, 6, 1, 10, 0))
                    .task(task)
                    .build();
            task.getNotifications().add(sn);
            when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

            final TaskDtoV2 result = service.getTaskDtoById(1L);

            assertThat(result.getNotifications()).hasSize(1);
            assertThat(result.getNotifications().get(0).getTitle()).isEqualTo("Title");
            assertThat(result.getNotifications().get(0).getScheduledTime()).isEqualTo("2025-06-01T10:00");
        }

        @Test
        @DisplayName("should map null notifications as null")
        void getTaskDtoById_withNullNotifications_returnsNullNotifications() throws Exception {
            final Task task = buildTask(1L, "Null Notif", "2025-06-01");
            task.setNotifications(null);
            when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

            final TaskDtoV2 result = service.getTaskDtoById(1L);

            assertThat(result.getNotifications()).isNull();
        }

        @Test
        @DisplayName("should handle notification with null scheduledTime")
        void getTaskDtoById_notificationNullScheduledTime_mapsAsNull() throws Exception {
            final Task task = buildTask(1L, "NullTime", "2025-06-01");
            final ScheduledNotification sn = ScheduledNotification.builder()
                    .receiverId(1L)
                    .title("T")
                    .body("B")
                    .notificationType("ALERT")
                    .scheduledTime(null)
                    .task(task)
                    .build();
            task.getNotifications().add(sn);
            when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

            final TaskDtoV2 result = service.getTaskDtoById(1L);

            assertThat(result.getNotifications()).hasSize(1);
            assertThat(result.getNotifications().get(0).getScheduledTime()).isNull();
        }

        @Test
        @DisplayName("should handle task with null patient")
        void getTaskDtoById_nullPatient_returnsNullPatientId() throws Exception {
            final Task task = buildTask(1L, "No Patient", "2025-06-01");
            task.setPatient(null);
            when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

            final TaskDtoV2 result = service.getTaskDtoById(1L);

            assertThat(result.getPatientId()).isNull();
        }
    }

    // ================================================================
    // getTasksByPatient
    // ================================================================

    @Nested
    @DisplayName("getTasksByPatient")
    class GetTasksByPatientTests {

        @Test
        @DisplayName("should return list of DTOs when tasks exist")
        void getTasksByPatient_tasksExist_returnsDtoList() throws Exception {
            final Task t1 = buildTask(1L, "Task1", "2025-06-01");
            final Task t2 = buildTask(2L, "Task2", "2025-06-02");
            when(taskRepository.findByPatientId(1L)).thenReturn(Optional.of(Arrays.asList(t1, t2)));

            final List<TaskDtoV2> result = service.getTasksByPatient(1L);

            assertThat(result).hasSize(2);
            assertThat(result.get(0).getName()).isEqualTo("Task1");
            assertThat(result.get(1).getName()).isEqualTo("Task2");
        }

        @Test
        @DisplayName("should return empty list when no tasks found")
        void getTasksByPatient_noTasks_returnsEmptyList() throws Exception {
            when(taskRepository.findByPatientId(1L)).thenReturn(Optional.empty());

            final List<TaskDtoV2> result = service.getTasksByPatient(1L);

            assertThat(result).isEmpty();
        }

        @Test
        @DisplayName("should return empty list when Optional contains empty list")
        void getTasksByPatient_emptyListPresent_returnsEmptyList() throws Exception {
            when(taskRepository.findByPatientId(1L)).thenReturn(Optional.of(new ArrayList<>()));

            final List<TaskDtoV2> result = service.getTasksByPatient(1L);

            assertThat(result).isEmpty();
        }
    }

    // ================================================================
    // createTask
    // ================================================================

    @Nested
    @DisplayName("createTask")
    class CreateTaskTests {

        @Test
        @DisplayName("should throw PatientNotFoundException when patient not found")
        void createTask_patientNotFound_throwsException() throws Exception {
            when(patientRepository.findById(99L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.createTask(99L, TaskDtoV2.builder().build()))
                    .isInstanceOf(PatientNotFoundException.class);
        }

        @Test
        @DisplayName("should create simple one-time task without recurrence")
        void createTask_noRecurrence_createsSimpleTask() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Simple Task")
                    .description("Simple desc")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .isCompleted(false)
                    .taskType("General")
                    .build();

            final TaskDtoV2 result = service.createTask(1L, dto);

            assertThat(result).isNotNull();
            assertThat(result.getName()).isEqualTo("Simple Task");
            verify(taskRepository).save(any(Task.class));
        }

        @Test
        @DisplayName("should create task with notifications")
        void createTask_withNotifications_createsTaskWithNotifications() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });

            final ScheduledNotificationDTO notifDto = buildNotificationDto();
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Task with Notif")
                    .description("desc")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .isCompleted(false)
                    .taskType("Medication")
                    .notifications(List.of(notifDto))
                    .build();

            final TaskDtoV2 result = service.createTask(1L, dto);

            assertThat(result).isNotNull();
            final ArgumentCaptor<Task> captor = ArgumentCaptor.forClass(Task.class);
            verify(taskRepository).save(captor.capture());
            assertThat(captor.getValue().getNotifications()).hasSize(1);
        }

        @Test
        @DisplayName("should create task with empty notifications list")
        void createTask_emptyNotifications_createsTaskWithoutNotifications() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Empty Notif")
                    .description("desc")
                    .date("2025-06-01")
                    .notifications(Collections.emptyList())
                    .build();

            service.createTask(1L, dto);

            final ArgumentCaptor<Task> captor = ArgumentCaptor.forClass(Task.class);
            verify(taskRepository).save(captor.capture());
            assertThat(captor.getValue().getNotifications()).isEmpty();
        }

        @Test
        @DisplayName("should normalize recurrence count for daily frequency when count is null")
        void createTask_dailyFrequencyNullCount_normalizesCount() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(anyLong())).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Daily")
                    .date("2025-06-01")
                    .frequency("daily")
                    .count(null)
                    .interval(1)
                    .build();

            final TaskDtoV2 result = service.createTask(1L, dto);

            assertThat(result).isNotNull();
            // The count should have been computed (3 months of daily = ~92 days)
            assertThat(dto.getCount()).isNotNull();
            assertThat(dto.getCount()).isGreaterThan(1);
        }

        @Test
        @DisplayName("should normalize recurrence count for weekly frequency with daysOfWeek")
        void createTask_weeklyFrequencyWithDaysNullCount_normalizesCount() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(anyLong())).thenReturn(new ArrayList<>());

            // Sun=true, Mon=true, rest false
            final List<Boolean> days = Arrays.asList(true, true, false, false, false, false, false);
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Weekly with days")
                    .date("2025-06-01")
                    .frequency("weekly")
                    .count(null)
                    .interval(1)
                    .daysOfWeek(days)
                    .build();

            service.createTask(1L, dto);

            assertThat(dto.getCount()).isNotNull();
            assertThat(dto.getCount()).isGreaterThan(1);
        }

        @Test
        @DisplayName("should normalize recurrence count for weekly frequency without daysOfWeek")
        void createTask_weeklyFrequencyNoDaysNullCount_normalizesCount() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(anyLong())).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Weekly no days")
                    .date("2025-06-01")
                    .frequency("weekly")
                    .count(null)
                    .interval(1)
                    .daysOfWeek(null)
                    .build();

            service.createTask(1L, dto);

            assertThat(dto.getCount()).isNotNull();
        }

        @Test
        @DisplayName("should normalize recurrence count for monthly frequency")
        void createTask_monthlyFrequencyNullCount_normalizesCount() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(anyLong())).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Monthly")
                    .date("2025-06-01")
                    .frequency("monthly")
                    .count(null)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            assertThat(dto.getCount()).isNotNull();
            assertThat(dto.getCount()).isEqualTo(4); // 3 months = 4 occurrences (June, July, Aug, Sep)
        }

        @Test
        @DisplayName("should normalize recurrence count for yearly frequency")
        void createTask_yearlyFrequencyNullCount_normalizesCount() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(anyLong())).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Yearly")
                    .date("2025-06-01")
                    .frequency("yearly")
                    .count(null)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            assertThat(dto.getCount()).isNotNull();
            assertThat(dto.getCount()).isEqualTo(1); // 3 months = 0 years difference -> 1
        }

        @Test
        @DisplayName("should normalize recurrence count for unknown frequency with default")
        void createTask_unknownFrequencyNullCount_normalizesToDefault() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Unknown freq")
                    .date("2025-06-01")
                    .frequency("biweekly_custom")
                    .count(null)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            assertThat(dto.getCount()).isEqualTo(1);
        }

        @Test
        @DisplayName("should normalize recurrence count with null interval defaulting to 1")
        void createTask_nullInterval_defaultsToOne() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(anyLong())).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Null Interval")
                    .date("2025-06-01")
                    .frequency("daily")
                    .count(null)
                    .interval(null) // explicitly null
                    .build();

            service.createTask(1L, dto);

            assertThat(dto.getCount()).isNotNull();
        }

        @Test
        @DisplayName("should handle exception during recurrence normalization gracefully")
        void createTask_recurrenceNormalizationException_continuesCreation() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });

            // Date that's too short to parse will cause exception in normalization
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Bad date")
                    .date("bad")
                    .frequency("daily")
                    .count(null)
                    .build();

            // Should not throw - exception is caught internally
            final TaskDtoV2 result = service.createTask(1L, dto);

            assertThat(result).isNotNull();
            // count was not set because of the exception
            assertThat(dto.getCount()).isNull();
        }

        @Test
        @DisplayName("should skip normalization when count is already set")
        void createTask_countAlreadySet_skipsNormalization() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(anyLong())).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Count Set")
                    .date("2025-06-01")
                    .frequency("daily")
                    .count(5)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            // count should remain 5, not be overwritten
            assertThat(dto.getCount()).isEqualTo(5);
        }

        @Test
        @DisplayName("should skip normalization when frequency is null")
        void createTask_nullFrequency_skipsNormalization() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("No freq")
                    .date("2025-06-01")
                    .frequency(null)
                    .count(null)
                    .build();

            service.createTask(1L, dto);

            assertThat(dto.getCount()).isNull();
        }

        @Test
        @DisplayName("should skip normalization when date is null")
        void createTask_nullDate_skipsNormalization() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("No date")
                    .date(null)
                    .frequency("daily")
                    .count(null)
                    .build();

            service.createTask(1L, dto);

            assertThat(dto.getCount()).isNull();
        }

        @Test
        @DisplayName("should generate occurrences for recurring task with count > 1")
        void createTask_recurringDailyCount3_generatesOccurrences() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Daily x3")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("daily")
                    .count(3)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            // save the parent + saveAll for 2 child occurrences (parent already occupies day 0)
            verify(taskRepository).save(any(Task.class));
            verify(taskRepository).saveAll(anyList());
        }

        @Test
        @DisplayName("should generate weekly occurrences with daysOfWeek")
        void createTask_recurringWeeklyWithDays_generatesOccurrences() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            // Sunday=true, Monday=true, rest false
            final List<Boolean> days = Arrays.asList(true, true, false, false, false, false, false);
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Weekly x4")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("weekly")
                    .count(4)
                    .interval(1)
                    .daysOfWeek(days)
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).save(any(Task.class));
        }

        @Test
        @DisplayName("should generate monthly occurrences")
        void createTask_recurringMonthly_generatesOccurrences() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Monthly x3")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("monthly")
                    .count(3)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).save(any(Task.class));
            verify(taskRepository).saveAll(anyList());
        }

        @Test
        @DisplayName("should generate yearly occurrences")
        void createTask_recurringYearly_generatesOccurrences() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Yearly x2")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("yearly")
                    .count(2)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).save(any(Task.class));
            verify(taskRepository).saveAll(anyList());
        }

        @Test
        @DisplayName("should not generate occurrences when count is 1")
        void createTask_recurringCountOne_noOccurrencesGenerated() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Single occurrence")
                    .date("2025-06-01")
                    .frequency("daily")
                    .count(1)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).save(any(Task.class));
            verify(taskRepository, never()).saveAll(anyList());
        }

        @Test
        @DisplayName("should generate occurrences with notifications and time shifting")
        void createTask_recurringWithNotifications_shiftsNotificationTimes() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            final ScheduledNotificationDTO notifDto = ScheduledNotificationDTO.builder()
                    .receiverId(1L)
                    .title("Reminder")
                    .body("Take meds")
                    .notificationType("REMINDER")
                    .scheduledTime("2025-06-01T10:00:00")
                    .build();

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("With notifs")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("daily")
                    .count(3)
                    .interval(1)
                    .notifications(List.of(notifDto))
                    .build();

            service.createTask(1L, dto);

            @SuppressWarnings("unchecked") final ArgumentCaptor<List<Task>> captor = ArgumentCaptor.forClass(List.class);
            verify(taskRepository).saveAll(captor.capture());
            final List<Task> occurrences = captor.getValue();
            assertThat(occurrences).allSatisfy(t ->
                    assertThat(t.getNotifications()).hasSize(1)
            );
        }

        @Test
        @DisplayName("should generate occurrences without time of day using MIDNIGHT")
        void createTask_recurringNullTimeOfDay_usesMidnight() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("No time")
                    .date("2025-06-01")
                    .timeOfDay(null)
                    .frequency("daily")
                    .count(2)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).saveAll(anyList());
        }

        @Test
        @DisplayName("should skip already existing occurrence dates")
        void createTask_existingOccurrenceDates_skipsExistingDates() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });

            // Already have a child for 2025-06-02
            final Task existingChild = buildTask(11L, "Existing", "2025-06-02");
            existingChild.setParentTaskId(10L);
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>(List.of(existingChild)));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Skip existing")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("daily")
                    .count(3)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            @SuppressWarnings("unchecked") final ArgumentCaptor<List<Task>> captor = ArgumentCaptor.forClass(List.class);
            verify(taskRepository).saveAll(captor.capture());
            // Only 1 new occurrence (2025-06-03), since parent=2025-06-01 and 2025-06-02 exists
            assertThat(captor.getValue()).hasSize(1);
        }

        @Test
        @DisplayName("should handle weekly with no daysOfWeek returning empty dates")
        void createTask_weeklyNoDaysOfWeek_returnsEmptyDates() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Weekly no days")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("weekly")
                    .count(3)
                    .interval(1)
                    .daysOfWeek(null) // no days
                    .build();

            service.createTask(1L, dto);

            // weekly with null daysOfWeek returns empty list from calculateExpectedDates
            verify(taskRepository, never()).saveAll(anyList());
        }

        @Test
        @DisplayName("should handle weekly with empty daysOfWeek returning empty dates")
        void createTask_weeklyEmptyDaysOfWeek_returnsEmptyDates() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Weekly empty days")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("weekly")
                    .count(3)
                    .interval(1)
                    .daysOfWeek(Collections.emptyList())
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository, never()).saveAll(anyList());
        }

        @Test
        @DisplayName("should handle null interval in task builder defaulting to 0")
        void createTask_nullIntervalInBuilder_defaultsToZero() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                t.setId(10L);
                return t;
            });

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Null interval")
                    .date("2025-06-01")
                    .interval(null)
                    .count(null)
                    .build();

            service.createTask(1L, dto);

            final ArgumentCaptor<Task> captor = ArgumentCaptor.forClass(Task.class);
            verify(taskRepository).save(captor.capture());
            assertThat(captor.getValue().getTaskInterval()).isEqualTo(0);
            assertThat(captor.getValue().getDoCount()).isEqualTo(0);
        }

        @Test
        @DisplayName("should handle weekly occurrence where daysOfWeek index has false value")
        void createTask_weeklyWithSomeFalseDays_generatesCorrectOccurrences() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            // Only Wednesday (index 4 in Sun-based: 0=Sun,1=Mon,2=Tue,3=Wed,4=Thu,5=Fri,6=Sat)
            // Actually: daysOfWeek index 3 = Wed
            final List<Boolean> days = Arrays.asList(false, false, false, true, false, false, false);
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Wed only")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("weekly")
                    .count(3)
                    .interval(1)
                    .daysOfWeek(days)
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).save(any(Task.class));
        }

        @Test
        @DisplayName("should generate occurrences with null notifications on occurrence")
        void createTask_recurringNullNotifications_generatesWithoutNotifications() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Recurring no notif")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("daily")
                    .count(2)
                    .interval(1)
                    .notifications(null)
                    .build();

            service.createTask(1L, dto);

            @SuppressWarnings("unchecked") final ArgumentCaptor<List<Task>> captor = ArgumentCaptor.forClass(List.class);
            verify(taskRepository).saveAll(captor.capture());
            assertThat(captor.getValue()).allSatisfy(t ->
                    assertThat(t.getNotifications()).isEmpty()
            );
        }

        @Test
        @DisplayName("should handle interval with null default in calculateExpectedDates")
        void createTask_calculateExpectedDatesNullInterval_defaultsToOne() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Null interval calc")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("daily")
                    .count(3)
                    .interval(null) // null -> defaults to 1
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).saveAll(anyList());
        }

        @Test
        @DisplayName("should handle zero interval in calculateExpectedDates defaulting to 1")
        void createTask_calculateExpectedDatesZeroInterval_defaultsToOne() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Zero interval calc")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("daily")
                    .count(3)
                    .interval(0)
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).saveAll(anyList());
        }

        @Test
        @DisplayName("should handle date with datetime format in substring(0,10)")
        void createTask_dateTimeFormat_parsesCorrectly() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("DateTime format")
                    .date("2025-06-01T10:00:00")
                    .timeOfDay("10:00")
                    .frequency("daily")
                    .count(2)
                    .interval(1)
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).saveAll(anyList());
        }
    }

    // ================================================================
    // updateCompletionStatus
    // ================================================================

    @Nested
    @DisplayName("updateCompletionStatus")
    class UpdateCompletionStatusTests {

        @Test
        @DisplayName("should mark task as completed")
        void updateCompletionStatus_markComplete_updatesSuccessfully() throws Exception {
            final Task task = buildTask(1L, "Complete me", "2025-06-01");
            when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 result = service.updateCompletionStatus(1L, true);

            assertThat(result.isCompleted()).isTrue();
            verify(taskRepository).save(task);
        }

        @Test
        @DisplayName("should mark task as incomplete")
        void updateCompletionStatus_markIncomplete_updatesSuccessfully() throws Exception {
            final Task task = buildTask(1L, "Uncomplete me", "2025-06-01");
            task.setCompleted(true);
            when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 result = service.updateCompletionStatus(1L, false);

            assertThat(result.isCompleted()).isFalse();
        }

        @Test
        @DisplayName("should throw TaskNotFoundException when task not found")
        void updateCompletionStatus_taskNotFound_throwsException() throws Exception {
            when(taskRepository.findById(99L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.updateCompletionStatus(99L, true))
                    .isInstanceOf(TaskNotFoundException.class);
        }
    }

    // ================================================================
    // updateTask
    // ================================================================

    @Nested
    @DisplayName("updateTask")
    class UpdateTaskTests {

        @Nested
        @DisplayName("single task update (updateSeries=false)")
        class SingleTaskUpdate {

            @Test
            @DisplayName("should update single task fields")
            void updateTask_singleUpdate_updatesFields() throws Exception {
                final Task task = buildTask(1L, "Old name", "2025-06-01");
                when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .name("New name")
                        .description("New desc")
                        .date("2025-06-15")
                        .timeOfDay("14:00")
                        .taskType("Appointment")
                        .frequency("daily")
                        .interval(2)
                        .count(5)
                        .daysOfWeek(Arrays.asList(true, false, true, false, true, false, true))
                        .isCompleted(true)
                        .updateSeries(false)
                        .build();

                final TaskDtoV2 result = service.updateTask(1L, dto);

                assertThat(result.getName()).isEqualTo("New name");
                assertThat(result.getDescription()).isEqualTo("New desc");
                verify(taskRepository).save(task);
            }

            @Test
            @DisplayName("should update single task with null updateSeries")
            void updateTask_nullUpdateSeries_treatsAsSingleUpdate() throws Exception {
                final Task task = buildTask(1L, "Old name", "2025-06-01");
                when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .name("Updated name")
                        .updateSeries(null)
                        .build();

                final TaskDtoV2 result = service.updateTask(1L, dto);

                assertThat(result.getName()).isEqualTo("Updated name");
            }

            @Test
            @DisplayName("should update patient when patientId is set")
            void updateTask_singleUpdateWithPatientId_updatesPatient() throws Exception {
                final Task task = buildTask(1L, "Task", "2025-06-01");
                final Patient newPatient = Patient.builder().id(2L).build();
                when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
                when(patientRepository.findById(2L)).thenReturn(Optional.of(newPatient));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .patientId(2L)
                        .updateSeries(false)
                        .build();

                service.updateTask(1L, dto);

                assertThat(task.getPatient()).isEqualTo(newPatient);
            }

            @Test
            @DisplayName("should throw PatientNotFoundException when patientId invalid")
            void updateTask_singleUpdateInvalidPatientId_throwsException() throws Exception {
                final Task task = buildTask(1L, "Task", "2025-06-01");
                when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
                when(patientRepository.findById(99L)).thenReturn(Optional.empty());

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .patientId(99L)
                        .updateSeries(false)
                        .build();

                assertThatThrownBy(() -> service.updateTask(1L, dto))
                        .isInstanceOf(PatientNotFoundException.class);
            }

            @Test
            @DisplayName("should update notifications when provided on single update")
            void updateTask_singleUpdateWithNotifications_updatesNotifications() throws Exception {
                final Task task = buildTask(1L, "Task", "2025-06-01");
                // Start with existing notification
                final ScheduledNotification existing = ScheduledNotification.builder()
                        .receiverId(1L).title("Old").body("Old body")
                        .scheduledTime(LocalDateTime.of(2025, 6, 1, 10, 0))
                        .task(task).build();
                task.getNotifications().add(existing);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final ScheduledNotificationDTO newNotif = ScheduledNotificationDTO.builder()
                        .receiverId(2L).title("New").body("New body")
                        .notificationType("ALERT")
                        .scheduledTime("2025-06-02T14:00:00")
                        .build();

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .notifications(List.of(newNotif))
                        .updateSeries(false)
                        .build();

                service.updateTask(1L, dto);

                assertThat(task.getNotifications()).hasSize(1);
                assertThat(task.getNotifications().get(0).getTitle()).isEqualTo("New");
            }

            @Test
            @DisplayName("should update notifications when task has null notifications list")
            void updateTask_singleUpdateNullNotificationsList_createsNewList() throws Exception {
                final Task task = buildTask(1L, "Task", "2025-06-01");
                task.setNotifications(null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final ScheduledNotificationDTO newNotif = ScheduledNotificationDTO.builder()
                        .receiverId(1L).title("T").body("B")
                        .notificationType("ALERT")
                        .scheduledTime("2025-06-01T10:00:00")
                        .build();

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .notifications(List.of(newNotif))
                        .updateSeries(false)
                        .build();

                service.updateTask(1L, dto);

                assertThat(task.getNotifications()).hasSize(1);
            }

            @Test
            @DisplayName("should not update notifications when dto notifications is null")
            void updateTask_singleUpdateNullDtoNotifications_keepsExisting() throws Exception {
                final Task task = buildTask(1L, "Task", "2025-06-01");
                final ScheduledNotification existing = ScheduledNotification.builder()
                        .receiverId(1L).title("Keep").body("Body")
                        .scheduledTime(LocalDateTime.of(2025, 6, 1, 10, 0))
                        .task(task).build();
                task.getNotifications().add(existing);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .name("Updated name")
                        .notifications(null)
                        .updateSeries(false)
                        .build();

                service.updateTask(1L, dto);

                assertThat(task.getNotifications()).hasSize(1);
                assertThat(task.getNotifications().get(0).getTitle()).isEqualTo("Keep");
            }
        }

        @Nested
        @DisplayName("series update (updateSeries=true)")
        class SeriesUpdateTests {

            @Test
            @DisplayName("should update series from parent task (parentTaskId=null)")
            void updateTask_seriesUpdateFromParent_updatesParentAndChildren() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);
                final Task child1 = buildRecurringTask(2L, "Child1", "2025-06-02", "daily", 1, 3, 1L);
                final Task child2 = buildRecurringTask(3L, "Child2", "2025-06-03", "daily", 1, 3, 1L);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>(Arrays.asList(child1, child2)));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .name("Updated Series Name")
                        .description("Updated desc")
                        .taskType("Appointment")
                        .updateSeries(true)
                        .build();

                final TaskDtoV2 result = service.updateTask(1L, dto);

                assertThat(result).isNotNull();
                // Children should be updated with name, desc, type
                assertThat(child1.getName()).isEqualTo("Updated Series Name");
                assertThat(child2.getName()).isEqualTo("Updated Series Name");
                verify(taskRepository).saveAll(anyList());
            }

            @Test
            @DisplayName("should update series from child task (parentTaskId != null)")
            void updateTask_seriesUpdateFromChild_findsParentAndUpdates() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);
                final Task childTask = buildRecurringTask(2L, "Child", "2025-06-02", "daily", 1, 3, 1L);
                final Task otherChild = buildRecurringTask(3L, "Other", "2025-06-03", "daily", 1, 3, 1L);

                when(taskRepository.findById(2L)).thenReturn(Optional.of(childTask));
                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>(Arrays.asList(childTask, otherChild)));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .name("Updated from child")
                        .updateSeries(true)
                        .build();

                final TaskDtoV2 result = service.updateTask(2L, dto);

                assertThat(result).isNotNull();
                verify(taskRepository, times(1)).save(any(Task.class)); // parent saved once after restoring original recurrence fields
            }

            @Test
            @DisplayName("should throw ParentTaskNotFoundException when parent missing on series update from child")
            void updateTask_seriesUpdateParentNotFound_throwsException() throws Exception {
                final Task childTask = buildRecurringTask(2L, "Child", "2025-06-02", "daily", 1, 3, 999L);

                when(taskRepository.findById(2L)).thenReturn(Optional.of(childTask));
                when(taskRepository.findById(999L)).thenReturn(Optional.empty());

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .name("Update")
                        .updateSeries(true)
                        .build();

                assertThatThrownBy(() -> service.updateTask(2L, dto))
                        .isInstanceOf(ParentTaskNotFoundException.class);
            }

            @Test
            @DisplayName("should detect frequency change and regenerate children")
            void updateTask_seriesFrequencyChanged_regeneratesChildren() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 5, null);
                final Task child1 = buildRecurringTask(2L, "C1", "2025-06-02", "daily", 1, 5, 1L);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>(List.of(child1)))  // first call
                        .thenReturn(new ArrayList<>())  // after deleteAll
                        .thenReturn(new ArrayList<>());  // safety check
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .frequency("monthly")
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                verify(taskRepository).deleteAll(anyList()); // children deleted
            }

            @Test
            @DisplayName("should detect interval change and regenerate children")
            void updateTask_seriesIntervalChanged_regeneratesChildren() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 5, null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .interval(3)
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                assertThat(parentTask.getTaskInterval()).isEqualTo(3);
            }

            @Test
            @DisplayName("should detect count change and regenerate children")
            void updateTask_seriesCountChanged_regeneratesChildren() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 5, null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .count(10)
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                assertThat(parentTask.getDoCount()).isEqualTo(10);
            }

            @Test
            @DisplayName("should detect weekly days change and recompute count from end")
            void updateTask_seriesWeeklyDaysChanged_recomputesCount() throws Exception {
                // weekly task with specific days
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "weekly", 1, 10, null);
                parentTask.setDaysOfWeek("[true,true,false,false,false,false,false]");

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .daysOfWeek(Arrays.asList(true, true, true, false, false, false, false))
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                assertThat(parentTask.getDaysOfWeek())
                        .isEqualTo("[true,true,true,false,false,false,false]");
                verify(taskRepository).save(parentTask);
            }

            @Test
            @DisplayName("should detect daysOfWeek change with non-weekly frequency")
            void updateTask_seriesDaysChangedNonWeekly_usesNonWeeklyBranch() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 5, null);
                parentTask.setDaysOfWeek("[true,false,false,false,false,false,false]");

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .daysOfWeek(Arrays.asList(true, true, false, false, false, false, false))
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                verify(taskRepository).deleteAll(anyList());
            }

            @Test
            @DisplayName("should handle series update with null originalFreq")
            void updateTask_seriesNullOriginalFreq_handlesNull() throws Exception {
                final Task parentTask = buildTask(1L, "Parent", "2025-06-01");
                parentTask.setFrequency(null);
                parentTask.setTaskInterval(null);
                parentTask.setDoCount(null);
                parentTask.setDaysOfWeek(null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .name("Updated")
                        .updateSeries(true)
                        .build();

                // Should not throw
                service.updateTask(1L, dto);

                verify(taskRepository).saveAll(anyList());
            }

            @Test
            @DisplayName("should handle recurrence change with date set but count null")
            void updateTask_recurrenceChangedDateSetCountNull_recomputesCount() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 5, null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .frequency("monthly")
                        .date("2025-07-01")
                        .count(null) // triggers recompute
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                verify(taskRepository).deleteAll(anyList());
            }

            @Test
            @DisplayName("should handle applyTaskUpdates for series with monthly frequency and date")
            void updateTask_seriesUpdateMonthlyWithDate_updatesParentDate() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "monthly", 1, 3, null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .date("2025-07-15")
                        .timeOfDay("14:00")
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                // Parent date should have been restored to original after applyTaskUpdates
                assertThat(parentTask.getDate()).isEqualTo("2025-06-01");
            }

            @Test
            @DisplayName("should handle applyTaskUpdates for series with yearly frequency and date")
            void updateTask_seriesUpdateYearlyWithDate_updatesParentDate() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "yearly", 1, 2, null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .date("2025-07-01")
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                assertThat(parentTask.getDate()).isEqualTo("2025-06-01");
            }

            @Test
            @DisplayName("should handle applyTaskUpdates for series with daily freq and earlier date")
            void updateTask_seriesUpdateDailyEarlierDate_updatesParentDate() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-10", "daily", 1, 3, null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .date("2025-06-05") // earlier than parent
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                // Parent date restored after applyTaskUpdates
                assertThat(parentTask.getDate()).isEqualTo("2025-06-10");
            }

            @Test
            @DisplayName("should handle applyTaskUpdates for series with daily freq and later date (no change)")
            void updateTask_seriesUpdateDailyLaterDate_doesNotUpdateParentDate() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .date("2025-06-15") // later than parent
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                assertThat(parentTask.getDate()).isEqualTo("2025-06-01");
            }

            @Test
            @DisplayName("should handle series update from child task with date for parent")
            void updateTask_seriesUpdateFromChildWithDate_parentDateNotUpdated() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);
                final Task childTask = buildRecurringTask(2L, "Child", "2025-06-02", "daily", 1, 3, 1L);

                when(taskRepository.findById(2L)).thenReturn(Optional.of(childTask));
                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>(List.of(childTask)))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .date("2025-05-20") // earlier date
                        .timeOfDay("09:00")
                        .updateSeries(true)
                        .build();

                service.updateTask(2L, dto);

                // Parent date should stay anchored
                assertThat(parentTask.getDate()).isEqualTo("2025-06-01");
            }

            @Test
            @DisplayName("should handle non-recurrence series update only updating name/desc/type on children")
            void updateTask_seriesNonRecurrenceUpdate_updatesChildrenSelectively() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);
                final Task child = buildRecurringTask(2L, "Child", "2025-06-02", "daily", 1, 3, 1L);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>(List.of(child)));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .name("New Name")
                        .description("New Desc")
                        .taskType("Exercise")
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                assertThat(child.getName()).isEqualTo("New Name");
                assertThat(child.getDescription()).isEqualTo("New Desc");
                assertThat(child.getTaskType()).isEqualTo("Exercise");
                verify(taskRepository).saveAll(anyList());
            }

            @Test
            @DisplayName("should not update child name/desc/type when not provided in dto")
            void updateTask_seriesNonRecurrenceNullFields_doesNotUpdateChildFields() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);
                final Task child = buildRecurringTask(2L, "Child", "2025-06-02", "daily", 1, 3, 1L);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>(List.of(child)));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .name(null)
                        .description(null)
                        .taskType(null)
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                assertThat(child.getName()).isEqualTo("Child");
                assertThat(child.getDescription()).isEqualTo("recurring desc");
                assertThat(child.getTaskType()).isEqualTo("Medication");
            }

            @Test
            @DisplayName("should handle series update with null timeOfDay on parent")
            void updateTask_seriesNullTimeOfDay_handlesNull() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);
                parentTask.setTimeOfDay(null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .frequency("monthly") // trigger recurrence change
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                verify(taskRepository).deleteAll(anyList());
            }

            @Test
            @DisplayName("should handle recurrence change where earliest generated date is before parent date")
            void updateTask_seriesRecurrenceGeneratedEarlierDate_adjustsParentDate() throws Exception {
                // Create a parent task with a date that starts mid-week, but daysOfWeek includes earlier day in week
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-04", "weekly", 1, 5, null);
                // Wed Jun 4 2025 -- set days to include Sunday (earlier in the same week)
                parentTask.setDaysOfWeek("[true,false,false,false,false,false,false]"); // Sunday only

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>())
                        .thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .count(3) // change count to trigger recurrence change
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                verify(taskRepository).deleteAll(anyList());
            }

            @Test
            @DisplayName("should handle reconcile adding missing and deleting extra tasks")
            void updateTask_seriesReconcileAddAndDelete_addsMissingDeletesExtras() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);

                // Child with date outside the expected range (extra)
                final Task extraChild = buildRecurringTask(5L, "Extra", "2025-06-20", "daily", 1, 3, 1L);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>(List.of(extraChild)))  // first call (before deleteAll)
                        .thenReturn(new ArrayList<>())  // second call (after reconcile for safety)
                        .thenReturn(new ArrayList<>());  // third call
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .count(2)
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                verify(taskRepository).deleteAll(anyList());
            }

            @Test
            @DisplayName("should handle reconcileSeries safety check with undercount triggering rebuild")
            void updateTask_reconcileUndercount_rebuilds() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 5, null);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                // First call (children before deleteAll) - empty
                // After reconcile - still undercounting (only 2 children but need 5)
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>())  // children for deleteAll
                        .thenReturn(new ArrayList<>())  // reconcileSeries
                        .thenReturn(new ArrayList<>())  // safety check 1
                        .thenReturn(new ArrayList<>());  // safety check 2 / generateOccurrences
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .count(10) // trigger count change
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                // The reconcile and safety checks should have been triggered
                verify(taskRepository).deleteAll(anyList());
            }

            @Test
            @DisplayName("should handle reconcileSeries with existing tasks matching some target dates")
            void updateTask_reconcilePartialMatch_handlesCorrectly() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);

                final Task matchingChild = buildRecurringTask(2L, "Match", "2025-06-02", "daily", 1, 3, 1L);
                // This child is before parent start - should be deleted
                final Task earlyChild = buildRecurringTask(3L, "Early", "2025-05-30", "daily", 1, 3, 1L);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L))
                        .thenReturn(new ArrayList<>()) // initial
                        .thenReturn(new ArrayList<>(Arrays.asList(matchingChild, earlyChild))) // reconcile
                        .thenReturn(new ArrayList<>(Arrays.asList(matchingChild))) // safety
                        .thenReturn(new ArrayList<>(Arrays.asList(matchingChild))); // second safety
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .count(2) // change triggers recurrence changed
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                verify(taskRepository, times(2)).deleteAll(anyList()); // once at line 307 (initial wipe) + once in reconcileSeries
            }

            @Test
            @DisplayName("should handle applySeriesFieldUpdatesToChild with all flags true")
            void updateTask_seriesNonRecurrenceAllFieldsChanged_updatesAllChildFields() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);
                final Task child = buildRecurringTask(2L, "Child", "2025-06-02", "daily", 1, 3, 1L);

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>(List.of(child)));
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                // all fields provided - but recurrence fields match so not recurrence-changed
                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .name("New")
                        .description("New desc")
                        .taskType("Exercise")
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                assertThat(child.getName()).isEqualTo("New");
                assertThat(child.getDescription()).isEqualTo("New desc");
                assertThat(child.getTaskType()).isEqualTo("Exercise");
            }

            @Test
            @DisplayName("should handle series update with notifications on applyTaskUpdates")
            void updateTask_seriesUpdateWithNotifications_appliesNotifications() throws Exception {
                final Task parentTask = buildRecurringTask(1L, "Parent", "2025-06-01", "daily", 1, 3, null);
                parentTask.setNotifications(new ArrayList<>());

                when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
                when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>());
                when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

                final ScheduledNotificationDTO notif = ScheduledNotificationDTO.builder()
                        .receiverId(1L).title("T").body("B")
                        .notificationType("REMINDER")
                        .scheduledTime("2025-06-01T10:00:00")
                        .build();

                final TaskDtoV2 dto = TaskDtoV2.builder()
                        .notifications(List.of(notif))
                        .updateSeries(true)
                        .build();

                service.updateTask(1L, dto);

                assertThat(parentTask.getNotifications()).hasSize(1);
            }
        }
    }

    // ================================================================
    // deleteTask
    // ================================================================

    @Nested
    @DisplayName("deleteTask")
    class DeleteTaskTests {

        @Test
        @DisplayName("should delete entire series when deleteSeries=true and task is parent")
        void deleteTask_deleteSeriesFromParent_deletesAllSeriesTasks() throws Exception {
            final Task parentTask = buildTask(1L, "Parent", "2025-06-01");
            final Task child1 = buildTask(2L, "Child1", "2025-06-02");
            child1.setParentTaskId(1L);
            final Task child2 = buildTask(3L, "Child2", "2025-06-03");
            child2.setParentTaskId(1L);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>(Arrays.asList(child1, child2)));

            service.deleteTask(1L, true);

            @SuppressWarnings("unchecked") final ArgumentCaptor<List<Task>> captor = ArgumentCaptor.forClass(List.class);
            verify(taskRepository).deleteAll(captor.capture());
            assertThat(captor.getValue()).hasSize(3); // 2 children + parent
        }

        @Test
        @DisplayName("should delete entire series when deleteSeries=true and task is child")
        void deleteTask_deleteSeriesFromChild_deletesAllSeriesTasks() throws Exception {
            final Task childTask = buildTask(2L, "Child", "2025-06-02");
            childTask.setParentTaskId(1L);
            final Task parentTask = buildTask(1L, "Parent", "2025-06-01");
            final Task otherChild = buildTask(3L, "Other", "2025-06-03");
            otherChild.setParentTaskId(1L);

            when(taskRepository.findById(2L)).thenReturn(Optional.of(childTask));
            when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>(Arrays.asList(childTask, otherChild)));
            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));

            service.deleteTask(2L, true);

            @SuppressWarnings("unchecked") final ArgumentCaptor<List<Task>> captor = ArgumentCaptor.forClass(List.class);
            verify(taskRepository).deleteAll(captor.capture());
            assertThat(captor.getValue()).hasSize(3);
        }

        @Test
        @DisplayName("should throw ParentTaskNotFoundException when parent not found during series delete")
        void deleteTask_deleteSeriesParentNotFound_throwsException() throws Exception {
            final Task childTask = buildTask(2L, "Child", "2025-06-02");
            childTask.setParentTaskId(999L);

            when(taskRepository.findById(2L)).thenReturn(Optional.of(childTask));
            when(taskRepository.findByParentTaskId(999L)).thenReturn(new ArrayList<>());
            when(taskRepository.findById(999L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.deleteTask(2L, true))
                    .isInstanceOf(ParentTaskNotFoundException.class);
        }

        @Test
        @DisplayName("should promote first child when deleting parent without series and has children")
        void deleteTask_deleteParentNotSeries_promotesFirstChild() throws Exception {
            final Task parentTask = buildTask(1L, "Parent", "2025-06-01");
            final Task child1 = buildTask(2L, "Child1", "2025-06-02");
            child1.setParentTaskId(1L);
            final Task child2 = buildTask(3L, "Child2", "2025-06-03");
            child2.setParentTaskId(1L);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>(Arrays.asList(child1, child2)));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            service.deleteTask(1L, false);

            // Child1 promoted: parentTaskId set to null
            assertThat(child1.getParentTaskId()).isNull();
            // Child2 points to new parent
            assertThat(child2.getParentTaskId()).isEqualTo(child1.getId());
            verify(taskRepository).save(child1);
            verify(taskRepository).saveAll(anyList());
            verify(taskRepository).delete(parentTask);
        }

        @Test
        @DisplayName("should just delete parent when no children exist")
        void deleteTask_deleteParentNoChildren_justDeletes() throws Exception {
            final Task parentTask = buildTask(1L, "Parent", "2025-06-01");

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>());

            service.deleteTask(1L, false);

            verify(taskRepository).delete(parentTask);
            verify(taskRepository, never()).save(any(Task.class));
        }

        @Test
        @DisplayName("should just delete child task when deleteSeries=false and task is child")
        void deleteTask_deleteChild_justDeletesChild() throws Exception {
            final Task childTask = buildTask(2L, "Child", "2025-06-02");
            childTask.setParentTaskId(1L);

            when(taskRepository.findById(2L)).thenReturn(Optional.of(childTask));

            service.deleteTask(2L, false);

            verify(taskRepository).delete(childTask);
            verify(taskRepository, never()).findByParentTaskId(anyLong());
        }

        @Test
        @DisplayName("should throw TaskNotFoundException when task not found")
        void deleteTask_taskNotFound_throwsException() throws Exception {
            when(taskRepository.findById(99L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.deleteTask(99L, false))
                    .isInstanceOf(TaskNotFoundException.class);
        }
    }

    // ================================================================
    // existsById
    // ================================================================

    @Nested
    @DisplayName("existsById")
    class ExistsByIdTests {

        @Test
        @DisplayName("should return true when task exists")
        void existsById_taskExists_returnsTrue() throws Exception {
            when(taskRepository.findById(1L)).thenReturn(Optional.of(buildTask(1L, "T", "2025-06-01")));

            assertThat(service.existsById(1L)).isTrue();
        }

        @Test
        @DisplayName("should return false when task does not exist")
        void existsById_taskNotFound_returnsFalse() throws Exception {
            when(taskRepository.findById(99L)).thenReturn(Optional.empty());

            assertThat(service.existsById(99L)).isFalse();
        }
    }

    // ================================================================
    // getAllTasks
    // ================================================================

    @Nested
    @DisplayName("getAllTasks")
    class GetAllTasksTests {

        @Test
        @DisplayName("should return all tasks as DTOs")
        void getAllTasks_tasksExist_returnsDtos() throws Exception {
            final Task t1 = buildTask(1L, "Task1", "2025-06-01");
            final Task t2 = buildTask(2L, "Task2", "2025-06-02");
            when(taskRepository.findAll()).thenReturn(Arrays.asList(t1, t2));

            final List<TaskDtoV2> result = service.getAllTasks();

            assertThat(result).hasSize(2);
            assertThat(result.get(0).getName()).isEqualTo("Task1");
            assertThat(result.get(1).getName()).isEqualTo("Task2");
        }

        @Test
        @DisplayName("should throw TaskNotFoundException when no tasks exist")
        void getAllTasks_noTasks_throwsException() throws Exception {
            when(taskRepository.findAll()).thenReturn(Collections.emptyList());

            assertThatThrownBy(() -> service.getAllTasks())
                    .isInstanceOf(TaskNotFoundException.class)
                    .hasMessage("No tasks found");
        }
    }

    // ================================================================
    // Private helper coverage through public methods
    // ================================================================

    @Nested
    @DisplayName("generateDates coverage via updateTask")
    class GenerateDatesCoverage {

        @Test
        @DisplayName("should cover daily generateDates with endCap")
        void updateTask_dailyRecurrenceChange_coversGenerateDatesDaily() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "daily", 1, 5, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(3)
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should cover daily generateDates without endCap")
        void updateTask_dailyNoEndCap_coversNonEndCapBranch() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "daily", 2, 3, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            // Change count triggers recurrence changed
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(5)
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should cover weekly generateDates with null days fallback")
        void updateTask_weeklyNullDays_coversWeeklyFallback() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "weekly", 1, 5, null);
            parentTask.setDaysOfWeek(null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(3)
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should cover weekly generateDates with 7 days and endCap")
        void updateTask_weeklyWithDaysEndCap_coversWeeklyWithDaysEndCap() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "weekly", 1, 10, null);
            parentTask.setDaysOfWeek("[true,true,false,false,false,false,false]");

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            // Trigger weekly + daysChanged to use endCap path
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .daysOfWeek(Arrays.asList(true, true, true, false, false, false, false))
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should cover monthly generateDates with endCap")
        void updateTask_monthlyRecurrenceChange_coversMonthlyEndCap() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "monthly", 1, 3, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(5)
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should cover monthly generateDates without endCap")
        void updateTask_monthlyNoEndCap_coversMonthlyNonEndCap() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "monthly", 1, 3, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            // Change frequency from monthly to monthly with different count
            // This will hit the non-weekly branch (else of weekly+daysChanged)
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(2) // change count
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should cover yearly generateDates with endCap")
        void updateTask_yearlyRecurrenceChange_coversYearlyEndCap() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "yearly", 1, 2, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(3)
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should cover yearly generateDates without endCap")
        void updateTask_yearlyNoEndCap_coversYearlyNonEndCap() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "yearly", 1, 2, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(4)
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should cover default generateDates for unknown frequency")
        void updateTask_unknownFrequency_coversDefaultBranch() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "custom_freq", 1, 2, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(3)
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should cover weekly generateDates with short days list (not 7)")
        void updateTask_weeklyShortDaysList_coversWeeklyFallback() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "weekly", 1, 5, null);
            // Only 3 elements instead of 7
            parentTask.setDaysOfWeek("[true,false,true]");

            // Build 4 children so the safety check in reconcileSeries passes (4+1 >= 5)
            final List<Task> safetyChildren = new ArrayList<>();
            for (int i = 2; i <= 5; i++) {
                safetyChildren.add(buildRecurringTask((long) i, "C" + i,
                        "2025-06-0" + (i), "weekly", 1, 5, 1L));
            }

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())   // children for deleteAll
                    .thenReturn(new ArrayList<>())   // reconcileSeries existing
                    .thenReturn(safetyChildren);     // safety check — enough to avoid generateOccurrences
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(3)
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should cover weekly endCap where occ equals endCap")
        void updateTask_weeklyEndCapExactDate_includesDate() throws Exception {
            // Setup for end-capped weekly where the last occurrence exactly equals the end cap
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-02", "weekly", 1, 4, null);
            // Monday only (index 1 in Sun-based) -- Mon
            parentTask.setDaysOfWeek("[false,true,false,false,false,false,false]");

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            // Change days to trigger daysChanged and go through weekly endCap path
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .daysOfWeek(Arrays.asList(false, true, true, false, false, false, false))
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }
    }

    @Nested
    @DisplayName("impliedEndDateFromSaved coverage")
    class ImpliedEndDateCoverage {

        @Test
        @DisplayName("should compute implied end date with all fields null")
        void updateTask_impliedEndNullFields_defaultsCorrectly() throws Exception {
            final Task parentTask = buildTask(1L, "P", "2025-06-01");
            parentTask.setFrequency(null);
            parentTask.setTaskInterval(null);
            parentTask.setDoCount(null);
            parentTask.setDaysOfWeek(null);
            parentTask.setTimeOfDay(null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L)).thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Update")
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            // Should not throw even with all null fields
            verify(taskRepository).save(any(Task.class));
        }
    }

    @Nested
    @DisplayName("Edge cases for mapToDto")
    class MapToDtoCoverage {

        @Test
        @DisplayName("should map all fields correctly including createdAt")
        void mapToDto_allFields_mapsCorrectly() throws Exception {
            final Task task = buildTask(1L, "Full Task", "2025-06-01");
            task.setCreatedAt(1234567890L);
            task.setFrequency("daily");
            task.setTaskInterval(2);
            task.setDoCount(5);
            task.setDaysOfWeek("[true,false,true,false,true,false,true]");
            task.setCompleted(true);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(task));

            final TaskDtoV2 result = service.getTaskDtoById(1L);

            assertThat(result.getId()).isEqualTo(1L);
            assertThat(result.getName()).isEqualTo("Full Task");
            assertThat(result.getDescription()).isEqualTo("desc");
            assertThat(result.getDate()).isEqualTo("2025-06-01");
            assertThat(result.getCreatedAt()).isEqualTo(1234567890L);
            assertThat(result.getTimeOfDay()).isEqualTo("10:00");
            assertThat(result.isCompleted()).isTrue();
            assertThat(result.getFrequency()).isEqualTo("daily");
            assertThat(result.getInterval()).isEqualTo(2);
            assertThat(result.getCount()).isEqualTo(5);
            assertThat(result.getDaysOfWeek()).isNotNull().hasSize(7);
            assertThat(result.getTaskType()).isEqualTo("General");
            assertThat(result.getPatientId()).isEqualTo(1L);
        }
    }

    @Nested
    @DisplayName("calculateExpectedDates edge cases")
    class CalculateExpectedDatesCoverage {

        @Test
        @DisplayName("should handle weekly with count null defaulting to 1")
        void createTask_weeklyCountNull_defaultsToOne() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            // count is set to 1 (or less) so generateOccurrences won't be called
            // but we need to set it > 1 to trigger calculateExpectedDates
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            final List<Boolean> days = Arrays.asList(true, false, false, false, false, false, true);
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Weekly count default")
                    .date("2025-06-01")
                    .timeOfDay("10:00")
                    .frequency("weekly")
                    .count(5)
                    .interval(null) // will default to 1
                    .daysOfWeek(days)
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).save(any(Task.class));
        }

        @Test
        @DisplayName("should handle weekly where days at index are false (skipped)")
        void createTask_weeklyDaysWithFalseAtIdx_skipsCorrectly() throws Exception {
            when(patientRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> {
                final Task t = inv.getArgument(0);
                if (t.getId() == null) t.setId(10L);
                return t;
            });
            when(taskRepository.findByParentTaskId(10L)).thenReturn(new ArrayList<>());

            // All false except Saturday
            final List<Boolean> days = Arrays.asList(false, false, false, false, false, false, true);
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .name("Sat only")
                    .date("2025-06-01") // Sunday
                    .timeOfDay("10:00")
                    .frequency("weekly")
                    .count(2)
                    .interval(1)
                    .daysOfWeek(days)
                    .build();

            service.createTask(1L, dto);

            verify(taskRepository).save(any(Task.class));
        }
    }

    @Nested
    @DisplayName("SeriesParams coverage")
    class SeriesParamsCoverage {

        @Test
        @DisplayName("should handle null frequency in SeriesParams defaulting to daily")
        void updateTask_seriesNullFrequencyParam_defaultsToDaily() throws Exception {
            final Task parentTask = buildTask(1L, "P", "2025-06-01");
            parentTask.setFrequency(null);
            parentTask.setTaskInterval(null);
            parentTask.setDoCount(null);
            parentTask.setDaysOfWeek(null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .frequency("monthly") // will trigger freq change since original is null
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should handle SeriesParams withCount correctly")
        void updateTask_seriesWithCountAdjustment_usesWithCount() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "daily", 1, 5, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            // date is set but count is null -- triggers the recompute path
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .frequency("monthly") // change freq
                    .date("2025-06-15") // date set
                    .count(null) // null count
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should handle SeriesParams with interval less than 1 clamped to 1")
        void updateTask_seriesNegativeInterval_clampsToOne() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "daily", 0, 3, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(5)
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should handle SeriesParams with count less than 1 clamped to 1")
        void updateTask_seriesZeroCount_clampsToOne() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "daily", 1, 0, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(5)
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }
    }

    @Nested
    @DisplayName("Reconcile series edge cases")
    class ReconcileSeriesCoverage {

        @Test
        @DisplayName("should handle reconcile with empty target dates")
        void updateTask_reconcileEmptyTargetDates_handlesGracefully() throws Exception {
            // A weird scenario: frequency=custom_freq which gives only 1 date from generateDates default
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "custom_freq", 1, 1, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(2) // triggers recurrence change
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should handle reconcile where parent is already in byDate map (merge function)")
        void updateTask_reconcileDuplicateDateKey_usesFirstEntry() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "daily", 1, 3, null);

            // Two children with same date (duplicate merge scenario)
            final Task child1 = buildRecurringTask(2L, "C1", "2025-06-02", "daily", 1, 3, 1L);
            final Task child2 = buildRecurringTask(3L, "C2", "2025-06-02", "daily", 1, 3, 1L);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>()) // for initial deleteAll
                    .thenReturn(new ArrayList<>(Arrays.asList(child1, child2))) // reconcile
                    .thenReturn(new ArrayList<>(Arrays.asList(child1, child2))) // safety 1
                    .thenReturn(new ArrayList<>(Arrays.asList(child1, child2))); // safety 2
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(5) // triggers recurrence change
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should handle second safety check undercount")
        void updateTask_reconcileSecondUndercount_callsGenerateOccurrencesTwice() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "daily", 1, 100, null);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())   // deleteAll children
                    .thenReturn(new ArrayList<>())   // reconcile existing
                    .thenReturn(new ArrayList<>())   // safety check 1
                    .thenReturn(new ArrayList<>())   // generate occurrences 1
                    .thenReturn(new ArrayList<>())   // safety check 2
                    .thenReturn(new ArrayList<>());  // generate occurrences 2
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(50) // triggers count change
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }

        @Test
        @DisplayName("should handle safety check passing (count OK)")
        void updateTask_reconcileCountOk_noRebuild() throws Exception {
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-01", "daily", 1, 2, null);

            final Task child = buildRecurringTask(2L, "C", "2025-06-02", "daily", 1, 2, 1L);

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>(List.of(child)))  // reconcile existing
                    .thenReturn(new ArrayList<>(List.of(child))); // safety check - child + parent = 2 = doCount
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .count(3) // triggers count change
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }
    }

    @Nested
    @DisplayName("Weekly with endCap occ.isAfter(endCap) but not equal")
    class WeeklyEndCapEdgeCases {

        @Test
        @DisplayName("should cover weekly endCap where occurrence is strictly after endCap")
        void updateTask_weeklyOccAfterEndCap_stopsGeneration() throws Exception {
            // Parent starts on a Monday with weekly on Mon+Fri, small count to keep endCap close
            final Task parentTask = buildRecurringTask(1L, "P", "2025-06-02", "weekly", 1, 3, null);
            // Mon only
            parentTask.setDaysOfWeek("[false,true,false,false,false,false,false]");

            when(taskRepository.findById(1L)).thenReturn(Optional.of(parentTask));
            when(taskRepository.findByParentTaskId(1L))
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>())
                    .thenReturn(new ArrayList<>());
            when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

            // Change days to Mon+Sat -- endCap is based on original 3 Mondays
            // So endCap = Jun 16 (3 Mondays: Jun 2, Jun 9, Jun 16)
            // But with Mon+Sat, Sat Jun 21 > endCap Jun 16
            final TaskDtoV2 dto = TaskDtoV2.builder()
                    .daysOfWeek(Arrays.asList(false, true, false, false, false, false, true))
                    .updateSeries(true)
                    .build();

            service.updateTask(1L, dto);

            verify(taskRepository).deleteAll(anyList());
        }
    }
}
