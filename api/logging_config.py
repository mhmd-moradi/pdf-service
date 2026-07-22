"""
Structured (JSON) logging setup.

Why JSON logs from day one: once this runs in Kubernetes, CloudWatch/Fluent
Bit/OTel collectors all parse JSON logs far more easily than free-text lines.
Setting this up now means Phase 10 (observability) is just "point a collector
at stdout" instead of a logging rewrite.
"""
import logging
import json
import sys
from datetime import datetime, timezone


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        # Allow callers to attach extra structured fields, e.g.
        # logger.info("job created", extra={"job_id": "...", "url": "..."})
        for key, value in record.__dict__.items():
            if key in ("job_id", "url", "status", "duration_ms", "error"):
                payload[key] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def setup_logging(service_name: str) -> logging.Logger:
    logger = logging.getLogger(service_name)
    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    logger.handlers = [handler]
    logger.propagate = False
    return logger
