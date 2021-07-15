create table album (
  id integer primary key 
    generated always as identity,
  title varchar(255) not null,
  cover_photo varchar(255) not null,
  year integer,
  legal_notice text,
  date_added timestamp not null default now(),
  active boolean not null default true
);

create table recording_type (
  id integer primary key 
    generated always as identity,
  "name" varchar(255) not null,
  file_type varchar(5) not null,
  quality_level smallint unique not null
);

create table genre (
  id integer primary key 
    generated always as identity,
  name varchar(255) not null
);

create table track (
  id integer primary key 
    generated always as identity,
  title varchar(255) not null,
  "length" integer not null,
  position smallint not null,
  disc_num smallint not null default 1,
  genre_id integer not null,
  album_id integer not null,
  active boolean not null default true,
  constraint fk_genre_id 
    foreign key (genre_id) 
    references genre(id),
  constraint fk_album_id 
    foreign key (album_id) 
    references album(id)
);

create table "user" (
  id integer primary key 
    generated always as identity,
  email varchar(255) unique not null,
  "password" varchar(255) not null,
  active boolean not null default true,
  first_name varchar(255) not null,
  last_name varchar(255) not null,
  prefer_recording_type integer not null,
  constraint fk_rec_type 
    foreign key(prefer_recording_type) 
    references recording_type(id)
);

create table artist (
  id integer primary key 
    generated always as identity,
  "name" varchar(255) not null,
  cover_photo varchar(255) not null,
  short_bio text,
  active boolean not null default true
);

create table recording (
  id integer primary key 
    generated always as identity,
  recording_type_id integer not null,
  file_uri varchar(255) not null,
  track_id integer not null,
  constraint fk_rec_type 
    foreign key(recording_type_id) 
    references recording_type(id),
  constraint fk_recording_track 
    foreign key(track_id) 
    references track(id)
);

create table album_artist (
  album_id integer not null,
  artist_id integer not null,
  primary key (album_id, artist_id),
  constraint fk_album_id 
    foreign key (album_id) 
    references album(id),
  constraint fk_artist_id 
    foreign key (artist_id)
    references artist(id)
);

create table playlist (
  id integer primary key 
    generated always as identity,
  title varchar(255) not null,
  description text,
  is_private boolean not null 
    default false,
  cover_photo varchar(255),
  user_id integer not null,
  constraint fk_user_id 
    foreign key (user_id) 
    references "user"(id)
);

create table playlist_track (
  playlist_id integer not null,
  track_id integer not null,
  position smallint not null 
    default 1,
  primary key (playlist_id, track_id),
  constraint fk_album_id 
    foreign key (playlist_id) 
    references playlist(id),
  constraint fk_track_id 
    foreign key (track_id) 
    references track(id)
);

create table track_artist (
  track_id integer not null,
  artist_id integer not null,
  is_featured boolean not null
    default false,
  primary key (track_id, artist_id),
  constraint fk_track_id 
    foreign key (track_id)
    references track(id),
  constraint fk_artist_id
    foreign key (artist_id)
    references artist(id)
);

create table play_history (
  id bigint primary key
    generated always as identity,
  user_id integer not null,
  track_id integer not null,
  date_played timestamp not null 
    default now(),
  constraint fk_user_id 
    foreign key (user_id)
    references "user"(id),
  constraint fk_track_id
    foreign key (track_id)
    references track(id)
);