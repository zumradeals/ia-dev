-- Migration 004 : last_activity workspaces + claude_model utilisateur

ALTER TABLE workspaces ADD COLUMN IF NOT EXISTS last_activity TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE users      ADD COLUMN IF NOT EXISTS claude_model  VARCHAR(50);
