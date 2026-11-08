# Database Normalization Report: xChat Storage Engine

**Project:** xChat — Decentralized Multi-Transport Private Messenger  
**Module:** Relational Storage Architecture & Formal Normalization  
**Course:** Advanced Programming (AP) / Database Management Systems (DBMS)  
**Evaluation Target:** CP1 (`dbms/01_normalization.md`)  
**Date:** November 2026  

---

## Table of Contents
1. [Executive Summary & Architectural Scope](#1-executive-summary--architectural-scope)
2. [Theoretical Foundations & Mathematical Notation](#2-theoretical-foundations--mathematical-notation)
3. [Universal Relation: 0NF (Unnormalized Form)](#3-universal-relation-0nf-unnormalized-form)
   - 3.1 Universal Relation Schema
   - 3.2 Concrete Sample Data Matrix (0NF)
   - 3.3 Concrete Anomaly Demonstrations
4. [Transformation to First Normal Form (1NF)](#4-transformation-to-first-normal-form-1nf)
   - 4.1 Domain Atomicity Enforcement
   - 4.2 Flattened 1NF Schema
   - 4.3 Candidate Key Formulation & Remaining Anomaly Analysis
5. [Transformation to Second Normal Form (2NF)](#5-transformation-to-second-normal-form-2nf)
   - 5.1 Identification of Partial Functional Dependencies
   - 5.2 2NF Decomposition Algorithm
   - 5.3 Proving 2NF Compliance
6. [Transformation to Third Normal Form (3NF)](#6-transformation-to-third-normal-form-3nf)
   - 6.1 Identification of Transitive Functional Dependencies
   - 6.2 3NF Decomposition & Entity Extraction
   - 6.3 Proving 3NF Compliance
7. [Transformation to Boyce-Codd Normal Form (BCNF)](#7-transformation-to-boyce-codd-normal-form-bcnf)
   - 7.1 The BCNF Strict Determinant Requirement
   - 7.2 Overlapping Candidate Key Analysis
   - 7.3 Proving BCNF Compliance Across All Decomposed Relations
8. [Formal Mathematical Proofs](#8-formal-mathematical-proofs)
   - 8.1 Minimal Canonical Cover ($F_c$) Derivation
   - 8.2 Lossless-Join Decomposition Verification
   - 8.3 Dependency Preservation Verification
9. [Final Normalized Relational Schema Specification](#9-final-normalized-relational-schema-specification)
10. [Conclusion & Engineering Takeaways](#10-conclusion--engineering-takeaways)

---

## 1. Executive Summary & Architectural Scope

Modern instant messengers (such as Signal, WhatsApp, and Telegram) rely on centralized database clusters to manage user directories, message delivery queues, and contact discovery. In contrast, **xChat** is an edge-native, decentralized, multi-transport private messenger engineered to operate with **zero central servers**. 

In xChat, every participating node (mobile device, laptop, or localized relay) hosts an autonomous relational storage engine. This local database performs four mission-critical functions:
1. **Cryptographic Vault:** Persists master identity keypairs (Ed25519 signing, X25519 Diffie-Hellman), signed prekeys, and one-time prekeys required by the **Extended Triple Diffie-Hellman (X3DH)** asynchronous protocol.
2. **Session Ratchet State Machine:** Records active **Double Ratchet** parameters (root keys, symmetric send/receive chain keys, DH ratchet public keys, and skipped message key caches) to guarantee forward secrecy and post-compromise security.
3. **Multi-Transport Store-and-Forward Outbox:** Buffers encrypted envelopes across heterogeneous transport interfaces (Local TCP/LAN, Bluetooth Low Energy Mesh, and Chaumian Sphinx Mixnet) with retry timers and dead-letter queue limits.
4. **Relay Blind Transit Buffer:** Stores opaque transit envelopes on intermediary nodes without exposing sender, receiver, or plaintext payload data.

### Why Rigorous Normalization is Essential for xChat
In a traditional web application, a database anomaly causes minor UI glitches. In a peer-to-peer cryptographic system, database anomalies cause **catastrophic security failures**:
- **Ratchet Desynchronization Anomaly:** If an update anomaly occurs during ratchet state transitions, root keys desynchronize. The two peers can never decrypt each other's messages again without an out-of-band reset.
- **Identity Wipe Deletion Anomaly:** If deleting a conversation thread inadvertently purges a peer's identity key, future signature verifications fail, leaving the user vulnerable to person-in-the-middle (MITM) impersonation.
- **Outbox Starvation Insertion Anomaly:** If a pending outbound packet cannot be queued without an established contact record, offline ad-hoc beacon messages cannot be dispatched.

This report demonstrates the complete, formal, step-by-step normalization of xChat’s storage engine from an unnormalized universal relation (**0NF**) to **Boyce-Codd Normal Form (BCNF)**, accompanied by mathematical proofs of lossless join and dependency preservation.

---

## 2. Theoretical Foundations & Mathematical Notation

Throughout this document, relational database theory is formulated using standard mathematical conventions:

- **Universal Attribute Set ($U$):** The set of all attributes under consideration: $U = \{A_1, A_2, \dots, A_n\}$.
- **Relation Schema ($R(X)$):** A named relation with an attribute subset $X \subseteq U$.
- **Tuple ($t$):** A mapping from $X$ to their respective domains; $t[A]$ denotes the value of attribute $A$ for tuple $t$.
- **Functional Dependency ($X \to Y$):** Given $X, Y \subseteq U$, $X$ functionally determines $Y$ in relation $R$ if and only if for every pair of tuples $t_1, t_2 \in R$, $t_1[X] = t_2[X] \implies t_1[Y] = t_2[Y]$.
- **Attribute Closure ($X^+$):** The set of all attributes functionally determined by $X$ under a set of functional dependencies $F$, calculated using Armstrong’s Axioms:
  $$X^{(0)} = X$$
  $$X^{(i+1)} = X^{(i)} \cup \{Z \mid \exists (Y \to Z) \in F \text{ such that } Y \subseteq X^{(i)}\}$$
- **Superkey ($SK$):** A subset $K \subseteq U$ such that $K^+ = U$.
- **Candidate Key ($CK$):** A minimal superkey; that is, $K$ is a candidate key if $K^+ = U$ and $\forall A \in K, (K - \{A\})^+ \neq U$.
- **Prime Attribute:** Any attribute $A \in U$ that is a member of at least one candidate key $CK$.
- **Non-Prime Attribute:** An attribute $A \in U$ that does not belong to any candidate key.

### Armstrong's Axioms & Inference Rules
1. **Reflexivity:** If $Y \subseteq X$, then $X \to Y$.
2. **Augmentation:** If $X \to Y$, then $XZ \to YZ$ for any $Z$.
3. **Transitivity:** If $X \to Y$ and $Y \to Z$, then $X \to Z$.
4. **Union (Additive):** If $X \to Y$ and $X \to Z$, then $X \to YZ$.
5. **Decomposition (Projective):** If $X \to YZ$, then $X \to Y$ and $X \to Z$.
6. **Pseudotransitivity:** If $X \to Y$ and $WY \to Z$, then $WX \to Z$.

---

## 3. Universal Relation: 0NF (Unnormalized Form)

### 3.1 Universal Relation Schema
In an unnormalized design, all application parameters—local accounts, peer contacts, identity keys, prekey bundles, chat conversations, message payloads, Double Ratchet cryptographic states, outbox queues, and relay buffers—are pooled into a single monolithic flat table:

$$\text{UNF\_XCHAT}($$
$$\quad \text{user\_id}, \text{username}, \text{master\_fingerprint}, \text{user\_created\_at},$$
$$\quad \text{identity\_keys\_list}, \text{prekey\_pool},$$
$$\quad \text{contacts\_list},$$
$$\quad \text{conversation\_id}, \text{conv\_type}, \text{conv\_title}, \text{conv\_last\_active},$$
$$\quad \text{messages\_list},$$
$$\quad \text{session\_id}, \text{peer\_dh\_pub}, \text{local\_dh\_pub}, \text{root\_key\_hash}, \text{send\_chain\_hash}, \text{recv\_chain\_hash}, \text{send\_ctr}, \text{recv\_ctr}, \text{skipped\_keys\_list},$$
$$\quad \text{outbox\_envelopes\_list},$$
$$\quad \text{relay\_transit\_list}$$
$$)$$

Where the multi-valued attributes and nested repeating groups are defined as:
- $\text{identity\_keys\_list} = \{(\text{key\_id}, \text{key\_type}, \text{public\_key}, \text{enc\_privkey})^*\}$
- $\text{prekey\_pool} = \{(\text{prekey\_id}, \text{key\_id\_num}, \text{prekey\_type}, \text{prekey\_pub}, \text{signature}, \text{is\_consumed})^*\}$
- $\text{contacts\_list} = \{(\text{contact\_id}, \text{peer\_address}, \text{peer\_name}, \text{reachable\_socket}, \text{fingerprint}, \text{trust\_status})^*\}$
- $\text{messages\_list} = \{(\text{msg\_id}, \text{sender\_address}, \text{recipient\_address}, \text{ciphertext}, \text{nonce}, \text{ratchet\_ctr}, \text{delivery\_status}, \text{sent\_at})^*\}$
- $\text{skipped\_keys\_list} = \{(\text{dh\_ratchet\_pub}, \text{message\_counter}, \text{message\_key}, \text{expires\_at})^*\}$
- $\text{outbox\_envelopes\_list} = \{(\text{envelope\_id}, \text{dest\_addr}, \text{transport\_type}, \text{raw\_payload}, \text{retry\_count}, \text{next\_retry\_at}, \text{outbox\_status})^*\}$
- $\text{relay\_transit\_list} = \{(\text{route\_token}, \text{opaque\_payload}, \text{hop\_count}, \text{ttl\_seconds}, \text{relay\_expires\_at})^*\}$

---

### 3.2 Concrete Sample Data Matrix (0NF)

Below is a representative sample of tuples in $\text{UNF\_XCHAT}$, highlighting nested non-atomic collections and duplicate data:

| user_id | username | master_fingerprint | identity_keys_list (Repeating Group) | contacts_list (Repeating Group) | conversation_id | messages_list (Repeating Group) | session_id | root_key_hash |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `usr_01` | Aujasya | `fp_8f9c2d1e0a...` | `[(k1, ED25519, pk_ed1), (k2, X25519, pk_dh1)]` | `[(c1, xchat_alice, 192.168.1.42:8080), (c2, xchat_bob, 192.168.1.99:8080)]` | `conv_01` | `[(m1, xchat_alice, usr_01, "c1a9...", DELIVERED), (m2, usr_01, xchat_alice, "8f3b...", READ)]` | `ses_01` | `rk_9a8b7c` |
| `usr_01` | Aujasya | `fp_8f9c2d1e0a...` | `[(k1, ED25519, pk_ed1), (k2, X25519, pk_dh1)]` | `[(c1, xchat_alice, 192.168.1.42:8080), (c2, xchat_bob, 192.168.1.99:8080)]` | `conv_02` | `[(m3, xchat_bob, usr_01, "33d1...", PENDING)]` | `ses_02` | `rk_112233` |
| `usr_02` | Bob | `fp_3c4d5e6f7a...` | `[(k3, ED25519, pk_ed2)]` | `[(c3, xchat_alice, 192.168.1.42:8080)]` | `NULL` | `NULL` | `NULL` | `NULL` |

---

### 3.3 Concrete Anomaly Demonstrations

#### Anomaly 1: Insertion Anomaly
*Scenario:* A new peer contact, Charlie (`xchat_charlie`, socket `10.0.0.15:9090`), is discovered over the local Wi-Fi mesh.  
*Failure in 0NF:* Because `conversation_id` and `msg_id` are part of the primary key identification in the flat record, Charlie’s contact details cannot be recorded unless a conversation is created and a message is immediately drafted. Attempting to insert Charlie with `NULL` in messaging attributes violates entity integrity constraints.

#### Anomaly 2: Deletion Anomaly
*Scenario:* The user decides to clear chat history with Bob (`conv_02`) to free storage.  
*Failure in 0NF:* Deleting the row for `conv_02` simultaneously erases Bob's contact address (`xchat_bob`), his verified cryptographic safety fingerprint (`fp_bob_5678`), and his stored prekey bundle. When Bob transmits a new message later, his identity can no longer be verified.

#### Anomaly 3: Update Anomaly (State Desynchronization)
*Scenario:* Alice moves from Wi-Fi to cellular data, updating her reachable socket from `192.168.1.42:8080` to `172.56.21.9:8080`.  
*Failure in 0NF:* Because Alice's socket is replicated across multiple conversation and outbox records, if an update statement modifies only the active conversation row while background outbox records remain unchanged, subsequent packet dispatches are routed to the old IP. The socket is inconsistent across rows.

---

## 4. Transformation to First Normal Form (1NF)

### 4.1 Domain Atomicity Enforcement
A relation is in **First Normal Form (1NF)** if and only if:
1. Every attribute domain contains only atomic (indivisible) values.
2. There are no repeating groups, nested structures, or array columns.
3. Every tuple can be uniquely identified by a defined Primary Key.

To achieve 1NF, we flatten the repeating groups. Each element of a repeating group produces a distinct row combined with the primary key attributes of the parent entity.

### 4.2 Flattened 1NF Schema
$$\text{XCHAT\_1NF}($$
$$\quad \underline{\text{user\_id}, \text{key\_id}, \text{prekey\_id}, \text{contact\_id}, \text{conversation\_id}, \text{msg\_id}, \text{envelope\_id}, \text{route\_token}},$$
$$\quad \text{username}, \text{master\_fingerprint}, \text{user\_created\_at},$$
$$\quad \text{key\_type}, \text{public\_key}, \text{enc\_privkey},$$
$$\quad \text{key\_id\_num}, \text{prekey\_type}, \text{prekey\_pub}, \text{signature}, \text{is\_consumed},$$
$$\quad \text{peer\_address}, \text{peer\_name}, \text{reachable\_socket}, \text{fingerprint}, \text{trust\_status},$$
$$\quad \text{conv\_type}, \text{conv\_title}, \text{conv\_last\_active},$$
$$\quad \text{sender\_address}, \text{recipient\_address}, \text{ciphertext}, \text{nonce}, \text{ratchet\_ctr}, \text{delivery\_status}, \text{sent\_at},$$
$$\quad \text{session\_id}, \text{peer\_dh\_pub}, \text{local\_dh\_pub}, \text{root\_key\_hash}, \text{send\_chain\_hash}, \text{recv\_chain\_hash}, \text{send\_ctr}, \text{recv\_ctr},$$
$$\quad \text{skipped\_dh\_pub}, \text{skipped\_msg\_ctr}, \text{skipped\_msg\_key}, \text{skipped\_expires\_at},$$
$$\quad \text{dest\_addr}, \text{transport\_type}, \text{raw\_payload}, \text{retry\_count}, \text{next\_retry\_at}, \text{outbox\_status},$$
$$\quad \text{opaque\_payload}, \text{hop\_count}, \text{ttl\_seconds}, \text{relay\_expires\_at}$$
$$)$$

### 4.3 Candidate Key Formulation & Remaining Anomaly Analysis
The Composite Primary Key in 1NF requires the conjunction of all entity discriminators:
$$\text{PK}_{\text{1NF}} = \{\text{user\_id}, \text{key\_id}, \text{prekey\_id}, \text{contact\_id}, \text{conversation\_id}, \text{msg\_id}, \text{envelope\_id}, \text{route\_token}\}$$

**Why 1NF is Deficient:**  
Although 1NF achieves atomic cell values, it creates extreme redundancy. If a user has $2$ identity keys, $50$ prekeys, $20$ contacts, and $1,000$ messages, the Cartesian expansion creates $2 \times 50 \times 20 \times 1,000 = 2,000,000$ tuples. Almost every attribute depends on only a *subset* of the primary key, violating Second Normal Form.

---

## 5. Transformation to Second Normal Form (2NF)

### 5.1 Identification of Partial Functional Dependencies
A relation is in **Second Normal Form (2NF)** if and only if:
1. It is in **1NF**.
2. No non-prime attribute is **partially functionally dependent** on any candidate key. That is, every non-prime attribute must depend on the *entire* candidate key, not a proper subset.

Formally, a dependency $X \to Y$ is a **Partial Dependency** if:
$$X \subset CK \quad \text{and} \quad Y \text{ is a non-prime attribute.}$$

Evaluating the functional dependencies against $\text{PK}_{\text{1NF}}$:
1. $\text{user\_id} \subset \text{PK}_{\text{1NF}}$, yet:
   $$\text{user\_id} \to \{\text{username}, \text{master\_fingerprint}, \text{user\_created\_at}\} \quad \text{\textbf{(Partial Dependency)}}$$
2. $\{\text{user\_id}, \text{key\_id}\} \subset \text{PK}_{\text{1NF}}$, yet:
   $$\{\text{user\_id}, \text{key\_id}\} \to \{\text{key\_type}, \text{public\_key}, \text{enc\_privkey}\} \quad \text{\textbf{(Partial Dependency)}}$$
3. $\{\text{user\_id}, \text{prekey\_id}\} \subset \text{PK}_{\text{1NF}}$, yet:
   $$\{\text{user\_id}, \text{prekey\_id}\} \to \{\text{key\_id\_num}, \text{prekey\_type}, \text{prekey\_pub}, \text{signature}, \text{is\_consumed}\} \quad \text{\textbf{(Partial Dependency)}}$$
4. $\{\text{user\_id}, \text{contact\_id}\} \subset \text{PK}_{\text{1NF}}$, yet:
   $$\{\text{user\_id}, \text{contact\_id}\} \to \{\text{peer\_address}, \text{peer\_name}, \text{reachable\_socket}, \text{fingerprint}, \text{trust\_status}\} \quad \text{\textbf{(Partial Dependency)}}$$
5. $\text{conversation\_id} \subset \text{PK}_{\text{1NF}}$, yet:
   $$\text{conversation\_id} \to \{\text{user\_id}, \text{contact\_id}, \text{conv\_type}, \text{conv\_title}, \text{conv\_last\_active}\} \quad \text{\textbf{(Partial Dependency)}}$$
6. $\text{msg\_id} \subset \text{PK}_{\text{1NF}}$, yet:
   $$\text{msg\_id} \to \{\text{conversation\_id}, \text{sender\_address}, \text{recipient\_address}, \text{ciphertext}, \text{nonce}, \text{ratchet\_ctr}, \text{delivery\_status}, \text{sent\_at}\} \quad \text{\textbf{(Partial Dependency)}}$$
7. $\text{envelope\_id} \subset \text{PK}_{\text{1NF}}$, yet:
   $$\text{envelope\_id} \to \{\text{conversation\_id}, \text{dest\_addr}, \text{transport\_type}, \text{raw\_payload}, \text{retry\_count}, \text{next\_retry\_at}, \text{outbox\_status}\} \quad \text{\textbf{(Partial Dependency)}}$$
8. $\text{route\_token} \subset \text{PK}_{\text{1NF}}$, yet:
   $$\text{route\_token} \to \{\text{opaque\_payload}, \text{hop\_count}, \text{ttl\_seconds}, \text{relay\_expires\_at}\} \quad \text{\textbf{(Partial Dependency)}}$$

---

### 5.2 2NF Decomposition Algorithm
To eliminate partial dependencies, we project the relation into sub-relations where the determinant of each partial dependency becomes the full primary key of a dedicated relation.

#### Relation 2NF.1: `R_USERS`
$$\text{R\_USERS}(\underline{\text{user\_id}}, \text{username}, \text{master\_fingerprint}, \text{created\_at})$$
- Determinant: $\{\text{user\_id}\}$ (Full primary key)

#### Relation 2NF.2: `R_IDENTITY_KEYS`
$$\text{R\_IDENTITY\_KEYS}(\underline{\text{key\_id}}, \text{user\_id}, \text{key\_type}, \text{public\_key}, \text{enc\_privkey})$$
- Determinant: $\{\text{key\_id}\}$ (Full primary key)

#### Relation 2NF.3: `R_PREKEYS`
$$\text{R\_PREKEYS}(\underline{\text{prekey\_id}}, \text{user\_id}, \text{key\_id\_num}, \text{prekey\_type}, \text{prekey\_pub}, \text{signature}, \text{is\_consumed})$$
- Determinant: $\{\text{prekey\_id}\}$ (Full primary key)

#### Relation 2NF.4: `R_CONTACTS_CONVERSATIONS`
$$\text{R\_CONTACTS\_CONVERSATIONS}(\underline{\text{conversation\_id}}, \text{user\_id}, \text{contact\_id}, \text{peer\_address}, \text{peer\_name}, \text{reachable\_socket}, \text{fingerprint}, \text{trust\_status}, \text{conv\_type}, \text{conv\_title}, \text{conv\_last\_active})$$
- Determinant: $\{\text{conversation\_id}\}$ (Full primary key)

#### Relation 2NF.5: `R_MESSAGES`
$$\text{R\_MESSAGES}(\underline{\text{msg\_id}}, \text{conversation\_id}, \text{sender\_address}, \text{recipient\_address}, \text{ciphertext}, \text{nonce}, \text{ratchet\_ctr}, \text{delivery\_status}, \text{sent\_at})$$
- Determinant: $\{\text{msg\_id}\}$ (Full primary key)

#### Relation 2NF.6: `R_RATCHET_SESSIONS`
$$\text{R\_RATCHET\_SESSIONS}(\underline{\text{session\_id}}, \text{conversation\_id}, \text{peer\_dh\_pub}, \text{local\_dh\_pub}, \text{root\_key\_hash}, \text{send\_chain\_hash}, \text{recv\_chain\_hash}, \text{send\_ctr}, \text{recv\_ctr})$$
- Determinant: $\{\text{session\_id}\}$ (Full primary key)

#### Relation 2NF.7: `R_SKIPPED_KEYS`
$$\text{R\_SKIPPED\_KEYS}(\underline{\text{session\_id}, \text{skipped\_dh\_pub}, \text{skipped\_msg\_ctr}}, \text{skipped\_msg\_key}, \text{skipped\_expires\_at})$$
- Determinant: $\{\text{session\_id}, \text{skipped\_dh\_pub}, \text{skipped\_msg\_ctr}\}$ (Full composite primary key)

#### Relation 2NF.8: `R_OUTBOX`
$$\text{R\_OUTBOX}(\underline{\text{envelope\_id}}, \text{conversation\_id}, \text{dest\_addr}, \text{transport\_type}, \text{raw\_payload}, \text{retry\_count}, \text{next\_retry\_at}, \text{outbox\_status})$$
- Determinant: $\{\text{envelope\_id}\}$ (Full primary key)

#### Relation 2NF.9: `R_RELAY`
$$\text{R\_RELAY}(\underline{\text{route\_token}}, \text{opaque\_payload}, \text{hop\_count}, \text{ttl\_seconds}, \text{relay\_expires\_at})$$
- Determinant: $\{\text{route\_token}\}$ (Full primary key)

### 5.3 Proving 2NF Compliance
In every sub-relation $R_i \in \{\text{2NF.1} \dots \text{2NF.9}\}$, every non-prime attribute depends on the full primary key of $R_i$. There are **zero partial dependencies**. Thus, the schema is strictly in **2NF**.

---

## 6. Transformation to Third Normal Form (3NF)

### 6.1 Identification of Transitive Functional Dependencies
A relation is in **Third Normal Form (3NF)** if and only if:
1. It is in **2NF**.
2. No non-prime attribute is **transitively dependent** on any candidate key.

Formally, a transitive dependency exists if:
$$X \to Y \quad \text{and} \quad Y \to Z$$
where $X$ is a candidate key, $Y$ is a non-candidate key attribute set, and $Z$ is a non-prime attribute ($Y \not\to X$).

#### Transitive Dependency in `R_CONTACTS_CONVERSATIONS`
In relation 2NF.4:
$$\text{PK} = \{\text{conversation\_id}\}$$
We have:
1. $\text{conversation\_id} \to \text{contact\_id}$
2. $\text{contact\_id} \to \{\text{peer\_address}, \text{peer\_name}, \text{reachable\_socket}, \text{fingerprint}, \text{trust\_status}\}$
3. However, $\text{contact\_id} \not\to \text{conversation\_id}$ (a contact can participate in multiple conversations, e.g., Direct and Ephemeral Burner).

Thus, $\{\text{peer\_address}, \text{peer\_name}, \text{reachable\_socket}, \text{fingerprint}, \text{trust\_status}\}$ transitively depend on $\text{conversation\_id}$ through $\text{contact\_id}$. This causes update anomalies whenever a contact updates their IP socket.

---

### 6.2 3NF Decomposition & Entity Extraction
We decompose `R_CONTACTS_CONVERSATIONS` into two distinct relations:

1. **`CONTACTS`** (Transitive entity extracted)
   $$\text{CONTACTS}(\underline{\text{contact\_id}}, \text{user\_id}, \text{peer\_address}, \text{peer\_name}, \text{reachable\_socket}, \text{fingerprint}, \text{trust\_status}, \text{updated\_at})$$
   - Primary Key: $\{\text{contact\_id}\}$
   - Foreign Key: `user_id` $\to$ `USERS(user_id)`

2. **`CONVERSATIONS`** (Cleaned relation)
   $$\text{CONVERSATIONS}(\underline{\text{conversation\_id}}, \text{user\_id}, \text{contact\_id}, \text{conv\_type}, \text{title}, \text{is\_muted}, \text{created\_at}, \text{last\_active\_at})$$
   - Primary Key: $\{\text{conversation\_id}\}$
   - Foreign Key 1: `user_id` $\to$ `USERS(user_id)`
   - Foreign Key 2: `contact_id` $\to$ `CONTACTS(contact_id)`

---

### 6.3 Proving 3NF Compliance
By Codd’s theorem, a relation $R$ is in 3NF if for every non-trivial functional dependency $X \to Y$:
- Condition A: $X$ is a Superkey of $R$, **OR**
- Condition B: Every attribute $A \in (Y - X)$ is a prime attribute (member of a candidate key).

Inspecting all relations:
- In `CONTACTS`: $\text{contact\_id}$ is a superkey. Condition A is satisfied.
- In `CONVERSATIONS`: $\text{conversation\_id}$ is a superkey. Condition A is satisfied.
- In `MESSAGES`: $\text{msg\_id}$ is a superkey. Condition A is satisfied.
- In `RATCHET_SESSIONS`: $\text{session\_id}$ is a superkey. Condition A is satisfied.
- In `SKIPPED_KEYS`: $\{\text{session\_id}, \text{skipped\_dh\_pub}, \text{skipped\_msg\_ctr}\}$ is a superkey. Condition A is satisfied.
- In `OUTBOX`: $\text{envelope\_id}$ is a superkey. Condition A is satisfied.
- In `RELAY`: $\text{route\_token}$ is a superkey. Condition A is satisfied.

No transitive dependencies remain. The schema is strictly in **3NF**.

---

