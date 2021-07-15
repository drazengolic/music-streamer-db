--------------------------------------------
-- Steps for moving play_history trigger 
-- work into the background process.
--------------------------------------------

-- 1) New function based on 'update_play_count_fnc', which uses input params instead of the 'NEW' variable

create or replace function update_play_counts (n_track_id int, n_user_id int)
  returns int
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
      id in (
        select
          artist_id
        from
          track_artist
        where
          track_id = n_track_id
          and is_featured = false)
      returning
        total_play_count
)
  select
    max(total_play_count) into artist_tpc_max
  from
    updated_artists;
  update
    bigint_max
  set
    v = artist_tpc_max
  where
    k = 'artist.tpc'
    and v < artist_tpc_max;
    
  -- user_artist_tpc upsert
  insert into user_artist_tpc as a (user_id, artist_id, total_play_count)
  select
    n_user_id,
    artist_id,
    1
  from
    track_artist
  where
    track_id = n_track_id
    and is_featured = false
  on conflict (user_id,
    artist_id)
    do update set
      total_play_count = a.total_play_count + 1;

  -- track
  with updated_track as (
    update
      track
    set
      total_play_count = total_play_count + 1
    where
      id = n_track_id
    returning
      total_play_count
)
  select
    total_play_count into track_tpc_max
  from
    updated_track;
  update
    bigint_max
  set
    v = track_tpc_max
  where
    k = 'track.tpc'
    and v < track_tpc_max;

  -- album
  with updated_album as (
    update
      album
    set
      total_play_count = total_play_count + 1
    where
      id = (
        select
          album_id
        from
          track
        where
          id = n_track_id)
      returning
        total_play_count
)
  select
    total_play_count into album_tpc_max
  from
    updated_album;
  update
    bigint_max
  set
    v = album_tpc_max
  where
    k = 'album.tpc'
    and v < album_tpc_max;
  return 0;
end;
$$;

-- 2) Make trigger function 'update_play_count_fnc' send data to a channel instead

create or replace function update_play_count_fnc ()
  returns trigger
  language plpgsql
  as $$
begin
  perform
    pg_notify('play_history_insert', row_to_json(NEW)::text);
  return NEW;
end;
$$;

