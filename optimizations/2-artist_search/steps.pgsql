-- 
-- Original query.
--
-- Searches artists via partial, case-insensitive text.
--
prepare artist_search (text) as
select
  a.id,
  a.name,
  a.cover_photo,
  count(distinct ph.id) as rating
from
  artist a
  inner join track_artist ta on ta.artist_id = a.id
  left join play_history ph on ph.track_id = ta.track_id
where
  a.name ilike '%' || $1 || '%'
  and a.active = true
group by
  a.id
order by
  rating desc
limit 5;

execute artist_search ('the');

-------------------------
-- Optimization steps
-------------------------

-- 1) Create total_play_count column

alter table artist
  add column total_play_count bigint default 0 not null;

-- 2) Update new column with existing counts

with ratings as (
  select
    a.id,
    count(distinct ph.id) as rating
  from
    artist a
    inner join track_artist ta on ta.artist_id = a.id
    inner join play_history ph on ph.track_id = ta.track_id
  group by
    a.id)
update
  artist
set
  total_play_count = ratings.rating
from
  ratings
where
  artist.id = ratings.id;

-- 3) Create trigger to maintain play counts

create or replace function update_play_count_fnc()
  returns trigger
  language plpgsql
as $$
begin
  update 
    artist
  set 
    total_play_count = total_play_count + 1
  where
    id in (select artist_id from track_artist where track_id = NEW.track_id and is_featured = false);

  return NEW;
end;
$$;

create trigger update_play_count after insert on play_history
  for each row execute procedure update_play_count_fnc();

-- 4) Create cache table for bigint values. This will be used in k-NN search via GiST index

create table bigint_max (
  k varchar(100) primary key not null,
  v bigint not null
);

-- 5) Store max value of total_play_count under key 'artist.tpc'

insert into bigint_max 
  select 'artist.tpc',  max(total_play_count) from artist;

-- 6) Update existing trigger function to maintain 'artist.tpc' value

create or replace function update_play_count_fnc()
  returns trigger
  language plpgsql
as $$
declare
  artist_tpc_max bigint;
begin
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

  return NEW;
end;
$$;

-- 7) Create extensions

create extension pg_trgm; -- to improve text search performance
create extension btree_gist; -- for k-NN


-- 8) Create GiST index for text search

create index artist_name_gist_idx on artist using gist ("name" gist_trgm_ops, total_play_count) where active = true;

-- 9) New query that utilises the GiST index and 'emulates' sorting via k-NN algorithm.
--    Important note: 
--      Number 5000 here is 'artist.tpc' value provided as a constant within query.
--      If the value is provided as a subquery, Index Scan will not be used for sorted output.

prepare artist_search (text) as
select
  a.id,
  a.name,
  a.cover_photo,
  total_play_count as rating
from
  artist a
where
  a.name ilike '%' || $1 || '%'
  and a.active = true
order by
  total_play_count <-> 5000
limit 5;