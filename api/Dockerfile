FROM python:3.11-slim                        # base image: official Python 3.11, "slim" variant strips dev tools/docs to keep the image small (~50 MB vs ~300 MB for the full image)

WORKDIR /app                                 # all subsequent COPY/RUN/CMD instructions run relative to /app inside the container; creates the dir if it doesn't exist

# Install deps first so Docker can cache this layer separately from app code —
# code changes won't force a full dependency reinstall on every rebuild.
COPY requirements.txt .                      # copy ONLY the requirements file first — Docker compares file contents to decide whether to reuse a cached layer; if requirements.txt hasn't changed, the next RUN is skipped entirely
RUN pip install --no-cache-dir -r requirements.txt  # --no-cache-dir: don't write pip's download cache to disk; keeps the layer smaller since we don't need to re-download packages after install

COPY . .                                     # copy the rest of the source (main.py, db.py, config.py, etc.) into /app; this is a separate layer so changing code doesn't invalidate the pip layer above

EXPOSE 8000                                  # documents that the container listens on 8000; doesn't actually open a port — that's done at runtime with -p or in Compose's `ports:` block

# --host 0.0.0.0 is required in containers: binding to 127.0.0.1 would make
# the server unreachable from outside the container.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]  # exec form (JSON array): runs uvicorn directly as PID 1, not wrapped in a shell — this is important so SIGTERM from Kubernetes/Docker reaches uvicorn directly, not a shell that ignores it
