-- Migration 005 : vérification email + reset mot de passe

ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_token    VARCHAR(64);
ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_token    VARCHAR(64);
ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_expires  TIMESTAMPTZ;

-- Les comptes créés avant cette migration (admin, OAuth) sont pré-vérifiés
UPDATE users SET email_verified = true WHERE is_admin = true OR password_hash = '';
