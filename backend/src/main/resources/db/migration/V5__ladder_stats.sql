-- Phase 5: Smogon's monthly ladder stats, reduced (Ladder.Stats), one row per format, month and
-- rating. Written from ladder.stats, so the table can be rebuilt by reading the topic again.
create table ladder_stats (
    format      varchar(64)              not null,  -- Smogon's id: gen9championsvgc2026regmc
    stats_month varchar(7)               not null,  -- 2026-09
    rating      integer                  not null,  -- Smogon's cutoff: 0, 1500, 1630, 1760
    regulation  varchar(32)              not null,  -- M-C
    mode        varchar(16)              not null,  -- doubles, singles
    best_of     integer                  not null,
    battles     bigint                   not null,
    reduction   integer                  not null,  -- LadderReducer.REDUCTION when it was made
    fetched_at  timestamp with time zone not null,
    -- Each Pokémon's usage, as a JSON object by name: read for trends and the other ratings'
    -- usage without reading whole records.
    usage_by_name text                   not null,
    -- The whole record, as JSON.
    stats       text                     not null,
    primary key (format, stats_month, rating)
);
