package com.pkreference.backend.ingest;

import com.pkreference.backend.config.Topics;
import com.pkreference.backend.model.Events.Tournament;
import com.pkreference.backend.model.Events.TournamentDiscovered;
import com.pkreference.backend.usage.ProcessedTournamentRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

/** Polls Limitless for recent tournaments and emits one event per tournament not yet aggregated. */
@Component
@ConditionalOnProperty(name = "pkref.limitless.ingest-enabled", havingValue = "true", matchIfMissing = true)
public class TournamentIngestor {
    private static final Logger log = LoggerFactory.getLogger(TournamentIngestor.class);

    private final LimitlessClient client;
    private final ProcessedTournamentRepository processed;
    private final KafkaTemplate<String, Object> kafka;

    public TournamentIngestor(LimitlessClient client, ProcessedTournamentRepository processed,
                              KafkaTemplate<String, Object> kafka) {
        this.client = client;
        this.processed = processed;
        this.kafka = kafka;
    }

    @Scheduled(initialDelayString = "${pkref.limitless.initial-delay:5s}",
               fixedDelayString = "${pkref.limitless.poll-interval:30m}")
    public void poll() {
        List<Tournament> page;
        try {
            page = client.tournaments(1);
        } catch (RuntimeException e) {
            log.error("Could not list Limitless tournaments", e);
            return;
        }
        int sent = 0;
        for (Tournament t : page) {
            if (processed.existsById(t.id())) continue;
            kafka.send(Topics.TOURNAMENTS_DISCOVERED, t.id(), new TournamentDiscovered(t));
            sent++;
        }
        log.info("Ingest: {} tournaments listed, {} new", page.size(), sent);
    }
}
