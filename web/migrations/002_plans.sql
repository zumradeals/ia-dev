-- Phase 1 : plans utilisateurs + billing (bases)
ALTER TABLE users ADD COLUMN IF NOT EXISTS plan VARCHAR(20) DEFAULT 'free';

CREATE TABLE IF NOT EXISTS plans (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(20) UNIQUE NOT NULL,
    label       TEXT NOT NULL,
    price_month INTEGER DEFAULT 0,
    max_repos   INTEGER DEFAULT 10,
    cpu_limit   REAL DEFAULT 1.0,
    ram_limit   INTEGER DEFAULT 512,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO plans (name, label, price_month, max_repos, cpu_limit, ram_limit) VALUES
    ('free',       'Gratuit',    0,    5,  0.5, 256),
    ('pro',        'Pro',        1999, 50, 2.0, 1024),
    ('enterprise', 'Entreprise', 9999, -1, 4.0, 4096)
ON CONFLICT (name) DO NOTHING;
