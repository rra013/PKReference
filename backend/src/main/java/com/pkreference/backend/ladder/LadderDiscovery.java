package com.pkreference.backend.ladder;

import com.pkreference.backend.config.KafkaSends;
import com.pkreference.backend.config.SmogonProperties;
import com.pkreference.backend.config.Topics;
import com.pkreference.backend.model.Ladder.Stats;
import com.pkreference.backend.model.Ladder.StatsFetched;
import com.pkreference.backend.standardize.SpeciesVocabularies;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Looks through Smogon's newest months for Champions ladder stats not stored yet, and fetches,
 * reduces and publishes each on ladder.stats. A month appears on the 1st of the next and never
 * changes, so each file is fetched once; a longer lookback, set once, is the backfill.
 */
@Component
@ConditionalOnProperty(name = "pkref.smogon.ingest-enabled", havingValue = "true", matchIfMissing = true)
public class LadderDiscovery {
    private static final Logger log = LoggerFactory.getLogger(LadderDiscovery.class);
    /** "gen9championsvgc2026regmc-1760.json": the format, then the rating. */
    private static final Pattern FILE = Pattern.compile("^(.+)-(\\d+)\\.json$");

    private final SmogonClient client;
    private final LadderReducer reducer;
    private final LadderStore store;
    private final SpeciesVocabularies vocabularies;
    private final KafkaTemplate<String, Object> kafka;
    private final SmogonProperties props;
    private final Clock clock;

    public LadderDiscovery(SmogonClient client, LadderReducer reducer, LadderStore store,
                           SpeciesVocabularies vocabularies, KafkaTemplate<String, Object> kafka,
                           SmogonProperties props, Clock clock) {
        this.client = client;
        this.reducer = reducer;
        this.store = store;
        this.vocabularies = vocabularies;
        this.kafka = kafka;
        this.props = props;
        this.clock = clock;
    }

    @Scheduled(initialDelayString = "${pkref.smogon.initial-delay:20s}",
               fixedDelayString = "${pkref.smogon.poll-interval:12h}")
    public void poll() {
        discover();
    }

    /** The records published, as their topic keys, newest month first. */
    List<String> discover() {
        List<String> months;
        try {
            months = client.months();
        } catch (RuntimeException e) {
            log.error("Could not list Smogon's months", e);
            return List.of();
        }
        Set<String> regulations = vocabularies.formats();
        List<String> published = new ArrayList<>();
        Set<String> skipped = new TreeSet<>();
        int found = 0;
        for (String month : months.subList(0, Math.min(props.lookbackMonths(), months.size()))) {
            List<String> files;
            try {
                files = client.chaosFiles(month);
            } catch (RuntimeException e) {
                log.error("Could not list Smogon's stats for {}", month, e);
                continue;
            }
            for (String file : files) {
                Matcher m = FILE.matcher(file);
                if (!m.matches() || !m.group(1).contains("champions")) continue;
                int rating = Integer.parseInt(m.group(2));
                LadderFormat format = LadderFormat.parse(m.group(1), regulations);
                if (format == null) {
                    skipped.add(m.group(1));
                    continue;
                }
                if (!props.ratings().contains(rating)) continue;
                found++;
                if (store.has(format.id(), month, rating, LadderReducer.REDUCTION)) continue;
                try {
                    String leads = client.leads(month, format.id() + "-" + rating + ".txt");
                    Stats stats = client.chaos(month, file, body -> reducer.reduce(body, leads, format, month, rating));
                    var fetched = new StatsFetched(stats, clock.instant());
                    KafkaSends.await(kafka.send(Topics.LADDER_STATS, fetched.key(), fetched));
                    published.add(fetched.key());
                } catch (RuntimeException e) {
                    // Not stored, so the next poll fetches it again.
                    log.error("Could not fetch ladder stats {} for {}", file, month, e);
                }
            }
        }
        // Smogon's own tiers (OU, UU), or a regulation the bundled data doesn't know yet.
        if (!skipped.isEmpty()) log.info("Ladder discovery left out {}", skipped);
        log.info("Ladder discovery: {} files of Champions ladder stats listed, {} fetched", found, published.size());
        return published;
    }
}
