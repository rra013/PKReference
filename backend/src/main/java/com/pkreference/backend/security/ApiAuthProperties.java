package com.pkreference.backend.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.Locale;

/**
 * Who may use the API, and how (README, "Signing in to the API").
 *
 * <p>{@code keyHashes}: the API keys the server accepts, as the SHA-256 hashes of the keys (hex), so
 * the configuration never holds a key itself. None, and every request is let in, as on a server only
 * this machine can reach. Set them with PKREF_API_KEY_HASHES (comma-separated);
 * backend/scripts/new-api-key.sh makes a key and its hash.
 *
 * <p>{@code tokenLifetime}: how long an access token, which a key is traded for, is good for. 15
 * minutes unless set (PKREF_TOKEN_LIFETIME, such as "30m").
 *
 * <p>{@code tokenSecret}: what signs the tokens (PKREF_TOKEN_SECRET), at least 32 characters. Unset,
 * the server makes a random one each time it starts: tokens from before a restart stop working, and
 * the app trades its key for a new one. Set it only to keep tokens across restarts.
 */
@ConfigurationProperties(prefix = "pkref.api")
public record ApiAuthProperties(List<String> keyHashes, Duration tokenLifetime, String tokenSecret) {
    static final Duration DEFAULT_TOKEN_LIFETIME = Duration.ofMinutes(15);
    /** HS256 signs with a 256-bit key: a shorter secret is easier to guess than the signature is to forge. */
    static final int MIN_SECRET_BYTES = 32;

    /**
     * Checked when the record is built, which is at start-up: a mistake in the configuration (a key
     * where a hash belongs, a secret that's too short) stops the server from starting, with a
     * message saying what to fix, instead of leaving it running open or weak.
     */
    public ApiAuthProperties {
        keyHashes = keyHashes == null ? List.of()
                : keyHashes.stream().map(h -> h.trim().toLowerCase(Locale.ROOT)).filter(h -> !h.isEmpty()).toList();
        for (String hash : keyHashes) {
            if (!hash.matches("[0-9a-f]{64}")) {
                throw new IllegalArgumentException("pkref.api.key-hashes takes SHA-256 hashes (64 hex digits), "
                        + "not keys: see backend/scripts/new-api-key.sh");
            }
        }
        if (tokenLifetime == null) tokenLifetime = DEFAULT_TOKEN_LIFETIME;
        if (tokenLifetime.isZero() || tokenLifetime.isNegative()) {
            throw new IllegalArgumentException("pkref.api.token-lifetime must be longer than nothing");
        }
        if (tokenSecret != null && tokenSecret.isBlank()) tokenSecret = null;
        if (tokenSecret != null && tokenSecret.getBytes(StandardCharsets.UTF_8).length < MIN_SECRET_BYTES) {
            throw new IllegalArgumentException("pkref.api.token-secret needs at least " + MIN_SECRET_BYTES
                    + " characters: openssl rand -base64 48 makes one");
        }
    }

    /** Only keys, with the default lifetime and a random secret. */
    public static ApiAuthProperties ofKeys(List<String> keyHashes) {
        return new ApiAuthProperties(keyHashes, null, null);
    }

    /** Whether signing in is on: true once at least one key hash is configured. */
    public boolean required() {
        return !keyHashes.isEmpty();
    }

    /**
     * A short name for a key, from its hash: what a token says it was traded for, and what the logs
     * say, without either holding the key or its whole hash.
     */
    static String keyId(String hash) {
        return hash.substring(0, 8);
    }
}
