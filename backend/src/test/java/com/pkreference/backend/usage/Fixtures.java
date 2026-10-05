package com.pkreference.backend.usage;

import com.pkreference.backend.model.Events.Standing;
import com.pkreference.backend.model.Events.StandingsFetched;
import com.pkreference.backend.model.Events.TeamMember;
import com.pkreference.backend.model.Events.Tournament;

import java.util.List;

final class Fixtures {
    private Fixtures() {}

    static TeamMember member(String id, String item, String move, String nature) {
        return new TeamMember(id, id, item, "Intimidate", List.of(move), nature, "fire");
    }

    static Standing standing(int placing, TeamMember... team) {
        return new Standing("p" + placing, "Player " + placing, null, placing, null, null, List.of(team), null);
    }

    /** Four teams (all run incineroar, with messy spellings; one runs rillaboom) plus a dropped player. */
    static StandingsFetched tournament(String id) {
        var t = new Tournament(id, "Test Cup", "VGC", "reg-m-a", "2026-09-01T00:00:00.000Z", 5);
        return new StandingsFetched(t, List.of(
                standing(1, member("incineroar", "Sitrus Berry", "Fake Out", "Jolly"),
                            member("rillaboom", "Assault Vest", "Grassy Glide", "Adamant")),
                standing(2, member("incineroar", "Safety Goggles", "Fake Out", "jolly")),
                standing(3, new TeamMember("Incineroar", "incineroar", "sitrus berry", "intimidate",
                        List.of("FAKE OUT", "Darkest Larient"), "JOLLY", null)),
                standing(4, new TeamMember("Incineroar", "incineroar", "LIFE ORB", "Intimidate",
                        List.of("Flare Blitz"), "Adamant", null)),
                new Standing("p5", "Dropped", null, null, null, null, null, 1)));
    }
}
