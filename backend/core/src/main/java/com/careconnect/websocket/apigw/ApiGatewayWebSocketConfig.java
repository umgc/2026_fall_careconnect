package com.careconnect.websocket.apigw;

import lombok.extern.slf4j.Slf4j;
import org.apache.catalina.connector.Connector;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.WebServerFactoryCustomizer;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

/**
 * Wires websockets through an API Gateway WebSocket API (deployed environments).
 *
 * <p>Active when {@code careconnect.websocket.mode=aws} and the API's callback endpoint is set.
 * Local development uses {@link com.careconnect.config.WebSocketConfig} instead.
 *
 * <p>API Gateway reaches the backend over VPC Link → internal NLB → {@code internal-port}. A second
 * Tomcat connector listens there, and {@link InternalPortFilter} keeps the callback endpoints off
 * the public port.
 */
@Slf4j
@Configuration
@ConditionalOnExpression(ApiGatewayWebSocketConfig.ENABLED)
public class ApiGatewayWebSocketConfig {

    /** SpEL condition shared by every API Gateway websocket bean. */
    public static final String ENABLED = "'${careconnect.websocket.mode:aws}' == 'aws'"
            + " && '${careconnect.websocket.aws.api-gateway-endpoint:}' != ''";

    @Bean(destroyMethod = "close")
    public ApiGatewayConnectionClient apiGatewayConnectionClient(
            @Value("${careconnect.websocket.aws.api-gateway-endpoint}") final String endpoint,
            @Value("${careconnect.websocket.aws.region:us-east-1}") final String region) {
        log.info("API Gateway websocket mode: callback endpoint {}", endpoint);
        return ApiGatewayConnectionClient.create(endpoint, region);
    }

    @Bean
    public ApiGatewaySessionRegistry apiGatewaySessionRegistry() {
        return new ApiGatewaySessionRegistry();
    }

    @Bean
    public WebServerFactoryCustomizer<TomcatServletWebServerFactory> internalWebSocketConnector(
            @Value("${careconnect.websocket.aws.internal-port:8082}") final int internalPort) {
        return factory -> {
            final Connector connector = new Connector(TomcatServletWebServerFactory.DEFAULT_PROTOCOL);
            connector.setPort(internalPort);
            factory.addAdditionalTomcatConnectors(connector);
        };
    }

    @Bean
    public FilterRegistrationBean<InternalPortFilter> internalPortFilter(
            @Value("${careconnect.websocket.aws.internal-port:8082}") final int internalPort) {
        final FilterRegistrationBean<InternalPortFilter> registration =
                new FilterRegistrationBean<>(new InternalPortFilter(internalPort));
        // Before Spring Security, so the public port never reaches the callback endpoints.
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE);
        return registration;
    }
}
