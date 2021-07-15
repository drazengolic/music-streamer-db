-- 
-- Original query.
--
-- Retrieves last 10 tracks played by the user.
--
prepare last10 (int) as
select
  track.id,
  track.title,
  string_agg(distinct album.cover_photo, ','::text) cover_photo,
  json_object_agg(distinct artist.id, artist.name) as artists_json,
  date_played
from
  play_history ph
  inner join track on ph.track_id = track.id
    and track.active = true
  inner join album on track.album_id = album.id
    and album.active = true
  inner join track_artist ta on ta.track_id = ph.track_id
    and ta.is_featured = false
  inner join artist on ta.artist_id = artist.id
    and artist.active = true
where
  user_id = $1
group by
  track.id,
  date_played
order by
  date_played desc
limit 10;

-- 1) New query based on previous work

prepare last10 (int) as
select
  track.id,
  track.title,
  track.cover_photo,
  track.artists_json,
  ph.date_played
from
  play_history ph
  inner join track on ph.track_id = track.id
    and track.active = true
where
  ph.user_id = $1
order by
  date_played desc
limit 10;

-- 2) Improve performance with index on play_history

create index play_history_user_desc_idx on play_history (user_id, date_played desc);