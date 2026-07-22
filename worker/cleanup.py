"""
Run on a schedule by a Kubernetes CronJob (see helm/worker/templates/cronjob.yaml).
Deletes result PDFs older than RETENTION_DAYS and removes their job rows.

Uses the same Docker image as the worker Deployment -- the CronJob just
overrides the container's command to run this script instead of worker.py.
"""
import os
import psycopg2
from datetime import datetime, timezone

from config import (
    POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD,
)
from logging_config import setup_logging

logger = setup_logging("cleanup")

RETENTION_DAYS = int(os.getenv("RETENTION_DAYS", "7"))


def main():
    logger.info("cleanup job starting", extra={"retention_days": RETENTION_DAYS})

    conn = psycopg2.connect(
        host=POSTGRES_HOST, port=POSTGRES_PORT, dbname=POSTGRES_DB,
        user=POSTGRES_USER, password=POSTGRES_PASSWORD,
    )
    cur = conn.cursor()

    cur.execute(
        """SELECT id, result_path FROM jobs
           WHERE created_at < now() - (%s || ' days')::interval
           AND status IN ('completed', 'failed')""",
        (RETENTION_DAYS,),
    )
    rows = cur.fetchall()

    deleted_files = 0
    deleted_rows = 0

    for job_id, result_path in rows:
        if result_path and os.path.exists(result_path):
            try:
                os.remove(result_path)
                deleted_files += 1
            except OSError as e:
                logger.info(
                    "failed to delete file",
                    extra={"job_id": str(job_id), "error": str(e)},
                )

        cur.execute("DELETE FROM jobs WHERE id = %s", (job_id,))
        deleted_rows += 1

    conn.commit()
    cur.close()
    conn.close()

    logger.info(
        "cleanup job finished",
        extra={"deleted_files": deleted_files, "deleted_rows": deleted_rows},
    )


if __name__ == "__main__":
    main()
