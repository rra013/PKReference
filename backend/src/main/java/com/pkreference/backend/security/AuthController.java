package com.pkreference.backend.security;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Map;

/**
 * Trades an API key for an access token. ApiAuthFilter has already checked the key by the time a
 * request gets here, and says which key it was (ApiAuthFilter.KEY_ID); this only makes the token.
 */
@RestController
@RequestMapping("/v1/auth")
@Tag(name = "Signing in", description = """
        Trade your API key for a short-lived access token, then send the token with every other \
        request. When the token runs out (401, code token_expired), trade the key again.""")
public class AuthController {
    /** With no keys configured the server lets everyone in; a token then names this in place of a key. */
    static final String OPEN = "open";

    @Schema(description = "An access token, and how long it's good for.")
    public record TokenResponse(
            @Schema(description = "The access token (a JWT): send it as Authorization: Bearer <token>.") String token,
            @Schema(description = "Always Bearer.", example = "Bearer") String tokenType,
            @Schema(description = "Seconds until it runs out, from now.", example = "900") long expiresIn,
            @Schema(description = "When it runs out, by the server's clock.") Instant expiresAt) {}

    private final TokenService tokens;
    private final ApiAuthProperties properties;

    public AuthController(TokenService tokens, ApiAuthProperties properties) {
        this.tokens = tokens;
        this.properties = properties;
    }

    @PostMapping("/token")
    @Operation(summary = "Trade an API key for an access token",
            description = "Send the API key as Authorization: Bearer <key>. 401 with code invalid_key when "
                    + "it isn't one the server accepts.",
            security = @SecurityRequirement(name = SecurityConfig.API_KEY))
    public ResponseEntity<?> token(HttpServletRequest request) {
        String keyId = (String) request.getAttribute(ApiAuthFilter.KEY_ID);
        // Only a request the filter matched a key for gets a token: never one that came with a token
        // (which would let a token renew itself for ever), by whatever spelling of this path.
        if (keyId == null && properties.required()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .header(HttpHeaders.WWW_AUTHENTICATE, "Bearer error=\"invalid_token\", error_description=\"invalid_key\"")
                    .cacheControl(CacheControl.noStore())
                    .body(Map.of("error", "A token is only given for an API key.", "code", "invalid_key"));
        }
        var issued = tokens.issue(keyId == null ? OPEN : keyId);
        // A token is a credential: nothing between here and the client may keep a copy.
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(new TokenResponse(issued.token(), "Bearer", issued.expiresInSeconds(), issued.expiresAt()));
    }
}
