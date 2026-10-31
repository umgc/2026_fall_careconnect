package com.careconnect.repository.conditiondetection;

import static org.assertj.core.api.Assertions.assertThat;

import com.careconnect.model.CallSession;
import com.careconnect.model.conditiondetection.ConditionDetectionRun;
import com.careconnect.model.conditiondetection.ConditionInputKind;
import com.careconnect.model.conditiondetection.ConditionRunState;
import com.careconnect.repository.projection.ConditionDueRunProjection;
import com.careconnect.testsupport.fixtures.ConditionDetectionFixtures;
import jakarta.persistence.EntityManager;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * Runs the worker's native queries against the in-memory test database: fair due-run selection
 * (a voice backlog must not starve transcript screening) and the reconciliation query that finds
 * ended calls whose runs termination failed to create. Times are set with database-clock SQL,
 * as production writes them, so no host time-zone shift affects what counts as due or recent.
 */
@DataJpaTest
@ActiveProfiles("test")
class ConditionDetectionRunRepositoryTest {

    private static final String DAM = "kintsugi-dam-3.1";
    private static final String BEDROCK = "bedrock-transcript-screen-v1";

    @Autowired
    private ConditionDetectionRunRepository repository;

    @Autowired
    private EntityManager entityManager;

    /** A run of {@code modelId} for {@code callId}, due now by the database clock. */
    private ConditionDetectionRun dueRun(final String callId, final String modelId) {
        final ConditionDetectionRun run = newRun(callId, modelId, ConditionRunState.READY);
        repository.markDueNow(run.getId());
        return run;
    }

    private ConditionDetectionRun newRun(final String callId, final String modelId, final ConditionRunState state) {
        final ConditionDetectionRun run = new ConditionDetectionRun();
        run.setCallId(callId);
        run.setPatientId(ConditionDetectionFixtures.PATIENT_ID);
        run.setPatientUserId(ConditionDetectionFixtures.PATIENT_USER_ID);
        run.setModelId(modelId);
        run.setInputKind(DAM.equals(modelId) ? ConditionInputKind.PATIENT_AUDIO : ConditionInputKind.TRANSCRIPT);
        run.setState(state);
        return repository.saveAndFlush(run);
    }

    /** A session in {@code status} that ended {@code hoursAgo} hours ago by the database clock. */
    private void session(final String callId, final String status, final int hoursAgo) {
        final CallSession session = new CallSession();
        session.setCallId(callId);
        session.setPatientId(ConditionDetectionFixtures.PATIENT_ID);
        session.setCreatedByUserId(ConditionDetectionFixtures.CAREGIVER_USER_ID);
        session.setStatus(status);
        entityManager.persist(session);
        entityManager.flush();
        entityManager.createNativeQuery(
                        "UPDATE call_sessions SET ended_at = CURRENT_TIMESTAMP - (CAST(:h AS INTEGER) * INTERVAL '1' HOUR)"
                                + " WHERE call_id = :callId")
                .setParameter("h", hoursAgo)
                .setParameter("callId", callId)
                .executeUpdate();
    }

    // -------------------------------------------------------------- findDueRuns

    /**
     * The reviewer's backlog scenario against the real SQL: twelve voice runs (more than one
     * window) are due before a transcript run. Both models are reported as having due work, the
     * transcript run is fetched in its own model's window, and voice is capped at ten.
     */
    @Test
    void findDueRuns_voiceBacklog_doesNotStarveTranscriptRun() {
        // Arrange: voice runs first, so they are older (same due time, lower ids).
        for (int i = 0; i < 12; i++) {
            dueRun("call-" + i, DAM);
        }
        final ConditionDetectionRun transcript = dueRun("call-0", BEDROCK);

        // Act
        final List<String> models = repository.findDueModelIds();
        final List<ConditionDueRunProjection> voice = repository.findDueRuns(DAM);
        final List<ConditionDueRunProjection> text = repository.findDueRuns(BEDROCK);

        // Assert
        assertThat(models).containsExactlyInAnyOrder(DAM, BEDROCK);
        assertThat(voice).hasSize(10).allMatch(d -> DAM.equals(d.getModelId()));
        assertThat(text).extracting(d -> d.getId().longValue()).containsExactly(transcript.getId());
    }

    /** Finished runs and runs whose next attempt is in the future are not due. */
    @Test
    void findDueRuns_excludesFinishedAndFutureRuns() {
        // Arrange
        newRun("call-done", DAM, ConditionRunState.COMPLETE);
        final ConditionDetectionRun later = newRun("call-later", DAM, ConditionRunState.READY);
        entityManager.createNativeQuery(
                        "UPDATE condition_detection_runs SET next_attempt_at = CURRENT_TIMESTAMP + (1 * INTERVAL '1' HOUR)"
                                + " WHERE id = :id")
                .setParameter("id", later.getId())
                .executeUpdate();
        final ConditionDetectionRun now = dueRun("call-now", DAM);

        // Act + Assert
        assertThat(repository.findDueRuns(DAM)).extracting(d -> d.getId().longValue())
                .containsExactly(now.getId());
    }

    // ------------------------------------------------- findEndedCallsMissingRuns

    /**
     * Only fully ended calls inside the lookback that lack a run for some enabled model are
     * returned: not one with every model's run, not one still terminating (its recording may not
     * be final), and not one that ended before the window.
     */
    @Test
    void findEndedCallsMissingRuns_returnsOnlyRecentEndedCallsMissingAModel() {
        // Arrange
        session("no-runs", "ENDED", 1);
        session("partial", "ENDED", 2);
        dueRun("partial", DAM);
        session("complete", "ENDED", 1);
        dueRun("complete", DAM);
        dueRun("complete", BEDROCK);
        session("terminating", "TERMINATING", 1);
        session("too-old", "ENDED", 30);

        // Act
        final List<String> missing = repository.findEndedCallsMissingRuns(24, List.of(DAM, BEDROCK), 2);

        // Assert: oldest end first.
        assertThat(missing).containsExactly("partial", "no-runs");
    }

    /** A run for a model that is no longer enabled does not count toward the enabled models. */
    @Test
    void findEndedCallsMissingRuns_ignoresRunsOfDisabledModels() {
        session("old-model-only", "ENDED", 1);
        dueRun("old-model-only", "retired-model");

        assertThat(repository.findEndedCallsMissingRuns(24, List.of(DAM), 1))
                .containsExactly("old-model-only");
    }
}
