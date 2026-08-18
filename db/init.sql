-- Data tier: schema initialised once when the container first starts.
-- Postgres runs every *.sql file in /docker-entrypoint-initdb.d/ on first boot.

CREATE TABLE IF NOT EXISTS users (
    id    SERIAL PRIMARY KEY,
    name  TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE
);

-- Seed one row so the frontend has something to show immediately.
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com') ON CONFLICT DO NOTHING;
