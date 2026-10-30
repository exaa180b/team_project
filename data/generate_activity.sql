-- =========================================================
-- Generate synthetic user activity
-- =========================================================
-- ~2,000 users (the 4 hand-made demo users + generated ones), playlists,
-- playlist songs, collaborators, likes, and ~1M plays.
-- The catalog is real (data_inserts.sql + load_spotify_tracks.sql); this data is
-- random but shaped to look realistic:
--   * each user has 1-3 favourite genres (popular genres are picked more often)
--     and 85% of their plays come from those genres
--   * popular songs get played more
--   * a few users are heavy listeners, most are light
--   * more listening in the evening, a bit more in recent months
--   * users only like songs they've played, and only after first playing them
--
-- Run from the repo root, after data/load_spotify_tracks.sql:
--   psql -d <db> -v ON_ERROR_STOP=1 -f data/generate_activity.sql
--
-- Deterministic: fixed random seed and a fixed "now" (:anchor below), so query
-- results don't drift between reloads. Re-running replaces everything this
-- script generates: users with user_id > 4 (cascading to their playlists and
-- likes) and all listening history. The 4 demo users keep their hand-made
-- playlists and likes.

\encoding UTF8
\set n_users 2000
\set n_plays 1000000
\set anchor '2026-10-01 00:00:00'

BEGIN;
SET LOCAL timezone = 'America/Los_Angeles';
SELECT setseed(0.18);


-- ---------------------------------------------------------
-- Start clean
-- ---------------------------------------------------------
TRUNCATE listening_history RESTART IDENTITY;
DELETE FROM app_user WHERE user_id > 4;   -- cascades to their playlists, likes, collaborations
SELECT setval(pg_get_serial_sequence('app_user', 'user_id'),     (SELECT max(user_id)     FROM app_user));
SELECT setval(pg_get_serial_sequence('playlist', 'playlist_id'), (SELECT max(playlist_id) FROM playlist));


-- ---------------------------------------------------------
-- Users
-- ---------------------------------------------------------
INSERT INTO app_user (username, email, password_hash, date_joined)
SELECT lower(first_name || '_' || last_name) || g,
       lower(first_name || '.' || last_name) || g || '@example.com',
       'demo-placeholder',
       joined
FROM (SELECT g,
             (ARRAY['Olivia','Liam','Emma','Noah','Ava','Ethan','Sophia','Mason','Isabella','Lucas',
                    'Mia','Logan','Amelia','James','Harper','Aiden','Evelyn','Elijah','Abigail','Daniel',
                    'Emily','Matthew','Ella','Jackson','Sofia','Sebastian','Camila','David','Aria','Joseph',
                    'Priya','Arjun','Mei','Wei','Hana','Kenji','Min-jun','Ji-woo','Diego','Valentina',
                    'Mateo','Lucia','Omar','Layla','Yusuf','Amara','Kwame','Zara','Ivan','Anya'])[1 + floor(random() * 50)::int] AS first_name,
             (ARRAY['Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez',
                    'Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Martin',
                    'Lee','Perez','Thompson','White','Harris','Sanchez','Clark','Ramirez','Lewis','Robinson',
                    'Nguyen','Kim','Park','Chen','Wang','Patel','Shah','Singh','Tanaka','Sato',
                    'Ali','Khan','Okafor','Mensah','Ivanov','Novak','Rossi','Muller','Silva','Cohen'])[1 + floor(random() * 50)::int] AS last_name,
             date '2022-01-01' + floor(random() * (:'anchor'::date - date '2022-01-01'))::int AS joined
      FROM generate_series(5, :n_users) g) x
ORDER BY g;


-- ---------------------------------------------------------
-- Per-user plan: activity level, favourite genres, how many likes/playlists
-- ---------------------------------------------------------
CREATE TEMP TABLE user_plan ON COMMIT DROP AS
SELECT user_id,
       date_joined,
       least(365, :'anchor'::date - date_joined) AS window_days,   -- days they could have listened
       CASE WHEN user_id <= 4 THEN 25 ELSE exp(random() * 3.5) END AS activity,  -- ~1 to 33
       1 + floor(random() * 3)::int  AS n_genres,
       5 + floor(random() * 41)::int AS n_likes,
       floor(random() * 6)::int      AS n_playlists
FROM app_user
ORDER BY user_id;

-- Genres weighted by catalog size, as cumulative [lo, hi) ranges for sampling.
CREATE TEMP TABLE genre_weight ON COMMIT DROP AS
SELECT genre_id,
       (running - n) / total AS lo,
       running / total       AS hi
FROM (SELECT genre_id, n,
             sum(n) OVER (ORDER BY genre_id) AS running,
             sum(n) OVER ()                  AS total
      FROM (SELECT genre_id, count(*)::float8 AS n FROM song_genre GROUP BY genre_id) c) w;

CREATE TEMP TABLE user_taste ON COMMIT DROP AS
SELECT d.user_id, array_agg(DISTINCT gw.genre_id ORDER BY gw.genre_id) AS genre_ids
FROM (SELECT p.user_id, random() AS r
      FROM user_plan p, generate_series(1, 3) k
      WHERE k <= p.n_genres AND p.user_id > 4
      ORDER BY p.user_id, k) d
JOIN genre_weight gw ON d.r >= gw.lo AND d.r < gw.hi
GROUP BY d.user_id
UNION ALL
-- Demo users keep the tastes data_inserts.sql gave them.
SELECT t.user_id, array_agg(g.genre_id ORDER BY g.genre_id)
FROM (VALUES (1, 'Pop'), (2, 'Hip-Hop'), (2, 'R&B'), (3, 'Rock'), (3, 'Metal'),
             (4, 'Jazz'), (4, 'Electronic')) AS t(user_id, genre_name)
JOIN genre g USING (genre_name)
GROUP BY t.user_id;

-- Songs per genre, most popular first. Hand-entered songs without a
-- popularity score are treated as 75 (they're well-known classics).
CREATE TEMP TABLE genre_pool ON COMMIT DROP AS
SELECT sg.genre_id,
       array_agg(sg.song_id ORDER BY coalesce(s.popularity, 75) DESC, sg.song_id) AS songs,
       count(*)::int AS n
FROM song_genre sg
JOIN song s USING (song_id)
GROUP BY sg.genre_id;

CREATE TEMP TABLE global_pool ON COMMIT DROP AS
SELECT array_agg(song_id ORDER BY coalesce(popularity, 75) DESC, song_id) AS songs,
       count(*)::int AS n
FROM song;

-- Listening hour of day, weighted towards the evening (weights sum to 100).
CREATE TEMP TABLE hour_slots ON COMMIT DROP AS
SELECT array_agg(h ORDER BY h) AS slots
FROM (VALUES (0,2),(1,1),(2,1),(3,1),(4,1),(5,1),(6,2),(7,4),(8,5),(9,5),(10,4),(11,4),
             (12,5),(13,5),(14,4),(15,4),(16,5),(17,6),(18,7),(19,8),(20,8),(21,8),(22,6),(23,3)) AS w(h, weight),
     generate_series(1, weight);


-- ---------------------------------------------------------
-- Listening history (~1M plays)
-- ---------------------------------------------------------
-- Each user's share of plays is proportional to activity x days since joining.
-- genre_id NULL = a play from outside their favourite genres (15%).
CREATE TEMP TABLE play_draw ON COMMIT DROP AS
SELECT p.user_id,
       CASE WHEN random() < 0.15 THEN NULL
            ELSE t.genre_ids[1 + floor(random() * cardinality(t.genre_ids))::int]
       END AS genre_id,
       random() AS r_song,
       (:'anchor'::date - 1 - floor(power(random(), 1.2) * p.window_days)::int)
         + make_interval(hours => hs.slots[1 + floor(random() * 100)::int])
         + random() * interval '1 hour' AS played_at
FROM (SELECT user_id, window_days,
             round(:n_plays * activity * window_days / sum(activity * window_days) OVER ())::int AS n
      FROM user_plan) p
JOIN user_taste t USING (user_id)
CROSS JOIN hour_slots hs
CROSS JOIN LATERAL generate_series(1, p.n) i
ORDER BY p.user_id, i;

-- Inserted in time order, so history_id follows played_at (as in a real app,
-- and it lets a BRIN index on played_at work well).
INSERT INTO listening_history (user_id, song_id, played_at)
SELECT d.user_id,
       CASE WHEN d.genre_id IS NULL
            THEN g.songs[1 + floor(power(d.r_song, 2) * g.n)::int]
            ELSE gp.songs[1 + floor(power(d.r_song, 2) * gp.n)::int]
       END,
       d.played_at::timestamptz    -- local time in the session zone (America/Los_Angeles)
FROM play_draw d
LEFT JOIN genre_pool gp USING (genre_id)
CROSS JOIN global_pool g
ORDER BY 3, 1;                     -- sort after conversion so the DST fall-back hour stays in order


-- ---------------------------------------------------------
-- Likes: each generated user likes their 5-45 most-played songs,
-- some time after first playing each one.
-- ---------------------------------------------------------
INSERT INTO liked_song (user_id, song_id, liked_at)
SELECT x.user_id, x.song_id,
       x.first_play + random() * least(interval '14 days', :'anchor'::timestamptz - x.first_play)
FROM (SELECT h.user_id, h.song_id, min(h.played_at) AS first_play,
             row_number() OVER (PARTITION BY h.user_id ORDER BY count(*) DESC, h.song_id) AS rn
      FROM listening_history h
      WHERE h.user_id > 4
      GROUP BY h.user_id, h.song_id) x
JOIN user_plan p USING (user_id)
WHERE x.rn <= p.n_likes
ORDER BY x.user_id, x.song_id;


-- ---------------------------------------------------------
-- Playlists: 0-5 per generated user
-- ---------------------------------------------------------
INSERT INTO playlist (user_id, playlist_name, description, created_at)
SELECT user_id, playlist_name, description, created_at
FROM (SELECT p.user_id,
             CASE WHEN random() < 0.3
                  THEN (SELECT genre_name FROM genre WHERE genre_id = t.genre_ids[1]) || ' '
                       || (ARRAY['Favorites','Mix','Essentials','Rotation','Deep Cuts'])[1 + floor(random() * 5)::int]
                  ELSE (ARRAY['Chill Vibes','Workout','Road Trip','Study Session','Party Mix','Late Night',
                              'Morning Commute','Sunday Morning','Throwbacks','Feel Good','Rainy Day',
                              'Summer Hits','Focus','Sleep','Cooking','Running','Gaming','Heartbreak',
                              'Main Character','Car Karaoke','Gym Hype','Coffee Shop','Night Drive',
                              'Pregame','Wind Down','On Repeat','Golden Hour','Beach Day',
                              'Throwback Thursday','My Playlist'])[1 + floor(random() * 30)::int]
             END AS playlist_name,
             CASE WHEN random() < 0.5
                  THEN (ARRAY['songs on repeat lately','for the drive home','no skips','updated weekly',
                              'turn it up','vibes only','for when you need a boost','my current favorites'])[1 + floor(random() * 8)::int]
             END AS description,
             p.date_joined + random() * (:'anchor'::timestamptz - p.date_joined::timestamptz) AS created_at
      FROM user_plan p
      JOIN user_taste t USING (user_id)
      CROSS JOIN LATERAL generate_series(1, p.n_playlists) k
      WHERE p.user_id > 4) x
ORDER BY created_at;

-- 8-25 songs per generated playlist, mostly from the owner's genres.
CREATE TEMP TABLE playlist_plan ON COMMIT DROP AS
SELECT pl.playlist_id, pl.user_id, pl.created_at,
       8 + floor(random() * 18)::int AS n_songs,
       CASE WHEN random() < 0.15 THEN 1 + floor(random() * 3)::int ELSE 0 END AS n_collaborators
FROM playlist pl
WHERE pl.user_id > 4
ORDER BY pl.playlist_id;

INSERT INTO playlist_song (playlist_id, song_id, added_at)
SELECT d.playlist_id,
       CASE WHEN d.genre_id IS NULL
            THEN g.songs[1 + floor(power(d.r_song, 1.5) * g.n)::int]
            ELSE gp.songs[1 + floor(power(d.r_song, 1.5) * gp.n)::int]
       END,
       d.added_at
FROM (SELECT pp.playlist_id,
             CASE WHEN random() < 0.1 THEN NULL
                  ELSE t.genre_ids[1 + floor(random() * cardinality(t.genre_ids))::int]
             END AS genre_id,
             random() AS r_song,
             pp.created_at + random() * (:'anchor'::timestamptz - pp.created_at) AS added_at
      FROM playlist_plan pp
      JOIN user_taste t USING (user_id)
      CROSS JOIN LATERAL generate_series(1, pp.n_songs) k
      ORDER BY pp.playlist_id, k) d
LEFT JOIN genre_pool gp USING (genre_id)
CROSS JOIN global_pool g
ORDER BY d.playlist_id, d.added_at
ON CONFLICT DO NOTHING;   -- the same song drawn twice for one playlist

-- ~15% of generated playlists get 1-3 collaborators (never the owner),
-- added after both the playlist and the collaborator existed.
INSERT INTO playlist_collaborator (playlist_id, user_id, added_at)
SELECT d.playlist_id, u.user_id,
       greatest(d.created_at, u.date_joined::timestamptz)
         + random() * (:'anchor'::timestamptz - greatest(d.created_at, u.date_joined::timestamptz))
FROM (SELECT pp.playlist_id, pp.user_id AS owner_id, pp.created_at,
             5 + floor(random() * (:n_users - 4))::int AS collaborator_id
      FROM playlist_plan pp
      CROSS JOIN LATERAL generate_series(1, pp.n_collaborators) k
      ORDER BY pp.playlist_id, k) d
JOIN app_user u ON u.user_id = d.collaborator_id
WHERE u.user_id <> d.owner_id
ORDER BY d.playlist_id, u.user_id
ON CONFLICT DO NOTHING;

COMMIT;

ANALYZE app_user, playlist, playlist_song, playlist_collaborator, liked_song, listening_history;
