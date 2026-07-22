FROM python:3.11-slim

WORKDIR /app

# Install deps first so Docker can cache this layer separately from app code —
# code changes won't force a full dependency reinstall on every rebuild.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# --host 0.0.0.0 is required in containers: binding to 127.0.0.1 would make
# the server unreachable from outside the container.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
