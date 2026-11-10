# Entity-Relationship (ER) Architecture Report: xChat Storage Engine

**Project:** xChat — Decentralized Multi-Transport Private Messenger  
**Module:** DBMS Relational Architecture & ER Modeling  
**Author:** Aujasya Rajput  
**Course:** Advanced Programming / Database Management Systems  
**Evaluation Target:** CP2 (`dbms/02_er_diagram.*` & `dbms/03_schema.sql`)  
**Prerequisite:** CP1 Relational Decomposition (`dbms/01_normalization.md`)  

---

## 1. Executive Summary & Conceptual Framework

In Checkpoint 1 (`dbms/01_normalization.md`), the xChat storage engine was rigorously decomposed from an unnormalized universal relation (**0NF**) through First (1NF), Second (2NF), and Third Normal Form (3NF), concluding with formal mathematical proofs of **Boyce-Codd Normal Form (BCNF)**, minimal canonical cover ($F_c$), and lossless join decomposition.

Checkpoint 2 (**CP2**) establishes the **Entity-Relationship (ER) Architecture** that bridges this theoretical BCNF formulation to physical relational database engines (such as SQLite 3.35+ and PostgreSQL 14+). 

Unlike conventional centralized chat platforms that offload state consistency to central server farms, xChat is an **autonomous peer-to-peer (P2P) decentralized system**. Every participating node must locally maintain:
1. **Asymmetric Cryptographic Keystores**: Long-term Ed25519 identity keys, pre-generated X25519 prekey bundles, and cryptographic signatures.
2. **Double Ratchet State Machines**: Root key chains, sending/receiving symmetric key ratchets, and ephemeral Diffie-Hellman public keys.
3. **Out-of-Order Key Vaults**: Skipped message keys stored temporarily to handle packets arriving out-of-order over lossy radio meshes.
4. **Decentralized Contact Registry & Socket Telemetry**: Peer public keys, cryptographically computed fingerprints, reachable transport endpoints (IP/port, Bluetooth MAC), and trust verification levels.
5. **Threaded Encrypted Conversations**: Cryptographic ciphertexts, initialization vectors (nonces), delivery states, and ratchet counters.
6. **Multi-Transport Outbox & Relay Cache**: Envelopes queued across heterogeneous physical carriers (TCP LAN sockets, Bluetooth Low Energy GATT mesh, Chaumian Sphinx mixnet nodes, and cellular SMS), along with ephemeral blind relay packets.

This report documents the formal conceptual schema, entity classifications, and relational mapping dictionary.

---

## 2. Entity Classification & Semantic Descriptions

The xChat database consists of **ten normalized entity relations**, categorized into **Strong Entities** (autonomous life cycle, independent primary keys) and **Weak / Dependent Entities** (existence-dependent on parent entities, referencing foreign keys).

```
+----------------------------------------------------------------------------------------------------+
|                                    ENTITY CLASSIFICATION TAXONOMY                                   |
+----------------------------------------------------------------------------------------------------+
|  STRONG (REGULAR) ENTITIES                       WEAK / DEPENDENT ENTITIES                          |
|  -------------------------                       -------------------------                          |
|  1. USERS                                        5. IDENTITY_KEYS     (Child of USERS)             |
|  2. CONTACTS                                     6. PREKEY_BUNDLES    (Child of USERS)             |
|  3. CONVERSATIONS                                7. MESSAGES          (Child of CONVERSATIONS)      |
|  4. RELAY_CACHE                                  8. RATCHET_SESSIONS  (Child of CONVERSATIONS)      |
|                                                  9. SKIPPED_KEYS      (Child of RATCHET_SESSIONS)  |
|                                                 10. OUTBOX_QUEUE      (Child of CONVERSATIONS)      |
+----------------------------------------------------------------------------------------------------+
```

### 2.1 Strong Entities

#### 1. `USERS`
* **Semantic Purpose:** Represents the local node identity within the device vault. In a decentralized environment, this table stores the root identity profile of the local operator.
* **Primary Key:** `user_id` (UUIDv4 string format).
* **Key Attributes:** `username`, `master_fingerprint` (Hexadecimal SHA-256 digest of the root identity key), `created_at`.
* **Existence Dependency:** None (Root entity).

#### 2. `CONTACTS`
* **Semantic Purpose:** Represents remote peers discovered via peer discovery (mDNS, Bluetooth Low Energy advertising, or manual QR/fingerprint scanning).
* **Primary Key:** `contact_id` (UUIDv4).
* **Alternative / Candidate Key:** `(user_id, peer_address)`.
* **Key Attributes:** `peer_name`, `peer_address` (P2P public identity address), `reachable_socket` (e.g., `192.168.1.50:9400` or `ble://XX:XX:XX:XX:XX:XX`), `public_key`, `fingerprint`, `trust_status`.

#### 3. `CONVERSATIONS`
* **Semantic Purpose:** Represents a logical communication channel between the local user and a contact. Serves as the aggregation root for encrypted message feeds, active ratchet sessions, and transport outbox queues.
* **Primary Key:** `conversation_id` (UUIDv4).
* **Key Attributes:** `conv_type` (`DIRECT`, `BURNER`, `SOS_BEACON`), `title`, `is_muted`, `created_at`, `last_active_at`.

#### 4. `RELAY_CACHE`
* **Semantic Purpose:** Implements store-and-forward mesh routing. When the local node acts as an intermediate blind relay for third-party traffic in a mesh or Chaumian mixnet, it buffers encrypted opaque envelopes without possessing decryption keys.
* **Primary Key:** `route_token` (SHA-256 HMAC of routing header).
* **Key Attributes:** `opaque_envelope` (Binary ciphertext payload), `hop_count`, `ttl_seconds`, `received_at`, `expires_at`.
* **Existence Dependency:** Autonomous (Relayed packets do not belong to local conversations).

---

### 2.2 Weak / Dependent Entities

#### 5. `IDENTITY_KEYS`
* **Semantic Purpose:** Stores the master cryptographic identity and Diffie-Hellman key pairs of the local node.
* **Existence Dependency:** Existence-dependent on `USERS`.
* **Primary Key:** `key_id` (UUIDv4).
* **Foreign Key:** `user_id` $\to$ `USERS(user_id)` with `ON DELETE CASCADE`.
* **Key Attributes:** `key_type` (`ED25519_SIGNING`, `X25519_DH`), `public_key` (Base64/Hex curve point), `encrypted_privkey` (AES-256-GCM encrypted vault blob), `created_at`.

#### 6. `PREKEY_BUNDLES`
* **Semantic Purpose:** Maintains pre-published public keys used for asynchronous X3DH (Extended Triple Diffie-Hellman) key exchange protocols, allowing peers to initiate conversations even while this node is temporarily offline.
* **Existence Dependency:** Existence-dependent on `USERS`.
* **Primary Key:** `prekey_id` (UUIDv4).
* **Candidate Key:** `(user_id, key_id_num, key_type)`.
* **Foreign Key:** `user_id` $\to$ `USERS(user_id)` with `ON DELETE CASCADE`.
* **Key Attributes:** `key_id_num` (Monotonic counter), `key_type` (`SIGNED_PREKEY`, `ONE_TIME_PREKEY`), `public_key`, `signature`, `is_consumed`.

#### 7. `MESSAGES`
* **Semantic Purpose:** Stores individual incoming and outgoing encrypted message payloads belonging to a specific conversation.
* **Existence Dependency:** Existence-dependent on `CONVERSATIONS`.
* **Primary Key:** `message_id` (UUIDv4).
* **Foreign Key:** `conversation_id` $\to$ `CONVERSATIONS(conversation_id)` with `ON DELETE CASCADE`.
* **Key Attributes:** `sender_address`, `recipient_address`, `ciphertext` (AES-256-GCM encrypted payload), `nonce` (12-byte initialization vector), `ratchet_counter`, `delivery_status`, `sent_at`, `delivered_at`.

#### 8. `RATCHET_SESSIONS`
* **Semantic Purpose:** Encapsulates the active Double Ratchet cryptographic state machine for a conversation, securing forward secrecy and post-compromise security.
* **Existence Dependency:** Existence-dependent on `CONVERSATIONS`.
* **Primary Key:** `session_id` (UUIDv4).
* **Candidate Key / Unique Constraint:** `conversation_id` (Enforces strict $1:1$ relationship per active conversation).
* **Foreign Key:** `conversation_id` $\to$ `CONVERSATIONS(conversation_id)` with `ON DELETE CASCADE`.
* **Key Attributes:** `peer_dh_ratchet_pub`, `local_dh_ratchet_pub`, `root_key_hash`, `send_chain_key_hash`, `recv_chain_key_hash`, `send_counter`, `recv_counter`, `last_ratchet_at`.

#### 9. `SKIPPED_KEYS`
* **Semantic Purpose:** Persists ephemeral message keys derived during symmetric ratchet stepping when packets arrive out of sequential order or over multi-hop mesh paths.
* **Existence Dependency:** Existence-dependent on `RATCHET_SESSIONS`.
* **Primary Key (Composite):** `(session_id, dh_ratchet_pub, message_counter)`.
* **Foreign Key:** `session_id` $\to$ `RATCHET_SESSIONS(session_id)` with `ON DELETE CASCADE`.
* **Key Attributes:** `message_key` (Encrypted symmetric key), `expires_at` (TTL boundary preventing indefinite memory bloat).

#### 10. `OUTBOX_QUEUE`
* **Semantic Purpose:** Manages transactional store-and-forward dispatching across heterogeneous multi-transport channels (TCP sockets, BLE mesh, Sphinx mixnet, cellular SMS).
* **Existence Dependency:** Existence-dependent on `CONVERSATIONS`.
* **Primary Key:** `envelope_id` (UUIDv4).
* **Foreign Key:** `conversation_id` $\to$ `CONVERSATIONS(conversation_id)` with `ON DELETE CASCADE`.
* **Key Attributes:** `destination_address`, `transport_type`, `raw_payload`, `retry_count`, `max_retries`, `next_retry_at`, `status`.

---

## 3. Comprehensive Relational Data Dictionary

Below is the exhaustive relational attribute specification mapping physical storage columns, domain types, constraints, and business logic:

### Table 1: `users`
| Column Name | SQL Data Type | Modifiers / Constraints | Description & Domain |
| :--- | :--- | :--- | :--- |
| `user_id` | `TEXT` | `PRIMARY KEY` | UUIDv4 string uniquely identifying the local user account. |
| `username` | `TEXT` | `NOT NULL` | Local operator screen handle or display name. |
| `master_fingerprint` | `TEXT` | `NOT NULL UNIQUE` | 64-character hex SHA-256 fingerprint derived from master identity key. |
| `created_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Node initialization timestamp. |

### Table 2: `identity_keys`
| Column Name | SQL Data Type | Modifiers / Constraints | Description & Domain |
| :--- | :--- | :--- | :--- |
| `key_id` | `TEXT` | `PRIMARY KEY` | UUIDv4 string uniquely identifying the key pair. |
| `user_id` | `TEXT` | `NOT NULL REFERENCES users(user_id) ON DELETE CASCADE` | Owning user reference. Cascades on user deletion. |
| `key_type` | `TEXT` | `NOT NULL CHECK (key_type IN ('ED25519_SIGNING', 'X25519_DH'))` | Cryptographic curve role. |
| `public_key` | `TEXT` | `NOT NULL UNIQUE` | Base64-encoded Curve25519/Ed25519 public key point. |
| `encrypted_privkey` | `BLOB` | `NOT NULL` | Private key bytes protected by AES-256-GCM using device passphrase. |
| `created_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Key creation timestamp. |

### Table 3: `prekey_bundles`
| Column Name | SQL Data Type | Modifiers / Constraints | Description & Domain |
| :--- | :--- | :--- | :--- |
| `prekey_id` | `TEXT` | `PRIMARY KEY` | UUIDv4 string uniquely identifying the prekey entry. |
| `user_id` | `TEXT` | `NOT NULL REFERENCES users(user_id) ON DELETE CASCADE` | Owning node identity reference. |
| `key_id_num` | `INTEGER` | `NOT NULL CHECK (key_id_num >= 0)` | Monotonically incrementing key index. |
| `key_type` | `TEXT` | `NOT NULL CHECK (key_type IN ('SIGNED_PREKEY', 'ONE_TIME_PREKEY'))` | X3DH role classification. |
| `public_key` | `TEXT` | `NOT NULL UNIQUE` | Curve25519 public key point available for key agreements. |
| `signature` | `TEXT` | `NULL` | Ed25519 identity signature (required for `SIGNED_PREKEY`). |
| `is_consumed` | `BOOLEAN` | `NOT NULL DEFAULT 0 CHECK (is_consumed IN (0, 1))` | 1 if used in an X3DH session initiation, preventing key reuse. |
| `created_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Publishing timestamp. |

### Table 4: `contacts`
| Column Name | SQL Data Type | Modifiers / Constraints | Description & Domain |
| :--- | :--- | :--- | :--- |
| `contact_id` | `TEXT` | `PRIMARY KEY` | UUIDv4 string uniquely identifying the contact record. |
| `user_id` | `TEXT` | `NOT NULL REFERENCES users(user_id) ON DELETE CASCADE` | Local node owning this contact card. |
| `peer_address` | `TEXT` | `NOT NULL` | Cryptographic public address of the peer. |
| `peer_name` | `TEXT` | `NOT NULL` | User-assigned or peer-announced display name. |
| `reachable_socket` | `TEXT` | `NOT NULL` | Direct network endpoint (e.g. `192.168.1.15:9400`, `ble://...`). |
| `public_key` | `TEXT` | `NOT NULL` | Verified long-term Ed25519 identity public key. |
| `fingerprint` | `TEXT` | `NOT NULL` | Visual verification hex string displayed for out-of-band verification. |
| `trust_status` | `TEXT` | `NOT NULL CHECK (trust_status IN ('VERIFIED', 'UNVERIFIED', 'BLOCKED'))` | Out-of-band trust certification level. |
| `created_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Record creation timestamp. |
| `updated_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Telemetry/socket heartbeat update timestamp. |

### Table 5: `conversations`
| Column Name | SQL Data Type | Modifiers / Constraints | Description & Domain |
| :--- | :--- | :--- | :--- |
| `conversation_id`| `TEXT` | `PRIMARY KEY` | UUIDv4 string uniquely identifying the thread. |
| `user_id` | `TEXT` | `NOT NULL REFERENCES users(user_id) ON DELETE CASCADE` | Local account owner. |
| `contact_id` | `TEXT` | `NOT NULL REFERENCES contacts(contact_id) ON DELETE RESTRICT`| Peer contact. Prevent contact deletion while active thread exists. |
| `conv_type` | `TEXT` | `NOT NULL CHECK (conv_type IN ('DIRECT', 'BURNER', 'SOS_BEACON'))` | Channel privacy and persistence mode. |
| `title` | `TEXT` | `NOT NULL` | Visual header shown in chat UI. |
| `is_muted` | `BOOLEAN` | `NOT NULL DEFAULT 0 CHECK (is_muted IN (0, 1))` | Mute notification alerts toggle. |
| `created_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Channel establishment timestamp. |
| `last_active_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Timestamp of most recently received/dispatched message. |

### Table 6: `messages`
| Column Name | SQL Data Type | Modifiers / Constraints | Description & Domain |
| :--- | :--- | :--- | :--- |
| `message_id` | `TEXT` | `PRIMARY KEY` | UUIDv4 message identifier. |
| `conversation_id`| `TEXT` | `NOT NULL REFERENCES conversations(conversation_id) ON DELETE CASCADE`| Parent conversation thread. |
| `sender_address` | `TEXT` | `NOT NULL` | Origin node address string. |
| `recipient_address`| `TEXT` | `NOT NULL` | Target node address string. |
| `ciphertext` | `BLOB` | `NOT NULL` | Encrypted message body (AES-256-GCM). |
| `nonce` | `TEXT` | `NOT NULL` | 12-byte initialization vector used for decryption. |
| `ratchet_counter`| `INTEGER` | `NOT NULL DEFAULT 0 CHECK (ratchet_counter >= 0)` | Step index in the symmetric message ratchet chain. |
| `delivery_status`| `TEXT` | `NOT NULL CHECK (delivery_status IN ('PENDING', 'SENT', 'DELIVERED', 'READ', 'FAILED'))`| Message delivery receipt status. |
| `sent_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Emission timestamp. |
| `delivered_at` | `DATETIME` | `NULL` | Timestamp when P2P delivery ACK was validated. |

### Table 7: `ratchet_sessions`
| Column Name | SQL Data Type | Modifiers / Constraints | Description & Domain |
| :--- | :--- | :--- | :--- |
| `session_id` | `TEXT` | `PRIMARY KEY` | UUIDv4 session identifier. |
| `conversation_id`| `TEXT` | `NOT NULL UNIQUE REFERENCES conversations(conversation_id) ON DELETE CASCADE`| Enforces strict $1:1$ mapping to conversation. |
| `peer_dh_ratchet_pub`| `TEXT` | `NOT NULL` | Remote peer's current ephemeral DH ratchet public key. |
| `local_dh_ratchet_pub`| `TEXT` | `NOT NULL` | Local node's active ephemeral DH ratchet public key. |
| `root_key_hash` | `TEXT` | `NOT NULL` | SHA-256 digest of root key (protects raw key in storage). |
| `send_chain_key_hash`| `TEXT` | `NOT NULL` | SHA-256 digest of active sending chain key. |
| `recv_chain_key_hash`| `TEXT` | `NOT NULL` | SHA-256 digest of active receiving chain key. |
| `send_counter` | `INTEGER` | `NOT NULL DEFAULT 0 CHECK (send_counter >= 0)` | Sequential outgoing message counter. |
| `recv_counter` | `INTEGER` | `NOT NULL DEFAULT 0 CHECK (recv_counter >= 0)` | Sequential incoming message counter. |
| `last_ratchet_at`| `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Timestamp of latest DH ratchet step. |

### Table 8: `skipped_keys`
| Column Name | SQL Data Type | Modifiers / Constraints | Description & Domain |
| :--- | :--- | :--- | :--- |
| `session_id` | `TEXT` | `NOT NULL REFERENCES ratchet_sessions(session_id) ON DELETE CASCADE`| Owning ratchet session. |
| `dh_ratchet_pub` | `TEXT` | `NOT NULL` | Diffie-Hellman public key identifying the ratchet step. |
| `message_counter`| `INTEGER` | `NOT NULL CHECK (message_counter >= 0)` | Counter of the missed message. |
| `message_key` | `TEXT` | `NOT NULL` | Derived symmetric key stored until late message arrives. |
| `expires_at` | `DATETIME` | `NOT NULL` | Garbage collection deadline (defaults to 14 days). |

### Table 9: `outbox_queue`
| Column Name | SQL Data Type | Modifiers / Constraints | Description & Domain |
| :--- | :--- | :--- | :--- |
| `envelope_id` | `TEXT` | `PRIMARY KEY` | UUIDv4 envelope identifier. |
| `conversation_id`| `TEXT` | `NOT NULL REFERENCES conversations(conversation_id) ON DELETE CASCADE`| Origin conversation. |
| `destination_address`| `TEXT`| `NOT NULL` | Final destination peer address. |
| `transport_type` | `TEXT` | `NOT NULL CHECK (transport_type IN ('TCP_LAN', 'BLE_MESH', 'SPHINX_MIXNET', 'SMS_MODEM'))`| Designated transmission carrier. |
| `raw_payload` | `BLOB` | `NOT NULL` | Wire-format serialized message frame. |
| `retry_count` | `INTEGER` | `NOT NULL DEFAULT 0 CHECK (retry_count >= 0)` | Number of failed dispatch attempts. |
| `max_retries` | `INTEGER` | `NOT NULL DEFAULT 5 CHECK (max_retries >= 0)` | Maximum retry limit before failure. |
| `next_retry_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Exponential backoff scheduled timestamp. |
| `status` | `TEXT` | `NOT NULL CHECK (status IN ('QUEUED', 'IN_FLIGHT', 'ACKNOWLEDGED', 'DEAD_LETTER'))`| Current outbox delivery status. |
| `created_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Timestamp envelope was generated. |

### Table 10: `relay_cache`
| Column Name | SQL Data Type | Modifiers / Constraints | Description & Domain |
| :--- | :--- | :--- | :--- |
| `route_token` | `TEXT` | `PRIMARY KEY` | Blind HMAC routing token identifying the relay envelope. |
| `opaque_envelope`| `BLOB` | `NOT NULL` | Unreadable encrypted envelope buffered for third-party mesh nodes. |
| `hop_count` | `INTEGER` | `NOT NULL DEFAULT 1 CHECK (hop_count >= 0)` | Number of intermediate mesh hops traversed. |
| `ttl_seconds` | `INTEGER` | `NOT NULL DEFAULT 3600 CHECK (ttl_seconds >= 0)`| Remaining packet lifetime in seconds. |
| `received_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Time envelope was received over mesh. |
| `expires_at` | `DATETIME` | `NOT NULL` | Automatic deletion timestamp (`received_at + ttl_seconds`). |

---

## 4. Traceability Matrix: CP1 BCNF $\leftrightarrow$ CP2 ER Architecture

The following matrix formally verifies that every BCNF relation and functional dependency established in CP1 is fully represented and preserved in the CP2 ER model:

| CP1 BCNF Relation | CP2 ER Entity | Primary Key in ER Model | Referential Foreign Keys | BCNF Functional Dependency Preserved? |
| :--- | :--- | :--- | :--- | :---: |
| `R_USERS` | `USERS` | `user_id` | None | **Yes** ($\text{user\_id} \to \text{Attributes}$) |
| `R_IDENTITY_KEYS` | `IDENTITY_KEYS` | `key_id` | `user_id` $\to$ `USERS` | **Yes** ($\text{key\_id} \to \text{Attributes}$) |
| `R_PREKEYS` | `PREKEY_BUNDLES` | `prekey_id` | `user_id` $\to$ `USERS` | **Yes** ($\text{prekey\_id} \to \text{Attributes}$) |
| `CONTACTS` | `CONTACTS` | `contact_id` | `user_id` $\to$ `USERS` | **Yes** ($\text{contact\_id} \to \text{Attributes}$) |
| `CONVERSATIONS` | `CONVERSATIONS` | `conversation_id` | `user_id`, `contact_id` | **Yes** ($\text{conv\_id} \to \text{Attributes}$) |
| `R_MESSAGES` | `MESSAGES` | `message_id` | `conversation_id` $\to$ `CONVERSATIONS` | **Yes** ($\text{msg\_id} \to \text{Attributes}$) |
| `R_RATCHET_SESSIONS`| `RATCHET_SESSIONS` | `session_id` | `conversation_id` $\to$ `CONVERSATIONS` | **Yes** ($\text{session\_id} \to \text{Attributes}$) |
| `R_SKIPPED_KEYS` | `SKIPPED_KEYS` | `(session_id, dh_pub, ctr)` | `session_id` $\to$ `RATCHET_SESSIONS` | **Yes** ($\text{Composite} \to \text{Key}$) |
| `R_OUTBOX` | `OUTBOX_QUEUE` | `envelope_id` | `conversation_id` $\to$ `CONVERSATIONS` | **Yes** ($\text{envelope\_id} \to \text{Attributes}$) |
| `R_RELAY` | `RELAY_CACHE` | `route_token` | None | **Yes** ($\text{route\_token} \to \text{Attributes}$) |
