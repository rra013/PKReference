package com.pkreference.backend.insight;

import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.filter.ShallowEtagHeaderFilter;

/**
 * ETags for /v1, worked out from each response's body: a matching If-None-Match gets a 304. Weak
 * ETags (W/"..."), because Tomcat doesn't gzip a response with a strong one, and a gzipped body is
 * the same content in another encoding.
 */
@Configuration
public class MetaWebConfig {
    /**
     * Registers Spring's ETag filter for every path under /v1. A servlet filter sees each request
     * before the controller and each response after it. This one holds the response back, hashes
     * its body into an {@code ETag} header, and compares that with the request's
     * {@code If-None-Match}: when they're equal, the client already has this answer, and it gets a
     * 304 Not Modified with no body. The server still does the work; what's saved is the transfer.
     *
     * <p>{@code FilterRegistrationBean} is how a filter is given its URL patterns and order; a filter
     * declared as a plain bean would apply to every path.
     */
    @Bean
    FilterRegistrationBean<ShallowEtagHeaderFilter> v1Etags() {
        var filter = new ShallowEtagHeaderFilter();
        filter.setWriteWeakETag(true);
        var registration = new FilterRegistrationBean<>(filter);
        registration.addUrlPatterns("/v1/*");
        return registration;
    }
}
