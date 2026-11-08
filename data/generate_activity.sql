-- extra plays, likes, and playlists for the 4 demo users.

-- setseed makes random() return the same numbers every time, so reloading gives the same data.
SELECT setseed(0.18);


-- Songs ranked by Spotify popularity (rank 1 = most popular). Hand-entered songs
-- without a score count as 75. Below, songs are picked by rank with
-- power(random(), 2), which favors small numbers, so popular songs get played,
-- liked and added to playlists more often.
CREATE TEMP TABLE song_rank AS
SELECT song_id,
       row_number() OVER (ORDER BY coalesce(popularity, 75) DESC, song_id) AS song_rank
FROM song;


-- Listening history: 900,000 plays from Oct 2025 to Oct 2026 Sorted by time, so history_id
-- goes up with played_at like it would in a real app.
INSERT INTO listening_history (user_id, song_id, played_at)
SELECT p.user_id, r.song_id, p.played_at
FROM (SELECT 1 + floor(random() * 4)::int AS user_id,
             1 + floor(power(random(), 2) * (SELECT count(*) FROM song_rank))::int AS song_rank,
             timestamptz '2026-10-01 00:00:00-07' - random() * interval '365 days' AS played_at
      FROM generate_series(1, 300000)) p
JOIN song_rank r ON r.song_rank = p.song_rank
ORDER BY p.played_at;


-- Liked songs: 50,000 tries. Picking the same user and song twice is skipped.
INSERT INTO liked_song (user_id, song_id, liked_at)
SELECT l.user_id, r.song_id, l.liked_at
FROM (SELECT 1 + floor(random() * 4)::int AS user_id,
             1 + floor(power(random(), 2) * (SELECT count(*) FROM song_rank))::int AS song_rank,
             timestamptz '2026-10-01 00:00:00-07' - random() * interval '365 days' AS liked_at
      FROM generate_series(1, 50000)) l
JOIN song_rank r ON r.song_rank = l.song_rank
ON CONFLICT DO NOTHING;


-- Playlists 13-42 (1-12 are in data_inserts.sql), 
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


-- Songs in those playlists: 80,000 tries. The same song twice in a playlist is skipped.
INSERT INTO playlist_song (playlist_id, song_id, added_at)
SELECT ps.playlist_id, r.song_id, ps.added_at
FROM (SELECT 13 + floor(random() * 30)::int AS playlist_id,
             1 + floor(power(random(), 2) * (SELECT count(*) FROM song_rank))::int AS song_rank,
             timestamptz '2026-10-01 00:00:00-07' - random() * interval '365 days' AS added_at
      FROM generate_series(1, 3000)) ps
JOIN song_rank r ON r.song_rank = ps.song_rank
ON CONFLICT DO NOTHING;


-- Shared playlists: 1,500 tries. Owners can't be collaborators on their own playlist.
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
