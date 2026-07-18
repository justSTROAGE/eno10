-- Switch conversations.id from a bigserial surrogate key to a TEXT key
-- that is deterministically derived from the two participant handles
-- (see internal/chat/convoid.go). The shape stays compatible with the
-- existing UNIQUE(user_a, user_b) + CHECK(user_a < user_b) invariant;
-- the synthesized id is just a derived primary key.

ALTER TABLE messages DROP CONSTRAINT messages_conversation_id_fkey;
ALTER TABLE conversations DROP CONSTRAINT conversations_pkey;
ALTER TABLE conversations ALTER COLUMN id DROP DEFAULT;
ALTER TABLE conversations ALTER COLUMN id TYPE TEXT USING id::text;
ALTER TABLE messages ALTER COLUMN conversation_id TYPE TEXT USING conversation_id::text;
ALTER TABLE conversations ADD PRIMARY KEY (id);
ALTER TABLE messages
    ADD CONSTRAINT messages_conversation_id_fkey
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE;

DROP SEQUENCE IF EXISTS conversations_id_seq;
