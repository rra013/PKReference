package com.pkreference.backend.corpus;

import com.pkreference.backend.model.Events.Standing;
import com.pkreference.backend.model.Events.Tournament;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;

/**
 * The stored events in Limitless's shapes, for the app's Team Search corpus: the same two calls it
 * makes to Limitless (a page of a format's tournaments, and one tournament's standings), answered
 * from the server, so devices stop crawling Limitless each.
 */
@RestController
@RequestMapping("/v1")
@Tag(name = "Corpus", description = """
        Stored events in Limitless's own JSON shapes, for the app's Team Search corpus. Cached for 15 minutes, with \
        ETags.""")
public class CorpusController {
    static final CacheControl CACHE = CacheControl.maxAge(Duration.ofMinutes(15)).cachePublic();
    static final int MAX_LIMIT = 100;

    private final CorpusRepository corpus;

    public CorpusController(CorpusRepository corpus) {
        this.corpus = corpus;
    }

    @GetMapping("/formats/{format}/tournaments")
    @Operation(summary = "A page of a format's events",
            description = "Newest first, as Limitless's GET /tournaments lists them.")
    public ResponseEntity<List<Tournament>> tournaments(
            @Parameter(description = "Limitless format id.", example = "M-C") @PathVariable String format,
            @Parameter(description = "Page, from 1.") @RequestParam(defaultValue = "1") int page,
            @Parameter(description = "Events a page, up to 100.") @RequestParam(defaultValue = "50") int limit) {
        if (page < 1 || limit < 1) throw new IllegalArgumentException("page and limit must be at least 1");
        return ResponseEntity.ok().cacheControl(CACHE)
                .body(corpus.tournaments(format, page, Math.min(limit, MAX_LIMIT)));
    }

    @GetMapping("/tournaments/{id}/standings")
    @Operation(summary = "One event's standings and teams",
            description = "As Limitless's GET /tournaments/{id}/standings returns them. 404 when the event isn't stored.")
    public ResponseEntity<List<Standing>> standings(@PathVariable String id) {
        var standings = corpus.standings(id);
        if (standings == null) throw new NoSuchElementException("No stored event " + id);
        return ResponseEntity.ok().cacheControl(CACHE).body(standings);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> badRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(NoSuchElementException.class)
    ResponseEntity<Map<String, String>> notFound(NoSuchElementException e) {
        return ResponseEntity.status(404).body(Map.of("error", e.getMessage()));
    }
}
