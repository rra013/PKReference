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
    @Bean
    FilterRegistrationBean<ShallowEtagHeaderFilter> v1Etags() {
        var filter = new ShallowEtagHeaderFilter();
        filter.setWriteWeakETag(true);
        var registration = new FilterRegistrationBean<>(filter);
        registration.addUrlPatterns("/v1/*");
        return registration;
    }
}
