-- Phase 1: every event's teams and matches, and what's been asked for.

-- What discovery has asked for, and what's come back. Owned by EventDiscovery and EventFetcher.
create table event_fetch (
    event_id       varchar(64)              not null primary key,
    format         varchar(32),
    event_date     timestamp with time zone,
    requested_at   timestamp with time zone not null,
    fetched_at     timestamp with time zone,
    standings_final boolean                 not null default false
);

-- The rest is the team store, written from standings.fetched and pairings.fetched. Each new
-- fetch of an event replaces its rows, so the tables can be rebuilt by reading the topics again.

create table event (
    id         varchar(64)  not null primary key,
    game       varchar(32),
    format     varchar(32)  not null,
    name       varchar(512),
    event_date timestamp with time zone,
    players    integer      not null,
    organizer  varchar(255),
    platform   varchar(32),
    online     boolean,
    decklists  boolean,
    fetched_at timestamp with time zone,
    standings_final boolean not null
);

create index event_format_date on event (format, event_date);

-- SWISS, SINGLE_BRACKET and so on, from the event's details.
create table event_phase (
    event_id varchar(64) not null references event (id) on delete cascade,
    phase    integer     not null,
    type     varchar(32),
    rounds   integer,
    mode     varchar(16),
    primary key (event_id, phase)
);

-- One player's entry: their record, placing, and (when the event published it) their team.
create table team (
    event_id     varchar(64)  not null references event (id) on delete cascade,
    player       varchar(255) not null,
    name         varchar(255),
    country      varchar(8),
    placement    integer,  -- Limitless's "placing", a reserved word in Postgres
    wins         integer,
    losses       integer,
    ties         integer,
    dropped      integer,
    primary key (event_id, player)
);

create table team_member (
    event_id     varchar(64)  not null,
    player       varchar(255) not null,
    slot         integer      not null,
    name         varchar(255),
    limitless_id varchar(255),
    item         varchar(255),
    ability      varchar(255),
    nature       varchar(64),
    tera         varchar(64),
    primary key (event_id, player, slot),
    foreign key (event_id, player) references team (event_id, player) on delete cascade
);

create table team_member_move (
    event_id  varchar(64)  not null,
    player    varchar(255) not null,
    slot      integer      not null,
    move_slot integer      not null,
    move      varchar(255) not null,
    primary key (event_id, player, slot, move_slot),
    foreign key (event_id, player, slot) references team_member (event_id, player, slot) on delete cascade
);

-- Matches. No key to event: pairings can arrive before standings.
-- result: P1, P2 (who won), TIE, DOUBLE_LOSS, BYE (player1 had no opponent and won) or
-- NO_SHOW (player1 had no opponent and lost, for lateness).
create table pairing (
    event_id varchar(64)  not null,
    ordinal  integer      not null,
    round    integer      not null,
    phase    integer      not null,
    table_no integer,
    label    varchar(32),
    player1  varchar(255),
    player2  varchar(255),
    winner   varchar(255),
    result   varchar(16)  not null,
    primary key (event_id, ordinal)
);

create index pairing_event_phase on pairing (event_id, phase);

-- When each event's pairings were last fetched (an event can have none), so an older fetch
-- doesn't replace a newer one.
create table pairing_fetch (
    event_id   varchar(64) not null primary key,
    fetched_at timestamp with time zone
);
