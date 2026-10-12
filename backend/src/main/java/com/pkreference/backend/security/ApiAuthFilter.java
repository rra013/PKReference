package com.pkreference.backend.security;

import com.pkreference.backend.security.TokenService.InvalidTokenException;
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
 * Who gets in, checked before anything else sees the request. With API keys configured
 * (ApiAuthProperties), every request carries {@code Authorization: Bearer <credential>}:
 *
 * <ul>
 * <li>{@code POST /v1/auth/token} takes an <b>API key</b>, and AuthController answers with an
 * access token. The key is checked by its SHA-256 hash, in constant time.
 * <li>Everything else takes an <b>access token</b> (TokenService), not the key: the long-lived key
 * is then sent once every few minutes rather than with every request, and a token that leaks stops
 * working by itself.
 * </ul>
 *
 * <p>Anything else gets a 401 that says why in {@code code}, so a client knows whether to trade its
 * key again ({@code token_expired}, {@code invalid_token}) or stop ({@code invalid_key}). Neither
 * credential is ever read from the URL, where proxies and logs keep it, or logged.
 *
 * <p>Swagger UI and the OpenAPI document are let in without either: they describe the API, as the
 * repository does, and hold no data.
 *
 * <p>Answers that say they may be reused publicly ({@code Cache-Control: public}) say {@code private}
 * instead, so a cache in front of the server can't hand a signed-in answer to a caller who isn't.
 */
public class ApiAuthFilter extends OncePerRequestFilter {
    /** The request attribute holding the id of the key a token request came with, for AuthController. */
    public static final String KEY_ID = ApiAuthFilter.class.getName() + ".keyId";
    public static final String TOKEN_PATH = "/v1/auth/token";

    private static final Logger log = LoggerFactory.getLogger(ApiAuthFilter.class);
    private static final String BEARER = "bearer ";

    private final List<String> hashes;
    private final List<byte[]> hashBytes;
    private final TokenService tokens;

    public ApiAuthFilter(ApiAuthProperties properties, TokenService tokens) {
        hashes = properties.keyHashes();
        hashBytes = hashes.stream().map(HexFormat.of()::parseHex).toList();
        this.tokens = tokens;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (hashes.isEmpty() || isDocumentation(request)) {
            chain.doFilter(request, response);
            return;
        }
        String credential = bearer(request);
        if (credential == null) {
            refuse(request, response, "missing_credentials",
                    "This server needs signing in: trade your API key for a token at POST " + TOKEN_PATH);
            return;
        }
        if (TOKEN_PATH.equals(path(request))) {
            String keyId = keyId(credential);
            if (keyId == null) {
                refuse(request, response, "invalid_key", "That API key isn't one this server accepts.");
                return;
            }
            request.setAttribute(KEY_ID, keyId);
            chain.doFilter(request, response);
            return;
        }
        try {
            tokens.verify(credential);
        } catch (InvalidTokenException e) {
            switch (e.refusal()) {
                case EXPIRED -> refuse(request, response, "token_expired",
                        "The access token has run out: trade your API key for a new one at POST " + TOKEN_PATH);
                default -> refuse(request, response, "invalid_token",
                        "That isn't an access token this server made: trade your API key for one at POST " + TOKEN_PATH);
            }
            return;
        }
        chain.doFilter(request, new PrivateCaching(response));
    }

    /** What follows "Bearer " in the Authorization header, or null. */
    private static String bearer(HttpServletRequest request) {
        String header = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (header == null || !header.toLowerCase(Locale.ROOT).startsWith(BEARER)) return null;
        String credential = header.substring(BEARER.length()).trim();
        return credential.isEmpty() ? null : credential;
    }

    private static void refuse(HttpServletRequest request, HttpServletResponse response, String code, String message)
            throws IOException {
        log.info("Refused {} {} from {}: {}", request.getMethod(), request.getRequestURI(), request.getRemoteAddr(), code);
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        // RFC 6750: how a Bearer-protected resource says what was wrong.
        response.setHeader(HttpHeaders.WWW_AUTHENTICATE, "Bearer error=\"" + ("missing_credentials".equals(code)
                ? "invalid_request" : "invalid_token") + "\", error_description=\"" + code + "\"");
        response.setHeader(HttpHeaders.CACHE_CONTROL, "no-store");
        response.setContentType("application/json");
        response.getWriter().write("{\"error\":\"" + message + "\",\"code\":\"" + code + "\"}");
    }

    private static String path(HttpServletRequest request) {
        return request.getRequestURI().substring(request.getContextPath().length());
    }

    /**
     * Swagger UI's page and assets, and the OpenAPI document it reads. The path is the request's as
     * sent; one that Tomcat would rewrite before routing it ("/swagger-ui/../v1/formats", encoded
     * characters, ";" parameters, "//") never counts, so it can't reach data without signing in.
     */
    static boolean isDocumentation(HttpServletRequest request) {
        String path = path(request);
        if (path.contains("..") || path.contains("%") || path.contains(";") || path.contains("//")) return false;
        return path.equals("/swagger-ui.html") || path.startsWith("/swagger-ui/") || path.startsWith("/v3/api-docs");
    }

    /**
     * The id of the configured key `key` is, or null when it isn't one. Every hash is compared, each in
     * constant time, so how long this takes says nothing about which key came close.
     */
    String keyId(String key) {
        if (key.isEmpty()) return null;
        byte[] hash = sha256(key);
        String found = null;
        for (int i = 0; i < hashBytes.size(); i++) {
            if (MessageDigest.isEqual(hash, hashBytes.get(i))) found = ApiAuthProperties.keyId(hashes.get(i));
        }
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
