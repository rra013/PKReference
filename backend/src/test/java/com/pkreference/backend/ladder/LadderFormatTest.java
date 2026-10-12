package com.pkreference.backend.ladder;

import org.junit.jupiter.api.Test;

import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class LadderFormatTest {
    private static final Set<String> REGULATIONS = Set.of("m-a", "m-b", "m-c");

    @Test
    void readsSmogonsIds() {
        assertThat(LadderFormat.parse("gen9championsvgc2026regmc", REGULATIONS))
                .isEqualTo(new LadderFormat("gen9championsvgc2026regmc", "M-C", "doubles", 1));
        assertThat(LadderFormat.parse("gen9championsvgc2026regmbbo3", REGULATIONS))
                .isEqualTo(new LadderFormat("gen9championsvgc2026regmbbo3", "M-B", "doubles", 3));
        assertThat(LadderFormat.parse("gen9championsbssregmc", REGULATIONS))
                .isEqualTo(new LadderFormat("gen9championsbssregmc", "M-C", "singles", 1));
        // Another year's doubles, and another generation's.
        assertThat(LadderFormat.parse("gen10championsvgc2027regma", REGULATIONS).regulation()).isEqualTo("M-A");
    }

    @Test
    void leavesOutEverythingElse() {
        for (String id : new String[] {
                "gen9championsou", "gen9championsuu", "gen9vgc2026regi", "gen9championsvgc2026regmd",
                "gen9championsvgc2026regmc-1760", "gen9championsbssreg", "championsbssregmc", ""}) {
            assertThat(LadderFormat.parse(id, REGULATIONS)).as(id).isNull();
        }
        assertThat(LadderFormat.parse("gen9championsbssregmc", Set.of())).isNull();
    }
}
