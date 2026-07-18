package com.careconnect.ai;

import com.careconnect.service.BedrockAIChatService;
import com.careconnect.service.DeepSeekService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.factory.ObjectProvider;

import java.lang.reflect.Field;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AIServiceFactoryTest {

    @Mock
    private DeepSeekService deepSeekService;

    @Mock
    private BedrockAIChatService bedrockService;

    @SuppressWarnings("unchecked")
    private AIServiceFactory factory(DeepSeekService deepSeek,
                                     BedrockAIChatService bedrock,
                                     String provider) throws Exception {
        ObjectProvider<DeepSeekService> deepSeekProvider = mock(ObjectProvider.class);
        ObjectProvider<BedrockAIChatService> bedrockProvider = mock(ObjectProvider.class);
        when(deepSeekProvider.getIfAvailable()).thenReturn(deepSeek);
        when(bedrockProvider.getIfAvailable()).thenReturn(bedrock);

        AIServiceFactory factory = new AIServiceFactory(deepSeekProvider, bedrockProvider);

        Field providerField = AIServiceFactory.class.getDeclaredField("provider");
        providerField.setAccessible(true);
        providerField.set(factory, provider);
        return factory;
    }

    @Test
    void getService_bedrockProvider_returnsBedrockService() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, "bedrock");

        assertThat(factory.getService()).isSameAs(bedrockService);
    }

    @Test
    void getService_deepseekProvider_returnsDeepSeekService() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, "deepseek");

        assertThat(factory.getService()).isSameAs(deepSeekService);
    }

    @Test
    void getService_providerIsCaseInsensitive() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, "BEDROCK");

        assertThat(factory.getService()).isSameAs(bedrockService);
    }

    @Test
    void getService_unknownProvider_failsSafelyWithClearError() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, "not-a-provider");

        assertThatThrownBy(factory::getService)
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Unknown provider: not-a-provider");
    }

    @Test
    void getService_bedrockConfiguredButBeanMissing_failsSafely() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, null, "bedrock");

        assertThatThrownBy(factory::getService)
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("BedrockService not available");
    }

    @Test
    void getService_deepseekConfiguredButBeanMissing_failsSafely() throws Exception {
        AIServiceFactory factory = factory(null, bedrockService, "deepseek");

        assertThatThrownBy(factory::getService)
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("DeepSeekService not available");
    }
}
