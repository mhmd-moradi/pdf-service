import uuid
import os
import time
from fastapi import FastAPI, HTTPException, Path
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, HttpUrl

import db
import job_queue
from config import RESULTS_DIR
from logging_config import setup_logging

logger = setup_logging("api")

app = FastAPI(title="URL-to-PDF Service API")

# Wide open for local dev. Tighten this before it's exposed anywhere real.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class SubmitJobRequest(BaseModel):
    url: HttpUrl


class SubmitJobResponse(BaseModel):
    job_id: str
    status: str


@app.get("/health")
def health():
    """Basic liveness/readiness check — will become the K8s probe target."""
    return {"status": "ok"}


@app.post("/jobs", response_model=SubmitJobResponse, status_code=201)
def submit_job(payload: SubmitJobRequest):
    job_id = str(uuid.uuid4())
    url_str = str(payload.url)

    start = time.time()
    db.create_job(job_id, url_str)
    job_queue.enqueue_job(job_id, url_str)
    duration_ms = round((time.time() - start) * 1000, 2)

    logger.info(
        "job submitted",
        extra={"job_id": job_id, "url": url_str, "duration_ms": duration_ms},
    )
    return SubmitJobResponse(job_id=job_id, status="pending")


def _validate_job_id(job_id: str) -> None:
    """job_id is stored as a Postgres UUID column; a malformed value would
    otherwise crash with a raw DB error instead of a clean 404."""
    try:
        uuid.UUID(job_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="job not found")


@app.get("/jobs")
def get_jobs():
    """List past jobs, most recent first."""
    return db.list_jobs()


@app.get("/jobs/{job_id}")
def get_job_status(job_id: str):
    _validate_job_id(job_id)
    job = db.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    return job


@app.get("/jobs/{job_id}/result")
def get_job_result(job_id: str):
    _validate_job_id(job_id)
    job = db.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    if job["status"] != "completed":
        raise HTTPException(
            status_code=409,
            detail=f"job is not completed yet (status: {job['status']})",
        )
    result_path = job["result_path"]
    if not result_path or not os.path.exists(result_path):
        raise HTTPException(status_code=500, detail="result file missing on disk")

    return FileResponse(
        result_path, media_type="application/pdf", filename=f"{job_id}.pdf"
    )
