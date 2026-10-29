-- Source id for songs, so a load can be traced and never duplicates a song.
ALTER TABLE song ADD COLUMN spotify_id TEXT UNIQUE;
 
 
-- The dataset has no artist or album ids, so the name IS the identity.
ALTER TABLE artist ADD CONSTRAINT artist_name_unique UNIQUE (artist_name);
ALTER TABLE album  ADD CONSTRAINT album_artist_title_unique UNIQUE (artist_id, album_title);
 
 
-- Songs can have several artists. artist_position 1 is the primary artist,
CREATE TABLE song_artist (
    song_id          INTEGER NOT NULL REFERENCES song (song_id)     ON DELETE CASCADE,
    artist_id        INTEGER NOT NULL REFERENCES artist (artist_id) ON DELETE RESTRICT,
    artist_position  INTEGER NOT NULL DEFAULT 1 CHECK (artist_position >= 1),
    PRIMARY KEY (song_id, artist_id),
    UNIQUE (song_id, artist_position)
);
 