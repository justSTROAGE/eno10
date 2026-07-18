CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE users (
id UUID PRIMARY KEY DEFAULT uuidv7(),
username CITEXT NOT NULL UNIQUE,
first_name TEXT NOT NULL,
last_name TEXT,
bio TEXT,
available_for_hire BOOLEAN NOT NULL DEFAULT false,
premium BOOLEAN NOT NULL DEFAULT false,
password TEXT NOT NULL,
created_at TIMESTAMP NOT NULL DEFAULT now(),
updated_at TIMESTAMP NOT NULL DEFAULT now(),
storage_quota BIGINT NOT NULL DEFAULT 2048000, --2MB
storage_quota_used BIGINT NOT NULL DEFAULT 0,
CONSTRAINT storage_quota_not_exceeded CHECK (storage_quota_used <= storage_quota)
);
CREATE INDEX users_created_at_idx ON users (created_at);


CREATE TYPE photo_privacy AS ENUM ('private', 'premium', 'public');
CREATE TYPE mimetype AS ENUM ('png', 'jpg', 'webp', 'other');

CREATE TABLE photos (
id UUID PRIMARY KEY DEFAULT uuidv7(),
public_id VARCHAR(12) NOT NULL UNIQUE,
asset_id UUID NOT NULL UNIQUE DEFAULT uuidv7(),
description TEXT,
creator UUID NOT NULL,
	FOREIGN KEY (creator) REFERENCES users(id) ON DELETE CASCADE,
file_size INT NOT NULL,
CONSTRAINT max_file_size CHECK (file_size < 1024000), --1MB
privacy photo_privacy NOT NULL DEFAULT 'public',
show_on_profile BOOLEAN NOT NULL DEFAULT true,
mimetype mimetype NOT NULL DEFAULT 'other',
location TEXT,
camera TEXT,
likes_count INT NOT NULL DEFAULT 0,
views BIGINT NOT NULL DEFAULT 0,
downloads BIGINT NOT NULL DEFAULT 0,
created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX photos_created_at_idx ON photos (created_at);


CREATE TABLE tags (
tag CITEXT PRIMARY KEY
);


CREATE TABLE photos_tags (
tag CITEXT NOT NULL,
    	 FOREIGN KEY (tag) REFERENCES tags(tag),
photo_id UUID NOT NULL,
	 FOREIGN KEY (photo_id) REFERENCES photos(id) ON DELETE CASCADE,
PRIMARY KEY (tag, photo_id)
);


CREATE TABLE collections (
id UUID PRIMARY KEY DEFAULT uuidv7(),
public_id VARCHAR(12) NOT NULL UNIQUE,
name TEXT NOT NULL,
description TEXT,
creator UUID NOT NULL,
	FOREIGN KEY (creator) REFERENCES users(id) ON DELETE CASCADE,
private BOOLEAN NOT NULL DEFAULT false
);

create table collections_photos (
photo_id UUID NOT NULL,
	 FOREIGN KEY (photo_id) REFERENCES photos(id) ON DELETE CASCADE,
collection_id UUID NOT NULL,
	 FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE,
PRIMARY KEY (photo_id, collection_id)
);

CREATE TABLE likes (
user_id UUID NOT NULL,
	FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
photo_id UUID NOT NULL,
	FOREIGN KEY (photo_id) REFERENCES photos(id) ON DELETE CASCADE,
PRIMARY KEY (user_id, photo_id)
);
