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
