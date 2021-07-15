-- 
-- Original query.
--
-- Searches tracks via partial, case-insensitive text.
--
prepare track_search (text) as
select
  track.id,
  track.title,
  track.length,
  track.album_id,
  string_agg(distinct album.cover_photo, ','::text) cover_photo,
  json_object_agg(distinct artist.id, artist.name) as artists_json,
  count(distinct ph.id) as rating
from
  track
  inner join album on track.album_id = album.id
    and album.active = true
  inner join track_artist ta on ta.track_id = track.id
    and ta.is_featured = false
  inner join artist on ta.artist_id = artist.id
    and artist.active = true
  left join play_history ph on ph.track_id = track.id
where
  track.title ilike '%' || $1 || '%'
  and track.active = true
group by
  track.id
order by
  rating desc
limit 5;

-------------------------
-- Optimization steps
-------------------------

-- 1) Create total_play_count column

alter table track
  add column total_play_count bigint default 0 not null;

-- 2) Update new column with existing counts

with ratings as (
  select
    track_id,
    count(*) as rating
  from
    play_history
  group by
    track_id
  having
    count(*) > 0)
update
  track
set
  total_play_count = ratings.rating
from
  ratings
where
  track.id = ratings.track_id;

-- 3) Store the max value under 'track.tpc' key

insert into bigint_max 
  select 'track.tpc',  max(total_play_count) from track;

-- 4) Update trigger function to maintain new total_play_count column and it's maximum value

create or replace function update_play_count_fnc ()
  returns trigger
  language plpgsql
  as $$
declare
  artist_tpc_max bigint;
  track_tpc_max bigint;
begin
  -- artists
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

  -- tracks
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

  return NEW;
end;
$$;

-- 5) Create reduntant column cover_photo and aggregate column artists_json

alter table track
  add column cover_photo varchar(255);

alter table track
  add column artists_json jsonb not null default '{}'::jsonb;

-- 6) Populate new columns with data

with artists as (
  select
    ta.track_id,
    jsonb_object_agg(a.id, a.name) agg
  from
    track_artist ta
    inner join artist a on a.id = ta.artist_id and ta.is_featured = false
  group by
    ta.track_id
), covers as (
  select
    track.id as track_id,
    album.cover_photo
  from 
    track
    inner join album on track.album_id = album.id
)
update
  track
set
  cover_photo = covers.cover_photo,
  artists_json = artists.agg
from
  covers
  inner join artists on covers.track_id = artists.track_id
where
  track.id = covers.track_id;
-- Time: 7317319.987 ms (02:01:57.320)
 
-- 7) Create trigger on 'album' table to maintain cover_photo

create or replace function album_update_fnc()
  returns trigger
  language plpgsql
as $$
begin
  if NEW.cover_photo <> OLD.cover_photo then
    -- needs index on album_id
    update track set cover_photo = NEW.cover_photo where album_id = NEW.id;
  end if;

  return NEW;
end;
$$;

create trigger album_update_t after update on album
  for each row execute procedure album_update_fnc();

-- needed index
create index track_album_id_idx on track (album_id);

-- 8) Create trigger on 'track' table to maintain cover_photo column

create or replace function track_insert_fnc()
  returns trigger
  language plpgsql
as $$
begin
  select cover_photo into NEW.cover_photo from album where id = NEW.album_id;
  return NEW;
end;
$$;

create trigger track_insert_t before insert on track
  for each row execute procedure track_insert_fnc();

-- 9) Create trigger on 'track_artist' to maintain 'artists_json' aggregate

create or replace function track_artist_cng_fnc()
  returns trigger
  language plpgsql
as $$
begin
  if TG_OP='INSERT' and NEW.is_featured = false then
    update 
      track 
    set 
      artists_json = artists_json || (select jsonb_object_agg(id, name) from artist where id = NEW.artist_id)
    where
      id = NEW.track_id;
    return NEW;
  elseif TG_OP='DELETE' then
    update 
      track 
    set 
      artists_json = artists_json - OLD.artist_id::text
    where
      id = OLD.track_id;
    return null;
  else
    return null;
  end if;
end;
$$;

create trigger track_artist_cng_t after insert or delete on track_artist
  for each row execute procedure track_artist_cng_fnc();

-- 10) Create GiST index 

create index track_title_gist_idx on track using gist (title gist_trgm_ops, total_play_count) where active = true;

-- 11) New query that utilizes GiST index like the previous artist search

prepare track_search (text) as
select
  id,
  title,
  length,
  album_id,
  cover_photo,
  artists_json,
  total_play_count as rating
from
  track
where
  title ilike '%' || $1 || '%'
  and active = true
order by
  total_play_count <-> 100
limit 5;
