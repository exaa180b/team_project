-- these are test queries to run on the database to make sure it's working correctly and that it loaded everything we needed it to
-- Expect 4
SELECT count(*) AS demo_users FROM app_user;
-- Expect about 3012
SELECT count(*) AS songs FROM song;
-- Expect 21 (GENRE_MAP)
SELECT count(*) AS genres FROM genre;
-- Expect at least 42
SELECT max(playlist_id) AS max_playlist_id FROM playlist;
-- Expect a large number (hundreds of thousands)
SELECT count(*) AS plays FROM listening_history;
-- Expect 0 (only users 1-4)
SELECT count(*) AS bad_user_plays
FROM listening_history
WHERE user_id NOT BETWEEN 1 AND 4;

-- tests for data integrity, we should expect these to return 0 meaning there are no errors
-- plays with a missing user or song
SELECT count(*) FROM listening_history h
WHERE NOT EXISTS (SELECT 1 FROM app_user u WHERE u.user_id = h.user_id)
   OR NOT EXISTS (SELECT 1 FROM song s WHERE s.song_id = h.song_id);
-- playlist songs with a missing playlist or song
SELECT count(*) FROM playlist_song ps
WHERE NOT EXISTS (SELECT 1 FROM playlist p WHERE p.playlist_id = ps.playlist_id)
   OR NOT EXISTS (SELECT 1 FROM song s WHERE s.song_id = ps.song_id);
-- likes with a missing user or song
SELECT count(*) FROM liked_song l
WHERE NOT EXISTS (SELECT 1 FROM app_user u WHERE u.user_id = l.user_id)
   OR NOT EXISTS (SELECT 1 FROM song s WHERE s.song_id = l.song_id);
-- owner also listed as collaborator
SELECT count(*) FROM playlist_collaborator pc
JOIN playlist p ON p.playlist_id = pc.playlist_id
WHERE p.user_id = pc.user_id;