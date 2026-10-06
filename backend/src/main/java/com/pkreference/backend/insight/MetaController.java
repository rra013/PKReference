package com.pkreference.backend.insight;

import com.pkreference.backend.insight.MetaResponses.ArchetypeDetail;
import com.pkreference.backend.insight.MetaResponses.Archetypes;
import com.pkreference.backend.insight.MetaResponses.Cores;
import com.pkreference.backend.insight.MetaResponses.Events;
import com.pkreference.backend.insight.MetaResponses.Formats;
import com.pkreference.backend.insight.MetaResponses.PokemonDetail;
import com.pkreference.backend.insight.MetaResponses.PokemonList;
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

/**
 * API v1: read-only, the same for everyone, and cached. Responses may be reused for 15 minutes,
 * and carry a weak ETag, so a client that has the current one gets a 304 with no body. Swagger UI
 * at /swagger-ui.html shows it, from these annotations.
 */
@RestController
@RequestMapping("/v1")
@Tag(name = "Meta", description = """
        Tournament insights from Limitless events: usage, top-cut rate, trends, win rates, sets, cores and \
        archetypes, and the newest events. Read-only and cached (15 minutes, with ETags). Shares are 0 to 1.""")
public class MetaController {
    static final CacheControl CACHE = CacheControl.maxAge(Duration.ofMinutes(15)).cachePublic();
    static final int MAX_EVENTS = 50;
    private static final String WINDOW = "14d, 30d (the default) or regulation (every stored event of the format).";

    private final MetaService meta;

    public MetaController(MetaService meta) {
        this.meta = meta;
    }

    @GetMapping("/formats")
    @Operation(summary = "The formats with data",
            description = "Each Limitless format stored: its events, teams, first and last event, and when it was last fetched.")
    public ResponseEntity<Formats> formats() {
        return ResponseEntity.ok().cacheControl(CACHE).body(meta.formats());
    }

    @GetMapping("/formats/{format}/pokemon")
    @Operation(summary = "Every Pokémon's usage",
            description = "Each Pokémon on a team in the window: usage, top-cut rate, trend and win record, most used first.")
    public ResponseEntity<PokemonList> pokemon(
            @Parameter(description = "Limitless format id.", example = "M-C") @PathVariable String format,
            @Parameter(description = WINDOW) @RequestParam(required = false) String window) {
        return ResponseEntity.ok().cacheControl(CACHE).body(meta.pokemon(format, MetaWindow.parse(window)));
    }

    @GetMapping("/formats/{format}/pokemon/{key}")
    @Operation(summary = "One Pokémon's page",
            description = "Its usage and record, items, abilities, natures, moves, Mega Stones, teammates, top whole "
                    + "sets and weekly usage. 404 when no team in the window had it.")
    public ResponseEntity<PokemonDetail> pokemon(
            @Parameter(description = "Limitless format id.", example = "M-C") @PathVariable String format,
            @Parameter(description = "The app's species key.", example = "rillaboom") @PathVariable String key,
            @Parameter(description = WINDOW) @RequestParam(required = false) String window) {
        return ResponseEntity.ok().cacheControl(CACHE).body(meta.pokemon(format, key, MetaWindow.parse(window)));
    }

    @GetMapping("/formats/{format}/cores")
    @Operation(summary = "Pokémon chosen together",
            description = "The 20 most common pairs and trios (on at least 4 teams), with their lift over chance.")
    public ResponseEntity<Cores> cores(
            @Parameter(description = "Limitless format id.", example = "M-C") @PathVariable String format,
            @Parameter(description = WINDOW) @RequestParam(required = false) String window) {
        return ResponseEntity.ok().cacheControl(CACHE).body(meta.cores(format, MetaWindow.parse(window)));
    }

    @GetMapping("/formats/{format}/archetypes")
    @Operation(summary = "Archetypes and their matchups",
            description = "Teams grouped by their core of four: each archetype's usage, top-cut rate, record, and "
                    + "record against each other archetype.")
    public ResponseEntity<Archetypes> archetypes(
            @Parameter(description = "Limitless format id.", example = "M-C") @PathVariable String format,
            @Parameter(description = WINDOW) @RequestParam(required = false) String window) {
        return ResponseEntity.ok().cacheControl(CACHE).body(meta.archetypes(format, MetaWindow.parse(window)));
    }

    @GetMapping("/formats/{format}/archetypes/{id}")
    @Operation(summary = "One archetype, with example teams",
            description = "The archetype as the list has it, and its best-placed teams with their sets. 404 when "
                    + "the window has no archetype with that id.")
    public ResponseEntity<ArchetypeDetail> archetype(
            @Parameter(description = "Limitless format id.", example = "M-C") @PathVariable String format,
            @Parameter(description = "The archetype's id: its core's species keys, sorted, joined with +.",
                    example = "garchomp+gholdengo+incineroar+rillaboom") @PathVariable String id,
            @Parameter(description = WINDOW) @RequestParam(required = false) String window) {
        return ResponseEntity.ok().cacheControl(CACHE).body(meta.archetype(format, id, MetaWindow.parse(window)));
    }

    @GetMapping("/formats/{format}/events")
    @Operation(summary = "The newest stored events",
            description = "Newest first, each with its size, whether its standings are final, its top cut's size "
                    + "and its winner's team.")
    public ResponseEntity<Events> events(
            @Parameter(description = "Limitless format id.", example = "M-C") @PathVariable String format,
            @Parameter(description = "How many, from 1 to " + MAX_EVENTS + ".") @RequestParam(defaultValue = "10") int limit) {
        if (limit < 1 || limit > MAX_EVENTS) throw new IllegalArgumentException("limit must be 1 to " + MAX_EVENTS);
        return ResponseEntity.ok().cacheControl(CACHE).body(meta.events(format, limit));
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
