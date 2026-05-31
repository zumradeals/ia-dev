-- Migration 006 : template de workspace
ALTER TABLE workspaces ADD COLUMN IF NOT EXISTS template VARCHAR(30) DEFAULT 'blank';
