# The official Playwright image ships with Chromium AND all its system-level
# dependencies (fonts, shared libs) already installed and correctly configured.
# This sidesteps the notoriously fiddly "apt-get install this specific list of
# .so files for headless Chrome" problem entirely. Version pinned to match
# the playwright pip package version in requirements.txt.
FROM mcr.microsoft.com/playwright/python:v1.47.0-jammy

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# Browsers are already present in this base image, so no
# `playwright install chromium` step is needed at build time here.

COPY . .

CMD ["python3", "worker.py"]
