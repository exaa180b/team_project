-- extra plays, likes, and playlists for the 4 demo users.

-- setseed makes random() return the same numbers every time, so reloading gives the same data.
SELECT setseed(0.18);


-- Songs ranked by Spotify popularity (rank 1 = most popular). Below, songs are
-- picked by rank with power(random(), 2), which favors small numbers, so popular
-- songs get played and added to playlists more often.
CREATE TEMP TABLE song_rank AS
SELECT song_id,
       row_number() OVER (ORDER BY popularity DESC, song_id) AS song_rank
FROM song;


-- Each demo user's favorite genres.
CREATE TEMP TABLE favorite_genre (user_id INTEGER, genre_name TEXT);
INSERT INTO favorite_genre VALUES
  (1, 'Pop'),                       -- alex_rivera
  (2, 'Hip-Hop'), (2, 'R&B'),       -- maya_chen
  (3, 'Rock'), (3, 'Metal'),        -- jordan_blake
  (4, 'Jazz'), (4, 'Electronic');   -- sam_patel

-- The songs in each user's favorite genres, ranked by popularity.
CREATE TEMP TABLE favorite_song AS
SELECT f.user_id, s.song_id,
       row_number() OVER (PARTITION BY f.user_id ORDER BY s.popularity DESC, s.song_id) AS song_rank
FROM favorite_genre f
JOIN genre g       ON g.genre_name = f.genre_name
JOIN song_genre sg ON sg.genre_id = g.genre_id
JOIN song s        ON s.song_id = sg.song_id
GROUP BY f.user_id, s.song_id, s.popularity;   -- a song in both of a user's genres counts once


-- Listening history: 300,000 plays from Oct 2025 to Oct 2026. 70% come from the
-- user's favorite genres, the other 30% can be any song. Sorted by time, so
-- history_id goes up with played_at like it would in a real app.
INSERT INTO listening_history (user_id, song_id, played_at)
SELECT user_id, song_id, played_at
FROM (
    -- 210,000 plays from the user's favorite genres
    SELECT p.user_id, f.song_id, p.played_at
    FROM (SELECT 1 + floor(random() * 4)::int AS user_id,
                 random() AS pick,
                 timestamptz '2026-10-01 00:00:00-07' - random() * interval '365 days' AS played_at
          FROM generate_series(1, 210000)) p
    JOIN (SELECT user_id, count(*) AS songs FROM favorite_song GROUP BY user_id) c
         ON c.user_id = p.user_id
    JOIN favorite_song f
         ON f.user_id = p.user_id AND f.song_rank = 1 + floor(power(p.pick, 2) * c.songs)::int

    UNION ALL

    -- 90,000 plays of any song
    SELECT p.user_id, r.song_id, p.played_at
    FROM (SELECT 1 + floor(random() * 4)::int AS user_id,
                 1 + floor(power(random(), 2) * (SELECT count(*) FROM song_rank))::int AS song_rank,
                 timestamptz '2026-10-01 00:00:00-07' - random() * interval '365 days' AS played_at
          FROM generate_series(1, 90000)) p
    JOIN song_rank r ON r.song_rank = p.song_rank
) plays
ORDER BY played_at;


-- Liked songs: each user likes the songs they've played at least 30 times,
-- liked on the day they first played them.
INSERT INTO liked_song (user_id, song_id, liked_at)
SELECT user_id, song_id, min(played_at)
FROM listening_history
GROUP BY user_id, song_id
HAVING count(*) >= 30;


-- Playlists 13-42 (1-12 are in demo_users.sql)
INSERT INTO playlist (playlist_id, user_id, playlist_name, description, created_at)
SELECT g,
       1 + floor(random() * 4)::int,
       (ARRAY['Chill Vibes','Workout','Road Trip','Study Session','Party Mix','Late Night',
              'Morning Commute','Sunday Morning','Throwbacks','Feel Good','Rainy Day',
              'Summer Hits','Focus','Sleep','Cooking','Running','Gaming','Heartbreak',
              'Main Character','Car Karaoke','Gym Hype','Coffee Shop','Night Drive',
              'Pregame','Wind Down','On Repeat','Golden Hour','Beach Day',
              'Throwback Thursday','My Playlist'])[1 + floor(random() * 30)::int],
       CASE WHEN random() < 0.5
            THEN (ARRAY['songs on repeat lately','for the drive home','no skips','updated weekly',
                        'turn it up','vibes only','for when you need a boost','my current favorites'])[1 + floor(random() * 8)::int]
       END,
       timestamptz '2025-10-01 00:00:00-07' - random() * interval '365 days'
FROM generate_series(13, 42) g;


-- Songs in those playlists: 3,000 tries. The same song twice in a playlist is skipped.
INSERT INTO playlist_song (playlist_id, song_id, added_at)
SELECT ps.playlist_id, r.song_id, ps.added_at
FROM (SELECT 13 + floor(random() * 30)::int AS playlist_id,
             1 + floor(power(random(), 2) * (SELECT count(*) FROM song_rank))::int AS song_rank,
             timestamptz '2026-10-01 00:00:00-07' - random() * interval '365 days' AS added_at
      FROM generate_series(1, 3000)) ps
JOIN song_rank r ON r.song_rank = ps.song_rank
ON CONFLICT DO NOTHING;


-- Shared playlists: 80 tries. Owners can't be collaborators on their own playlist.
INSERT INTO playlist_collaborator (playlist_id, user_id, added_at)
SELECT c.playlist_id, c.user_id, c.added_at
FROM (SELECT 13 + floor(random() * 30)::int AS playlist_id,
             1 + floor(random() * 4)::int AS user_id,
             timestamptz '2026-10-01 00:00:00-07' - random() * interval '365 days' AS added_at
      FROM generate_series(1, 80)) c
JOIN playlist p ON p.playlist_id = c.playlist_id
WHERE p.user_id <> c.user_id
ON CONFLICT DO NOTHING;


SELECT setval(pg_get_serial_sequence('app_user', 'user_id'),     (SELECT max(user_id)     FROM app_user));
SELECT setval(pg_get_serial_sequence('playlist', 'playlist_id'), (SELECT max(playlist_id) FROM playlist));


-- Update the statistics Postgres uses to plan queries, now that the tables are full.
-- (Without this, the first queries after a fresh load can pick very slow plans.)
ANALYZE;
