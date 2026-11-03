-- Real songs from Spotify: ~2,900 popular tracks (popularity 70+), added after the
-- hand-made catalog in data_inserts.sql. Run this right after data_inserts.sql,
-- from the repo root with psql (\copy reads the files from your computer).
--
-- The CSV files in data/spotify/ were made by data/clean_spotify_data.py from the
-- Spotify Tracks Dataset (huggingface.co/datasets/maharshipandya/spotify-tracks-dataset).

\copy genre       (genre_id, genre_name)                                           FROM 'data/spotify/genres.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy artist      (artist_id, artist_name)                                         FROM 'data/spotify/artists.csv'     WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy album       (album_id, artist_id, album_title, cover_url)                    FROM 'data/spotify/albums.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy song        (song_id, album_id, song_title, duration_ms, spotify_id, popularity) FROM 'data/spotify/songs.csv'   WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy song_artist (song_id, artist_id, artist_position)                            FROM 'data/spotify/song_artist.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy song_genre  (song_id, genre_id)                                              FROM 'data/spotify/song_genre.csv'  WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

SELECT setval(pg_get_serial_sequence('genre',  'genre_id'),  (SELECT max(genre_id)  FROM genre));
SELECT setval(pg_get_serial_sequence('artist', 'artist_id'), (SELECT max(artist_id) FROM artist));
SELECT setval(pg_get_serial_sequence('album',  'album_id'),  (SELECT max(album_id)  FROM album));
SELECT setval(pg_get_serial_sequence('song',   'song_id'),   (SELECT max(song_id)   FROM song));
