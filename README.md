# EXAAtunes

CMPE 180B team project: a music streaming database in PostgreSQL (hosted on Supabase),
with a small web app on top for the demo.

**Team EXAA:** Xiaohui, Arye, Ehsan, Andrew

## What's in the database

| Table | Rows | Where it comes from |
|---|---|---|
| artist, album, song | 1,891 / 2,446 / 3,082 | 142 hand-entered songs + real Spotify songs with popularity 70+ ([Spotify Tracks Dataset](https://huggingface.co/datasets/maharshipandya/spotify-tracks-dataset)) |
| genre, song_genre, song_artist | 21 / 3,932 / 4,231 | Same |
| app_user | 4 | demo users |
| playlist, playlist_song, playlist_collaborator | 5,012 / 79,454 / 1,503 | Hand-made + random |
| liked_song | 49,498 | Hand-made + random |
| listening_history | 1,000,000 | Random (Oct 2025 – Oct 2026) |

The random data uses a fixed seed, so rebuilding always gives the same rows.

## Files

```
tables/table_creation.sql    all the tables and the song_details view
data/data_inserts.sql        hand-entered songs, demo users, playlists, likes, plays
data/load_spotify_data.sql   loads the Spotify songs from data/spotify/*.csv
data/generate_activity.sql   random users, plays, likes and playlists
data/clean_spotify_data.py   made data/spotify/*.csv from data/source/spotify_tracks_pop70.csv
queries/                     our queries
tests/                       our tests
backend/                     web app server (FastAPI): main.py = endpoints, db.py = connection
frontend/                    web pages (plain HTML, CSS, JavaScript)
```

## Building the database

You need `psql`, which comes with [PostgreSQL](https://www.postgresql.org/download/).
```
From the repo root run these commands:
psql "<DATABASE_URL>" -f tables/table_creation.sql
psql "<DATABASE_URL>" -f data/load_spotify_data.sql
psql "<DATABASE_URL>" -f data/demo_users.sql
psql "<DATABASE_URL>" -f data/generate_activity.sql
```

`<DATABASE_URL>` is the connection string (for Supabase: Project → Connect →
"Session pooler").

## Running the web app

You need **Python 3.11+**.

1. Install the dependencies (from the repo root):
   ```
   py -m venv .venv
   .venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   ```
   On macOS/Linux use `python3 -m venv .venv` and `source .venv/bin/activate`.
   If PowerShell won't run `Activate.ps1`, run
   `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once.
2. Copy `.env.example` to `.env` and put the real `DATABASE_URL` in it
   (`.env` is in `.gitignore`, so it never gets committed).
3. Start the server:
   ```
   uvicorn backend.main:app --reload
   ```
4. Open **http://localhost:8000**
