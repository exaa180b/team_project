"""EXAAtunes API, plus the static frontend.

Run from the repo root:
    uvicorn backend.main:app --reload
then open http://localhost:8000

Every endpoint returns {"data": ..., "queries": [...]}. "queries" lists the SQL the
request ran, for the SQL panel at the bottom of each page.

Each request uses one connection from the pool inside `with db.pool.connection()`.
That block is a single transaction: it commits at the end, or rolls back if anything
raises (including the HTTPExceptions below), so a request never half-applies.
"""
import time
from contextlib import asynccontextmanager
from typing import Annotated
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException
from fastapi.staticfiles import StaticFiles
from psycopg import errors
from psycopg.rows import tuple_row
from pydantic import BaseModel, Field

from backend import db

FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"


@asynccontextmanager
async def lifespan(app):
    db.pool.open()
    yield
    db.pool.close()


app = FastAPI(title="EXAAtunes", lifespan=lifespan)


# There's no login: the frontend sends the chosen demo user in an X-User-Id header.
UserId = Annotated[int, Header(alias="X-User-Id")]


class PlaylistIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=300)


# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------

@app.get("/api/users")
def list_demo_users():
    log = []
    with db.pool.connection() as conn:
        # Users 1-4 are the hand-made demo accounts from data/data_inserts.sql.
        users = db.run(conn, log, """
            SELECT user_id, username
            FROM app_user
            WHERE user_id <= 4
            ORDER BY user_id
        """)
    return {"data": users, "queries": log}


# ---------------------------------------------------------------------------
# Home
# ---------------------------------------------------------------------------

@app.get("/api/home")
def home(user_id: UserId = 1):
    log = []
    params = {"user_id": user_id}
    with db.pool.connection() as conn:
        recent = db.run(conn, log, """
            SELECT h.played_at, d.song_id, d.song_title, d.artists, d.album_title
            FROM listening_history h
            JOIN song_details d ON d.song_id = h.song_id
            WHERE h.user_id = %(user_id)s
            ORDER BY h.played_at DESC
            LIMIT 10
        """, params)

        # "Last 30 days" ends at the user's latest play (the generated data stops
        # at 2026-10-01, so counting back from today would find nothing).
        stats = db.run(conn, log, """
            SELECT count(*) AS plays,
                   coalesce(sum(s.duration_ms), 0) / 60000 AS minutes
            FROM listening_history h
            JOIN song s ON s.song_id = h.song_id
            WHERE h.user_id = %(user_id)s
              AND h.played_at > (SELECT max(played_at) FROM listening_history
                                 WHERE user_id = %(user_id)s) - interval '30 days'
        """, params)[0]

        top_artists = db.run(conn, log, """
            SELECT a.artist_id, a.artist_name, count(*) AS plays
            FROM listening_history h
            JOIN song_artist sa ON sa.song_id = h.song_id
            JOIN artist a       ON a.artist_id = sa.artist_id
            WHERE h.user_id = %(user_id)s
              AND h.played_at > (SELECT max(played_at) FROM listening_history
                                 WHERE user_id = %(user_id)s) - interval '30 days'
            GROUP BY a.artist_id, a.artist_name
            ORDER BY plays DESC, a.artist_name
            LIMIT 8
        """, params)

        # Playlists the user owns or collaborates on, newest first.
        playlists = db.run(conn, log, """
            SELECT p.playlist_id,
                   p.playlist_name,
                   u.username AS owner,
                   p.user_id = %(user_id)s AS is_owner,
                   (SELECT count(*) FROM playlist_song ps
                    WHERE ps.playlist_id = p.playlist_id) AS song_count
            FROM playlist p
            JOIN app_user u ON u.user_id = p.user_id
            WHERE p.user_id = %(user_id)s
               OR EXISTS (SELECT 1 FROM playlist_collaborator pc
                          WHERE pc.playlist_id = p.playlist_id AND pc.user_id = %(user_id)s)
            ORDER BY p.created_at DESC
        """, params)

    data = {"recent": recent, "stats": stats, "top_artists": top_artists, "playlists": playlists}
    return {"data": data, "queries": log}


# ---------------------------------------------------------------------------
# Playlists
# ---------------------------------------------------------------------------

def get_access(conn, log, playlist_id, user_id):
    """Return (is_owner, is_collaborator) for a playlist, or raise 404."""
    rows = db.run(conn, log, """
        SELECT p.user_id = %(user_id)s AS is_owner,
               EXISTS (SELECT 1 FROM playlist_collaborator pc
                       WHERE pc.playlist_id = p.playlist_id
                         AND pc.user_id = %(user_id)s) AS is_collaborator
        FROM playlist p
        WHERE p.playlist_id = %(playlist_id)s
    """, {"playlist_id": playlist_id, "user_id": user_id})
    if not rows:
        raise HTTPException(404, "Playlist not found")
    return rows[0]["is_owner"], rows[0]["is_collaborator"]


def require_editor(conn, log, playlist_id, user_id):
    is_owner, is_collaborator = get_access(conn, log, playlist_id, user_id)
    if not (is_owner or is_collaborator):
        raise HTTPException(403, "Only the owner or a collaborator can change this playlist")


def require_owner(conn, log, playlist_id, user_id):
    is_owner, _ = get_access(conn, log, playlist_id, user_id)
    if not is_owner:
        raise HTTPException(403, "Only the owner can do that")


@app.get("/api/playlists/{playlist_id}")
def get_playlist(playlist_id: int, user_id: UserId = 1):
    log = []
    params = {"playlist_id": playlist_id, "user_id": user_id}
    with db.pool.connection() as conn:
        rows = db.run(conn, log, """
            SELECT p.playlist_id, p.playlist_name, p.description, p.created_at,
                   p.user_id AS owner_id, u.username AS owner
            FROM playlist p
            JOIN app_user u ON u.user_id = p.user_id
            WHERE p.playlist_id = %(playlist_id)s
        """, params)
        if not rows:
            raise HTTPException(404, "Playlist not found")
        playlist = rows[0]

        collaborators = db.run(conn, log, """
            SELECT u.user_id, u.username
            FROM playlist_collaborator pc
            JOIN app_user u ON u.user_id = pc.user_id
            WHERE pc.playlist_id = %(playlist_id)s
            ORDER BY pc.added_at
        """, params)

        songs = db.run(conn, log, """
            SELECT d.song_id, d.song_title, d.artists, d.album_title,
                   d.duration_ms, ps.added_at,
                   EXISTS (SELECT 1 FROM liked_song l
                           WHERE l.user_id = %(user_id)s AND l.song_id = d.song_id) AS liked
            FROM playlist_song ps
            JOIN song_details d ON d.song_id = ps.song_id
            WHERE ps.playlist_id = %(playlist_id)s
            ORDER BY ps.added_at, d.song_title
        """, params)

    is_owner = playlist["owner_id"] == user_id
    is_collaborator = any(c["user_id"] == user_id for c in collaborators)
    playlist.update(
        collaborators=collaborators,
        songs=songs,
        total_ms=sum(s["duration_ms"] for s in songs),
        is_owner=is_owner,
        can_edit=is_owner or is_collaborator,
    )
    return {"data": playlist, "queries": log}


@app.post("/api/playlists", status_code=201)
def create_playlist(body: PlaylistIn, user_id: UserId = 1):
    name = body.name.strip()
    if not name:
        raise HTTPException(400, "Playlist name can't be empty")
    log = []
    with db.pool.connection() as conn:
        rows = db.run(conn, log, """
            INSERT INTO playlist (user_id, playlist_name, description)
            VALUES (%(user_id)s, %(name)s, %(description)s)
            RETURNING playlist_id
        """, {"user_id": user_id, "name": name, "description": body.description or None})
    return {"data": rows[0], "queries": log}


@app.patch("/api/playlists/{playlist_id}")
def update_playlist(playlist_id: int, body: PlaylistIn, user_id: UserId = 1):
    name = body.name.strip()
    if not name:
        raise HTTPException(400, "Playlist name can't be empty")
    log = []
    with db.pool.connection() as conn:
        require_owner(conn, log, playlist_id, user_id)
        db.run(conn, log, """
            UPDATE playlist
            SET playlist_name = %(name)s,
                description = %(description)s
            WHERE playlist_id = %(playlist_id)s
        """, {"playlist_id": playlist_id, "name": name, "description": body.description or None})
    return {"data": {"playlist_id": playlist_id}, "queries": log}


@app.delete("/api/playlists/{playlist_id}")
def delete_playlist(playlist_id: int, user_id: UserId = 1):
    log = []
    with db.pool.connection() as conn:
        require_owner(conn, log, playlist_id, user_id)
        # playlist_song and playlist_collaborator rows go too (ON DELETE CASCADE).
        db.run(conn, log, "DELETE FROM playlist WHERE playlist_id = %(playlist_id)s",
               {"playlist_id": playlist_id})
    return {"data": {"playlist_id": playlist_id}, "queries": log}


@app.delete("/api/playlists/{playlist_id}/songs/{song_id}")
def remove_song_from_playlist(playlist_id: int, song_id: int, user_id: UserId = 1):
    log = []
    with db.pool.connection() as conn:
        require_editor(conn, log, playlist_id, user_id)
        rows = db.run(conn, log, """
            DELETE FROM playlist_song
            WHERE playlist_id = %(playlist_id)s AND song_id = %(song_id)s
            RETURNING song_id
        """, {"playlist_id": playlist_id, "song_id": song_id})
        if not rows:
            raise HTTPException(404, "That song isn't in this playlist")
    return {"data": {"playlist_id": playlist_id, "song_id": song_id}, "queries": log}


# ---------------------------------------------------------------------------
# Likes
# ---------------------------------------------------------------------------

@app.post("/api/songs/{song_id}/like")
def like_song(song_id: int, user_id: UserId = 1):
    log = []
    with db.pool.connection() as conn:
        try:
            db.run(conn, log, """
                INSERT INTO liked_song (user_id, song_id)
                VALUES (%(user_id)s, %(song_id)s)
                ON CONFLICT DO NOTHING
            """, {"user_id": user_id, "song_id": song_id})
        except errors.ForeignKeyViolation:
            raise HTTPException(404, "Song not found")
    return {"data": {"song_id": song_id, "liked": True}, "queries": log}


@app.delete("/api/songs/{song_id}/like")
def unlike_song(song_id: int, user_id: UserId = 1):
    log = []
    with db.pool.connection() as conn:
        db.run(conn, log, """
            DELETE FROM liked_song
            WHERE user_id = %(user_id)s AND song_id = %(song_id)s
        """, {"user_id": user_id, "song_id": song_id})
    return {"data": {"song_id": song_id, "liked": False}, "queries": log}


# ---------------------------------------------------------------------------
# SQL console (for demos)
# ---------------------------------------------------------------------------

class QueryIn(BaseModel):
    sql: str = Field(min_length=1)
    allow_changes: bool = False


@app.post("/api/sql")
def run_sql(body: QueryIn):
    """Run whatever SQL is typed on the SQL console page and return every result.

    Read-only unless "Allow changes" is ticked, so a demo can't break the data by
    accident. Several statements separated by ; are fine. Each result shows at most
    500 rows, and anything slower than 30 seconds is cancelled.
    """
    results = []
    with db.pool.connection() as conn:
        if not body.allow_changes:
            conn.execute("SET TRANSACTION READ ONLY")
        conn.execute("SET LOCAL statement_timeout = '30s'")
        cur = conn.cursor(row_factory=tuple_row)   # tuples, so repeated column names are kept
        start = time.perf_counter()
        try:
            cur.execute(body.sql)
            ms = round((time.perf_counter() - start) * 1000, 1)
            while True:
                result = {"status": cur.statusmessage, "columns": None, "rows": [], "truncated": False}
                if cur.description:
                    rows = cur.fetchmany(501)
                    result["columns"] = [col.name for col in cur.description]
                    result["rows"] = rows[:500]
                    result["truncated"] = len(rows) > 500
                results.append(result)
                if not cur.nextset():
                    break
        except errors.Error as e:
            raise HTTPException(400, str(e).strip())
    return {"data": {"results": results, "ms": ms}, "queries": []}


# The frontend (plain HTML/CSS/JS) is served from the same server, so there's
# only one thing to start. Mounted last so it doesn't shadow the /api routes.
app.mount("/", StaticFiles(directory=FRONTEND_DIR, html=True), name="frontend")
