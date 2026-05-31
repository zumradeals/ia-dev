-- Migration 007 : preview token par workspace
ALTER TABLE workspaces ADD COLUMN IF NOT EXISTS preview_token VARCHAR(48);

-- Générer des tokens pour les workspaces existants
UPDATE workspaces SET preview_token = encode(gen_random_bytes(24), 'hex') WHERE preview_token IS NULL;
