-- =========================================================
-- Load ~3,000 popular real Spotify tracks (popularity >= 70)
-- =========================================================
-- Source: data/source/spotify_tracks_pop70.csv, a filtered copy of the public
-- "Spotify Tracks Dataset" (huggingface.co/datasets/maharshipandya/spotify-tracks-dataset,
-- a ~2022 snapshot). Filtered to popularity >= 70, with duplicates of the same
-- title + primary artist (e.g. single vs. album vs. compilation releases) collapsed
-- to the most popular one; its genre tags are the union over all the duplicates.
--
-- Run from the repo root, after tables/*.sql and data/data_inserts.sql:
--   psql -d <db> -v ON_ERROR_STOP=1 -f data/load_spotify_tracks.sql
--
-- Hand-entered songs from data_inserts.sql that are also in the dataset (same title
-- and primary artist) are matched, not duplicated: they get their spotify_id,
-- popularity and explicit flag filled in. Safe to re-run: existing rows are skipped.

\encoding UTF8

BEGIN;

CREATE TEMP TABLE staging_track (
    spotify_id   TEXT PRIMARY KEY,
    track_name   TEXT NOT NULL,
    artists      TEXT NOT NULL,      -- ';'-separated, first one is the primary artist
    album_name   TEXT NOT NULL,
    popularity   SMALLINT NOT NULL,
    duration_ms  INTEGER NOT NULL,
    explicit     BOOLEAN NOT NULL,
    genres       TEXT NOT NULL       -- ';'-separated Spotify genre tags
) ON COMMIT DROP;

\copy staging_track FROM 'data/source/spotify_tracks_pop70.csv' WITH (FORMAT csv, HEADER true)


-- One row per (track, artist). A name listed twice on a track keeps its first position.
CREATE TEMP TABLE staging_track_artist ON COMMIT DROP AS
SELECT spotify_id,
       artist_name,
       row_number() OVER (PARTITION BY spotify_id ORDER BY min(pos)) AS artist_position
FROM (SELECT st.spotify_id, trim(a.name) AS artist_name, a.pos
      FROM staging_track st,
           unnest(string_to_array(st.artists, ';')) WITH ORDINALITY AS a(name, pos)) x
WHERE artist_name <> ''
GROUP BY spotify_id, artist_name;


-- ---------------------------------------------------------
-- Genres: map Spotify's ~100 fine-grained tags onto broad genres.
-- Fallback tags (moods, countries) are only used when a song has no other genre.
-- ---------------------------------------------------------
CREATE TEMP TABLE genre_map (
    tag          TEXT PRIMARY KEY,
    genre_name   TEXT NOT NULL,
    is_fallback  BOOLEAN NOT NULL DEFAULT false
) ON COMMIT DROP;

INSERT INTO genre_map (tag, genre_name, is_fallback) VALUES
  ('pop','Pop',false), ('dance','Pop',false), ('power-pop','Pop',false), ('synth-pop','Pop',false),
  ('mandopop','Pop',false), ('cantopop','Pop',false),
  ('sad','Pop',true), ('chill','Pop',true), ('party','Pop',true), ('piano','Pop',true),
  ('comedy','Pop',true), ('children','Pop',true), ('german','Pop',true), ('swedish','Pop',true),
  ('french','Pop',true),
  ('rock','Rock',false), ('alt-rock','Rock',false), ('alternative','Rock',false), ('hard-rock','Rock',false),
  ('grunge','Rock',false), ('psych-rock','Rock',false), ('garage','Rock',false), ('rock-n-roll','Rock',false),
  ('rockabilly','Rock',false), ('guitar','Rock',false), ('j-rock','Rock',false), ('british','Rock',true),
  ('indie','Indie',false), ('indie-pop','Indie',false),
  ('hip-hop','Hip-Hop',false),
  ('electro','Electronic',false), ('edm','Electronic',false), ('house','Electronic',false),
  ('progressive-house','Electronic',false), ('deep-house','Electronic',false), ('chicago-house','Electronic',false),
  ('techno','Electronic',false), ('trance','Electronic',false), ('dubstep','Electronic',false),
  ('electronic','Electronic',false), ('idm','Electronic',false), ('hardstyle','Electronic',false),
  ('club','Electronic',false), ('trip-hop','Electronic',false), ('ambient','Electronic',true),
  ('metal','Metal',false), ('metalcore','Metal',false), ('hardcore','Metal',false),
  ('death-metal','Metal',false), ('industrial','Metal',false),
  ('punk','Punk',false), ('punk-rock','Punk',false), ('emo','Punk',false), ('ska','Punk',false),
  ('latin','Latin',false), ('latino','Latin',false), ('reggaeton','Latin',false), ('salsa','Latin',false),
  ('pagode','Latin',false), ('brazil','Latin',false), ('spanish','Latin',true),
  ('reggae','Reggae',false), ('dancehall','Reggae',false), ('dub','Reggae',false),
  ('r-n-b','R&B',false),
  ('soul','Soul',false), ('funk','Soul',false), ('groove','Soul',false),
  ('jazz','Jazz',false),
  ('country','Country',false),
  ('folk','Folk',false), ('acoustic','Folk',false), ('songwriter','Folk',false), ('singer-songwriter','Folk',false),
  ('blues','Blues',false),
  ('disco','Disco',false),
  ('k-pop','K-Pop',false),
  ('j-pop','J-Pop',false), ('j-dance','J-Pop',false),
  ('pop-film','Soundtrack',false), ('show-tunes','Soundtrack',false), ('disney','Soundtrack',false),
  ('anime','Soundtrack',false),
  ('classical','Classical',false), ('sleep','Classical',true), ('new-age','Classical',true),
  ('afrobeat','World',false), ('world-music','World',false), ('indian','World',false),
  ('turkish','World',false), ('malay','World',false);

-- Fail loudly if the CSV has a tag nobody mapped, instead of silently dropping it.
DO $$
DECLARE missing TEXT;
BEGIN
    SELECT string_agg(DISTINCT t.tag, ', ') INTO missing
    FROM staging_track st, unnest(string_to_array(st.genres, ';')) AS t(tag)
    WHERE NOT EXISTS (SELECT 1 FROM genre_map gm WHERE gm.tag = t.tag);
    IF missing IS NOT NULL THEN
        RAISE EXCEPTION 'Unmapped genre tags: %', missing;
    END IF;
END $$;

INSERT INTO genre (genre_name)
SELECT DISTINCT genre_name FROM genre_map
ORDER BY genre_name
ON CONFLICT (genre_name) DO NOTHING;


-- ---------------------------------------------------------
-- Artists
-- ---------------------------------------------------------
INSERT INTO artist (artist_name)
SELECT DISTINCT artist_name FROM staging_track_artist
ORDER BY artist_name
ON CONFLICT (artist_name) DO NOTHING;


-- ---------------------------------------------------------
-- Match hand-entered songs (no spotify_id yet) by title + primary artist
-- ---------------------------------------------------------
UPDATE song s
SET spotify_id = m.spotify_id,
    popularity = m.popularity,
    explicit   = m.explicit
FROM (SELECT DISTINCT ON (s2.song_id) s2.song_id, st.spotify_id, st.popularity, st.explicit
      FROM staging_track st
      JOIN staging_track_artist sta ON sta.spotify_id = st.spotify_id AND sta.artist_position = 1
      JOIN artist a       ON a.artist_name = sta.artist_name
      JOIN song_artist sa ON sa.artist_id = a.artist_id AND sa.artist_position = 1
      JOIN song s2        ON s2.song_id = sa.song_id AND lower(s2.song_title) = lower(st.track_name)
      WHERE s2.spotify_id IS NULL
        AND NOT EXISTS (SELECT 1 FROM song x WHERE x.spotify_id = st.spotify_id)
      ORDER BY s2.song_id, st.popularity DESC) m
WHERE s.song_id = m.song_id;


-- ---------------------------------------------------------
-- Albums and songs for tracks not already in the catalog.
-- album.artist_id is the track's primary artist (the dataset has no album artist).
-- ---------------------------------------------------------
INSERT INTO album (artist_id, album_title)
SELECT DISTINCT a.artist_id, st.album_name
FROM staging_track st
JOIN staging_track_artist sta ON sta.spotify_id = st.spotify_id AND sta.artist_position = 1
JOIN artist a ON a.artist_name = sta.artist_name
WHERE NOT EXISTS (SELECT 1 FROM song s WHERE s.spotify_id = st.spotify_id)
ORDER BY a.artist_id, st.album_name
ON CONFLICT (artist_id, album_title) DO NOTHING;

INSERT INTO song (album_id, song_title, duration_ms, spotify_id, popularity, explicit)
SELECT al.album_id, st.track_name, st.duration_ms, st.spotify_id, st.popularity, st.explicit
FROM staging_track st
JOIN staging_track_artist sta ON sta.spotify_id = st.spotify_id AND sta.artist_position = 1
JOIN artist a ON a.artist_name = sta.artist_name
JOIN album al ON al.artist_id = a.artist_id AND al.album_title = st.album_name
WHERE NOT EXISTS (SELECT 1 FROM song s WHERE s.spotify_id = st.spotify_id)
ORDER BY st.popularity DESC, st.spotify_id
ON CONFLICT (spotify_id) DO NOTHING;


-- ---------------------------------------------------------
-- Song links. Matched hand-entered songs keep their existing links;
-- conflicting rows are skipped.
-- ---------------------------------------------------------
INSERT INTO song_artist (song_id, artist_id, artist_position)
SELECT s.song_id, a.artist_id, sta.artist_position
FROM staging_track_artist sta
JOIN song s   ON s.spotify_id = sta.spotify_id
JOIN artist a ON a.artist_name = sta.artist_name
ORDER BY s.song_id, sta.artist_position
ON CONFLICT DO NOTHING;

-- Up to 2 broad genres per song, the ones most of its tags point to.
-- Spotify tags much reggaeton as "reggae", so "reggae" is ignored on Latin tracks.
WITH tagged AS (
    SELECT st.spotify_id, gm.genre_name, gm.is_fallback
    FROM staging_track st
    CROSS JOIN unnest(string_to_array(st.genres, ';')) AS t(tag)
    JOIN genre_map gm ON gm.tag = t.tag
    WHERE NOT (t.tag = 'reggae' AND st.genres ~ '(^|;)(latin|latino|reggaeton)(;|$)')
), counted AS (
    SELECT spotify_id, genre_name, count(*) AS n_tags, bool_and(is_fallback) AS is_fallback
    FROM tagged
    GROUP BY spotify_id, genre_name
), ranked AS (
    SELECT counted.*,
           bool_or(NOT is_fallback) OVER (PARTITION BY spotify_id) AS has_main_genre,
           row_number() OVER (PARTITION BY spotify_id
                              ORDER BY is_fallback, n_tags DESC, genre_name) AS rn
    FROM counted
)
INSERT INTO song_genre (song_id, genre_id)
SELECT s.song_id, g.genre_id
FROM ranked r
JOIN song s  ON s.spotify_id = r.spotify_id
JOIN genre g ON g.genre_name = r.genre_name
WHERE r.rn <= 2
  AND (NOT r.is_fallback OR NOT r.has_main_genre)
ORDER BY s.song_id, g.genre_id
ON CONFLICT DO NOTHING;

COMMIT;

ANALYZE artist, album, song, genre, song_artist, song_genre;
