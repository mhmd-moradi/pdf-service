# The official Playwright image ships with Chromium AND all its system-level
# dependencies (fonts, shared libs) already installed and correctly configured.
# This sidesteps the notoriously fiddly "apt-get install this specific list of
# .so files for headless Chrome" problem entirely. Version pinned to match
# the playwright pip package version in requirements.txt.
FROM mcr.microsoft.com/playwright/python:v1.47.0-jammy  # Microsoft's image built on Ubuntu 22.04 ("jammy"); already contains Chromium binary + every shared library it needs (libglib, libnss, libatk, etc.) — without this base image you'd need ~20 apt-get packages

WORKDIR /app                                 # same pattern as api/Dockerfile — all paths below are relative to /app

COPY requirements.txt .                      # copy requirements first to get a cacheable pip layer
RUN pip install --no-cache-dir -r requirements.txt  # installs the playwright Python package (the thin wrapper); the actual browser binary is already in the base image
# Browsers are already present in this base image, so no
# `playwright install chromium` step is needed at build time here.
# (Locally you ran `playwright install chromium` manually; in this image Microsoft pre-baked it in.)

COPY . .                                     # copy worker.py, config.py, db.py, logging_config.py into /app

CMD ["python3", "worker.py"]                 # exec form again — PID 1 is python3 directly, so SIGTERM reaches the signal handler defined in worker.py's _handle_shutdown() function
