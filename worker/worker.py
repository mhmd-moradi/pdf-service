import json
import os
import time
import signal
import sys

import redis
from playwright.sync_api import sync_playwright

import db
from config import (
    REDIS_HOST, REDIS_PORT, REDIS_QUEUE_NAME, BLPOP_TIMEOUT,
    RESULTS_DIR, RENDER_TIMEOUT_MS,
)
from logging_config import setup_logging

logger = setup_logging("worker")

_shutdown = False


def _handle_shutdown(signum, frame):
    global _shutdown
    logger.info("shutdown signal received, finishing current job then exiting")
    _shutdown = True


signal.signal(signal.SIGTERM, _handle_shutdown)
signal.signal(signal.SIGINT, _handle_shutdown)


def render_url_to_pdf(page, url: str, output_path: str) -> None:
    page.goto(url, timeout=RENDER_TIMEOUT_MS, wait_until="networkidle")
    page.pdf(path=output_path, format="A4", print_background=True)


def process_job(browser, job_id: str, url: str) -> None:
    start = time.time()
    logger.info("job picked up", extra={"job_id": job_id, "url": url})
    db.mark_processing(job_id)

    os.makedirs(RESULTS_DIR, exist_ok=True)
    output_path = os.path.join(RESULTS_DIR, f"{job_id}.pdf")

    page = browser.new_page()
    try:
        render_url_to_pdf(page, url, output_path)
        db.mark_completed(job_id, output_path)
        duration_ms = round((time.time() - start) * 1000, 2)
        logger.info(
            "job completed",
            extra={"job_id": job_id, "url": url, "duration_ms": duration_ms},
        )
    except Exception as e:
        db.mark_failed(job_id, str(e))
        logger.info(
            "job failed",
            extra={"job_id": job_id, "url": url, "error": str(e)},
        )
    finally:
        page.close()


def main():
    logger.info("worker starting up")
    redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        logger.info("browser launched, waiting for jobs")

        while not _shutdown:
            # BLPOP blocks up to BLPOP_TIMEOUT seconds waiting for a job.
            # The timeout just lets us periodically check the shutdown flag.
            result = redis_client.blpop(REDIS_QUEUE_NAME, timeout=BLPOP_TIMEOUT)
            if result is None:
                continue

            _, raw_payload = result
            try:
                payload = json.loads(raw_payload)
                job_id = payload["job_id"]
                url = payload["url"]
            except (json.JSONDecodeError, KeyError) as e:
                logger.info("malformed queue message, skipping", extra={"error": str(e)})
                continue

            process_job(browser, job_id, url)

        browser.close()
    logger.info("worker shut down cleanly")


if __name__ == "__main__":
    main()
