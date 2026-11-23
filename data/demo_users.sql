INSERT INTO app_user (user_id, username, email, password_hash, date_joined)
VALUES
  (1, 'alex_rivera', 'alex.rivera@example.com', 'demo-placeholder', '2025-08-03'),
  (2, 'maya_chen', 'maya.chen@example.com', 'demo-placeholder', '2025-10-01'),
  (3, 'jordan_blake', 'jordan.blake@example.com', 'demo-placeholder', '2024-09-01'),
  (4, 'sam_patel', 'sam.patel@example.com', 'demo-placeholder', '2023-01-10');

-- playlist shells only (no hard-coded song ids from the old hand catalog)
INSERT INTO playlist (playlist_id, user_id, playlist_name, description)
VALUES
  (1, 1, 'Morning Coffee', 'Easy songs to start the day'),
  (2, 1, 'Road Trip', 'Windows down'),
  (3, 1, 'Sunday Acoustic', NULL),
  (4, 2, 'Gym Hype', 'Lift heavy'),
  (5, 2, 'Late Night Drive', NULL),
  (6, 2, 'Throwbacks', 'Songs from high school'),
  (7, 3, 'Classic Rock', NULL),
  (8, 3, 'Mosh Pit', NULL),
  (9, 3, 'Garage Band Practice', 'Songs we are learning'),
  (10, 4, 'Deep Focus', 'For studying'),
  (11, 4, 'Rainy Day Jazz', NULL),
  (12, 4, 'Dance Floor', NULL);

INSERT INTO playlist_collaborator (playlist_id, user_id)
VALUES
  (2, 2),
  (4, 3),
  (12, 1);

-- Songs in the 12 playlists above, looked up by title and main artist
-- (so this works no matter what ids the songs got when they were loaded).
INSERT INTO playlist_song (playlist_id, song_id, added_at)
SELECT v.playlist_id, s.song_id, timestamptz '2026-09-15 12:00:00-07'
FROM (VALUES
  -- Morning Coffee
  (1, 'Someone Like You', 'Adele'),
  (1, 'Perfect', 'Ed Sheeran'),
  (1, 'Skinny Love', 'Bon Iver'),
  (1, 'Watermelon Sugar', 'Harry Styles'),
  (1, 'Photograph', 'Ed Sheeran'),
  (1, 'Lover', 'Taylor Swift'),
  (1, 'Don''t Know Why', 'Norah Jones'),
  -- Road Trip
  (2, 'Shape of You', 'Ed Sheeran'),
  (2, 'Levitating', 'Dua Lipa'),
  (2, 'bad guy', 'Billie Eilish'),
  (2, 'Uptown Funk (feat. Bruno Mars)', 'Mark Ronson'),
  (2, 'Get Lucky (feat. Pharrell Williams & Nile Rodgers) - Radio Edit', 'Daft Punk'),
  (2, 'I Will Wait', 'Mumford & Sons'),
  (2, 'Take It Easy - 2013 Remaster', 'Eagles'),
  (2, 'As It Was', 'Harry Styles'),
  -- Sunday Acoustic
  (3, 'Skinny Love', 'Bon Iver'),
  (3, 'Jolene', 'Dolly Parton'),
  (3, 'Tennessee Whiskey', 'Chris Stapleton'),
  (3, 'Blackbird - Remastered 2009', 'The Beatles'),
  (3, 'Here Comes The Sun - Remastered 2009', 'The Beatles'),
  (3, 'Make You Feel My Love', 'Adele'),
  -- Gym Hype
  (4, 'HUMBLE.', 'Kendrick Lamar'),
  (4, 'N95', 'Kendrick Lamar'),
  (4, 'Stan', 'Eminem'),
  (4, 'Lose Yourself - From "8 Mile" Soundtrack', 'Eminem'),
  (4, 'Till I Collapse', 'Eminem'),
  (4, 'Jimmy Cooks (feat. 21 Savage)', 'Drake'),
  (4, 'God''s Plan', 'Drake'),
  -- Late Night Drive
  (5, 'Blinding Lights', 'The Weeknd'),
  (5, 'Starboy', 'The Weeknd'),
  (5, 'Save Your Tears', 'The Weeknd'),
  (5, 'Call Out My Name', 'The Weeknd'),
  (5, 'Nights', 'Frank Ocean'),
  (5, 'White Ferrari', 'Frank Ocean'),
  (5, 'Leave The Door Open', 'Bruno Mars'),
  -- Throwbacks
  (6, 'Thriller', 'Michael Jackson'),
  (6, 'Rock with You - Single Version', 'Michael Jackson'),
  (6, 'Gasolina', 'Daddy Yankee'),
  (6, 'Hips Don''t Lie (feat. Wyclef Jean)', 'Shakira'),
  (6, 'Whenever, Wherever', 'Shakira'),
  (6, 'I Say a Little Prayer', 'Aretha Franklin'),
  (6, 'Ain''t No Mountain High Enough', 'Marvin Gaye'),
  -- Classic Rock
  (7, 'Bohemian Rhapsody', 'Queen'),
  (7, 'Hotel California - 2013 Remaster', 'Eagles'),
  (7, 'Stairway to Heaven - Remaster', 'Led Zeppelin'),
  (7, 'Come Together - Remastered 2009', 'The Beatles'),
  (7, 'Money', 'Pink Floyd'),
  (7, 'Comfortably Numb', 'Pink Floyd'),
  -- Mosh Pit
  (8, 'Enter Sandman', 'Metallica'),
  (8, 'Master Of Puppets', 'Metallica'),
  (8, 'Sad But True', 'Metallica'),
  (8, 'Back In Black', 'AC/DC'),
  (8, 'Hells Bells', 'AC/DC'),
  (8, 'Immigrant Song - Remaster', 'Led Zeppelin'),
  -- Garage Band Practice
  (9, 'Smells Like Teen Spirit', 'Nirvana'),
  (9, 'Everlong', 'Foo Fighters'),
  (9, 'American Idiot', 'Green Day'),
  (9, 'Last Nite', 'The Strokes'),
  (9, 'Do I Wanna Know?', 'Arctic Monkeys'),
  (9, 'Black Dog - Remaster', 'Led Zeppelin'),
  -- Deep Focus
  (10, 'Time', 'Pink Floyd'),
  (10, 'Breathe (In the Air)', 'Pink Floyd'),
  (10, 'Nuvole Bianche', 'Ludovico Einaudi'),
  (10, 'River Flows In You', 'Yiruma'),
  (10, 'Time Moves Slow', 'BADBADNOTGOOD'),
  -- Rainy Day Jazz
  (11, 'Just the Two of Us (feat. Bill Withers)', 'Grover Washington, Jr.'),
  (11, 'Don''t Know Why', 'Norah Jones'),
  (11, 'Come Away With Me', 'Norah Jones'),
  (11, 'At Last', 'Etta James'),
  (11, 'Feeling Good', 'Nina Simone'),
  (11, 'What A Wonderful World', 'Louis Armstrong'),
  -- Dance Floor
  (12, 'Wake Me Up', 'Avicii'),
  (12, 'Levels - Radio Edit', 'Avicii'),
  (12, 'Levitating', 'Dua Lipa'),
  (12, 'Don''t Start Now', 'Dua Lipa'),
  (12, 'Get Lucky (feat. Pharrell Williams & Nile Rodgers) - Radio Edit', 'Daft Punk'),
  (12, 'Instant Crush (feat. Julian Casablancas)', 'Daft Punk'),
  (12, 'Feel Good Inc.', 'Gorillaz')
) AS v(playlist_id, song_title, artist_name)
JOIN song s         ON s.song_title = v.song_title
JOIN song_artist sa ON sa.song_id = s.song_id AND sa.artist_position = 1
JOIN artist a       ON a.artist_id = sa.artist_id AND a.artist_name = v.artist_name;
