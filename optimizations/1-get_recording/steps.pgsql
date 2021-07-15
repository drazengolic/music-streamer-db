-- 
-- Original query.
--
-- Obtains recording based on track id and maximum quality level.
--
prepare get_recording (int, int) as
select
  r.file_uri
from
  recording r
  inner join recording_type rt on r.recording_type_id = rt.id
where
  r.track_id = $1
  and rt.quality_level <= (
    select
      quality_level
    from
      recording_type
    where
      id = $2)
order by
  rt.quality_level desc
limit 1;

-------------------------
-- Optimization steps
-------------------------

-- 1) copy quality_level column

alter table recording
  add column quality_level smallint;

update
  recording
set
  quality_level = case
    when recording_type_id = 1 then 96
    when recording_type_id = 2 then 128
    when recording_type_id = 3 then 320
    else 1411
  end; -- 15m

alter table recording 
  alter column quality_level set not null;

-- 2) create trigger for consistency
create or replace function sync_rec_quality_lvl()
  returns trigger
  language plpgsql
as $$
begin
  if TG_OP='INSERT' or NEW.recording_type_id <> OLD.recording_type_id then
    select quality_level into NEW.quality_level from recording_type where id=NEW.recording_type_id;
  end if;

  return NEW;
end;
$$;

create trigger quality_level_sync before insert or update on recording
  for each row execute procedure sync_rec_quality_lvl();


-- 3) covering index for search

create unique index u_recording_locator on recording (track_id, quality_level desc) include (file_uri);

-- 4) New query with covering index

prepare get_recording (int, smallint) as
select
  file_uri
from
  recording
where
  track_id = $1
  and quality_level <= $2
order by
  track_id,
  quality_level desc
limit 1;