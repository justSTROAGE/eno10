-- Premium tier. is_premium is flipped via /api/me/redeem-premium after the
-- user presents a valid RS256 JWT minted by the payments service.
-- premium_perks holds one perk per premium user.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_premium BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS premium_perks (
    user_id    BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    perk_text  TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
