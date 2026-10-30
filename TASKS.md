# Task list: full marks on Features & Code (15%) + Demo (12%)

Drafted 2026-10-29 from the repo at commit `3e6c112`. Done so far: schema (12 tables) and seed data.
Everything below is still open. Each task names the rubric line it serves.

Rubric for code: "code quality, test cases, results, and adherence to best practices."
Required in the repo: creation/population/CRUD scripts, annotated complex queries, indexing scripts
with performance notes, transaction scripts explaining isolation levels, test scripts *and their
output*, and a README covering setup, execution, dependencies and testing.

---

## 0. Repo structure + one-command setup (best practices; demo reliability)

- [ ] Rename SQL into run order: `sql/01_schema.sql`, `02_schema_fixes.sql` (or merge the ALTERs
      into 01), `03_seed.sql`, `04_generate_data.sql`, `05_indexes.sql`, `06_views.sql`, …
- [ ] Make every script **re-runnable**: `DROP ... IF EXISTS` / `CREATE OR REPLACE` /
      `ON CONFLICT DO NOTHING`, all wrapped in `BEGIN; ... COMMIT;`.
- [ ] `scripts/setup.ps1` + `scripts/setup.sh`: create DB → run all SQL in order → print row counts.
      Everyone (and the demo laptop) builds the same DB from scratch with one command.
- [ ] `.env.example` (DB host/port/name/user, no password); confirm `.env` is gitignored (it is).
- [ ] Fix `.gitignore`: trailing spaces/comments on the same line (`.env `, `.cursor/ # EXAA`)
      can stop the patterns from matching.
- [ ] Use a non-superuser app role (`spotify_app`) with only the GRANTs it needs, and have the
      backend connect as it. Cheap to add and an easy "best practices" point.

## 1. Data volume: ≥1,000 rows per major table (required)

**DONE locally (2026-10-29):** `data/load_spotify_tracks.sql` (3,012 real tracks, popularity ≥ 70,
from `data/source/spotify_tracks_pop70.csv`) + `data/generate_activity.sql` (deterministic, fixed
"now" = 2026-10-01 LA time). Run order: tables/table_creation → tables/table_fixes → data/data_inserts
→ data/load_spotify_tracks → data/generate_activity (~40s total). Result: 1,891 artists, 2,446 albums,
3,082 songs, 21 genres, 2,000 users, 5,040 playlists, 80,544 playlist_song, 1,551 collaborators,
49,149 likes, 999,996 plays; ~100 MB. Verified invariants and that re-runs are identical.
`song` gained `popularity` and `explicit` columns (table_fixes.sql). The old 100k-play generator
in data_inserts.sql was removed. Applied to Supabase 2026-10-29 (identical data, 93 MB). Not yet committed.
The notes below are the original plan.

Current (verified by loading into Postgres 18, 2026-10-29): listening_history 100k (25k each for
4 users); everything else is tiny: 4 users, 142 songs, 83 albums, 69 artists, 12 playlists,
75 playlist_song, 27 liked_song, 203 song_genre, 153 song_artist. Every song has ≥1 genre and ≥1 artist.
The existing scripts load cleanly in ~2s.

- [ ] **Pick the source.** Recommended: load a public Spotify tracks CSV (e.g. a Kaggle
      "Spotify tracks" dataset) via `\copy` into a `staging_tracks` table, then normalize into
      artist/album/song/song_artist/song_genre with `INSERT ... SELECT ... ON CONFLICT`.
      `song.spotify_id` and the name-based UNIQUE constraints in table_fixes.sql were built for
      this. It also gives the report a real ETL/normalization story.
      Fallback: synthetic `generate_series` data (faster, but less realistic).
- [ ] Targets: songs ≥5k, artists ≥1k, albums ≥1k, genres (small lookup table; fine as is),
      app_user ≥1k–5k, playlist ≥2k, playlist_song ≥20k, liked_song ≥20k,
      listening_history **~1M** (needed for index timings that look convincing).
- [ ] Spread history over many users. With 4 users, an index on `user_id` matches 25% of the
      table, the planner ignores it, and the indexing demo shows nothing.
- [ ] Keep the invariant the current seed already meets: every song has ≥1 `song_artist`
      (position 1 = album's artist) and ≥1 `song_genre`.
- [ ] Use a fixed `setseed()` so data (and therefore test expectations) is reproducible.
- [ ] Run `VACUUM ANALYZE` at the end of the load.

## 2. Schema polish (feeds report + code quality)

- [ ] Postgres does **not** auto-index foreign keys: add indexes on `album.artist_id`,
      `song.album_id`, `song_artist.artist_id`, `song_genre.genre_id`, `playlist.user_id`,
      `playlist_song.song_id`, `liked_song.song_id`. (Keep these out of the "before" timings
      in the indexing demo, or add them as part of the "after" step.)
- [ ] Decide on `album.artist_id` vs `song_artist`: either keep both and document why
      (album artist ≠ track artists) or drop one. Note it as a design decision in the report.
- [ ] Add `playlist_song.position` (needed for ordering, and for concurrency scenario B below).
- [ ] Extra CHECKs: email format, `played_at <= now()`, `liked_at`/`added_at` sanity.
- [ ] ER diagram: export to `docs/er_diagram.png` (dbdiagram.io, or pgAdmin's ERD tool) and
      include it in the README.

## 3. CRUD scripts (required)

`sql/crud.sql`, one commented block per operation, using realistic app actions:
- [ ] Create: sign up a user, create a playlist, add a song to a playlist, like a song, log a play.
- [ ] Read: user profile + playlists, playlist contents with total duration, search songs by
      title/artist (`ILIKE`, or `pg_trgm` for fuzzy search).
- [ ] Update: rename a playlist, reorder a song, change an email (UNIQUE conflict handled).
- [ ] Delete: unlike, remove from playlist, delete user (cascades shown), and a delete that
      **fails** because of `ON DELETE RESTRICT` (deleting an artist that has albums).

## 4. Complex queries (required; core of the demo)

`queries/queries.sql`: 8–10 queries, each with a header comment: **purpose**, **techniques
used**, and a **sample output** pasted beneath it (or saved to `results/queries/*.txt`).
- [ ] Top 10 songs per genre in the last 30 days: `RANK() OVER (PARTITION BY genre ...)`.
- [ ] A user's "Wrapped": top artists/songs/genres for a year, total minutes listened (CTEs).
- [ ] Recommendations: songs liked by users who share ≥N likes with me that I haven't
      heard (self-join + `NOT EXISTS`).
- [ ] Listening trend by week/hour of day: `date_trunc`, `extract`, plus `FILTER`.
- [ ] Artist leaderboard: distinct listeners, plays, and play share (window `SUM() OVER ()`).
- [ ] Playlist summary: song count, total duration, genre mix, collaborators (multi-join + `string_agg`).
- [ ] Users who never listened to a given genre (anti-join).
- [ ] "Repeat listens": songs a user played ≥3 days in a row (`LAG`, gaps-and-islands).
- [ ] Optional: materialized view `mv_daily_song_plays` + `REFRESH MATERIALIZED VIEW CONCURRENTLY`.

## 5. Indexing + EXPLAIN before/after (required, demoed)

`sql/indexing.sql` plus `results/explain/`:
- [ ] Choose 4–5 of the queries above. For each: `EXPLAIN (ANALYZE, BUFFERS)` **without** the
      index → create the index → `ANALYZE` → rerun. Save both plans.
- [ ] Candidate indexes:
  - `listening_history (user_id, played_at DESC)`: per-user history / Wrapped
  - `listening_history (song_id, played_at)`: song charts in a time window
  - `listening_history (played_at)`, compared as BRIN vs B-tree (size vs speed; good talking point)
  - covering index with `INCLUDE`, to show an Index Only Scan
  - partial index (e.g. last 90 days) or expression index `lower(username)`
  - `pg_trgm` GIN index on `song_title` for search
- [ ] Summary table (query | before ms | after ms | plan change | index size) in
      `results/explain/README.md`. The report and slides reuse it.
- [ ] One example where an index **doesn't** help (low selectivity) and why; shows understanding.

## 6. Transactions, ACID, isolation levels (required, demoed)

`sql/transactions.sql` + `concurrency/` (two-session demos):
- [ ] **Atomicity:** "create user + default 'Liked Songs' playlist" in one transaction; force a
      failure midway, then show nothing was written. Also show a SAVEPOINT partial rollback.
- [ ] **Consistency:** a constraint violation (duplicate username, bad FK) aborts the transaction.
- [ ] **Durability:** commit, restart the server, row is still there (a screenshot is enough).
- [ ] **Concurrency scenarios** (each: anomaly under a weak level → fix):
  - A. Lost update / duplicate position: two collaborators append to the same playlist at once
       and both get `position = max+1`. Fix: `SELECT ... FOR UPDATE` on the playlist row, or
       `UNIQUE (playlist_id, position)` + retry.
  - B. Non-repeatable read: a report reads play counts twice while plays are inserted
       (READ COMMITTED vs REPEATABLE READ).
  - C. Write skew: rule "max 5 collaborators per playlist"; two concurrent adds both pass the
       check under REPEATABLE READ. SERIALIZABLE raises `40001` → retry loop.
  - D. Deadlock: two sessions lock rows in opposite order; Postgres detects it. Fix: consistent
       lock ordering.
- [ ] Automate A–D in Python (`concurrency/run_scenarios.py`, two psycopg connections plus
      threads/barriers) so they're **repeatable on demo day** and usable as tests. Keep the
      two-psql-window `.sql` versions for showing it live.

## 7. Tests + captured results (required; explicitly graded)

- [ ] Framework: **pytest + psycopg** against a fresh test DB built by the setup script
      (pgTAP is the alternative but is hard to install on Windows).
- [ ] `tests/test_integrity.py`: every PK/FK/UNIQUE/CHECK rejects bad data; cascades and
      restricts behave as documented.
- [ ] `tests/test_crud.py`: each CRUD operation from step 3.
- [ ] `tests/test_queries.py`: run complex queries on a small fixed fixture dataset and assert
      exact results.
- [ ] `tests/test_transactions.py`: rollback/atomicity; scenarios A–D give the anomaly at the
      weak level and the correct result at the fixed level.
- [ ] `tests/test_backup_restore.py` (or a script): dump → restore into a new DB → row counts
      and checksums match.
- [ ] `scripts/run_tests.ps1/.sh`: writes `results/tests/test_report.txt` (`pytest -v`, plus
      `--junitxml` if wanted). **Commit the output**, because the rubric asks for results.
- [ ] Optional: GitHub Actions workflow with a Postgres service container running the tests on
      every push (green badge in README).

## 8. Backup & recovery (required)

- [ ] `scripts/backup.ps1/.sh`: `pg_dump -Fc` with a timestamped filename into `backups/`
      (gitignored); also a schema-only dump.
- [ ] `scripts/restore.ps1/.sh`: `pg_restore` into a new DB, then verify row counts.
- [ ] Recovery drill: drop a table → restore that single table from the dump (`pg_restore -t`).
- [ ] A short strategy note (full dumps nightly; WAL archiving/PITR named as the production
      upgrade) for the README/report.

## 9. Backend (FastAPI, kept thin; serves the demo)

- [ ] `backend/db.py`: psycopg `ConnectionPool` from `.env`; **parameterized queries only**
      (mention SQL injection in the report).
- [ ] Endpoints that map to the SQL work (no new logic): search songs, user dashboard/Wrapped,
      charts, recommendations, playlist CRUD, like/unlike, log a play.
- [ ] Transactional endpoints use the same logic as step 6 (row lock or SERIALIZABLE + retry).
- [ ] "DB lab" endpoints for the demo: run a chosen query with/without an index and return the
      timing and EXPLAIN plan; trigger a concurrency scenario and return what happened.
- [ ] Proper HTTP errors (404, 409 on UNIQUE violation), plus FastAPI's auto `/docs` page.

## 10. Frontend (single page; demo engagement)

- [ ] `frontend/index.html` + plain JS `fetch` (no build step). Tabs: Search · My Library
      (playlists, likes) · Wrapped · Charts · **DB Lab**.
- [ ] DB Lab tab: before/after index timings side by side, EXPLAIN plan text, and a button that
      runs a concurrency scenario at each isolation level and shows the outcome.
      This is where demo engagement points come from.

## 11. README.md (required)

- [ ] Project overview, ER diagram, schema summary, design decisions.
- [ ] Prerequisites (Postgres 16+, Python 3.11+), setup (`.env`, setup script), running the
      backend/frontend, running tests, backup/restore.
- [ ] Repo map: what each file is and in what order it runs.
- [ ] Links to `results/` (test report, EXPLAIN summary, concurrency outputs).

## 12. Demo prep

- [ ] Demo script (minute-by-minute) and a rehearsal on the presenting laptop from a fresh clone.
- [ ] Fallback: pre-captured screenshots/outputs in `results/` if live runs misbehave.

---

### Suggested order
1 (data) → 2 → 3/4 in parallel → 5 → 6 → 7 (tests written alongside 3–6) → 8 → 9/10 → 11 → 12.
Data comes first because indexes, query results and tests all depend on its final shape.

### Suggested split (4 people)
- **Arye:** 4 (queries), 5 (indexing), 9 (backend). Matches the frontend/backend/queries request.
- **Ehsan:** 1 (data load), 2 (schema polish), 8 (backup), 0 (setup scripts).
- **Xiaohui:** 6 (transactions/concurrency), 7 (tests).
- **Andrew:** 10 (frontend), 11 (README), report + slides lead.
