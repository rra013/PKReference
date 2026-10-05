package com.pkreference.backend.standardize;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** Runs against the real regulation files bundled from the repo root. */
class NameStandardizerTest {
    private final NameStandardizer std = new NameStandardizer(new ObjectMapper());

    @Test
    void casingAndPunctuationCollapse() {
        assertThat(std.item("M-C", "MIRACLE SEED")).isEqualTo("Miracle Seed");
        assertThat(std.item("M-C", "miracle seed")).isEqualTo("Miracle Seed");
        assertThat(std.move("M-C", "Fake out")).isEqualTo("Fake Out");
        assertThat(std.move("M-C", "Fake-out")).isEqualTo("Fake Out");
        assertThat(std.move("M-C", "Hypervoice")).isEqualTo("Hyper Voice");
        assertThat(std.ability("M-C", "intimidate")).isEqualTo("Intimidate");
        assertThat(std.ability("M-C", "Good as gold")).isEqualTo("Good as Gold");
        assertThat(std.item("M-C", "Never-melt ice")).isEqualTo("Never-Melt Ice");
    }

    @Test
    void typosResolveToTheSingleNearbyName() {
        assertThat(std.move("M-C", "Darkest Larient")).isEqualTo("Darkest Lariat");
        assertThat(std.move("M-C", "Clam Mind")).isEqualTo("Calm Mind");
        assertThat(std.item("M-C", "Chopple Berry")).isEqualTo("Chople Berry");
        assertThat(std.item("M-C", "Staraptorite")).isEqualTo("Staraptite");
        assertThat(std.ability("M-C", "Lightening Rod")).isEqualTo("Lightning Rod");
        assertThat(std.nature("Adament")).isEqualTo("Adamant");
    }

    @Test
    void itemsMBAddedResolveForMC() {
        // Added in M-B; champions-m-b.json and champions-m-c.json list them since 2026-10-05.
        assertThat(std.item("M-C", "LIFE ORB")).isEqualTo("Life Orb");
        assertThat(std.item("M-C", "life orb")).isEqualTo("Life Orb");
        assertThat(std.item("M-C", "Wide Lens")).isEqualTo("Wide Lens");
        assertThat(std.item("M-C", "expert belt")).isEqualTo("Expert Belt");
    }

    @Test
    void namesInNoListAreKeptNotDropped() {
        // Not Champions items at all, but decklists in fan formats use them.
        assertThat(std.item("M-C", "ASSAULT VEST")).isEqualTo("Assault Vest");
        assertThat(std.item("CUSTOM", "safety goggles")).isEqualTo("Safety Goggles");
    }

    @Test
    void megaStonesUseTheGamesNames() {
        // The regulation files guessed "Golisopodite" and "Baxcaliburite" until 2026-10-05.
        assertThat(std.item("M-C", "Golisopite")).isEqualTo("Golisopite");
        assertThat(std.item("M-C", "baxcalibrite")).isEqualTo("Baxcalibrite");
        assertThat(std.item("M-C", "Golisopodite")).isEqualTo("Golisopite");
        assertThat(std.item("M-C", "light clay")).isEqualTo("Light Clay");
        assertThat(std.item("M-C", "Wise Glasses")).isEqualTo("Wise Glasses");
        assertThat(std.item("M-C", "Muscle  Band")).isEqualTo("Muscle Band");
    }

    @Test
    void noItemVariantsMerge() {
        assertThat(std.item("M-C", "none")).isEqualTo("No Item");
        assertThat(std.item("M-C", "No Item")).isEqualTo("No Item");
        assertThat(std.item("M-C", "  ")).isEqualTo("No Item");
        assertThat(std.item("M-C", null)).isNull();
    }

    @Test
    void unknownFormatsStillStandardize() {
        assertThat(std.move("CUSTOM", "fake out")).isEqualTo("Fake Out");
        assertThat(std.item(null, "Garchompite z")).isEqualTo("Garchompite Z");
    }

    @Test
    void teraAndNaturesAreCapitalized() {
        assertThat(std.tera("fire")).isEqualTo("Fire");
        assertThat(std.nature("JOLLY")).isEqualTo("Jolly");
        assertThat(std.tera(null)).isNull();
    }

    @Test
    void distinctShortNamesAreNotMerged() {
        // Under 5 letters, only exact matches count.
        assertThat(std.move("M-C", "Bite")).isEqualTo("Bite");
        assertThat(std.move("M-C", "Bide")).isEqualTo("Bide");
    }
}
