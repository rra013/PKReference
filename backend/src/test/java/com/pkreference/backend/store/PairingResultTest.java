package com.pkreference.backend.store;

import com.pkreference.backend.LimitlessFixtures;
import com.pkreference.backend.model.Events.Pairing;
import org.junit.jupiter.api.Test;

import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

class PairingResultTest {
    /** Limitless sends the winner as a username, or as the number 0 or -1. */
    @Test
    void readsARealEventsResults() {
        Map<PairingResult, Long> results = LimitlessFixtures.pairings().stream()
                .collect(Collectors.groupingBy(PairingResult::of, Collectors.counting()));
        assertThat(results).containsExactlyInAnyOrderEntriesOf(Map.of(
                PairingResult.P1, 90L, PairingResult.P2, 88L, PairingResult.NO_SHOW, 6L,
                PairingResult.DOUBLE_LOSS, 3L, PairingResult.BYE, 1L));
    }

    @Test
    void eachResult() {
        Function<Pairing, PairingResult> of = PairingResult::of;
        assertThat(of.apply(new Pairing(1, 1, 4, null, "a", "b", "a"))).isEqualTo(PairingResult.P1);
        assertThat(of.apply(new Pairing(1, 1, 4, null, "a", "b", "b"))).isEqualTo(PairingResult.P2);
        assertThat(of.apply(new Pairing(1, 1, 4, null, "a", "b", "0"))).isEqualTo(PairingResult.TIE);
        assertThat(of.apply(new Pairing(1, 1, 4, null, "a", "b", "-1"))).isEqualTo(PairingResult.DOUBLE_LOSS);
        assertThat(of.apply(new Pairing(1, 1, null, null, "a", null, "a"))).isEqualTo(PairingResult.BYE);
        assertThat(of.apply(new Pairing(1, 1, null, null, "a", null, "-1"))).isEqualTo(PairingResult.NO_SHOW);
        assertThat(of.apply(new Pairing(7, 2, null, "T4-1", "a", "b", null))).isEqualTo(PairingResult.UNKNOWN);
        assertThat(of.apply(new Pairing(1, 1, 4, null, "a", "b", "c"))).isEqualTo(PairingResult.UNKNOWN);

        assertThat(PairingResult.P1.wasPlayed()).isTrue();
        assertThat(PairingResult.DOUBLE_LOSS.wasPlayed()).isTrue();
        assertThat(PairingResult.BYE.wasPlayed()).isFalse();
        assertThat(PairingResult.NO_SHOW.wasPlayed()).isFalse();
    }
}
