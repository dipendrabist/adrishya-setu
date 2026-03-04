#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Adṛśya-Setu — The Invisible Bridge
#  Core IP Rotation Engine
#  Runs as a systemd service; rotates Tor circuit & logs new exit node IP.
# ─────────────────────────────────────────────────────────────────────────────

LOG_FILE="HOME/adrishya_setu.log"
STAT_FILE="HOME/adrishya_setu.stats"
MAX_LOG_LINES=5000          # Rotate log after this many lines
NEWNYM_COOLDOWN=10          # Tor enforces a 10-second minimum between NEWNYMs
TOR_CONTROL="127.0.0.1 9051"
TOR_SOCKS="--socks5-hostname 127.0.0.1:9050"
CHECK_URL="https://check.torproject.org/api/ip"
CURL_TIMEOUT=15

# ── Helpers ──────────────────────────────────────────────────────────────────

log() {
    local level="$1"; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" >> "$LOG_FILE"
}

rotate_log() {
    local lines
    lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [[ "$lines" -gt "$MAX_LOG_LINES" ]]; then
        tail -n $((MAX_LOG_LINES / 2)) "$LOG_FILE" > "${LOG_FILE}.tmp" \
            && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "INFO" "Log rotated (was ${lines} lines)"
    fi
}

update_stats() {
    local ip="$1"
    local rotations
    rotations=$(( $(grep -c "^ROTATIONS=" "$STAT_FILE" 2>/dev/null \
        && grep "^ROTATIONS=" "$STAT_FILE" | cut -d= -f2 || echo 0) + 1 ))
    # Rewrite stats atomically
    {
        echo "ROTATIONS=${rotations}"
        echo "LAST_IP=${ip}"
        echo "LAST_SEEN=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "STARTED=$(grep '^STARTED=' "$STAT_FILE" 2>/dev/null \
            | cut -d= -f2 || date '+%Y-%m-%d %H:%M:%S')"
    } > "${STAT_FILE}.tmp" && mv "${STAT_FILE}.tmp" "$STAT_FILE"
}

# ── Verify Tor is reachable ───────────────────────────────────────────────────

wait_for_tor() {
    local retries=10 delay=3
    for ((i=1; i<=retries; i++)); do
        if nc -z 127.0.0.1 9051 2>/dev/null && nc -z 127.0.0.1 9050 2>/dev/null; then
            return 0
        fi
        log "WARN" "Tor not ready (attempt ${i}/${retries}), waiting ${delay}s…"
        sleep "$delay"
    done
    log "ERROR" "Tor unreachable after ${retries} attempts. Aborting rotation."
    return 1
}

# ── Send NEWNYM via ControlPort ──────────────────────────────────────────────

send_newnym() {
    local cookie_file="/var/run/tor/control.authcookie"

    if [[ ! -r "$cookie_file" ]]; then
        log "ERROR" "Cannot read auth cookie at ${cookie_file}"
        return 1
    fi

    local cookie
    cookie=$(xxd -ps "$cookie_file" | tr -d '\n')
    if [[ -z "$cookie" ]]; then
        log "ERROR" "Auth cookie is empty"
        return 1
    fi

    local response
    response=$(printf 'AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n' "$cookie" \
        | nc -w 5 127.0.0.1 9051 2>/dev/null)

    if echo "$response" | grep -q "250 OK"; then
        return 0
    else
        log "WARN" "Unexpected ControlPort response: ${response}"
        return 1
    fi
}

# ── Fetch current Tor exit IP ────────────────────────────────────────────────

get_tor_ip() {
    local ip
    ip=$(curl -s $TOR_SOCKS --max-time "$CURL_TIMEOUT" \
        --retry 3 --retry-delay 2 "$CHECK_URL" 2>/dev/null \
        | jq -r '.IP // empty')
    echo "$ip"
}

# ── Main rotation logic ───────────────────────────────────────────────────────

rotate_ip() {
    wait_for_tor || return 1

    send_newnym || {
        log "ERROR" "NEWNYM signal failed; skipping rotation"
        return 1
    }

    # Tor may take a moment to build the new circuit
    sleep 3

    local ip
    ip=$(get_tor_ip)

    if [[ -z "$ip" || "$ip" == "null" ]]; then
        log "WARN" "Could not retrieve new IP (Tor may still be building circuit)"
        return 1
    fi

    log "INFO" "✦ New Exit Node → ${ip}"
    update_stats "$ip"
    rotate_log
}

# ── Entry point ───────────────────────────────────────────────────────────────

# Initialise stats file on first run
if [[ ! -f "$STAT_FILE" ]]; then
    echo "ROTATIONS=0" > "$STAT_FILE"
    echo "LAST_IP=—"   >> "$STAT_FILE"
    echo "LAST_SEEN=—" >> "$STAT_FILE"
    echo "STARTED=$(date '+%Y-%m-%d %H:%M:%S')" >> "$STAT_FILE"
fi

log "INFO" "Adṛśya-Setu rotation engine started (PID $$)"
rotate_ip