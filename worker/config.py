import os

# See api/config.py for why this resolves to an absolute, launch-dir-independent path.
_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DEFAULT_RESULTS_DIR = os.path.join(_PROJECT_ROOT, "results")

POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POSTGRES_DB = os.getenv("POSTGRES_DB", "pdfservice")
POSTGRES_USER = os.getenv("POSTGRES_USER", "pdfapp")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "pdfapp_dev_pw")

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_QUEUE_NAME = os.getenv("REDIS_QUEUE_NAME", "pdf_jobs")

# How long (seconds) BLPOP waits for a job before looping again to check for
# shutdown signals. Not a processing timeout — just a polling interval.
BLPOP_TIMEOUT = int(os.getenv("BLPOP_TIMEOUT", "5"))

RESULTS_DIR = os.getenv("RESULTS_DIR", _DEFAULT_RESULTS_DIR)

# Playwright's browser navigation timeout, in milliseconds.
RENDER_TIMEOUT_MS = int(os.getenv("RENDER_TIMEOUT_MS", "30000"))
