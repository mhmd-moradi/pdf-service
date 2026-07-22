import psycopg2
from contextlib import contextmanager
from config import (
    POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD,
)


@contextmanager
def get_conn():
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


def mark_processing(job_id: str) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE jobs SET status = 'processing' WHERE id = %s", (job_id,)
            )
        conn.commit()


def mark_completed(job_id: str, result_path: str) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """UPDATE jobs
                   SET status = 'completed', result_path = %s, completed_at = now()
                   WHERE id = %s""",
                (result_path, job_id),
            )
        conn.commit()


def mark_failed(job_id: str, error_message: str) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """UPDATE jobs
                   SET status = 'failed', error_message = %s, completed_at = now()
                   WHERE id = %s""",
                (error_message[:1000], job_id),
            )
        conn.commit()
