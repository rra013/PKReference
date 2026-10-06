package com.pkreference.backend.insight;

import com.pkreference.backend.insight.MetaResponses.Formats;
import com.pkreference.backend.insight.MetaResponses.PokemonDetail;
import com.pkreference.backend.insight.MetaResponses.PokemonList;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.Map;
import java.util.NoSuchElementException;

/**
 * API v1: read-only, the same for everyone, and cached. Responses may be reused for 15 minutes,
 * and carry an ETag, so a client that has the current one gets a 304 with no body.
 *
 * <pre>
 * GET /v1/formats
 * GET /v1/formats/M-C/pokemon?window=30d          (14d, 30d or regulation)
 * GET /v1/formats/M-C/pokemon/arcanine:hisui?window=30d
 * </pre>
 */
@RestController
@RequestMapping("/v1")
public class MetaController {
    static final CacheControl CACHE = CacheControl.maxAge(Duration.ofMinutes(15)).cachePublic();

    private final MetaService meta;

    public MetaController(MetaService meta) {
        this.meta = meta;
    }

    @GetMapping("/formats")
    public ResponseEntity<Formats> formats() {
        return ResponseEntity.ok().cacheControl(CACHE).body(meta.formats());
    }

    @GetMapping("/formats/{format}/pokemon")
    public ResponseEntity<PokemonList> pokemon(@PathVariable String format,
                                               @RequestParam(required = false) String window) {
        return ResponseEntity.ok().cacheControl(CACHE).body(meta.pokemon(format, MetaWindow.parse(window)));
    }

    @GetMapping("/formats/{format}/pokemon/{key}")
    public ResponseEntity<PokemonDetail> pokemon(@PathVariable String format, @PathVariable String key,
                                                 @RequestParam(required = false) String window) {
        return ResponseEntity.ok().cacheControl(CACHE).body(meta.pokemon(format, key, MetaWindow.parse(window)));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> badRequest(IllegalArgumentException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(NoSuchElementException.class)
    ResponseEntity<Map<String, String>> notFound(NoSuchElementException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", e.getMessage()));
    }
}
