package com.pkreference.backend.security;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JOSEObjectType;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jose.crypto.MACVerifier;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.text.ParseException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The API's access tokens: JSON Web Tokens (JWTs), which an API key is traded for and every other
 * request then carries.
 *
 * <p>A token is three parts joined by dots: a header (how it was signed), claims (who it's for and
 * when it runs out) and a signature over both. The first two are only base64, readable by anyone, so
 * nothing secret goes in them; the signature is what makes them trustworthy. It's HMAC-SHA256
 * ("HS256") with a secret only this server has, since this server both signs and verifies.
 *
 * <p>Verifying is strict about the things JWT libraries have been fooled by: the algorithm must be
 * HS256 (not "none", and not whatever the token says), the signature must match, the token must not
 * have run out, and it must have been made by this server, for this API, from a key that's still
 * configured, so removing a key's hash also ends its tokens.
 */
public class TokenService {
    static final String ISSUER = "pkreference-backend";
    static final String AUDIENCE = "pkreference-api";

    /** Why a token was refused. */
    public enum Refusal {
        /** Not a signed JWT at all: an API key sent where a token belongs, say. */
        MALFORMED,
        WRONG_ALGORITHM,
        BAD_SIGNATURE,
        EXPIRED,
        /** Signed by this server, but not for this API. */
        WRONG_CLAIMS,
        /** The key it was traded for is no longer configured. */
        KEY_REMOVED
    }

    /**
     * Thrown by verify, carrying why. A checked exception, so the filter has to decide what to
     * answer.
     */
    public static final class InvalidTokenException extends Exception {
        private final Refusal refusal;

        /** The exception's message is the refusal's name, for the logs of anything that prints it. */
        InvalidTokenException(Refusal refusal) {
            super(refusal.name());
            this.refusal = refusal;
        }

        /** Why the token was refused. */
        public Refusal refusal() {
            return refusal;
        }
    }

    /** A token just made, and when it stops working. */
    public record Issued(String token, Instant expiresAt, long expiresInSeconds) {}

    private final byte[] secret;
    private final Duration lifetime;
    private final Set<String> keyIds;
    private final boolean keysRequired;
    private final Clock clock;

    /**
     * Made by SecurityConfig. Uses the configured secret, or 32 random bytes when none is set.
     * Keeps the short ids of the configured keys, to check each token's subject against.
     */
    public TokenService(ApiAuthProperties properties, Clock clock) {
        this.secret = properties.tokenSecret() != null
                ? properties.tokenSecret().getBytes(StandardCharsets.UTF_8) : randomSecret();
        this.lifetime = properties.tokenLifetime();
        this.keyIds = properties.keyHashes().stream().map(ApiAuthProperties::keyId).collect(Collectors.toSet());
        this.keysRequired = properties.required();
        this.clock = clock;
    }

    /** 32 bytes from the operating system's secure random source, new each start. */
    private static byte[] randomSecret() {
        byte[] bytes = new byte[ApiAuthProperties.MIN_SECRET_BYTES];
        new SecureRandom().nextBytes(bytes);
        return bytes;
    }

    /** A token for the holder of the key named `keyId`, good for the configured lifetime. */
    public Issued issue(String keyId) {
        // JWT times are whole seconds.
        Instant now = clock.instant().truncatedTo(ChronoUnit.SECONDS);
        Instant expiresAt = now.plus(lifetime);
        var claims = new JWTClaimsSet.Builder()
                .issuer(ISSUER)
                .audience(AUDIENCE)
                .subject(keyId)
                .issueTime(Date.from(now))
                .expirationTime(Date.from(expiresAt))
                .jwtID(UUID.randomUUID().toString())
                .build();
        var jwt = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.HS256).type(JOSEObjectType.JWT).build(), claims);
        try {
            jwt.sign(new MACSigner(secret));
        } catch (JOSEException e) {
            throw new IllegalStateException("Couldn't sign a token", e);
        }
        return new Issued(jwt.serialize(), expiresAt, lifetime.toSeconds());
    }

    /** The id of the key `token` was traded for, when the token is good; otherwise why it isn't. */
    public String verify(String token) throws InvalidTokenException {
        SignedJWT jwt;
        try {
            jwt = SignedJWT.parse(token);
        } catch (ParseException e) {
            throw new InvalidTokenException(Refusal.MALFORMED);
        }
        // Before the signature: the header is the attacker's to write, so the server decides the algorithm.
        if (!JWSAlgorithm.HS256.equals(jwt.getHeader().getAlgorithm())) {
            throw new InvalidTokenException(Refusal.WRONG_ALGORITHM);
        }
        JWTClaimsSet claims;
        try {
            if (!jwt.verify(new MACVerifier(secret))) throw new InvalidTokenException(Refusal.BAD_SIGNATURE);
            claims = jwt.getJWTClaimsSet();
        } catch (JOSEException e) {
            throw new InvalidTokenException(Refusal.BAD_SIGNATURE);
        } catch (ParseException e) {
            throw new InvalidTokenException(Refusal.MALFORMED);
        }
        // Only now are the claims this server's own words.
        Date expires = claims.getExpirationTime();
        if (expires == null || !expires.toInstant().isAfter(clock.instant())) {
            throw new InvalidTokenException(Refusal.EXPIRED);
        }
        String keyId = claims.getSubject();
        if (!ISSUER.equals(claims.getIssuer()) || !claims.getAudience().contains(AUDIENCE) || keyId == null) {
            throw new InvalidTokenException(Refusal.WRONG_CLAIMS);
        }
        if (keysRequired && !keyIds.contains(keyId)) {
            throw new InvalidTokenException(Refusal.KEY_REMOVED);
        }
        return keyId;
    }
}
