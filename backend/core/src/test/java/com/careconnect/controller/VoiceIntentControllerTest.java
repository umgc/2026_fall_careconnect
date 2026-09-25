package com.careconnect.controller;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.careconnect.dto.VoiceIntentRequest;
import com.careconnect.dto.VoiceIntentResponse;
import com.careconnect.service.VoiceIntentService;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class VoiceIntentControllerTest {

    @Test
    void extractIntent_serviceException_returnsGenericErrorWithoutExceptionDetails() {
        VoiceIntentService service = mock(VoiceIntentService.class);
        VoiceIntentController controller = new VoiceIntentController(service);
        String utterance = "My medication is atorvastatin";
        String diagnostic = "credential-provider diagnostic detail";
        VoiceIntentRequest request = VoiceIntentRequest.builder()
                .utterance(utterance)
                .locale("en")
                .build();

        when(service.extractIntent(request))
                .thenThrow(new IllegalStateException(diagnostic));

        Logger logger = (Logger) LoggerFactory.getLogger(VoiceIntentController.class);
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.addAppender(appender);

        try {
            ResponseEntity<VoiceIntentResponse> response = controller.extractIntent(request);

            assertThat(response.getStatusCode().value()).isEqualTo(503);
            assertThat(response.getBody()).isNotNull();
            assertThat(response.getBody().getErrorMessage())
                    .isEqualTo("Voice intent service is temporarily unavailable.")
                    .doesNotContain(diagnostic);

            assertThat(appender.list)
                    .extracting(ILoggingEvent::getFormattedMessage)
                    .noneMatch(message -> message.contains(utterance) || message.contains(diagnostic));
        } finally {
            logger.detachAppender(appender);
            appender.stop();
        }
    }
}
