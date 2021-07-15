-- 
-- Original query.
--
-- Retrieves artists that have been played by the most users within last month.
--
prepare popular_artists_month as
select
  a.id,
  a.name,
  a.cover_photo,
  count(distinct ph.user_id) as popularity
from
  track_artist ta
  inner join play_history ph on ph.track_id = ta.track_id
  inner join artist a on ta.artist_id = a.id
    and a.active = true
where
  date_played between (select max(date_played) from play_history) - interval '1 month'
  and (select max(date_played) from play_history)
group by
  a.id
order by
  popularity desc
limit 10;

-------------------------
-- Optimization steps
-------------------------

-- 1) Index on play_history.date_played

create index play_history_date_played_dsc on play_history (date_played desc);

-- 2) Create materialized view from the original query

create materialized view popular_artists as
select
  a.id,
  a.name,
  a.cover_photo,
  count(distinct ph.user_id) as popularity
from
  track_artist ta
  inner join play_history ph on ph.track_id = ta.track_id
  inner join artist a on ta.artist_id = a.id
    and a.active = true
where
  date_played between (select max(date_played) from play_history) - interval '1 month'
  and (select max(date_played) from play_history)
group by
  a.id
order by
  popularity desc
limit 10
with data;

-- 3) Unique index for concurrent refreshing

create unique index u_popular_artists_idx on popular_artists (id);

-- 4) Refresh data occasionaly via:

refresh materialized view concurrently popular_artists; -- ~3s

-- 5) New query

select * from popular_artists;