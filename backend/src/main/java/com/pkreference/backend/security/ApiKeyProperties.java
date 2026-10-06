package com.pkreference.backend.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.List;
import java.util.Locale;

/**
 * The API keys the server accepts, as the SHA-256 hashes of the keys (hex), so the configuration
 * never holds a key itself. None, and every request is let in, as on a server only this machine can
 * reach. Set them with PKREF_API_KEY_HASHES (comma-separated); backend/scripts/new-api-key.sh makes a
 * key and its hash.
 */
@ConfigurationProperties(prefix = "pkref.api")
public record ApiKeyProperties(List<String> keyHashes) {
    public ApiKeyProperties {
        keyHashes = keyHashes == null ? List.of()
                : keyHashes.stream().map(h -> h.trim().toLowerCase(Locale.ROOT)).filter(h -> !h.isEmpty()).toList();
        for (String hash : keyHashes) {
            if (!hash.matches("[0-9a-f]{64}")) {
                throw new IllegalArgumentException("pkref.api.key-hashes takes SHA-256 hashes (64 hex digits), "
                        + "not keys: see backend/scripts/new-api-key.sh");
            }
        }
    }

    public boolean required() {
        return !keyHashes.isEmpty();
    }
}
