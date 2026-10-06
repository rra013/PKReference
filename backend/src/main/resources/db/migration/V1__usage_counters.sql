-- The usage counters, as the backend kept them before Flyway (UsageCounter, ProcessedTournament).

create table usage_counter (
    id       varchar(2048) not null primary key,
    fmt      varchar(255),
    category varchar(255),
    species  varchar(255),
    val      varchar(1024),
    n        bigint        not null
);

create index usage_counter_fmt_category_species on usage_counter (fmt, category, species);

-- Written in the same transaction as the counters, so a replayed tournament is a no-op.
create table processed_tournament (
    id varchar(255) not null primary key
);
