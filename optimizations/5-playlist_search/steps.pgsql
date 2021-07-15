-- 
-- Original query.
--
-- Searches playlists via partial, case-insensitive text.
--
prepare playlist_search (text) as
select
  id,
  title,
  cover_photo
from
  playlist
where
  title ilike '%' || $1 || '%'
  and is_private = false
limit 5;

execute playlist_search('metal'); -- ~1s, 20ms

-- No special requirements, just add GIN index

create index playlist_title_gin on playlist using gin(title gin_trgm_ops) where is_private = false;