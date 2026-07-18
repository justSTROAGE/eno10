CREATE TABLE IF NOT EXISTS server_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
    username TEXT PRIMARY KEY,
    user_password TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    encryption_key TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS follows (
    followee TEXT NOT NULL,
    follower TEXT NOT NULL,
    PRIMARY KEY (followee, follower),
    FOREIGN KEY (followee) REFERENCES users (username) ON DELETE CASCADE,
    FOREIGN KEY (follower) REFERENCES users (username) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS files (
    id BIGINT PRIMARY KEY,
    name TEXT NOT NULL,
    owner TEXT NOT NULL,
    visibility INTEGER NOT NULL,
    size BIGINT NOT NULL,
    content BYTEA NOT NULL,
    created_at BIGINT NOT NULL,
    protection_key TEXT NOT NULL,
    is_protected BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (owner) REFERENCES users (username) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS gdpr_data (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    timestamp BIGINT NOT NULL,
    nonce TEXT NOT NULL,
    content TEXT NOT NULL,
    FOREIGN KEY (username) REFERENCES users (username) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS auth_token (
    token TEXT PRIMARY KEY,
    username TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    FOREIGN KEY (username) REFERENCES users (username) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows (follower, followee);
CREATE INDEX IF NOT EXISTS idx_files_owner ON files (owner, visibility);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users (created_at);
CREATE INDEX IF NOT EXISTS idx_gdpr_username_nonce ON gdpr_data (username, nonce);
