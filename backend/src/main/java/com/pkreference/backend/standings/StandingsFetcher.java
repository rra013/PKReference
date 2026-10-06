package com.pkreference.backend.standings;

import com.pkreference.backend.config.KafkaSends;
import com.pkreference.backend.config.Topics;
import com.pkreference.backend.ingest.LimitlessClient;
import com.pkreference.backend.model.Events.StandingsFetched;
import com.pkreference.backend.model.Events.TournamentDiscovered;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

/** tournaments.discovered -> fetch standings -> standings.fetched. Failures retry, then go to the DLT. */
@Component
public class StandingsFetcher {
    private static final Logger log = LoggerFactory.getLogger(StandingsFetcher.class);

    private final LimitlessClient client;
    private final KafkaTemplate<String, Object> kafka;

    public StandingsFetcher(LimitlessClient client, KafkaTemplate<String, Object> kafka) {
        this.client = client;
        this.kafka = kafka;
    }

    @KafkaListener(topics = Topics.TOURNAMENTS_DISCOVERED, groupId = "standings-fetcher")
    public void onDiscovered(TournamentDiscovered event) {
        var t = event.tournament();
        var standings = client.standings(t.id());
        log.info("Fetched {} standings for {}", standings.size(), t.id());
        // A failed send throws, so the record retries and then goes to the DLT.
        KafkaSends.await(kafka.send(Topics.STANDINGS_FETCHED, t.id(), new StandingsFetched(t, standings)));
    }
}
