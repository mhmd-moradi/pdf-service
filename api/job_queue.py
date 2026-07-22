import redis
import json
from config import REDIS_HOST, REDIS_PORT, REDIS_QUEUE_NAME

_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def enqueue_job(job_id: str, url: str) -> None:
    """
    Push a job onto the Redis list used as our queue.
    This is what KEDA will later watch (queue length) to decide how many
    worker pods to run.
    """
    payload = json.dumps({"job_id": job_id, "url": url})
    _client.rpush(REDIS_QUEUE_NAME, payload)


def queue_depth() -> int:
    return _client.llen(REDIS_QUEUE_NAME)
