import psycopg2
import psycopg2.extras
from contextlib import contextmanager
from config import (
    POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD,
)


@contextmanager
def get_conn():
    """
    Opens a fresh connection per call. Fine for this project's scale.
    A real high-throughput service would use a connection pool
    (e.g. psycopg2.pool or SQLAlchemy) instead.
    """
    conn = psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        dbname=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
    )
    try:
        yield conn
    finally:
        conn.close()


def create_job(job_id: str, url: str) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO jobs (id, url, status) VALUES (%s, %s, 'pending')",
                (job_id, url),
            )
        conn.commit()


def get_job(job_id: str) -> dict | None:
    with get_conn() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT * FROM jobs WHERE id = %s", (job_id,))
            row = cur.fetchone()
            return dict(row) if row else None


def list_jobs(limit: int = 50) -> list[dict]:
    with get_conn() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                "SELECT * FROM jobs ORDER BY created_at DESC LIMIT %s", (limit,)
            )
            return [dict(row) for row in cur.fetchall()]
