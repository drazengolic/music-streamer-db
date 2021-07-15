-- 
-- Original query.
--
-- Searches albums via partial, case-insensitive text.
--
prepare album_search (text) as
select
  album.id,
  album.title,
  album.cover_photo,
  json_object_agg(distinct artist.id, artist.name) as artists_json,
  count(distinct ph.id) as rating
from
  album
  inner join album_artist aa on aa.album_id = album.id
  inner join artist on aa.artist_id = artist.id
    and artist.active = true
  inner join track on track.album_id = album.id
  left join play_history ph on ph.track_id = track.id
where
  album.title ilike '%' || $1 || '%'
  and album.active = true
group by
  album.id
order by
  rating desc
limit 5;

execute album_search ('for those');

-------------------------
-- Optimization steps
-------------------------

-- 1) Create total_play_count column

alter table album
  add column total_play_count bigint default 0 not null;

-- 2) Update new column with existing counts

with counts as (
    select 
      album_id, 
      sum(total_play_count) tpc
    from 
      track
    group by
      album_id
)
update
  album
set
  total_play_count = counts.tpc
from
  counts
where
  id = counts.album_id;

-- 3) Store the max value under 'album.tpc' key

insert into bigint_max 
  select 'album.tpc',  max(total_play_count) from album;

-- 4) Update trigger function to maintain new total_play_count column and it's maximum value

create or replace function update_play_count_fnc ()
  returns trigger
  language plpgsql
  as $$
declare
  artist_tpc_max bigint;
  track_tpc_max bigint;
  album_tpc_max bigint;
begin
  -- artist
  with updated_artists as (
    update 
      artist
    set 
      total_play_count = total_play_count + 1
    where
      id in (select artist_id from track_artist where track_id = NEW.track_id and is_featured = false)
    returning
      total_play_count
  )
  select max(total_play_count) into artist_tpc_max from updated_artists;
  update bigint_max set v = artist_tpc_max where k = 'artist.tpc' and v < artist_tpc_max;

  -- track
  with updated_track as (
    update
      track
    set
      total_play_count = total_play_count + 1
    where
      id = NEW.track_id
    returning total_play_count
  )
  select total_play_count into track_tpc_max from updated_track;
  update bigint_max set v = track_tpc_max where k = 'track.tpc' and v < track_tpc_max;

  -- album
  with updated_album as (
    update
      album
    set
      total_play_count = total_play_count + 1
    where
      id = (select album_id from track where id = NEW.track_id)
    returning total_play_count
  )
  select total_play_count into album_tpc_max from updated_album;
  update bigint_max set v = album_tpc_max where k = 'album.tpc' and v < album_tpc_max;

  return NEW;
end;
$$;

-- 5) Create aggregate column artists_json

alter table album
  add column artists_json jsonb not null default '{}'::jsonb;

-- 6) Populate new column with data

with artists as (
  select
    aa.album_id,
    jsonb_object_agg(a.id, a.name) agg
  from
    album_artist aa
    inner join artist a on a.id = aa.artist_id
  group by
    aa.album_id
)
update
  album
set
  artists_json = artists.agg
from
  artists
where
  album.id = artists.album_id;

-- 7) create trigger on 'album_artist' table to maintain the aggregate

create or replace function album_artist_cng_fnc()
  returns trigger
  language plpgsql
as $$
begin
  if TG_OP='INSERT' then
    update 
      album 
    set 
      artists_json = artists_json || (select jsonb_object_agg(id, name) from artist where id = NEW.artist_id)
    where
      id = NEW.album_id;
    return NEW;
  elseif TG_OP='DELETE' then
    update 
      album 
    set 
      artists_json = artists_json - OLD.artist_id::text
    where
      id = OLD.album_id;
    return null;
  else
    return null;
  end if;
end;
$$;

create trigger album_artist_cng_t after insert or delete on album_artist
  for each row execute procedure album_artist_cng_fnc();

-- 8) Create GiST index

create index album_title_gist_idx on album using gist (title gist_trgm_ops, total_play_count) where active = true;

-- 9) New query

prepare album_search (text) as
select
  id,
  title,
  cover_photo,
  artists_json,
  total_play_count as rating
from
  album
where
  title ilike '%' || $1 || '%'
  and active = true
order by
  total_play_count <-> 8075
limit 5;

execute album_search ('for those');