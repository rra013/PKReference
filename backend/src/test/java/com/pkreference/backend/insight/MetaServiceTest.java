package com.pkreference.backend.insight;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pkreference.backend.insight.MetaResponses.Core;
import com.pkreference.backend.insight.MetaResponses.PokemonUsage;
import com.pkreference.backend.insight.MetaResponses.Share;
import com.pkreference.backend.insight.MetaResponses.WinRecord;
import com.pkreference.backend.model.Events.PairingsFetched;
import com.pkreference.backend.model.Events.StandingsFetched;
import com.pkreference.backend.model.Events.Tournament;
import com.pkreference.backend.standardize.NameStandardizer;
import com.pkreference.backend.standardize.SpeciesVocabularies;
import com.pkreference.backend.store.TeamStore;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.NoSuchElementException;

import static com.pkreference.backend.LimitlessFixtures.details;
import static com.pkreference.backend.LimitlessFixtures.pairings;
import static com.pkreference.backend.LimitlessFixtures.standings;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The insights over the real fixture event, on the migrations. The expected numbers were worked out
 * separately, in Python, from the fixture and the species golden file.
 */
@JdbcTest
@Import({TeamStore.class, SpeciesVocabularies.class, MetaRepository.class, MetaService.class,
        NameStandardizer.class, MetaServiceTest.Config.class})
class MetaServiceTest {
    /** The day after the event. */
    static final Instant NOW = Instant.parse("2026-10-06T12:00:00Z");

    @TestConfiguration
    static class Config {
        /** In place of the application's clock. */
        @Bean
        @Primary
        Clock fixedClock() {
            return Clock.fixed(NOW, ZoneOffset.UTC);
        }

        @Bean
        ObjectMapper objectMapper() {
            return new ObjectMapper();
        }
    }

    @Autowired TeamStore store;
    @Autowired MetaService meta;

    private void put(String id, String date, int teams) {
        var t = new Tournament(id, "Test Event", "VGC", "M-C", date, 83);
        store.putStandings(new StandingsFetched(t, standings().subList(0, teams), details(), NOW, true));
        store.putPairings(new PairingsFetched(t, pairings(), NOW));
    }

    @BeforeEach
    void setUp() {
        meta.forget();
        put("event-83", "2026-10-05T18:00:00.000Z", 83);
    }

    private static PokemonUsage find(List<PokemonUsage> list, String key) {
        return list.stream().filter(p -> p.key().equals(key)).findFirst().orElseThrow();
    }

    @Test
    void usageAndTopCut() {
        var list = meta.pokemon("M-C", MetaWindow.DAYS_30);
        assertThat(list.sample().events()).isEqualTo(1);
        assertThat(list.sample().teams()).isEqualTo(83);
        assertThat(list.sample().topCutTeams()).isEqualTo(16);
        assertThat(list.pokemon()).extracting(PokemonUsage::key)
                .startsWith("rillaboom", "incineroar", "gholdengo", "raichu", "garchomp", "sneasler");
        // Records leave out mirror matches; the ranges are 95% Wilson intervals.
        assertThat(list.pokemon().get(0)).isEqualTo(new PokemonUsage("rillaboom", 44, 0.5301, 9, 0.5625, null,
                new WinRecord(46, 51, 0, 97, 0.4742, 0.3777, 0.5727)));
        assertThat(find(list.pokemon(), "garchomp")).isEqualTo(new PokemonUsage("garchomp", 26, 0.3133, 3, 0.1875, null,
                new WinRecord(36, 42, 0, 78, 0.4615, 0.3553, 0.5714)));
        assertThat(find(list.pokemon(), "incineroar").record()).isEqualTo(new WinRecord(47, 49, 0, 96, 0.4896, 0.3919, 0.588));
        // The format's case doesn't matter.
        assertThat(meta.pokemon("m-c", MetaWindow.DAYS_30).sample().teams()).isEqualTo(83);
    }

    @Test
    void aPokemonsPage() {
        var rillaboom = meta.pokemon("M-C", "rillaboom", MetaWindow.DAYS_30);
        assertThat(rillaboom.items()).startsWith(new Share("Miracle Seed", 38, 0.8636), new Share("Eject Button", 4, 0.0909));
        assertThat(rillaboom.abilities()).containsExactly(new Share("Grassy Surge", 44, 1.0));
        assertThat(rillaboom.moves()).startsWith(new Share("Fake Out", 44, 1.0), new Share("Grassy Glide", 44, 1.0),
                new Share("Wood Hammer", 39, 0.8864));
        assertThat(rillaboom.teammates()).startsWith(new Share("gholdengo", 24, 0.5455), new Share("raichu", 24, 0.5455),
                new Share("incineroar", 23, 0.5227));
        var top = rillaboom.sets().get(0);
        assertThat(top.item()).isEqualTo("Miracle Seed");
        assertThat(top.nature()).isEqualTo("Adamant");
        assertThat(top.moves()).containsExactly("Fake Out", "Grassy Glide", "High Horsepower", "Wood Hammer");
        assertThat(top.count()).isEqualTo(24);
        assertThat(rillaboom.megaStones()).isEmpty();
        assertThat(rillaboom.weekly()).hasSize(1).first()
                .satisfies(w -> {
                    assertThat(w.week()).isEqualTo(LocalDate.of(2026, 10, 5));
                    assertThat(w.teams()).isEqualTo(83);
                    assertThat(w.withPokemon()).isEqualTo(44);
                });

        assertThat(meta.pokemon("M-C", "raichu", MetaWindow.DAYS_30).megaStones())
                .startsWith(new Share("raichunitey", 26, 0.9286));
        assertThatThrownBy(() -> meta.pokemon("M-C", "missingno", MetaWindow.DAYS_30))
                .isInstanceOf(NoSuchElementException.class);
    }

    @Test
    void thinRecordsHaveNoRate() {
        var thin = list().pokemon().stream().filter(u -> u.record().matches() > 0 && u.record().matches() < 30).findFirst();
        assertThat(thin).hasValueSatisfying(u -> assertThat(u.record().winRate()).isNull());
    }

    @Test
    void cores() {
        var cores = meta.cores("M-C", MetaWindow.DAYS_30);
        assertThat(cores.pairs().get(0)).isEqualTo(new Core(List.of("gholdengo", "rillaboom"), 24, 0.2892, 1.6169));
        assertThat(cores.pairs().get(1)).isEqualTo(new Core(List.of("raichu", "rillaboom"), 24, 0.2892, 1.6169));
        assertThat(cores.pairs().get(2).members()).containsExactly("incineroar", "rillaboom");
        assertThat(cores.pairs().get(2).lift()).isEqualTo(1.3147);
        assertThat(cores.trios().get(0).members()).containsExactly("gholdengo", "raichu", "rillaboom");
        assertThat(cores.trios().get(0).teams()).isEqualTo(19);
        assertThat(cores.pairs()).hasSizeLessThanOrEqualTo(20).allSatisfy(c -> assertThat(c.teams()).isGreaterThanOrEqualTo(4));
    }

    @Test
    void archetypes() {
        var archetypes = meta.archetypes("M-C", MetaWindow.DAYS_30);
        assertThat(archetypes.other()).isEqualTo(59);
        var first = archetypes.archetypes().get(0);
        assertThat(first.id()).isEqualTo("garchomp+gholdengo+rillaboom+volcarona");
        assertThat(first.name()).isEqualTo("rillaboom+gholdengo");
        assertThat(first.teams()).isEqualTo(9);
        assertThat(first.usage()).isEqualTo(0.1084);
        assertThat(first.topCutTeams()).isZero();
        assertThat(first.record().wins()).isEqualTo(12);
        assertThat(first.record().losses()).isEqualTo(17);
        assertThat(first.record().winRate()).as("under 30 matches").isNull();
        assertThat(first.matchups()).filteredOn(m -> m.against().equals("gholdengo+incineroar+raichu+rillaboom"))
                .singleElement().satisfies(m -> {
                    assertThat(m.record().wins()).isEqualTo(3);
                    assertThat(m.record().losses()).isEqualTo(1);
                });
        var second = archetypes.archetypes().get(1);
        assertThat(second.id()).isEqualTo("arcanine:hisui+gholdengo+raichu+staraptor");
        assertThat(second.name()).isEqualTo("gholdengo+raichu");
        assertThat(second.topCutTeams()).isEqualTo(2);
        assertThat(second.record().wins()).isEqualTo(14);
        assertThat(second.record().losses()).isEqualTo(13);
        // Each team is in one archetype at most.
        assertThat(archetypes.archetypes().stream().mapToInt(a -> a.teams()).sum() + archetypes.other()).isEqualTo(83);
        // Two cores' two most-used members are Rillaboom and Incineroar: the one with fewer teams adds its third.
        assertThat(archetypes.archetypes()).extracting(MetaResponses.Archetype::name).containsExactly(
                "rillaboom+gholdengo", "gholdengo+raichu", "rillaboom+incineroar", "rillaboom+incineroar+gholdengo",
                "incineroar+raichu");
        assertThat(archetypes.archetypes().get(3).id()).isEqualTo("gholdengo+incineroar+raichu+rillaboom");
    }

    @Test
    void anArchetypesPage() {
        var page = meta.archetype("M-C", "garchomp+gholdengo+rillaboom+volcarona", MetaWindow.DAYS_30);
        assertThat(page.archetype().name()).isEqualTo("rillaboom+gholdengo");
        assertThat(page.sample().teams()).isEqualTo(83);
        // Its five best-placed teams of nine.
        assertThat(page.examples()).extracting(MetaResponses.ExampleTeam::placing).containsExactly(19, 23, 26, 33, 46);
        var best = page.examples().get(0);
        assertThat(best.player()).isEqualTo("Player 19");
        assertThat(best.eventName()).isEqualTo("Test Event");
        assertThat(best.players()).isEqualTo(83);
        assertThat(best.wins()).isEqualTo(3);
        assertThat(best.losses()).isEqualTo(1);
        assertThat(best.members()).hasSize(6);
        assertThat(best.members().get(0)).isEqualTo(new MetaResponses.ExampleMember("gholdengo", "Gholdengo",
                "Life Orb", "Good as Gold", "Modest", List.of("Protect", "Shadow Ball", "Nasty Plot", "Make It Rain")));
        assertThat(best.members()).extracting(MetaResponses.ExampleMember::key)
                .contains("garchomp", "gholdengo", "rillaboom", "volcarona");

        assertThatThrownBy(() -> meta.archetype("M-C", "a+b+c+d", MetaWindow.DAYS_30))
                .isInstanceOf(NoSuchElementException.class);
    }

    @Test
    void events() {
        put("older", "2026-09-01T18:00:00.000Z", 83);
        var events = meta.events("M-C", 10);
        assertThat(events.events()).extracting(MetaResponses.EventSummary::id).containsExactly("event-83", "older");
        var newest = events.events().get(0);
        assertThat(newest.name()).isEqualTo("Test Event");
        assertThat(newest.date()).isEqualTo(Instant.parse("2026-10-05T18:00:00Z"));
        assertThat(newest.players()).isEqualTo(83);
        assertThat(newest.standingsFinal()).isTrue();
        assertThat(newest.topCutPlayers()).isEqualTo(16);
        assertThat(newest.winner()).isEqualTo(new MetaResponses.EventWinner("Player 01", 8, 2, 0,
                List.of("grimmsnarl", "golisopod", "pelipper", "charizard", "basculegion", "archaludon")));
        assertThat(meta.events("M-C", 1).events()).hasSize(1);
        assertThat(meta.events("M-B", 10).events()).isEmpty();
    }

    @Test
    void namesAreUnique() {
        var record = new WinRecord(0, 0, 0, 0, null, null, null);
        var named = MetaService.named(List.of(
                new MetaResponses.Archetype("a+b+c+d", null, List.of("a", "b", "c", "d"), 9, 0, 0, null, record, List.of()),
                new MetaResponses.Archetype("a+b+e+f", null, List.of("a", "b", "e", "f"), 8, 0, 0, null, record, List.of()),
                new MetaResponses.Archetype("a+b+e+g", null, List.of("a", "b", "e", "g"), 7, 0, 0, null, record, List.of()),
                new MetaResponses.Archetype("b+c+g+h", null, List.of("b", "a", "g", "h"), 6, 0, 0, null, record, List.of())));
        assertThat(named).extracting(MetaResponses.Archetype::name)
                .containsExactly("a+b", "a+b+e", "a+b+e+g", "b+a");
    }

    private MetaResponses.PokemonList list() {
        return meta.pokemon("M-C", MetaWindow.DAYS_30);
    }

    @Test
    void windows() {
        put("older", "2026-09-01T18:00:00.000Z", 83);
        assertThat(meta.pokemon("M-C", MetaWindow.DAYS_14).sample().teams()).isEqualTo(83);
        assertThat(meta.pokemon("M-C", MetaWindow.DAYS_30).sample().teams()).isEqualTo(83);
        var all = meta.pokemon("M-C", MetaWindow.REGULATION);
        assertThat(all.sample().teams()).isEqualTo(166);
        assertThat(all.sample().events()).isEqualTo(2);
        assertThat(all.from()).isNull();
        assertThat(meta.formats().formats()).singleElement()
                .satisfies(f -> assertThat(f.teams()).isEqualTo(166));
    }

    /** The last 14 days (83 teams) against the 14 before (the first 60 teams of a copy). */
    @Test
    void trends() {
        put("three-weeks-ago", "2026-09-15T18:00:00.000Z", 60);
        var list = meta.pokemon("M-C", MetaWindow.DAYS_30);
        assertThat(find(list.pokemon(), "rillaboom").trend()).isEqualTo(-0.0199);
        assertThat(find(list.pokemon(), "incineroar").trend()).isEqualTo(-0.0024);
    }

    @Test
    void noTrendFromThinData() {
        put("three-weeks-ago", "2026-09-15T18:00:00.000Z", 40);
        assertThat(find(meta.pokemon("M-C", MetaWindow.DAYS_30).pokemon(), "rillaboom").trend()).isNull();
    }
}
