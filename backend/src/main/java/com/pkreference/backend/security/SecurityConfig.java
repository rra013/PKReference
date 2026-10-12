package com.pkreference.backend.security;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

import java.time.Clock;

/**
 * Signing in to the API, put together: the tokens, and the check ahead of every other filter and on
 * every path but Swagger UI's (/v1 and the older /api/usage).
 */
@Configuration
public class SecurityConfig {
    /** Swagger UI's names for the two credentials. */
    static final String API_KEY = "apiKey";
    static final String ACCESS_TOKEN = "accessToken";

    /** One for the whole server: its secret is what makes a token made here verify here. */
    @Bean
    TokenService tokenService(ApiAuthProperties properties, ObjectProvider<Clock> clock) {
        return new TokenService(properties, clock.getIfAvailable(Clock::systemUTC));
    }

    @Bean
    FilterRegistrationBean<ApiAuthFilter> apiAuth(ApiAuthProperties properties, TokenService tokens) {
        var registration = new FilterRegistrationBean<>(new ApiAuthFilter(properties, tokens));
        registration.addUrlPatterns("/*");
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE);
        return registration;
    }

    /**
     * Swagger UI's Authorize button, when signing in is required: the API key, which only the token
     * request takes, and the access token, which everything else does. Authorize with the key, run
     * POST /v1/auth/token, then Authorize with the token it returns.
     */
    @Bean
    OpenAPI openApi(ApiAuthProperties properties) {
        var api = new OpenAPI();
        if (properties.required()) {
            api.components(new Components()
                            .addSecuritySchemes(API_KEY, new SecurityScheme().type(SecurityScheme.Type.HTTP).scheme("bearer")
                                    .description("An API key made by backend/scripts/new-api-key.sh. Only POST "
                                            + ApiAuthFilter.TOKEN_PATH + " takes it."))
                            .addSecuritySchemes(ACCESS_TOKEN, new SecurityScheme().type(SecurityScheme.Type.HTTP)
                                    .scheme("bearer").bearerFormat("JWT")
                                    .description("The token POST " + ApiAuthFilter.TOKEN_PATH + " returns.")))
                    .addSecurityItem(new SecurityRequirement().addList(ACCESS_TOKEN));
        }
        return api;
    }
}
