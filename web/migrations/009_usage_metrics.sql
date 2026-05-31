-- Migration 009 : métriques d'usage workspace
ALTER TABLE workspaces
    ADD COLUMN IF NOT EXISTS session_started_at   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS usage_seconds_month  BIGINT  DEFAULT 0,
    ADD COLUMN IF NOT EXISTS usage_month          CHAR(7) DEFAULT '';

-- Initialiser session_started_at pour les workspaces déjà en cours
UPDATE workspaces SET session_started_at = NOW() WHERE status = 'running';
