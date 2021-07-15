-- 
-- Original query.
--
-- Retrieves most played artists by some user.
--
prepare favorite_artists (int) as
select
  a.id,
  a.name,
  a.cover_photo,
  count(*) as rating
from
  play_history ph
  inner join track_artist ta on ta.track_id = ph.track_id
  inner join artist a on ta.artist_id = a.id
    and a.active = true
where
  ph.user_id = $1
group by
  a.id
order by
  rating desc
limit 10;

execute favorite_artists (1001); -- ~200ms, 22s

-------------------------
-- Optimization steps
-------------------------

-- 1) Play count per user is required, so create a table for it:

create table user_artist_tpc (
    user_id integer not null,
    artist_id integer not null,
    total_play_count bigint not null default 0,
    primary key (user_id, artist_id)
);

-- 2) Populate new table with data

insert into user_artist_tpc
select
  ph.user_id,
  ta.artist_id,
  count(*) as rating
from
  play_history ph 
  inner join track_artist ta on ph.track_id = ta.track_id
group by
  ph.user_id,
  ta.artist_id;

-- 3) Update trigger function to maintan the new table as well

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

  -- user_artist_tpc upsert
  insert into user_artist_tpc as a (user_id, artist_id, total_play_count)
    select NEW.user_id, artist_id, 1 from track_artist where track_id = NEW.track_id and is_featured = false
    on conflict (user_id, artist_id) do update set total_play_count = a.total_play_count + 1;

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

-- 4) New query

prepare favorite_artists (int) as
select
  artist.id,
  artist.name,
  artist.cover_photo,
  uat.total_play_count as rating
from
  user_artist_tpc uat
  inner join artist on artist.id=uat.artist_id
where
  uat.user_id = $1
order by
  rating desc
limit 10;

-- 5) btree index to improve performance

create index user_artist_tpc_user_idx on user_artist_tpc (user_id, total_play_count desc);