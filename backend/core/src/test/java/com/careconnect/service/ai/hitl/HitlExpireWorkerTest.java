package com.careconnect.service.ai.hitl;

import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class HitlExpireWorkerTest {

    @Mock
    private HitlService hitlService;

    @Test
    @DisplayName("expireDueHolds stops after a short batch")
    void expireDueHolds_stopsWhenBatchNotFull() {
        when(hitlService.expireDueHolds(50)).thenReturn(12);
        final HitlExpireWorker worker = new HitlExpireWorker(hitlService, 50);

        worker.expireDueHolds();

        verify(hitlService, times(1)).expireDueHolds(50);
    }

    @Test
    @DisplayName("expireDueHolds drains full batches until a short one")
    void expireDueHolds_drainsMultiplePasses() {
        when(hitlService.expireDueHolds(100)).thenReturn(100, 100, 3);
        final HitlExpireWorker worker = new HitlExpireWorker(hitlService, 100);

        worker.expireDueHolds();

        verify(hitlService, times(3)).expireDueHolds(100);
    }

    @Test
    @DisplayName("batch size is clamped to at least 1")
    void constructor_clampsBatchSize() {
        when(hitlService.expireDueHolds(1)).thenReturn(0);
        final HitlExpireWorker worker = new HitlExpireWorker(hitlService, 0);

        worker.expireDueHolds();

        verify(hitlService).expireDueHolds(1);
    }

    @Test
    @DisplayName("expireDueHolds does not log when nothing expired")
    void expireDueHolds_noWorkIsQuiet() {
        when(hitlService.expireDueHolds(anyInt())).thenReturn(0);
        final HitlExpireWorker worker = new HitlExpireWorker(hitlService, 25);

        worker.expireDueHolds();

        verify(hitlService).expireDueHolds(25);
    }
}
