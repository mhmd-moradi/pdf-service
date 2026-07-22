-- gen_random_uuid() is built into Postgres 13+; this extension keeps it working on older versions too
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Jobs table: one row per submitted URL-to-PDF request
CREATE TABLE IF NOT EXISTS jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    url TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',  -- pending | processing | completed | failed
    result_path TEXT,                         -- filesystem path (later: S3 key) of the generated PDF
    error_message TEXT,                       -- populated if status = 'failed'
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- Speeds up "list past jobs, most recent first"
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs (created_at DESC);

-- If this schema is applied by a superuser (e.g. via `psql -U postgres`)
-- rather than by the app's own DB user, the app user won't have privileges
-- on the table by default. Grant explicitly so this doesn't bite you later.
-- Replace 'pdfapp' if you used a different app DB username.
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO pdfapp;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO pdfapp;

