-- Builds the whole database from scratch: creates the tables, then loads all the data.
-- Takes about a minute. Run it from the repo root with psql:
--
--     psql "<DATABASE_URL>" -f setup.sql
--
-- WARNING: this deletes everything that's in the database now.

\set ON_ERROR_STOP on
\encoding UTF8
SET statement_timeout = 0;   -- Supabase stops queries after 2 minutes by default
SET timezone = 'UTC';        -- so the random dates come out the same on every computer

\i tables/table_creation.sql
\i data/data_inserts.sql
\i data/load_spotify_data.sql
\i data/generate_activity.sql
