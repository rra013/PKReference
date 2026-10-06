-- Phase 2a: a counter the team store bumps in the same transaction as each write, so the
-- insights' memoized results are keyed on exactly what's committed.
create table store_version (
    id      integer not null primary key,
    version bigint  not null
);

insert into store_version (id, version) values (1, 0);
