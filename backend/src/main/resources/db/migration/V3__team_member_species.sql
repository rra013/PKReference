-- Phase 1b: each member's species the app's way (SpeciesVocabularies), so the server's counts can
-- match the app's. Rows stored before this get keys when the team store is rebuilt (README).

-- "arcanine:hisui": the species ID and the form words its regulation lists.
alter table team_member add column species_key varchar(255);
-- The held Mega Stone's ID ("charizarditey"), when it's one of the species' own.
alter table team_member add column mega_stone varchar(64);

create index team_member_species on team_member (species_key);
