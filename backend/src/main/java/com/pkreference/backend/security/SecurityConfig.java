package com.pkreference.backend.security;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

/**
 * The API key check, ahead of every other filter and on every path but Swagger UI's: /v1 and the
 * older /api/usage. Swagger UI's Authorize button takes the key.
 */
@Configuration
public class SecurityConfig {
    @Bean
    FilterRegistrationBean<ApiKeyFilter> apiKeys(ApiKeyProperties properties) {
        var registration = new FilterRegistrationBean<>(new ApiKeyFilter(properties));
        registration.addUrlPatterns("/*");
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE);
        return registration;
    }

    @Bean
    OpenAPI openApi(ApiKeyProperties properties) {
        var api = new OpenAPI();
        if (properties.required()) {
            api.components(new Components().addSecuritySchemes("apiKey",
                            new SecurityScheme().type(SecurityScheme.Type.HTTP).scheme("bearer")
                                    .description("A key made by backend/scripts/new-api-key.sh.")))
                    .addSecurityItem(new SecurityRequirement().addList("apiKey"));
        }
        return api;
    }
}
