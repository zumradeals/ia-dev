-- Phase 3 : billing GeniusPay — abonnements + historique paiements

-- Mise à jour des prix en XOF (GeniusPay)
UPDATE plans SET price_month = 9900  WHERE name = 'pro';
UPDATE plans SET price_month = 49000 WHERE name = 'enterprise';

-- Table abonnements actifs
CREATE TABLE IF NOT EXISTS subscriptions (
    id                SERIAL PRIMARY KEY,
    user_id           INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan              VARCHAR(20) NOT NULL,
    status            VARCHAR(20) NOT NULL DEFAULT 'active', -- active | cancelled | expired
    payment_reference VARCHAR(100),                          -- référence GeniusPay (MTX-...)
    started_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at        TIMESTAMPTZ,                           -- NULL = illimité (admin)
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user   ON subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status);

-- Table historique paiements GeniusPay
CREATE TABLE IF NOT EXISTS payment_events (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER REFERENCES users(id) ON DELETE SET NULL,
    reference   VARCHAR(100),
    event       VARCHAR(50),          -- payment.success | payment.failed | ...
    amount      INTEGER,
    currency    VARCHAR(10),
    status      VARCHAR(20),
    payload     JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_events_user      ON payment_events(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_events_reference ON payment_events(reference);
