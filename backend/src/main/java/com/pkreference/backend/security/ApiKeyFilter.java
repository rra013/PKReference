package com.pkreference.backend.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpServletResponseWrapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;

/**
 * With API keys configured (ApiKeyProperties), every request needs one, as
 * {@code Authorization: Bearer <key>}; anything else gets a 401. The key is checked by its SHA-256
 * hash, in constant time, and never logged or read from the URL, where proxies and logs keep it.
 *
 * <p>Swagger UI and the OpenAPI document are let in without one: they describe the API, as the
 * repository does, and hold no data. Swagger UI's Authorize button sends the key on the calls it
 * makes.
 *
 * <p>Answers that say they may be reused publicly ({@code Cache-Control: public}) say {@code private}
 * instead while keys are required, so a cache in front of the server can't hand a keyed answer to a
 * caller without a key.
 */
public class ApiKeyFilter extends OncePerRequestFilter {
    private static final Logger log = LoggerFactory.getLogger(ApiKeyFilter.class);
    private static final String BEARER = "bearer ";

    private final List<byte[]> hashes;

    public ApiKeyFilter(ApiKeyProperties properties) {
        hashes = properties.keyHashes().stream().map(HexFormat.of()::parseHex).toList();
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (hashes.isEmpty() || isDocumentation(request)) {
            chain.doFilter(request, response);
            return;
        }
        String header = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (header == null || !header.toLowerCase(Locale.ROOT).startsWith(BEARER) || !accepted(header.substring(BEARER.length()).trim())) {
            log.info("Refused {} {} from {}: {}", request.getMethod(), request.getRequestURI(), request.getRemoteAddr(),
                    header == null ? "no key" : "wrong key");
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setHeader(HttpHeaders.WWW_AUTHENTICATE, "Bearer");
            response.setContentType("application/json");
            response.getWriter().write("{\"error\":\"This server needs an API key: Authorization: Bearer <key>\"}");
            return;
        }
        chain.doFilter(request, new PrivateCaching(response));
    }

    /**
     * Swagger UI's page and assets, and the OpenAPI document it reads. The path is the request's as
     * sent; one that Tomcat would rewrite before routing it ("/swagger-ui/../v1/formats", encoded
     * characters, ";" parameters, "//") never counts, so it can't reach data without a key.
     */
    static boolean isDocumentation(HttpServletRequest request) {
        String path = request.getRequestURI().substring(request.getContextPath().length());
        if (path.contains("..") || path.contains("%") || path.contains(";") || path.contains("//")) return false;
        return path.equals("/swagger-ui.html") || path.startsWith("/swagger-ui/") || path.startsWith("/v3/api-docs");
    }

    /** Whether `key` hashes to a configured hash; every hash is compared, in constant time. */
    boolean accepted(String key) {
        if (key.isEmpty()) return false;
        byte[] hash = sha256(key);
        boolean found = false;
        for (byte[] known : hashes) found |= MessageDigest.isEqual(hash, known);
        return found;
    }

    static byte[] sha256(String key) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(key.getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Turns {@code Cache-Control: public} into {@code private}. */
    private static final class PrivateCaching extends HttpServletResponseWrapper {
        PrivateCaching(HttpServletResponse response) {
            super(response);
        }

        @Override
        public void setHeader(String name, String value) {
            super.setHeader(name, privately(name, value));
        }

        @Override
        public void addHeader(String name, String value) {
            super.addHeader(name, privately(name, value));
        }

        private static String privately(String name, String value) {
            return HttpHeaders.CACHE_CONTROL.equalsIgnoreCase(name) && value != null
                    ? value.replace("public", "private") : value;
        }
    }
}
