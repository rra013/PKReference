package com.pkreference.backend.ladder;

import com.pkreference.backend.ladder.LadderResponses.Index;
import com.pkreference.backend.ladder.LadderResponses.Stats;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
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
import java.util.regex.Pattern;

/** API v1's ladder: read-only and cached as the rest of /v1 is (MetaController). */
@RestController
@RequestMapping("/v1/ladder")
@Tag(name = "Ladder", description = """
        Pokémon Showdown's ladder, from Smogon's monthly usage stats: usage at each rating cutoff, items, \
        abilities, moves, natures, stat-point spreads, teammates and leads, for Champions doubles and singles. \
        A month's stats appear on the 1st of the next month. Read-only and cached (15 minutes, with ETags). \
        Shares are 0 to 1.""")
public class LadderController {
    /** {@code Cache-Control: max-age=900, public}, as MetaController's: 15 minutes. */
    static final CacheControl CACHE = CacheControl.maxAge(Duration.ofMinutes(15)).cachePublic();
    /** A month as the API takes it: four digits, a hyphen, 01 to 12. */
    private static final Pattern MONTH = Pattern.compile("^\\d{4}-(0[1-9]|1[0-2])$");

    private final LadderService ladder;

    /** Constructor injection: Spring supplies each parameter from the beans it has made. */
    public LadderController(LadderService ladder) {
        this.ladder = ladder;
    }

    /**
     * GET /v1/ladder: what the app reads first, to find the format id for a regulation's doubles or
     * singles ladder.
     */
    @GetMapping
    @Operation(summary = "The ladder stats stored",
            description = "Each format, month and rating the server has, with its regulation, doubles or singles, "
                    + "best of 1 or 3, and how many battles it's from.")
    public ResponseEntity<Index> index() {
        return ResponseEntity.ok().cacheControl(CACHE).body(ladder.index());
    }

    /**
     * GET /v1/ladder/{format}?rating=1760&month=2026-09. {@code required = false} with a boxed type
     * ({@code Integer}) lets a parameter be left out, arriving as null for the service to default.
     * A rating that isn't a number never reaches this method: Spring answers 400 itself.
     */
    @GetMapping("/{format}")
    @Operation(summary = "One month of a format's ladder",
            description = "Every Pokémon used that month, most used first, each with its usage, its change since the "
                    + "month before, its usage at the other ratings, its share of leads, and its abilities, items, "
                    + "moves, natures, spreads and teammates. 404 when the month isn't stored at that rating.")
    public ResponseEntity<Stats> stats(
            @Parameter(description = "Smogon's format id, from GET /v1/ladder.", example = "gen9championsvgc2026regmc")
            @PathVariable String format,
            @Parameter(description = "Smogon's rating cutoff: 0 (every player), 1500, 1630 or 1760 (the default).")
            @RequestParam(required = false) Integer rating,
            @Parameter(description = "The month, as 2026-09. The newest stored when left out.")
            @RequestParam(required = false) String month) {
        if (month != null && !MONTH.matcher(month).matches()) {
            throw new IllegalArgumentException("month must be like 2026-09");
        }
        return ResponseEntity.ok().cacheControl(CACHE).body(ladder.stats(format, rating, month));
    }

    /** A month that isn't one: 400, with the reason as JSON. */
    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> badRequest(IllegalArgumentException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error", e.getMessage()));
    }

    /** A format, month or rating that isn't stored: 404, with the reason as JSON. */
    @ExceptionHandler(NoSuchElementException.class)
    ResponseEntity<Map<String, String>> notFound(NoSuchElementException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", e.getMessage()));
    }
}
