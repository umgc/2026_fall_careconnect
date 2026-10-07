package com.careconnect.ai;

import com.careconnect.service.BedrockAIChatService;
import com.careconnect.service.DeepSeekService;
import com.careconnect.service.OllamaService;
import com.careconnect.service.ColibriService;
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

    @Mock
    private OllamaService ollamaService;

    @Mock
    private ColibriService colibriService;

    @SuppressWarnings("unchecked")
    private AIServiceFactory factory(DeepSeekService deepSeek,
                                     BedrockAIChatService bedrock,
                                     OllamaService ollama,
                                     ColibriService colibri,
                                     String provider) throws Exception {
        ObjectProvider<DeepSeekService> deepSeekProvider = mock(ObjectProvider.class);
        ObjectProvider<BedrockAIChatService> bedrockProvider = mock(ObjectProvider.class);
        ObjectProvider<OllamaService> ollamaProvider = mock(ObjectProvider.class);
        ObjectProvider<ColibriService> colibriProvider = mock(ObjectProvider.class);
        when(deepSeekProvider.getIfAvailable()).thenReturn(deepSeek);
        when(bedrockProvider.getIfAvailable()).thenReturn(bedrock);
        when(ollamaProvider.getIfAvailable()).thenReturn(ollama);
        when(colibriProvider.getIfAvailable()).thenReturn(colibri);

        AIServiceFactory factory = new AIServiceFactory(deepSeekProvider, bedrockProvider, ollamaProvider, colibriProvider);

        Field providerField = AIServiceFactory.class.getDeclaredField("provider");
        providerField.setAccessible(true);
        providerField.set(factory, provider);
        return factory;
    }

    @Test
    void getService_bedrockProvider_returnsBedrockService() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, ollamaService, colibriService, "bedrock");

        assertThat(factory.getService()).isSameAs(bedrockService);
    }

    @Test
    void getService_deepseekProvider_returnsDeepSeekService() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, ollamaService, colibriService, "deepseek");

        assertThat(factory.getService()).isSameAs(deepSeekService);
    }

    @Test
    void getService_ollamaProvider_returnsOllamaService() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, ollamaService, colibriService, "ollama");

        assertThat(factory.getService()).isSameAs(ollamaService);
    }

    @Test
    void getService_colibriProvider_returnsColibriService() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, ollamaService, colibriService, "colibri");

        assertThat(factory.getService()).isSameAs(colibriService);
    }

    @Test
    void getService_providerIsCaseInsensitive() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, ollamaService, colibriService, "BEDROCK");

        assertThat(factory.getService()).isSameAs(bedrockService);
    }

    @Test
    void getService_unknownProvider_failsSafelyWithClearError() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, ollamaService, colibriService, "not-a-provider");

        assertThatThrownBy(factory::getService)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Unknown AI provider 'not-a-provider'");
    }

    @Test
    void getService_bedrockConfiguredButBeanMissing_failsSafely() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, null, ollamaService, colibriService, "bedrock");

        assertThatThrownBy(factory::getService)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("BedrockAIChatService");
    }

    @Test
    void getService_deepseekConfiguredButBeanMissing_failsSafely() throws Exception {
        AIServiceFactory factory = factory(null, bedrockService, ollamaService, colibriService, "deepseek");

        assertThatThrownBy(factory::getService)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("DeepSeekService");
    }

    @Test
    void getService_ollamaConfiguredButBeanMissing_failsSafely() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, null, colibriService, "ollama");

        assertThatThrownBy(factory::getService)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("OllamaService");
    }

    @Test
    void getService_colibriConfiguredButBeanMissing_failsSafely() throws Exception {
        AIServiceFactory factory = factory(deepSeekService, bedrockService, ollamaService, null, "colibri");

        assertThatThrownBy(factory::getService)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("ColibriService");
    }

    @Test
    void logSelectedProvider_coversAllBranches() throws Exception {
        // Bedrock with service present and absent
        factory(deepSeekService, bedrockService, ollamaService, colibriService, "bedrock").logSelectedProvider();
        factory(deepSeekService, null, ollamaService, colibriService, "bedrock").logSelectedProvider();

        // DeepSeek with service present and absent
        factory(deepSeekService, bedrockService, ollamaService, colibriService, "deepseek").logSelectedProvider();
        factory(null, bedrockService, ollamaService, colibriService, "deepseek").logSelectedProvider();

        // Ollama with service present and absent
        factory(deepSeekService, bedrockService, ollamaService, colibriService, "ollama").logSelectedProvider();
        factory(deepSeekService, bedrockService, null, colibriService, "ollama").logSelectedProvider();

        // Colibri with service present and absent
        factory(deepSeekService, bedrockService, ollamaService, colibriService, "colibri").logSelectedProvider();
        factory(deepSeekService, bedrockService, ollamaService, null, "colibri").logSelectedProvider();

        // Unknown provider
        factory(deepSeekService, bedrockService, ollamaService, colibriService, "unknown-custom").logSelectedProvider();
    }
}
