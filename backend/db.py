"""Database access: one shared connection pool and a helper for running SQL."""
import os

from dotenv import load_dotenv
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

load_dotenv()

pool = ConnectionPool(
    os.environ["DATABASE_URL"],
    min_size=1,
    max_size=5,
    kwargs={"row_factory": dict_row},   # rows come back as dicts: {"song_title": ...}
    open=False,                         # opened when the app starts (see main.py)
)


def run(conn, sql, params=None):
    """Run one SQL statement and return its rows (an empty list if it returns none).

    Always pass values through `params` (written as %(name)s in the SQL), never by
    building the SQL string yourself. psycopg sends them separately from the SQL,
    which is what prevents SQL injection.
    """
    cur = conn.execute(sql, params)
    return cur.fetchall() if cur.description else []
