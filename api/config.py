"""
All config comes from environment variables — no hardcoded connection
details. This is what makes the later swap from in-cluster Postgres to
RDS (Phase 7) a config change instead of a code change.
"""
import os

POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POSTGRES_DB = os.getenv("POSTGRES_DB", "pdfservice")
POSTGRES_USER = os.getenv("POSTGRES_USER", "pdfapp")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "pdfapp_dev_pw")

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_QUEUE_NAME = os.getenv("REDIS_QUEUE_NAME", "pdf_jobs")

# Where result files live. Locally: a folder on disk. Later (Phase 9): an S3 key prefix.
_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS_DIR = os.getenv("RESULTS_DIR", os.path.join(_PROJECT_ROOT, "results"))