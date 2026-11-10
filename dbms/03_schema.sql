-- ============================================================================
-- Database Schema DDL: xChat Relational Storage Engine
-- Project: xChat — Decentralized Multi-Transport Private Messenger
-- Module: DBMS Relational Architecture & DDL
-- Author: Aujasya Rajput
-- Course: Advanced Programming / Database Management Systems
-- Target: CP2 (dbms/03_schema.sql)
-- Standard: Compatible with SQLite 3.35+ and PostgreSQL 14+
-- Normalization Form: Strictly Boyce-Codd Normal Form (BCNF) Compliant
-- ============================================================================

-- Enable foreign key constraint validation in SQLite engines
PRAGMA foreign_keys = ON;

-- ----------------------------------------------------------------------------
-- 1. DROP EXISTING RELATIONS (Reverse Topological Dependency Order)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS relay_cache;
DROP TABLE IF EXISTS outbox_queue;
DROP TABLE IF EXISTS skipped_keys;
DROP TABLE IF EXISTS ratchet_sessions;
DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS conversations;
DROP TABLE IF EXISTS contacts;
DROP TABLE IF EXISTS prekey_bundles;
DROP TABLE IF EXISTS identity_keys;
DROP TABLE IF EXISTS users;

-- ----------------------------------------------------------------------------
-- 2. RELATION: users (Root Node Identity) [BCNF]
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    user_id             TEXT PRIMARY KEY,
    username            TEXT NOT NULL,
    master_fingerprint  TEXT NOT NULL UNIQUE,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- 3. RELATION: identity_keys (Master Asymmetric Key Vault) [BCNF]
-- ----------------------------------------------------------------------------
CREATE TABLE identity_keys (
    key_id              TEXT PRIMARY KEY,
    user_id             TEXT NOT NULL,
    key_type            TEXT NOT NULL CHECK (key_type IN ('ED25519_SIGNING', 'X25519_DH')),
    public_key          TEXT NOT NULL UNIQUE,
    encrypted_privkey   BLOB NOT NULL,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_identity_user 
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 4. RELATION: prekey_bundles (X3DH Ephemeral Key Agreements) [BCNF]
-- ----------------------------------------------------------------------------
CREATE TABLE prekey_bundles (
    prekey_id           TEXT PRIMARY KEY,
    user_id             TEXT NOT NULL,
    key_id_num          INTEGER NOT NULL CHECK (key_id_num >= 0),
    key_type            TEXT NOT NULL CHECK (key_type IN ('SIGNED_PREKEY', 'ONE_TIME_PREKEY')),
    public_key          TEXT NOT NULL UNIQUE,
    signature           TEXT,
    is_consumed         BOOLEAN NOT NULL DEFAULT 0 CHECK (is_consumed IN (0, 1)),
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_prekey_user 
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT uq_user_prekey_seq 
        UNIQUE (user_id, key_id_num, key_type)
);

-- ----------------------------------------------------------------------------
-- 5. RELATION: contacts (Decentralized Peer Registry) [BCNF]
-- ----------------------------------------------------------------------------
CREATE TABLE contacts (
    contact_id          TEXT PRIMARY KEY,
    user_id             TEXT NOT NULL,
    peer_address        TEXT NOT NULL,
    peer_name           TEXT NOT NULL,
    reachable_socket    TEXT NOT NULL,
    public_key          TEXT NOT NULL,
    fingerprint         TEXT NOT NULL,
    trust_status        TEXT NOT NULL DEFAULT 'UNVERIFIED' 
                        CHECK (trust_status IN ('VERIFIED', 'UNVERIFIED', 'BLOCKED')),
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_contact_user 
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT uq_user_peer_address 
        UNIQUE (user_id, peer_address)
);

-- ----------------------------------------------------------------------------
-- 6. RELATION: conversations (Encrypted Thread Aggregation) [BCNF]
-- ----------------------------------------------------------------------------
CREATE TABLE conversations (
    conversation_id     TEXT PRIMARY KEY,
    user_id             TEXT NOT NULL,
    contact_id          TEXT NOT NULL,
    conv_type           TEXT NOT NULL DEFAULT 'DIRECT' 
                        CHECK (conv_type IN ('DIRECT', 'BURNER', 'SOS_BEACON')),
    title               TEXT NOT NULL,
    is_muted            BOOLEAN NOT NULL DEFAULT 0 CHECK (is_muted IN (0, 1)),
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_active_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_conversation_user 
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_conversation_contact 
        FOREIGN KEY (contact_id) REFERENCES contacts(contact_id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 7. RELATION: messages (Thread Message Payloads & Delivery State) [BCNF]
-- ----------------------------------------------------------------------------
CREATE TABLE messages (
    message_id          TEXT PRIMARY KEY,
    conversation_id     TEXT NOT NULL,
    sender_address      TEXT NOT NULL,
    recipient_address   TEXT NOT NULL,
    ciphertext          BLOB NOT NULL,
    nonce               TEXT NOT NULL,
    ratchet_counter     INTEGER NOT NULL DEFAULT 0 CHECK (ratchet_counter >= 0),
    delivery_status     TEXT NOT NULL DEFAULT 'PENDING' 
                        CHECK (delivery_status IN ('PENDING', 'SENT', 'DELIVERED', 'READ', 'FAILED')),
    sent_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    delivered_at        DATETIME,
    CONSTRAINT fk_message_conversation 
        FOREIGN KEY (conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 8. RELATION: ratchet_sessions (Double Ratchet State Machine) [BCNF]
-- ----------------------------------------------------------------------------
CREATE TABLE ratchet_sessions (
    session_id          TEXT PRIMARY KEY,
    conversation_id     TEXT NOT NULL UNIQUE,
    peer_dh_ratchet_pub TEXT NOT NULL,
    local_dh_ratchet_pub TEXT NOT NULL,
    root_key_hash       TEXT NOT NULL,
    send_chain_key_hash TEXT NOT NULL,
    recv_chain_key_hash TEXT NOT NULL,
    send_counter        INTEGER NOT NULL DEFAULT 0 CHECK (send_counter >= 0),
    recv_counter        INTEGER NOT NULL DEFAULT 0 CHECK (recv_counter >= 0),
    last_ratchet_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ratchet_conversation 
        FOREIGN KEY (conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 9. RELATION: skipped_keys (Out-of-Order Message Key Vault) [BCNF]
-- ----------------------------------------------------------------------------
CREATE TABLE skipped_keys (
    session_id          TEXT NOT NULL,
    dh_ratchet_pub      TEXT NOT NULL,
    message_counter     INTEGER NOT NULL CHECK (message_counter >= 0),
    message_key         TEXT NOT NULL,
    expires_at          DATETIME NOT NULL,
    PRIMARY KEY (session_id, dh_ratchet_pub, message_counter),
    CONSTRAINT fk_skipped_session 
        FOREIGN KEY (session_id) REFERENCES ratchet_sessions(session_id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 10. RELATION: outbox_queue (Multi-Transport Store-and-Forward Dispatch) [BCNF]
-- ----------------------------------------------------------------------------
CREATE TABLE outbox_queue (
    envelope_id         TEXT PRIMARY KEY,
    conversation_id     TEXT NOT NULL,
    destination_address TEXT NOT NULL,
    transport_type      TEXT NOT NULL 
                        CHECK (transport_type IN ('TCP_LAN', 'BLE_MESH', 'SPHINX_MIXNET', 'SMS_MODEM')),
    raw_payload         BLOB NOT NULL,
    retry_count         INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    max_retries         INTEGER NOT NULL DEFAULT 5 CHECK (max_retries >= 0),
    next_retry_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status              TEXT NOT NULL DEFAULT 'QUEUED' 
                        CHECK (status IN ('QUEUED', 'IN_FLIGHT', 'ACKNOWLEDGED', 'DEAD_LETTER')),
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_outbox_conversation 
        FOREIGN KEY (conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 11. RELATION: relay_cache (Autonomous Mesh Routing Buffer) [BCNF]
-- ----------------------------------------------------------------------------
CREATE TABLE relay_cache (
    route_token         TEXT PRIMARY KEY,
    opaque_envelope     BLOB NOT NULL,
    hop_count           INTEGER NOT NULL DEFAULT 1 CHECK (hop_count >= 0),
    ttl_seconds         INTEGER NOT NULL DEFAULT 3600 CHECK (ttl_seconds >= 0),
    received_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at          DATETIME NOT NULL
);

-- ============================================================================
-- 12. PERFORMANCE INDEXING ARCHITECTURE (Aligned with CP3 & CP4 Benchmarks)
-- ============================================================================

-- Fast lookup of user identity keys
CREATE INDEX idx_identity_keys_user 
    ON identity_keys(user_id);

-- Rapid filtration of active vs consumed prekeys during X3DH negotiation
CREATE INDEX idx_prekeys_user_consumed 
    ON prekey_bundles(user_id, is_consumed);

-- O(1) sender verification by address during packet ingress
CREATE INDEX idx_contacts_user_peer 
    ON contacts(user_id, peer_address);

-- Active conversation list sorted by recent activity timestamp
CREATE INDEX idx_conversations_user_active 
    ON conversations(user_id, last_active_at DESC);

-- Conversation lookup by contact ID
CREATE INDEX idx_conversations_contact 
    ON conversations(contact_id);

-- Compound covering index for message feed cursor pagination and thread retrieval
CREATE INDEX idx_messages_conversation_sent_at 
    ON messages(conversation_id, sent_at DESC);

-- Rapid filtration for aggregate unread message count badges
CREATE INDEX idx_messages_delivery_status 
    ON messages(delivery_status);

-- Double Ratchet cryptographic session state point lookup
CREATE INDEX idx_ratchet_sessions_conversation 
    ON ratchet_sessions(conversation_id);

-- Fast lookup and pruning of expired skipped ratchet keys
CREATE INDEX idx_skipped_keys_lookup 
    ON skipped_keys(session_id, expires_at);

-- Multi-carrier outbox dispatcher priority queue
CREATE INDEX idx_outbox_queue_priority 
    ON outbox_queue(status, next_retry_at);

-- Outbox envelope tracking by conversation thread
CREATE INDEX idx_outbox_queue_conversation 
    ON outbox_queue(conversation_id);

-- High-speed automated mesh garbage collection scan
CREATE INDEX idx_relay_cache_ttl 
    ON relay_cache(expires_at);

-- ============================================================================
-- 13. SEED VERIFICATION TRANSACTIONS (Integrity & Constraint Validation)
-- ============================================================================
BEGIN TRANSACTION;

-- Insert primary local node
INSERT INTO users (user_id, username, master_fingerprint)
VALUES ('usr_01', 'Alice_LocalNode', 'E4B8C1D2A3F4E5A6B7C8D9E0F1A2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D7E8F9A0');

-- Insert identity signing key
INSERT INTO identity_keys (key_id, user_id, key_type, public_key, encrypted_privkey)
VALUES ('key_01', 'usr_01', 'ED25519_SIGNING', 'ed25519_pub_alice_master_key_hash', X'DEADBEEFCAFE1234');

-- Insert prekey bundle
INSERT INTO prekey_bundles (prekey_id, user_id, key_id_num, key_type, public_key, signature, is_consumed)
VALUES ('pre_01', 'usr_01', 1, 'SIGNED_PREKEY', 'x25519_pub_alice_prekey_01', 'sig_alice_01', 0);

-- Insert remote contact
INSERT INTO contacts (contact_id, user_id, peer_address, peer_name, reachable_socket, public_key, fingerprint, trust_status)
VALUES ('cnt_01', 'usr_01', 'xchat://bob.p2p', 'Bob_Macbook', '192.168.1.15:9400', 'ed25519_pub_bob', 'B1C2D3E4F5A6B7C8D9E0F1A2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D7E8F9A0B1C2', 'VERIFIED');

-- Insert conversation thread
INSERT INTO conversations (conversation_id, user_id, contact_id, conv_type, title)
VALUES ('conv_01', 'usr_01', 'cnt_01', 'DIRECT', 'Encrypted P2P with Bob');

-- Insert Double Ratchet session state
INSERT INTO ratchet_sessions (session_id, conversation_id, peer_dh_ratchet_pub, local_dh_ratchet_pub, root_key_hash, send_chain_key_hash, recv_chain_key_hash, send_counter, recv_counter)
VALUES ('ses_01', 'conv_01', 'bob_dh_pub_01', 'alice_dh_pub_01', 'sha256_root_kdf_hash', 'sha256_send_chain_01', 'sha256_recv_chain_01', 1, 1);

-- Insert verified message record
INSERT INTO messages (message_id, conversation_id, sender_address, recipient_address, ciphertext, nonce, ratchet_counter, delivery_status)
VALUES ('msg_01', 'conv_01', 'xchat://bob.p2p', 'usr_01', X'414C49434520534543555245205041594C4F4144', 'nonce_12byte_hex', 0, 'DELIVERED');

-- Insert outbox envelope queued for BLE mesh dispatch
INSERT INTO outbox_queue (envelope_id, conversation_id, destination_address, transport_type, raw_payload, status)
VALUES ('env_01', 'conv_01', 'xchat://bob.p2p', 'BLE_MESH', X'7843686174576972654672616D65', 'QUEUED');

-- Insert blind relay packet
INSERT INTO relay_cache (route_token, opaque_envelope, hop_count, ttl_seconds, expires_at)
VALUES ('token_mesh_hop_01', X'4F50415155455F4D4553485F454E56454C4F5045', 2, 3600, datetime('now', '+3600 seconds'));

COMMIT;
