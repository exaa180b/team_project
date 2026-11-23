-- =====================================================================
-- EXAAtunes demo queries
-- =====================================================================
-- Paste one query at a time into the web app's SQL Console (sidebar).
-- Queries marked "Allow changes" need that box ticked; the rest are read-only.
-- Each query says what it shows and what our data returns.
-- Demo users: 1 = alex_rivera, 2 = maya_chen, 3 = jordan_blake.


-- =====================================================================
-- Query 1: Top 10 most-played songs
-- Purpose: the "Top Songs" chart, counted from every play in listening_history.
-- Shows:   subquery in FROM, GROUP BY, JOIN with the song_details view (which
--          adds album and artist names). Counting plays first and looking up
--          names for only the top 10 is much faster than joining every play.
-- Result:  "Quevedo: Bzrp Music Sessions, Vol. 52" is #1 with 4,571 plays, then
--          "I'm Good (Blue)" (3,817) and "Unholy" (3,584). Runs in about 50 ms.
-- =====================================================================
SELECT d.song_title, d.artists, top.plays
FROM (SELECT song_id, count(*) AS plays
      FROM listening_history
      GROUP BY song_id
      ORDER BY plays DESC
      LIMIT 10) top
JOIN song_details d ON d.song_id = top.song_id
ORDER BY top.plays DESC;


-- =====================================================================
-- Query 2: Most-played genres, with each genre's share of all plays
-- Purpose: what kind of music people listen to the most.
-- Shows:   3-table JOIN, GROUP BY, and a window function (sum(...) OVER ())
--          to turn counts into percentages
-- Result:  Pop is first with 27.6% of plays, then Electronic (17.0%), Rock (16.6%)
--          and Hip-Hop (13.5%).
-- =====================================================================
SELECT g.genre_name,
       count(*) AS plays,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS percent_of_plays
FROM listening_history h
JOIN song_genre sg ON sg.song_id = h.song_id
JOIN genre g       ON g.genre_id = sg.genre_id
GROUP BY g.genre_name
ORDER BY plays DESC
LIMIT 10;


-- =====================================================================
-- Query 3: Each demo user's top 3 artists
-- Purpose: "Your top artists" for every user at once.
-- Shows:   CTE (WITH), window function ROW_NUMBER() OVER (PARTITION BY ...)
-- Result:  each user's taste shows: alex_rivera (pop) -> Sam Smith, The Weeknd,
--          David Guetta; maya_chen (hip-hop) -> Eminem, Bizarrap, XXXTENTACION;
--          jordan_blake (rock) -> Arctic Monkeys, OneRepublic, The Neighbourhood.
-- =====================================================================
WITH artist_plays AS (
    SELECT u.username, a.artist_name, count(*) AS plays
    FROM listening_history h
    JOIN app_user u     ON u.user_id = h.user_id
    JOIN song_artist sa ON sa.song_id = h.song_id AND sa.artist_position = 1
    JOIN artist a       ON a.artist_id = sa.artist_id
    WHERE h.user_id IN (1, 2, 3)
    GROUP BY u.username, a.artist_name
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY username ORDER BY plays DESC, artist_name) AS rank
    FROM artist_plays
)
SELECT username, rank, artist_name, plays
FROM ranked
WHERE rank <= 3
ORDER BY username, rank;


-- =====================================================================
-- Query 4: alex_rivera's listening per month
-- Purpose: a "listening over time" chart for one user.
-- Shows:   date_trunc to group timestamps by month, SUM of song lengths
-- Result:  12 rows, Oct 2025 to Sep 2026, about 6,300 plays (365 hours) a month.
-- =====================================================================
SELECT to_char(date_trunc('month', h.played_at), 'YYYY-MM') AS month,
       count(*) AS plays,
       round(sum(s.duration_ms) / 3600000.0, 1) AS hours
FROM listening_history h
JOIN song s ON s.song_id = h.song_id
WHERE h.user_id = 1
GROUP BY 1
ORDER BY 1;


-- =====================================================================
-- Query 5: Songs alex_rivera keeps playing but hasn't liked yet
-- Purpose: a simple recommendation ("you might want to like these").
-- Shows:   NOT EXISTS (anti-join), GROUP BY with HAVING
-- Result:  10 songs alex played 28-29 times without liking them
--          (users like a song once they've played it 30 times).
-- =====================================================================
SELECT d.song_title, d.artists, count(*) AS times_played
FROM listening_history h
JOIN song_details d ON d.song_id = h.song_id
WHERE h.user_id = 1
  AND NOT EXISTS (SELECT 1 FROM liked_song l
                  WHERE l.user_id = 1 AND l.song_id = h.song_id)
GROUP BY d.song_id, d.song_title, d.artists
HAVING count(*) >= 20
ORDER BY times_played DESC, d.song_title
LIMIT 10;


-- =====================================================================
-- Query 6: Playlist overview
-- Purpose: every demo playlist with its owner, collaborators, song count and length.
-- Shows:   LEFT JOIN (keeps empty playlists), GROUP BY, string_agg, COALESCE
-- Result:  "Morning Commute" (jordan_blake, 131 songs, 469 min) is the biggest.
--          Playlists with no songs would still show up (0 songs) thanks to the LEFT JOIN.
-- =====================================================================
SELECT p.playlist_id,
       p.playlist_name,
       owner.username AS owner,
       coalesce((SELECT string_agg(u.username, ', ')
                 FROM playlist_collaborator pc
                 JOIN app_user u ON u.user_id = pc.user_id
                 WHERE pc.playlist_id = p.playlist_id), '-') AS collaborators,
       count(ps.song_id) AS songs,
       round(coalesce(sum(s.duration_ms), 0) / 60000.0) AS minutes
FROM playlist p
JOIN app_user owner     ON owner.user_id = p.user_id
LEFT JOIN playlist_song ps ON ps.playlist_id = p.playlist_id
LEFT JOIN song s           ON s.song_id = ps.song_id
WHERE p.user_id IN (1, 2, 3)
GROUP BY p.playlist_id, p.playlist_name, owner.username
ORDER BY songs DESC
LIMIT 15;


-- =====================================================================
-- Query 7: CRUD on a playlist (Create, Read, Update, Delete)   [Allow changes]
-- Purpose: the four basic operations, one after another. The console shows the
--          result of every statement, so you can watch each step.
-- Shows:   INSERT ... RETURNING, UPDATE, DELETE with ON DELETE CASCADE
--          (deleting the playlist also deletes its playlist_song rows)
-- Result:  makes the playlist, adds the 3 most popular songs, renames it, deletes it.
--          The last result is 0: the playlist and its songs are gone.
-- =====================================================================
-- Create
INSERT INTO playlist (user_id, playlist_name, description)
VALUES (1, 'Demo Playlist', 'made live during the demo')
RETURNING playlist_id, playlist_name;

INSERT INTO playlist_song (playlist_id, song_id)
SELECT p.playlist_id, s.song_id
FROM playlist p, (SELECT song_id FROM song ORDER BY popularity DESC LIMIT 3) s
WHERE p.user_id = 1 AND p.playlist_name = 'Demo Playlist';

-- Read
SELECT p.playlist_name, d.song_title, d.artists
FROM playlist p
JOIN playlist_song ps ON ps.playlist_id = p.playlist_id
JOIN song_details d   ON d.song_id = ps.song_id
WHERE p.user_id = 1 AND p.playlist_name = 'Demo Playlist';

-- Update
UPDATE playlist SET playlist_name = 'Demo Playlist (renamed)'
WHERE user_id = 1 AND playlist_name = 'Demo Playlist';

SELECT playlist_id, playlist_name, description FROM playlist
WHERE user_id = 1 AND playlist_name LIKE 'Demo Playlist%';

-- Delete (its songs go too, because playlist_song has ON DELETE CASCADE)
DELETE FROM playlist WHERE user_id = 1 AND playlist_name = 'Demo Playlist (renamed)';

SELECT count(*) AS demo_playlists_left FROM playlist
WHERE user_id = 1 AND playlist_name LIKE 'Demo Playlist%';


-- =====================================================================
-- Query 8: Indexing, before and after   [Allow changes]
-- Purpose: show how an index speeds up a lookup on the biggest table.
-- Shows:   EXPLAIN ANALYZE, CREATE INDEX. Without an index Postgres reads
--          every row of listening_history (Seq Scan); with one it jumps
--          straight to the matching rows (Bitmap Index Scan).
-- Result:  before: Parallel Seq Scan over all 300,000 rows, about 30 ms.
--          After: Index Only Scan using idx_history_song, about 0.2 ms.
-- =====================================================================
-- Before: no index on song_id
EXPLAIN ANALYZE
SELECT count(*) FROM listening_history WHERE song_id = 42;

CREATE INDEX idx_history_song ON listening_history (song_id);

-- After: same query with the index
EXPLAIN ANALYZE
SELECT count(*) FROM listening_history WHERE song_id = 42;

-- Remove it again so the demo can be repeated
DROP INDEX idx_history_song;


-- =====================================================================
-- Query 9: Trigger   [Allow changes]
-- Purpose: a playlist's owner can't also be a collaborator on it. The trigger
--          no_owner_as_collaborator (in tables/table_creation.sql) checks this
--          on every insert, because a CHECK constraint can't look at another table.
-- Run 9a and 9b separately.
-- =====================================================================
-- 9a: maya_chen (user 2) owns "Gym Hype" (playlist 4), so the trigger rejects this
-- Result: ERROR: User 2 already owns playlist 4, so they can't be a collaborator on it
INSERT INTO playlist_collaborator (playlist_id, user_id) VALUES (4, 2);

-- 9b: alex_rivera (user 1) doesn't own it, so this works. ROLLBACK undoes it afterwards.
-- Result: the insert works and playlist 4 shows alex_rivera as a collaborator; ROLLBACK undoes it.
BEGIN;
INSERT INTO playlist_collaborator (playlist_id, user_id) VALUES (4, 1);
SELECT pc.playlist_id, u.username AS collaborator
FROM playlist_collaborator pc JOIN app_user u ON u.user_id = pc.user_id
WHERE pc.playlist_id = 4;
ROLLBACK;


-- =====================================================================
-- Query 10: Concurrency - lost update, fixed with an isolation level   [Allow changes]
-- Purpose: two people update the same song at the same time. Each one reads the
--          popularity score, waits, then writes "what I read + 1". With two
--          updates the score should go up by 2.
-- How:     open the SQL Console in TWO browser tabs. Paste the same query into
--          both, run it in tab A, then run it in tab B within a few seconds.
--          The pg_sleep makes each transaction slow enough to overlap.
-- =====================================================================
-- 10a. The problem: READ COMMITTED (Postgres's default)
-- Result: both tabs read 70 and both commit. 10c then shows 71, not 72:
--         one of the two updates was lost.
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT popularity FROM song WHERE song_id = 3012;            -- both tabs read 70
SELECT pg_sleep(10);                                          -- the other tab runs meanwhile
UPDATE song SET popularity = 71 WHERE song_id = 3012;         -- each writes what it read + 1
COMMIT;

-- 10b. The fix: REPEATABLE READ. Same steps, different isolation level.
-- Result: tab A commits; tab B fails with "could not serialize access due to
--         concurrent update", so nothing is lost. The app would then retry tab B's
--         transaction: it would read 71 and write 72.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT popularity FROM song WHERE song_id = 3012;
SELECT pg_sleep(10);
UPDATE song SET popularity = 71 WHERE song_id = 3012;
COMMIT;

-- 10c. Check the score, then reset it to 70 for the next run
SELECT song_title, popularity FROM song WHERE song_id = 3012;
UPDATE song SET popularity = 70 WHERE song_id = 3012;
