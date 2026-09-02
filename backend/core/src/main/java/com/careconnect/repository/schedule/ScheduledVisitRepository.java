package com.careconnect.repository.schedule;

import com.careconnect.model.schedule.ScheduledVisit;

import com.careconnect.model.schedule.ScheduledVisitAudit;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;

@Repository
public interface ScheduledVisitRepository extends JpaRepository<ScheduledVisit, Long> {

    List<ScheduledVisit> findByCaregiverId(Long caregiverId);

    List<ScheduledVisit> findByCaregiverIdAndScheduledDate(Long caregiverId, LocalDate date);

    List<ScheduledVisit> findByCaregiverIdAndScheduledDateBetween(
            Long caregiverId,
            LocalDate startDate,
            LocalDate endDate);

    List<ScheduledVisit> findByCaregiverIdAndStatus(Long caregiverId, String status);

    @Query("SELECT COUNT(v) FROM ScheduledVisit v WHERE v.caregiverId = :caregiverId " +
            "AND (v.scheduledDate < :today OR (v.scheduledDate = :today AND v.scheduledTime < :currentTime)) "
            +
            "AND v.status = 'Scheduled'")
    long countOverdueVisits(@Param("caregiverId") Long caregiverId,
                            @Param("today") LocalDate today,
                            @Param("currentTime") LocalTime currentTime);

    @Query("SELECT COUNT(v) FROM ScheduledVisit v WHERE v.caregiverId = :caregiverId " +
            "AND v.scheduledDate = :today " +
            "AND v.scheduledTime <= :timeThreshold " +
            "AND v.status = 'Scheduled'")
    long countReadyVisits(@Param("caregiverId") Long caregiverId,
                          @Param("today") LocalDate today,
                          @Param("timeThreshold") LocalTime timeThreshold);

    @Query("SELECT COUNT(v) FROM ScheduledVisit v WHERE v.caregiverId = :caregiverId " +
            "AND ((v.scheduledDate = :today AND v.scheduledTime > :timeThreshold) " +
            "OR v.scheduledDate > :today) " +
            "AND v.status = 'Scheduled'")
    long countUpcomingVisits(@Param("caregiverId") Long caregiverId,
                             @Param("today") LocalDate today,
                             @Param("timeThreshold") LocalTime timeThreshold);

    @Query("SELECT COUNT(v) FROM ScheduledVisit v WHERE v.caregiverId = :caregiverId " +
            "AND v.scheduledDate = :today")
    long countTodayVisits(@Param("caregiverId") Long caregiverId,
                          @Param("today") LocalDate today);

    @Query("SELECT v FROM ScheduledVisit v WHERE v.caregiverId = :caregiverId " +
            "AND (v.scheduledDate < :today OR (v.scheduledDate = :today AND v.scheduledTime < :currentTime)) "
            +
            "AND v.status = 'Scheduled' " +
            "ORDER BY v.scheduledDate ASC, v.scheduledTime ASC")
    List<ScheduledVisit> findOverdueVisits(@Param("caregiverId") Long caregiverId,
                                           @Param("today") LocalDate today,
                                           @Param("currentTime") LocalTime currentTime);

    @Query("SELECT v FROM ScheduledVisit v WHERE v.caregiverId = :caregiverId " +
            "AND v.scheduledDate = :today " +
            "AND v.scheduledTime <= :timeThreshold " +
            "AND v.status = 'Scheduled' " +
            "ORDER BY v.scheduledTime ASC")
    List<ScheduledVisit> findReadyVisits(@Param("caregiverId") Long caregiverId,
                                         @Param("today") LocalDate today,
                                         @Param("timeThreshold") LocalTime timeThreshold);

    @Query("SELECT v FROM ScheduledVisit v WHERE v.caregiverId = :caregiverId " +
            "AND ((v.scheduledDate = :today AND v.scheduledTime > :timeThreshold) " +
            "OR v.scheduledDate > :today) " +
            "AND v.status = 'Scheduled' " +
            "ORDER BY v.scheduledDate ASC, v.scheduledTime ASC")
    List<ScheduledVisit> findUpcomingVisits(@Param("caregiverId") Long caregiverId,
                                            @Param("today") LocalDate today,
                                            @Param("timeThreshold") LocalTime timeThreshold);

    @Query("""
                SELECT sv FROM ScheduledVisit sv
                WHERE sv.caregiverId = :caregiverId
                AND sv.scheduledDate = :date
                AND sv.status != 'Cancelled'
                AND sv.scheduledTime < :endTime
            """)
    List<ScheduledVisit> findConflictingVisits(
            @Param("caregiverId") Long caregiverId,
            @Param("date") LocalDate date,
            @Param("startTime") LocalTime startTime,
            @Param("endTime") LocalTime endTime);

    @Query("SELECT COUNT(*) FROM ScheduledVisit WHERE caregiverId = :caregiverId AND scheduledDate = :date")
    long countVisitsOnDate(Long caregiverId, LocalDate date);

    @Query("""
                SELECT sva FROM ScheduledVisitAudit sva
                WHERE sva.visitId = :visitId
                ORDER BY sva.changedAt DESC
            """)
    List<ScheduledVisitAudit> findAuditHistory(@Param("visitId") Long visitId);

    @Query("SELECT sv FROM ScheduledVisit sv WHERE sv.patientId = :patientId")
    List<ScheduledVisit> findByPatientId(@Param("patientId") Long patientId);

    List<ScheduledVisit> findByPatientIdAndScheduledDateBetween(
            Long patientId,
            LocalDate startDate,
            LocalDate endDate);

    @Query("SELECT COUNT(sv) FROM ScheduledVisit sv WHERE sv.caregiverId = :caregiverId AND sv.scheduledDate = :date AND sv.status != :status")
    long countByCaregiverIdAndScheduledDateAndStatusNot(@Param("caregiverId") Long caregiverId, @Param("date") LocalDate date, @Param("status") String status);

}
