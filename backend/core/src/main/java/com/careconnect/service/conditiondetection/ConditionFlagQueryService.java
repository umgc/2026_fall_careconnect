package com.careconnect.service.conditiondetection;

import com.careconnect.dto.conditiondetection.ConditionFlagsResponse;
import com.careconnect.model.CallSession;
import com.careconnect.model.User;
import com.careconnect.model.conditiondetection.ConditionDetectionRun;
import com.careconnect.model.conditiondetection.ConditionFlag;
import com.careconnect.model.conditiondetection.ConditionRunState;
import com.careconnect.repository.conditiondetection.ConditionDetectionRunRepository;
import com.careconnect.repository.conditiondetection.ConditionFlagRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CallSessionService;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Reads a call's condition screening for the post-call screen. Patients are always refused,
 * including for their own calls; caregivers and family members need an active link to the
 * patient, and admins may read any call.
 */
@Service
@RequiredArgsConstructor
public class ConditionFlagQueryService {

    static final String STATUS_PENDING = "PENDING";
    static final String STATUS_PROCESSING = "PROCESSING";

    private final ConditionDetectionRunRepository runRepository;
    private final ConditionFlagRepository flagRepository;
    private final ConditionDetectionService detectionService;
    private final CallSessionService callSessionService;
    private final AuthorizationService authorizationService;

    @Transactional(readOnly = true)
    public ConditionFlagsResponse getFlags(final User user, final String callId)
            throws UnauthorizedException {
        if (user == null) {
            throw new UnauthorizedException("User is not authenticated");
        }
        if (user.isPatient()) {
            throw new UnauthorizedException("Patients cannot view condition screening flags");
        }
        final CallSession session = callSessionService.requireSession(callId);
        authorizationService.requirePatientAccess(user, callSessionService.requirePatientUserId(session));

        final List<ConditionModelAdapter> adapters =
                detectionService.isEnabled() ? detectionService.adapters() : List.of();
        final Map<String, ConditionModelAdapter> adaptersById = adapters.stream()
                .collect(Collectors.toMap(ConditionModelAdapter::modelId, a -> a, (a, b) -> a));
        final Map<Long, List<ConditionFlag>> flagsByRun = flagRepository.findByCallIdOrderByIdAsc(callId)
                .stream()
                .collect(Collectors.groupingBy(ConditionFlag::getRunId));

        final List<ConditionFlagsResponse.ModelRun> result = new ArrayList<>();
        final Set<String> seen = new HashSet<>();
        for (final ConditionDetectionRun run : runRepository.findByCallIdOrderByIdAsc(callId)) {
            seen.add(run.getModelId());
            result.add(toModelRun(run, adaptersById.get(run.getModelId()),
                    flagsByRun.getOrDefault(run.getId(), List.of())));
        }
        // Enabled models with no run yet: the call just ended and enqueue has not happened.
        for (final ConditionModelAdapter adapter : adapters) {
            if (!seen.contains(adapter.modelId())) {
                result.add(new ConditionFlagsResponse.ModelRun(
                        adapter.modelId(), adapter.displayName(), adapter.inputKind().name(),
                        STATUS_PENDING, null, null, List.of()));
            }
        }
        return new ConditionFlagsResponse(ConditionScreeningCopy.DISCLAIMER_EN, result);
    }

    private static ConditionFlagsResponse.ModelRun toModelRun(
            final ConditionDetectionRun run,
            final ConditionModelAdapter adapter,
            final List<ConditionFlag> flags) {
        final boolean complete = run.getState() == ConditionRunState.COMPLETE;
        return new ConditionFlagsResponse.ModelRun(
                run.getModelId(),
                adapter == null ? run.getModelId() : adapter.displayName(),
                run.getInputKind().name(),
                publicStatus(run.getState()),
                run.getSkipReason() == null ? null : run.getSkipReason().name(),
                run.getCompletedAt() == null
                        ? null : run.getCompletedAt().toInstant(ZoneOffset.UTC).toString(),
                complete ? flags.stream().map(ConditionFlagQueryService::toFlag).toList() : List.of());
    }

    static String publicStatus(final ConditionRunState state) {
        return switch (state) {
            case READY -> STATUS_PENDING;
            case CLAIMED, RUNNING, RETRYABLE -> STATUS_PROCESSING;
            case COMPLETE, SKIPPED, FAILED -> state.name();
        };
    }

    private static ConditionFlagsResponse.Flag toFlag(final ConditionFlag flag) {
        return new ConditionFlagsResponse.Flag(
                flag.getConditionName().name(),
                flag.getSeverityLevel(),
                flag.getSeverityLabel(),
                flag.getEvidenceSummary());
    }
}
