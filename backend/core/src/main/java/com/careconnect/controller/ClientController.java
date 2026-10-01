package com.careconnect.controller;

import com.careconnect.dto.BehavioralTrendDtos;
import com.careconnect.dto.CompetencyTrendDtos;
import com.careconnect.dto.ParticipationDtos;
import com.careconnect.dto.AuditLogDtos;
import com.careconnect.exception.AppException;
import com.careconnect.model.ActivityLog;
import com.careconnect.model.BehavioralIncident;
import com.careconnect.model.Caregiver;
import com.careconnect.model.ClientEvent;
import com.careconnect.model.IncidentAction;
import com.careconnect.model.IncidentReport;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.ActivityLogRepository;
import com.careconnect.repository.BehavioralIncidentRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.ClientEventRepository;
import com.careconnect.repository.IncidentReportRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.service.PatientService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.*;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.web.multipart.MultipartFile;

/**
 * Client-facing API (client = patient). Provides activities and related endpoints
 * so the frontend can call /v1/api/clients/{id}/activities.
 */
@RestController
@RequestMapping("/v1/api/clients")
public class ClientController {

    private static final double STATUS_MARGIN = 0.2;
    private static final Set<String> ADL_NAMES = Set.of(
            "bathing", "dressing", "toileting", "transferring", "mobility/ambulation",
            "eating", "personal hygiene & grooming");
    private static final Set<String> IADL_NAMES = Set.of(
            "meal preparation", "housekeeping", "laundry", "medication management",
            "money management", "transportation", "communication", "community participation",
            "shopping", "safety awareness");
    private static final int PARTICIPATION_TREND_MARGIN = 1;
    @Autowired
    private PatientService patientService;
    @Autowired
    private UserRepository userRepository;
    @Autowired
    private CaregiverPatientLinkService caregiverPatientLinkService;
    @Autowired
    private FamilyMemberService familyMemberService;
    @Autowired
    private CaregiverRepository caregiverRepository;
    @Autowired
    private BehavioralIncidentRepository behavioralIncidentRepository;
    @Autowired
    private IncidentReportRepository incidentReportRepository;
    @Autowired
    private ClientEventRepository clientEventRepository;
    @Autowired
    private ActivityLogRepository activityLogRepository;

    private static String deriveCategory(String activityName) {
        if (activityName == null || activityName.isBlank()) return "ADL";
        String normalized = activityName.trim().toLowerCase();
        if (ADL_NAMES.contains(normalized)) return "ADL";
        if (IADL_NAMES.contains(normalized)) return "IADL";
        return "ADL";
    }

    private static IncidentReport.IncidentType parseIncidentType(String raw) {
        String normalized = raw.trim().toUpperCase().replace(' ', '_');
        try {
            return IncidentReport.IncidentType.valueOf(normalized);
        } catch (IllegalArgumentException ex) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Unknown incident_type: " + raw);
        }
    }

    private User getCurrentUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        return userRepository.findByEmail(auth.getName())
                .orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated"));
    }

    private void validateAccessToPatient(Long patientId, User currentUser) {
        Patient patient = patientService.getPatientById(patientId);
        Long patientUserId = patient.getUser().getId();
        switch (currentUser.getRole()) {
            case PATIENT:
                if (!currentUser.getId().equals(patientUserId)) {
                    throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
                }
                break;
            case CAREGIVER:
                if (!caregiverPatientLinkService.hasAccessToPatient(currentUser.getId(), patientUserId)) {
                    throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
                }
                break;
            case FAMILY_MEMBER:
                if (!familyMemberService.hasAccessToPatient(currentUser.getId(), patientUserId)) {
                    throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
                }
                break;
            case ADMIN:
                break;
            default:
                throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
        }
    }

    private boolean isWithinRange(LocalDateTime ts, LocalDateTime start, LocalDateTime end) {
        if (ts == null) return false;
        if (start != null && ts.isBefore(start)) return false;
        if (end != null && ts.isAfter(end)) return false;
        return true;
    }

    private String formatUserName(User user) {
        if (user == null) return "Unknown caregiver";
        if (user.getName() != null && !user.getName().isEmpty()) {
            return user.getName();
        }
        if (user.getEmail() != null && !user.getEmail().isEmpty()) {
            return user.getEmail();
        }
        return "Unknown caregiver";
    }

    /**
     * Get activities enabled for this client (patient).
     * Returns a list of activities with id, name, category (ADL/IADL), icon URLs, enabled.
     * For now returns an empty list until activity definitions and client-activity links exist.
     */
    @GetMapping("/{id}/activities")
    public ResponseEntity<List<Map<String, Object>>> getClientActivities(@PathVariable("id") Long clientId) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);
        // TODO: load from activity + client_activity tables when they exist
        return ResponseEntity.ok(Collections.emptyList());
    }

    /**
     * Record a client-facing event (icon tap) for this client.
     * Body: { "activity_id": 123 }
     * caregiver_id comes from authenticated caregiver session.
     */
    @PostMapping("/{id}/events")
    public ResponseEntity<ClientEvent> createClientEvent(
            @PathVariable("id") Long clientId,
            @RequestBody Map<String, Object> body
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);

        Object activityRaw = body.get("activity_id");
        if (activityRaw == null || activityRaw.toString().trim().isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "activity_id is required");
        }
        Long activityId;
        try {
            activityId = Long.parseLong(activityRaw.toString());
        } catch (NumberFormatException e) {
            throw new AppException(HttpStatus.BAD_REQUEST, "activity_id must be a number");
        }

        Caregiver caregiver = caregiverRepository.findByUserId(currentUser.getId())
                .orElseThrow(() -> new AppException(HttpStatus.BAD_REQUEST, "Authenticated user is not a caregiver"));

        ClientEvent event = ClientEvent.builder()
                .clientId(clientId)
                .caregiverId(caregiver.getId())
                .activityId(activityId)
                .tappedAt(LocalDateTime.now())
                .createdBy(currentUser.getId()) // audit: always from session, never from request body
                .build();

        ClientEvent saved = clientEventRepository.save(event);
        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }

    /**
     * Get client event history (icon taps) for this client.
     */
    @GetMapping("/{id}/events")
    public ResponseEntity<List<ClientEvent>> listClientEvents(
            @PathVariable("id") Long clientId
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);
        List<ClientEvent> events = clientEventRepository.findByClientIdOrderByTappedAtDesc(clientId);
        return ResponseEntity.ok(events);
    }

    /**
     * Unified read-only audit log for this client, combining activity logs, behavioral incidents,
     * incident reports, and client events into a single chronological feed.
     * <p>
     * Optional filters:
     * - startDate / endDate: inclusive LocalDate range, applied to createdAt.
     * - type: one of ACTIVITY_LOG, BEHAVIORAL_INCIDENT, INCIDENT_REPORT, CLIENT_EVENT (or null for all).
     */
    @GetMapping("/{id}/audit-log")
    public ResponseEntity<List<AuditLogDtos.AuditLogItem>> getAuditLog(
            @PathVariable("id") Long clientId,
            @RequestParam(value = "startDate", required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(value = "endDate", required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate,
            @RequestParam(value = "type", required = false) String type
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);

        LocalDateTime startDateTime = startDate != null ? startDate.atStartOfDay() : null;
        LocalDateTime endDateTime = endDate != null ? endDate.plusDays(1).atStartOfDay().minusNanos(1) : null;
        String normalizedType = type != null ? type.trim().toUpperCase() : null;

        List<ActivityLog> activityLogs = activityLogRepository
                .findByClientIdOrderByCreatedAtDesc(clientId, org.springframework.data.domain.PageRequest.of(0, 1000));
        List<BehavioralIncident> behavioralIncidents = behavioralIncidentRepository
                .findByClientIdOrderByOccurredAtDesc(clientId);
        List<IncidentReport> incidentReports = incidentReportRepository
                .findByClientIdOrderByOccurredAtDesc(clientId);
        List<ClientEvent> clientEvents = clientEventRepository
                .findByClientIdOrderByTappedAtDesc(clientId);

        java.util.Set<Long> userIds = new java.util.HashSet<>();
        java.util.Set<Long> caregiverIdsForEvents = new java.util.HashSet<>();
        activityLogs.forEach(l -> {
            if (l.getCaregiverUserId() != null) userIds.add(l.getCaregiverUserId());
        });
        behavioralIncidents.forEach(b -> {
            if (b.getCreatedBy() != null) userIds.add(b.getCreatedBy());
        });
        incidentReports.forEach(r -> {
            if (r.getCreatedBy() != null) userIds.add(r.getCreatedBy());
        });
        clientEvents.forEach(e -> {
            if (e.getCaregiverId() != null) caregiverIdsForEvents.add(e.getCaregiverId());
        });

        Map<Long, Caregiver> caregiversById = caregiverIdsForEvents.isEmpty()
                ? Collections.emptyMap()
                : caregiverRepository.findAllById(caregiverIdsForEvents).stream()
                .collect(Collectors.toMap(Caregiver::getId, c -> c));

        caregiversById.values().forEach(c -> {
            if (c.getUser() != null && c.getUser().getId() != null) {
                userIds.add(c.getUser().getId());
            }
        });

        Map<Long, User> creators = userIds.isEmpty()
                ? Collections.emptyMap()
                : userRepository.findAllById(userIds).stream()
                .collect(Collectors.toMap(User::getId, u -> u));

        List<AuditLogDtos.AuditLogItem> items = new ArrayList<>();

        // ACTIVITY_LOG
        if (normalizedType == null || "ACTIVITY_LOG".equals(normalizedType)) {
            for (ActivityLog log : activityLogs) {
                LocalDateTime ts = log.getCreatedAt();
                if (!isWithinRange(ts, startDateTime, endDateTime)) continue;
                String caregiverName = formatUserName(creators.get(log.getCaregiverUserId()));
                String activityName = log.getActivityName() != null ? log.getActivityName()
                        : "Activity #" + log.getActivityId();
                String summary = "Activity log: " + activityName + " (score " + log.getCompetencyScore() + ")";
                items.add(AuditLogDtos.AuditLogItem.builder()
                        .type("ACTIVITY_LOG")
                        .summary(summary)
                        .caregiverName(caregiverName)
                        .createdAt(ts)
                        .build());
            }
        }

        // BEHAVIORAL_INCIDENT
        if (normalizedType == null || "BEHAVIORAL_INCIDENT".equals(normalizedType)) {
            for (BehavioralIncident inc : behavioralIncidents) {
                LocalDateTime ts = inc.getCreatedAt();
                if (!isWithinRange(ts, startDateTime, endDateTime)) continue;
                String caregiverName = formatUserName(creators.get(inc.getCreatedBy()));
                String summary = "Behavioral incident: " + inc.getObservedBehavior();
                items.add(AuditLogDtos.AuditLogItem.builder()
                        .type("BEHAVIORAL_INCIDENT")
                        .summary(summary)
                        .caregiverName(caregiverName)
                        .createdAt(ts)
                        .build());
            }
        }

        // INCIDENT_REPORT
        if (normalizedType == null || "INCIDENT_REPORT".equals(normalizedType)) {
            for (IncidentReport report : incidentReports) {
                LocalDateTime ts = report.getCreatedAt();
                if (!isWithinRange(ts, startDateTime, endDateTime)) continue;
                String caregiverName = formatUserName(creators.get(report.getCreatedBy()));
                String summary = "Incident report: " + report.getIncidentType() + " at " + report.getLocation();
                items.add(AuditLogDtos.AuditLogItem.builder()
                        .type("INCIDENT_REPORT")
                        .summary(summary)
                        .caregiverName(caregiverName)
                        .createdAt(ts)
                        .build());
            }
        }

        // CLIENT_EVENT
        if (normalizedType == null || "CLIENT_EVENT".equals(normalizedType)) {
            for (ClientEvent event : clientEvents) {
                LocalDateTime ts = event.getCreatedAt();
                if (!isWithinRange(ts, startDateTime, endDateTime)) continue;
                Caregiver cg = caregiversById.get(event.getCaregiverId());
                User cgUser = (cg != null) ? cg.getUser() : null;
                String caregiverName = formatUserName(cgUser);
                String summary = "Client event: activity #" + event.getActivityId() + " tapped";
                items.add(AuditLogDtos.AuditLogItem.builder()
                        .type("CLIENT_EVENT")
                        .summary(summary)
                        .caregiverName(caregiverName)
                        .createdAt(ts)
                        .build());
            }
        }

        items.sort(Comparator.comparing(AuditLogDtos.AuditLogItem::getCreatedAt).reversed());
        return ResponseEntity.ok(items);
    }

    /**
     * Get competency trend report: average competency score per activity per week.
     * Optional query params: startDate, endDate (ISO date). Default: last 8 weeks.
     * Status: IMPROVING = recent 2 weeks avg > prior 2 weeks by more than 0.2; DECLINING = lower by more than 0.2; STABLE otherwise.
     */
    @GetMapping("/{id}/reports/competency-trends")
    public ResponseEntity<CompetencyTrendDtos.CompetencyTrendsResponse> getCompetencyTrends(
            @PathVariable("id") Long clientId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);

        LocalDate end = endDate != null ? endDate : LocalDate.now();
        LocalDate start = startDate != null ? startDate : end.minusWeeks(8);
        if (!start.isBefore(end) && !start.equals(end)) {
            start = end.minusWeeks(8);
        }
        LocalDateTime rangeStart = start.atStartOfDay();
        LocalDateTime rangeEnd = end.plusDays(1).atStartOfDay();

        List<ActivityLog> logs = activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(
                clientId, rangeStart, rangeEnd);
        if (logs.isEmpty()) {
            return ResponseEntity.ok(new CompetencyTrendDtos.CompetencyTrendsResponse(
                    "STABLE", Collections.emptyList(), Collections.emptyList()));
        }

        // Group by (weekStart, activityId, activityName) -> list of logs
        Map<String, List<ActivityLog>> byWeekAndActivity = new LinkedHashMap<>();
        for (ActivityLog log : logs) {
            LocalDate d = log.getCreatedAt().toLocalDate();
            LocalDate weekStart = d.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
            String weekLabel = weekStart.format(DateTimeFormatter.ISO_LOCAL_DATE);
            Long aid = log.getActivityId();
            String name = log.getActivityName() != null && !log.getActivityName().isEmpty()
                    ? log.getActivityName() : "Activity " + aid;
            String key = weekLabel + "|" + aid + "|" + name;
            byWeekAndActivity.computeIfAbsent(key, k -> new ArrayList<>()).add(log);
        }

        List<String> weekLabels = byWeekAndActivity.keySet().stream()
                .map(k -> k.split("\\|")[0])
                .distinct()
                .sorted()
                .collect(Collectors.toList());

        Map<String, List<CompetencyTrendDtos.WeekDataPoint>> activityToPoints = new LinkedHashMap<>();
        for (Map.Entry<String, List<ActivityLog>> e : byWeekAndActivity.entrySet()) {
            String[] parts = e.getKey().split("\\|", 3);
            String weekStartDate = parts[0];
            Long activityId = Long.parseLong(parts[1]);
            String activityName = parts[2];
            List<ActivityLog> weekLogs = e.getValue();
            double avg = weekLogs.stream().mapToInt(ActivityLog::getCompetencyScore).average().orElse(0);
            int logCount = weekLogs.size();
            String actKey = activityId + "|" + activityName;
            activityToPoints.computeIfAbsent(actKey, k -> new ArrayList<>())
                    .add(new CompetencyTrendDtos.WeekDataPoint(weekStartDate, avg, logCount));
        }

        List<CompetencyTrendDtos.ActivityTrend> activityTrends = new ArrayList<>();
        for (Map.Entry<String, List<CompetencyTrendDtos.WeekDataPoint>> e : activityToPoints.entrySet()) {
            String[] parts = e.getKey().split("\\|", 2);
            List<CompetencyTrendDtos.WeekDataPoint> sorted = e.getValue().stream()
                    .sorted((a, b) -> a.getWeekStartDate().compareTo(b.getWeekStartDate()))
                    .collect(Collectors.toList());
            activityTrends.add(new CompetencyTrendDtos.ActivityTrend(
                    Long.parseLong(parts[0]), parts[1], sorted));
        }

        String status = computeCompetencyStatus(logs, weekLabels);
        return ResponseEntity.ok(new CompetencyTrendDtos.CompetencyTrendsResponse(status, weekLabels, activityTrends));
    }

    private String computeCompetencyStatus(List<ActivityLog> logs, List<String> weekLabels) {
        if (weekLabels.size() < 4) return "STABLE";
        String lastWeek = weekLabels.get(weekLabels.size() - 1);
        String prevWeek = weekLabels.get(weekLabels.size() - 2);
        String priorWeek1 = weekLabels.get(weekLabels.size() - 3);
        String priorWeek2 = weekLabels.get(weekLabels.size() - 4);
        double recentAvg = logs.stream()
                .filter(l -> {
                    LocalDate d = l.getCreatedAt().toLocalDate();
                    String w = d.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)).format(DateTimeFormatter.ISO_LOCAL_DATE);
                    return w.equals(lastWeek) || w.equals(prevWeek);
                })
                .mapToInt(ActivityLog::getCompetencyScore)
                .average().orElse(0);
        double priorAvg = logs.stream()
                .filter(l -> {
                    LocalDate d = l.getCreatedAt().toLocalDate();
                    String w = d.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)).format(DateTimeFormatter.ISO_LOCAL_DATE);
                    return w.equals(priorWeek1) || w.equals(priorWeek2);
                })
                .mapToInt(ActivityLog::getCompetencyScore)
                .average().orElse(0);
        if (recentAvg > priorAvg + STATUS_MARGIN) return "IMPROVING";
        if (recentAvg < priorAvg - STATUS_MARGIN) return "DECLINING";
        return "STABLE";
    }

    /**
     * Get behavioral incident frequency report: count per week, top 3 behavior keywords, trend.
     * Optional query params: startDate, endDate (default: last 8 weeks).
     * Trend: UP = last 2 weeks count > prior 2 weeks; DOWN = lower; STABLE otherwise.
     */
    @GetMapping("/{id}/reports/behavioral-trends")
    public ResponseEntity<BehavioralTrendDtos.BehavioralTrendsResponse> getBehavioralTrends(
            @PathVariable("id") Long clientId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);

        LocalDate end = endDate != null ? endDate : LocalDate.now();
        LocalDate start = startDate != null ? startDate : end.minusWeeks(8);
        if (!start.isBefore(end) && !start.equals(end)) {
            start = end.minusWeeks(8);
        }
        LocalDateTime rangeStart = start.atStartOfDay();
        LocalDateTime rangeEnd = end.plusDays(1).atStartOfDay();

        List<BehavioralIncident> incidents = behavioralIncidentRepository
                .findByClientIdAndOccurredAtBetweenOrderByOccurredAtAsc(clientId, rangeStart, rangeEnd);
        if (incidents.isEmpty()) {
            return ResponseEntity.ok(new BehavioralTrendDtos.BehavioralTrendsResponse(
                    "STABLE", Collections.emptyList(), Collections.emptyList()));
        }

        Map<String, Integer> countByWeek = new LinkedHashMap<>();
        for (BehavioralIncident inc : incidents) {
            LocalDate d = inc.getOccurredAt().toLocalDate();
            LocalDate weekStart = d.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
            String weekLabel = weekStart.format(DateTimeFormatter.ISO_LOCAL_DATE);
            countByWeek.merge(weekLabel, 1, Integer::sum);
        }
        List<String> sortedWeeks = countByWeek.keySet().stream().sorted().collect(Collectors.toList());
        List<BehavioralTrendDtos.WeekCount> weeklyCounts = sortedWeeks.stream()
                .map(w -> new BehavioralTrendDtos.WeekCount(w, countByWeek.get(w)))
                .collect(Collectors.toList());

        List<String> topKeywords = computeTopBehaviorKeywords(incidents, 3);
        String trend = computeBehavioralTrend(countByWeek, sortedWeeks);
        return ResponseEntity.ok(new BehavioralTrendDtos.BehavioralTrendsResponse(trend, weeklyCounts, topKeywords));
    }

    private List<String> computeTopBehaviorKeywords(List<BehavioralIncident> incidents, int limit) {
        java.util.Map<String, Integer> freq = new java.util.HashMap<>();
        java.util.Set<String> stopWords = java.util.Set.of("a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "is", "was", "are", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "must", "can", "this", "that", "it", "as", "by");
        for (BehavioralIncident inc : incidents) {
            String text = inc.getObservedBehavior() != null ? inc.getObservedBehavior() : "";
            String[] words = text.toLowerCase().split("[^a-z']+");
            for (String word : words) {
                String w = word.trim();
                if (w.length() >= 2 && !stopWords.contains(w)) {
                    freq.merge(w, 1, Integer::sum);
                }
            }
        }
        return freq.entrySet().stream()
                .sorted((a, b) -> Integer.compare(b.getValue(), a.getValue()))
                .limit(limit)
                .map(java.util.Map.Entry::getKey)
                .collect(Collectors.toList());
    }

    private String computeBehavioralTrend(Map<String, Integer> countByWeek, List<String> sortedWeeks) {
        if (sortedWeeks.size() < 4) return "STABLE";
        int lastTwo = countByWeek.getOrDefault(sortedWeeks.get(sortedWeeks.size() - 1), 0)
                + countByWeek.getOrDefault(sortedWeeks.get(sortedWeeks.size() - 2), 0);
        int priorTwo = countByWeek.getOrDefault(sortedWeeks.get(sortedWeeks.size() - 3), 0)
                + countByWeek.getOrDefault(sortedWeeks.get(sortedWeeks.size() - 4), 0);
        if (lastTwo > priorTwo) return "UP";
        if (lastTwo < priorTwo) return "DOWN";
        return "STABLE";
    }

    /**
     * Get activity participation report: per-activity log counts and last logged, with no-recent-activity flag.
     * Optional query params: startDate, endDate (default: last 4 weeks).
     * noRecentActivity = true when no logs in the past 7 days.
     */
    @GetMapping("/{id}/reports/participation")
    public ResponseEntity<ParticipationDtos.ParticipationResponse> getParticipation(
            @PathVariable("id") Long clientId,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);

        LocalDate end = endDate != null ? endDate : LocalDate.now();
        LocalDate start = startDate != null ? startDate : end.minusWeeks(4);
        if (!start.isBefore(end) && !start.equals(end)) {
            start = end.minusWeeks(4);
        }
        LocalDateTime rangeStart = start.atStartOfDay();
        LocalDateTime rangeEnd = end.plusDays(1).atStartOfDay();
        LocalDateTime sevenDaysAgo = LocalDateTime.now().minusDays(7);

        List<ActivityLog> logs = activityLogRepository.findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(
                clientId, rangeStart, rangeEnd);

        Map<String, Integer> countByWeek = new LinkedHashMap<>();
        for (ActivityLog log : logs) {
            LocalDate d = log.getCreatedAt().toLocalDate();
            LocalDate weekStart = d.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
            String weekLabel = weekStart.format(DateTimeFormatter.ISO_LOCAL_DATE);
            countByWeek.merge(weekLabel, 1, Integer::sum);
        }
        List<String> sortedWeeks = countByWeek.keySet().stream().sorted().collect(Collectors.toList());
        List<ParticipationDtos.WeekCount> weeklyCounts = sortedWeeks.stream()
                .map(w -> new ParticipationDtos.WeekCount(w, countByWeek.get(w)))
                .collect(Collectors.toList());

        Map<String, List<ActivityLog>> byActivity = new LinkedHashMap<>();
        for (ActivityLog log : logs) {
            Long aid = log.getActivityId();
            String name = log.getActivityName() != null && !log.getActivityName().isEmpty()
                    ? log.getActivityName() : "Activity " + aid;
            String key = aid + "|" + name;
            byActivity.computeIfAbsent(key, k -> new ArrayList<>()).add(log);
        }

        List<ParticipationDtos.ActivityParticipation> activities = new ArrayList<>();
        for (Map.Entry<String, List<ActivityLog>> e : byActivity.entrySet()) {
            String[] parts = e.getKey().split("\\|", 2);
            Long activityId = Long.parseLong(parts[0]);
            String activityName = parts[1];
            List<ActivityLog> groupLogs = e.getValue();
            int totalLogsInPeriod = groupLogs.size();
            LocalDateTime lastLoggedAt = groupLogs.stream()
                    .map(ActivityLog::getCreatedAt)
                    .max(LocalDateTime::compareTo)
                    .orElse(null);
            boolean noRecentActivity = lastLoggedAt == null || lastLoggedAt.isBefore(sevenDaysAgo);
            String category = deriveCategory(activityName);
            activities.add(new ParticipationDtos.ActivityParticipation(
                    activityId, activityName, category, totalLogsInPeriod, lastLoggedAt, noRecentActivity));
        }
        activities.sort((a, b) -> {
            int cat = a.getCategory().compareTo(b.getCategory());
            if (cat != 0) return cat;
            return a.getActivityName().compareToIgnoreCase(b.getActivityName());
        });
        String status = computeParticipationStatus(countByWeek, sortedWeeks);
        return ResponseEntity.ok(new ParticipationDtos.ParticipationResponse(status, weeklyCounts, activities));
    }

    private String computeParticipationStatus(Map<String, Integer> countByWeek, List<String> sortedWeeks) {
        if (sortedWeeks.size() < 4) return "STABLE";
        int lastTwo = countByWeek.getOrDefault(sortedWeeks.get(sortedWeeks.size() - 1), 0)
                + countByWeek.getOrDefault(sortedWeeks.get(sortedWeeks.size() - 2), 0);
        int priorTwo = countByWeek.getOrDefault(sortedWeeks.get(sortedWeeks.size() - 3), 0)
                + countByWeek.getOrDefault(sortedWeeks.get(sortedWeeks.size() - 4), 0);
        if (lastTwo > priorTwo + PARTICIPATION_TREND_MARGIN) return "IMPROVING";
        if (lastTwo < priorTwo - PARTICIPATION_TREND_MARGIN) return "DECLINING";
        return "STABLE";
    }

    /**
     * Create a new behavioral incident for this client (append-only).
     * Body: { "observed_behavior": "...", "occurred_at": "ISO8601", "trigger_notes": "..." }
     * caregiver_id and created_by are always derived from the authenticated user session.
     */
    @PostMapping("/{id}/behavioral-incidents")
    public ResponseEntity<BehavioralIncident> createBehavioralIncident(
            @PathVariable("id") Long clientId,
            @RequestBody Map<String, Object> body
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);

        Object observedRaw = body.get("observed_behavior");
        if (observedRaw == null || observedRaw.toString().trim().isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "observed_behavior is required");
        }
        String observedBehavior = observedRaw.toString().trim();

        LocalDateTime occurredAt = null;
        Object occurredRaw = body.get("occurred_at");
        if (occurredRaw != null) {
            try {
                occurredAt = LocalDateTime.parse(occurredRaw.toString());
            } catch (Exception e) {
                throw new AppException(HttpStatus.BAD_REQUEST, "occurred_at must be ISO-8601 datetime");
            }
        }
        if (occurredAt == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "occurred_at is required");
        }

        String triggerNotes = null;
        Object triggerRaw = body.get("trigger_notes");
        if (triggerRaw != null && !triggerRaw.toString().trim().isEmpty()) {
            triggerNotes = triggerRaw.toString().trim();
        }

        // Resolve caregiver_id from the authenticated user (must be a caregiver)
        Caregiver caregiver = caregiverRepository.findByUserId(currentUser.getId())
                .orElseThrow(() -> new AppException(HttpStatus.BAD_REQUEST, "Authenticated user is not a caregiver"));

        BehavioralIncident incident = BehavioralIncident.builder()
                .clientId(clientId)
                .caregiverId(caregiver.getId())
                .observedBehavior(observedBehavior)
                .occurredAt(occurredAt)
                .triggerNotes(triggerNotes)
                .createdBy(currentUser.getId())
                .build();

        BehavioralIncident saved = behavioralIncidentRepository.save(incident);
        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }

    /**
     * Get all behavioral incidents for this client, most recent first.
     */
    @GetMapping("/{id}/behavioral-incidents")
    public ResponseEntity<List<BehavioralIncident>> listBehavioralIncidents(
            @PathVariable("id") Long clientId
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);
        List<BehavioralIncident> list = behavioralIncidentRepository
                .findByClientIdOrderByOccurredAtDesc(clientId);
        return ResponseEntity.ok(list);
    }

    /**
     * Get a single behavioral incident in full detail.
     */
    @GetMapping("/{id}/behavioral-incidents/{incidentId}")
    public ResponseEntity<BehavioralIncident> getBehavioralIncident(
            @PathVariable("id") Long clientId,
            @PathVariable Long incidentId
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);
        BehavioralIncident incident = behavioralIncidentRepository.findById(incidentId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Incident not found"));
        if (!incident.getClientId().equals(clientId)) {
            throw new AppException(HttpStatus.FORBIDDEN, "Incident does not belong to this client");
        }
        return ResponseEntity.ok(incident);
    }

    /**
     * Create a structured incident report for this client (append-only).
     * Body: { incident_type, occurred_at, location, trigger_notes?, actions_taken: [..], outcome }
     * caregiver_id and created_by are always derived from the authenticated user session.
     */
    @PostMapping("/{id}/incident-reports")
    public ResponseEntity<IncidentReport> createIncidentReport(
            @PathVariable("id") Long clientId,
            @RequestBody Map<String, Object> body
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);

        Object typeRaw = body.get("incident_type");
        if (typeRaw == null || typeRaw.toString().trim().isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "incident_type is required");
        }
        IncidentReport.IncidentType type = parseIncidentType(typeRaw.toString());

        LocalDateTime occurredAt = null;
        Object occurredRaw = body.get("occurred_at");
        if (occurredRaw != null) {
            try {
                occurredAt = LocalDateTime.parse(occurredRaw.toString());
            } catch (Exception e) {
                throw new AppException(HttpStatus.BAD_REQUEST, "occurred_at must be ISO-8601 datetime");
            }
        }
        if (occurredAt == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "occurred_at is required");
        }

        Object locationRaw = body.get("location");
        if (locationRaw == null || locationRaw.toString().trim().isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "location is required");
        }
        String location = locationRaw.toString().trim();

        String triggerNotes = null;
        Object triggerRaw = body.get("trigger_notes");
        if (triggerRaw != null && !triggerRaw.toString().trim().isEmpty()) {
            triggerNotes = triggerRaw.toString().trim();
        }

        Object outcomeRaw = body.get("outcome");
        if (outcomeRaw == null || outcomeRaw.toString().trim().isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "outcome is required");
        }
        String outcome = outcomeRaw.toString().trim();

        // Resolve caregiver_id from the authenticated user (must be a caregiver)
        Caregiver caregiver = caregiverRepository.findByUserId(currentUser.getId())
                .orElseThrow(() -> new AppException(HttpStatus.BAD_REQUEST, "Authenticated user is not a caregiver"));

        IncidentReport report = IncidentReport.builder()
                .clientId(clientId)
                .caregiverId(caregiver.getId())
                .incidentType(type)
                .occurredAt(occurredAt)
                .location(location)
                .triggerNotes(triggerNotes)
                .outcome(outcome)
                .createdBy(currentUser.getId())
                .build();

        Object actionsRaw = body.get("actions_taken");
        if (actionsRaw instanceof Iterable<?>) {
            for (Object o : (Iterable<?>) actionsRaw) {
                if (o == null) continue;
                String text = o.toString().trim();
                if (text.isEmpty()) continue;
                IncidentAction action = IncidentAction.builder()
                        .incidentReport(report)
                        .actionTaken(text)
                        .build();
                report.getActions().add(action);
            }
        }

        IncidentReport saved = incidentReportRepository.save(report);
        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }

    /**
     * Get all incident reports for this client, most recent first.
     */
    @GetMapping("/{id}/incident-reports")
    public ResponseEntity<List<IncidentReport>> listIncidentReports(
            @PathVariable("id") Long clientId
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);
        List<IncidentReport> list = incidentReportRepository
                .findByClientIdOrderByOccurredAtDesc(clientId);
        return ResponseEntity.ok(list);
    }

    /**
     * Get a single incident report with all actions.
     */
    @GetMapping("/{id}/incident-reports/{reportId}")
    public ResponseEntity<IncidentReport> getIncidentReport(
            @PathVariable("id") Long clientId,
            @PathVariable Long reportId
    ) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);
        IncidentReport report = incidentReportRepository.findById(reportId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Incident report not found"));
        if (!report.getClientId().equals(clientId)) {
            throw new AppException(HttpStatus.FORBIDDEN, "Incident does not belong to this client");
        }
        return ResponseEntity.ok(report);
    }

    /**
     * Enable or disable an activity for this client.
     * Body: { "isEnabled": true | false }
     */
    @PutMapping("/{id}/activity-config/{activityId}")
    public ResponseEntity<Void> putActivityConfig(
            @PathVariable("id") Long clientId,
            @PathVariable Long activityId,
            @RequestBody Map<String, Object> body) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);
        // TODO: persist when client_activity_config exists
        return ResponseEntity.ok().build();
    }

    /**
     * Upload custom icon for a client's activity config.
     */
    @PostMapping("/{id}/activity-config/{activityId}/icon")
    public ResponseEntity<Map<String, String>> postActivityIcon(
            @PathVariable("id") Long clientId,
            @PathVariable Long activityId,
            @RequestParam("file") MultipartFile file) {
        User currentUser = getCurrentUser();
        validateAccessToPatient(clientId, currentUser);
        // TODO: store file and return iconUrl when implemented
        return ResponseEntity.ok(Collections.singletonMap("iconUrl", "/placeholder-icon"));
    }
}
