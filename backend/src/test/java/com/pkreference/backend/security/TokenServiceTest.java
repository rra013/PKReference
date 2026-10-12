package com.pkreference.backend.security;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.PlainJWT;
import com.nimbusds.jwt.SignedJWT;
import com.pkreference.backend.security.TokenService.InvalidTokenException;
import com.pkreference.backend.security.TokenService.Refusal;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.Date;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

/**
 * The access tokens: what a good one holds, and every way a bad one is refused. The forged tokens are
 * made here with the same library, as someone who knew everything but the secret would make them.
 */
class TokenServiceTest {
    static final String HASH = ApiAuthFilterTest.HASH;
    static final String KEY_ID = ApiAuthProperties.keyId(HASH);
    /** 64 characters: long enough for HS512 too, for the wrong-algorithm test. */
    static final String SECRET = "test-secret-only-for-tests-0123456789-0123456789-0123456789-0123";
    static final Instant NOW = Instant.parse("2026-10-11T12:00:00Z");

    /** A clock the test moves. */
    static final class TestClock extends Clock {
        Instant now = NOW;

        @Override
        public Instant instant() {
            return now;
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }
    }

    private final TestClock clock = new TestClock();
    private final TokenService tokens = service(List.of(HASH), SECRET);

    private TokenService service(List<String> hashes, String secret) {
        return new TokenService(new ApiAuthProperties(hashes, Duration.ofMinutes(15), secret), clock);
    }

    private Refusal refusal(TokenService service, String token) {
        return catchThrowableOfType(InvalidTokenException.class, () -> service.verify(token)).refusal();
    }

    /** A token signed with the real secret, with whatever claims the test wants. */
    private String signed(JWSAlgorithm algorithm, JWTClaimsSet claims) throws Exception {
        var jwt = new SignedJWT(new JWSHeader(algorithm), claims);
        jwt.sign(new MACSigner(SECRET.getBytes(StandardCharsets.UTF_8)));
        return jwt.serialize();
    }

    private JWTClaimsSet.Builder goodClaims() {
        return new JWTClaimsSet.Builder().issuer(TokenService.ISSUER).audience(TokenService.AUDIENCE).subject(KEY_ID)
                .expirationTime(Date.from(NOW.plusSeconds(900)));
    }

    @Test
    void aGoodToken() throws Exception {
        var issued = tokens.issue(KEY_ID);
        assertThat(issued.expiresInSeconds()).isEqualTo(900);
        assertThat(issued.expiresAt()).isEqualTo(NOW.plusSeconds(900));
        assertThat(tokens.verify(issued.token())).isEqualTo(KEY_ID);

        // Three parts; the first two are only base64, and say nothing secret.
        String[] parts = issued.token().split("\\.");
        assertThat(parts).hasSize(3);
        String header = new String(Base64.getUrlDecoder().decode(parts[0]), StandardCharsets.UTF_8);
        String claims = new String(Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8);
        assertThat(header).contains("\"alg\":\"HS256\"").contains("\"typ\":\"JWT\"");
        assertThat(claims).contains("\"iss\":\"pkreference-backend\"").contains("\"aud\":\"pkreference-api\"")
                .contains("\"sub\":\"" + KEY_ID + "\"").contains("\"exp\":" + NOW.plusSeconds(900).getEpochSecond())
                .contains("\"iat\":" + NOW.getEpochSecond()).contains("\"jti\"");
        assertThat(issued.token()).doesNotContain(HASH).doesNotContain(SECRET);
        // Each is its own token.
        assertThat(tokens.issue(KEY_ID).token()).isNotEqualTo(issued.token());
    }

    @Test
    void runsOut() throws Exception {
        String token = tokens.issue(KEY_ID).token();
        clock.now = NOW.plusSeconds(899);
        assertThat(tokens.verify(token)).isEqualTo(KEY_ID);
        clock.now = NOW.plusSeconds(900);
        assertThat(refusal(tokens, token)).isEqualTo(Refusal.EXPIRED);
        // One with no expiry at all never counts as good.
        assertThat(refusal(tokens, signed(JWSAlgorithm.HS256, goodClaims().expirationTime(null).build())))
                .isEqualTo(Refusal.EXPIRED);
    }

    @Test
    void notATokenAtAll() {
        assertThat(refusal(tokens, "pkr_test-key-only-for-tests")).as("an API key").isEqualTo(Refusal.MALFORMED);
        assertThat(refusal(tokens, "")).isEqualTo(Refusal.MALFORMED);
        assertThat(refusal(tokens, "a.b.c")).isEqualTo(Refusal.MALFORMED);
    }

    /** Changing a claim, or signing with another secret, breaks the signature. */
    @Test
    void forgedSignatures() throws Exception {
        String[] parts = tokens.issue(KEY_ID).token().split("\\.");
        String claims = new String(Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8);
        String longer = claims.replace("\"exp\":" + NOW.plusSeconds(900).getEpochSecond(),
                "\"exp\":" + NOW.plusSeconds(90_000_000).getEpochSecond());
        assertThat(longer).isNotEqualTo(claims);
        String tampered = parts[0] + "." + Base64.getUrlEncoder().withoutPadding()
                .encodeToString(longer.getBytes(StandardCharsets.UTF_8)) + "." + parts[2];
        assertThat(refusal(tokens, tampered)).isEqualTo(Refusal.BAD_SIGNATURE);

        var other = service(List.of(HASH), "another-secret-only-for-tests-0123456789-0123456789");
        assertThat(refusal(tokens, other.issue(KEY_ID).token())).isEqualTo(Refusal.BAD_SIGNATURE);

        assertThat(refusal(tokens, parts[0] + "." + parts[1] + ".")).as("no signature")
                .isIn(Refusal.BAD_SIGNATURE, Refusal.MALFORMED);
    }

    /** The server picks the algorithm, not the token: "none" and other algorithms are refused. */
    @Test
    void theAlgorithmIsNotTheTokensToChoose() throws Exception {
        String unsigned = new PlainJWT(goodClaims().build()).serialize();
        assertThat(refusal(tokens, unsigned)).isIn(Refusal.MALFORMED, Refusal.WRONG_ALGORITHM);
        // Signed correctly with the real secret, but not as this server signs.
        assertThat(refusal(tokens, signed(JWSAlgorithm.HS512, goodClaims().build()))).isEqualTo(Refusal.WRONG_ALGORITHM);
        // The same claims, signed as this server signs, are fine: only the algorithm was wrong.
        assertThat(tokens.verify(signed(JWSAlgorithm.HS256, goodClaims().build()))).isEqualTo(KEY_ID);
    }

    @Test
    void madeForSomethingElse() throws Exception {
        assertThat(refusal(tokens, signed(JWSAlgorithm.HS256, goodClaims().audience("another-api").build())))
                .isEqualTo(Refusal.WRONG_CLAIMS);
        assertThat(refusal(tokens, signed(JWSAlgorithm.HS256, goodClaims().issuer("someone-else").build())))
                .isEqualTo(Refusal.WRONG_CLAIMS);
        assertThat(refusal(tokens, signed(JWSAlgorithm.HS256, goodClaims().subject(null).build())))
                .isEqualTo(Refusal.WRONG_CLAIMS);
    }

    /** Removing a key's hash from the configuration ends the tokens it was traded for. */
    @Test
    void aRemovedKeysTokens() throws Exception {
        String token = tokens.issue(KEY_ID).token();
        var withoutIt = service(List.of("0".repeat(64)), SECRET);
        assertThat(refusal(withoutIt, token)).isEqualTo(Refusal.KEY_REMOVED);
        // With no keys configured, the server is open, and a token names no key.
        var open = service(List.of(), SECRET);
        assertThat(open.verify(open.issue(AuthController.OPEN).token())).isEqualTo(AuthController.OPEN);
    }

    /** With no secret configured, each start makes its own: a restart ends the tokens before it. */
    @Test
    void aRestartEndsTokens() throws Exception {
        var before = service(List.of(HASH), null);
        var after = service(List.of(HASH), null);
        String token = before.issue(KEY_ID).token();
        assertThat(before.verify(token)).isEqualTo(KEY_ID);
        assertThat(refusal(after, token)).isEqualTo(Refusal.BAD_SIGNATURE);
    }

    @Test
    void settings() {
        assertThat(ApiAuthProperties.ofKeys(List.of(HASH)).tokenLifetime()).isEqualTo(Duration.ofMinutes(15));
        assertThat(new ApiAuthProperties(List.of(), null, "  ").tokenSecret()).isNull();
        assertThatThrownBy(() -> new ApiAuthProperties(List.of(), null, "too-short"))
                .isInstanceOf(IllegalArgumentException.class).hasMessageContaining("32");
        assertThatThrownBy(() -> new ApiAuthProperties(List.of(), Duration.ZERO, null))
                .isInstanceOf(IllegalArgumentException.class);
        assertThat(KEY_ID).hasSize(8);
    }
}
