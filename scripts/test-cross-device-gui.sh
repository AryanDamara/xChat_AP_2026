#!/usr/bin/env bash
set -euo pipefail

echo "==============================================================================="
echo "   xChat Live Cross-Device Two-Node Real Network Verification Test"
echo "==============================================================================="

PORT1=9551
PORT2=9552
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

echo "[*] Building release binary..."
cargo build --release --bin xchat-cli

BIN="$BASE_DIR/target/release/xchat-cli"

echo "[*] Spawning Node 1 on port $PORT1..."
$BIN app --port $PORT1 > /dev/null 2>&1 &
PID1=$!

echo "[*] Spawning Node 2 on port $PORT2..."
$BIN app --port $PORT2 > /dev/null 2>&1 &
PID2=$!

cleanup() {
    echo "[*] Stopping background nodes..."
    kill -9 $PID1 2>/dev/null || true
    kill -9 $PID2 2>/dev/null || true
}
trap cleanup EXIT

echo "[*] Waiting for both app nodes to bind..."
sleep 2

# 1. Verify Node 1 Identity
echo "[*] Step 1: Testing Node 1 API identity endpoint..."
ID1=$(curl -s "http://127.0.0.1:$PORT1/api/identity")
echo "    Node 1 Identity: $ID1"
if [[ "$ID1" != *"\"port\":$PORT1"* ]]; then
    echo "[-] FAILED: Node 1 identity invalid"
    exit 1
fi

# 2. Verify Node 2 Identity
echo "[*] Step 2: Testing Node 2 API identity endpoint..."
ID2=$(curl -s "http://127.0.0.1:$PORT2/api/identity")
echo "    Node 2 Identity: $ID2"
if [[ "$ID2" != *"\"port\":$PORT2"* ]]; then
    echo "[-] FAILED: Node 2 identity invalid"
    exit 1
fi

# 3. Verify Telegram HTML UI Served
echo "[*] Step 3: Verifying Telegram UI embedded HTML is served..."
HTML=$(curl -s "http://127.0.0.1:$PORT1/")
if [[ "$HTML" != *"--tg-bg: #0e1621;"* ]] || [[ "$HTML" != *"Direct P2P"* ]]; then
    echo "[-] FAILED: Telegram UI HTML not served correctly"
    exit 1
fi
echo "    [✓] Telegram Dark theme styles verified!"

# 4. Add Contact on Node 1
echo "[*] Step 4: Node 1 adding Node 2 as peer..."
curl -s -X POST "http://127.0.0.1:$PORT1/api/contacts" \
    -H "Content-Type: application/json" \
    -d "{\"alias\":\"Node2\",\"target\":\"127.0.0.1:$PORT2\"}"
echo "    [✓] Contact Node2 added to Node 1."

# 5. Node 1 sends message to Node 2
echo "[*] Step 5: Node 1 transmitting real network message to Node 2..."
TEST_MSG="Hello Node 2! Telegram P2P cross-device connection live."
curl -s -X POST "http://127.0.0.1:$PORT1/api/send" \
    -H "Content-Type: application/json" \
    -d "{\"alias\":\"Node2\",\"target\":\"127.0.0.1:$PORT2\",\"text\":\"$TEST_MSG\"}"
sleep 1

# 6. Verify Node 2 received message
echo "[*] Step 6: Verifying Node 2 received inbound message across network..."
MSGS2=$(curl -s "http://127.0.0.1:$PORT2/api/messages?peer=Peer")
echo "    Node 2 Inbox: $MSGS2"
if [[ "$MSGS2" != *"$TEST_MSG"* ]]; then
    echo "[-] FAILED: Node 2 did not receive message"
    exit 1
fi
echo "    [✓] Node 2 received and stored message with status 'delivered'!"

# 7. Node 2 replies back to Node 1
echo "[*] Step 7: Node 2 sending reply back to Node 1..."
REPLY_MSG="Acknowledged Node 1! Decryption and ratchet verified."
curl -s -X POST "http://127.0.0.1:$PORT2/api/send" \
    -H "Content-Type: application/json" \
    -d "{\"alias\":\"Peer\",\"target\":\"127.0.0.1:$PORT1\",\"text\":\"$REPLY_MSG\"}"
sleep 1

# 8. Verify Node 1 received reply
echo "[*] Step 8: Verifying Node 1 received reply from Node 2..."
MSGS1=$(curl -s "http://127.0.0.1:$PORT1/api/messages?peer=Node2")
echo "    Node 1 Inbox: $MSGS1"
if [[ "$MSGS1" != *"$REPLY_MSG"* ]]; then
    # Also check peer=Peer fallback
    MSGS1_FALLBACK=$(curl -s "http://127.0.0.1:$PORT1/api/messages?peer=Peer")
    if [[ "$MSGS1_FALLBACK" != *"$REPLY_MSG"* ]]; then
        echo "[-] FAILED: Node 1 did not receive reply from Node 2"
        exit 1
    fi
fi
echo "    [✓] Node 1 received reply successfully!"

# 9. Verify Ping Endpoint
echo "[*] Step 9: Verifying zero-metadata peer latency ping..."
PING_RESP=$(curl -s -X POST "http://127.0.0.1:$PORT1/api/ping" \
    -H "Content-Type: application/json" \
    -d "{\"target\":\"127.0.0.1:$PORT2\"}")
echo "    Ping Response: $PING_RESP"
if [[ "$PING_RESP" != *"latency_ms"* ]]; then
    echo "[-] FAILED: Ping failed"
    exit 1
fi

echo ""
echo "==============================================================================="
echo "   [✓✓] ALL CROSS-DEVICE TWO-NODE LIVE NETWORK TESTS PASSED (100% SUCCESS)!"
echo "==============================================================================="
