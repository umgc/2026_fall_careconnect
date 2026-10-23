package com.careconnect.websocket.apigw;

import org.apache.catalina.connector.Connector;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.autoconfigure.context.PropertyPlaceholderAutoConfiguration;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.WebServerFactoryCustomizer;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.core.Ordered;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tests for {@link ApiGatewayWebSocketConfig}: when its beans load, and what they configure.
 *
 * <p>Uses {@link ApplicationContextRunner} with only this configuration, so no database, AWS
 * credentials, or web server are needed. The endpoint value is a placeholder; building the SDK
 * client makes no network call.
 */
class ApiGatewayWebSocketConfigTest {

    private static final String ENDPOINT = "https://abc123.execute-api.us-east-1.amazonaws.com/dev";

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withConfiguration(AutoConfigurations.of(PropertyPlaceholderAutoConfiguration.class))
            .withUserConfiguration(ApiGatewayWebSocketConfig.class);

    @Test
    void awsModeWithEndpoint_loadsBeans() {
        runner.withPropertyValues(
                        "careconnect.websocket.mode=aws",
                        "careconnect.websocket.aws.api-gateway-endpoint=" + ENDPOINT)
                .run(context -> {
                    assertThat(context).hasSingleBean(ApiGatewayConnectionClient.class);
                    assertThat(context).hasSingleBean(ApiGatewaySessionRegistry.class);
                    assertThat(context).hasBean("internalWebSocketConnector");
                    assertThat(context).hasBean("internalPortFilter");
                });
    }

    /** Prod profile before the stack sets the endpoint: nothing should load or fail. */
    @Test
    void awsModeWithoutEndpoint_loadsNothing() {
        runner.withPropertyValues(
                        "careconnect.websocket.mode=aws",
                        "careconnect.websocket.aws.api-gateway-endpoint=")
                .run(context -> assertThat(context).doesNotHaveBean(ApiGatewayConnectionClient.class));
    }

    @Test
    void localMode_loadsNothing() {
        runner.withPropertyValues(
                        "careconnect.websocket.mode=local",
                        "careconnect.websocket.aws.api-gateway-endpoint=" + ENDPOINT)
                .run(context -> assertThat(context).doesNotHaveBean(ApiGatewayConnectionClient.class));
    }

    @Test
    @SuppressWarnings("unchecked")
    void connectorCustomizer_addsInternalPortConnector() {
        runner.withPropertyValues(
                        "careconnect.websocket.mode=aws",
                        "careconnect.websocket.aws.api-gateway-endpoint=" + ENDPOINT,
                        "careconnect.websocket.aws.internal-port=9099")
                .run(context -> {
                    WebServerFactoryCustomizer<TomcatServletWebServerFactory> customizer =
                            context.getBean("internalWebSocketConnector", WebServerFactoryCustomizer.class);
                    TomcatServletWebServerFactory factory = new TomcatServletWebServerFactory();

                    customizer.customize(factory);

                    assertThat(factory.getAdditionalTomcatConnectors())
                            .extracting(Connector::getPort)
                            .containsExactly(9099);
                });
    }

    @Test
    void portFilter_runsBeforeEverythingElse() {
        runner.withPropertyValues(
                        "careconnect.websocket.mode=aws",
                        "careconnect.websocket.aws.api-gateway-endpoint=" + ENDPOINT)
                .run(context -> {
                    FilterRegistrationBean<?> registration =
                            context.getBean("internalPortFilter", FilterRegistrationBean.class);
                    assertThat(registration.getOrder()).isEqualTo(Ordered.HIGHEST_PRECEDENCE);
                    assertThat(registration.getFilter()).isInstanceOf(InternalPortFilter.class);
                });
    }
}
