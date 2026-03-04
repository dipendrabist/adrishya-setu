#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Adṛśya-Setu — The Invisible Bridge  v2.0
#  Interactive Foreground Mode — live terminal dashboard
# ─────────────────────────────────────────────────────────────────────────────

# ── Colours & glyphs ─────────────────────────────────────────────────────────
R='\033[0;31m'   BRED='\033[1;31m'
G='\033[0;32m'   BGRN='\033[1;32m'
Y='\033[1;33m'   CYN='\033[0;36m'
BLU='\033[0;34m' WHT='\033[1;37m'
DIM='\033[2m'    BLD='\033[1m'
NC='\033[0m'

TICK="✦"  CROSS="✘"  ARROW="➤"  DOT="•"  LINE="─"

# ── Banner ────────────────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${CYN}"
    cat << 'EOF'
   ___       _  __ _           ___     _
  / _ \   __| |/ _(_)_ __  ___/ __| __| |_  _
 | (_) | / _` |  _| |  _ \/ -_\__ \/ _` | || |
  \___/ /_/ \____|_|____/\___|___/\__,_|\___,/
EOF
    echo -e "${DIM}${WHT}           A d ṛ ś y a - S e t u${NC}"
    echo -e "${DIM}${CYN}        ── The Invisible Bridge ──${NC}"
    echo
    echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}"
    echo -e " ${DIM}Author : TechChip   ${BLU}youtube.com/@techchipnet${NC}"
    echo -e " ${DIM}Version: 2.0   License: MIT${NC}"
    echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}"
    echo
}

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ "$UID" -ne 0 ]] && {
    echo -e "${BRED}${CROSS} Run as root: sudo $0${NC}"; exit 1
}

for cmd in curl tor jq xxd nc; do
    command -v "$cmd" &>/dev/null || {
        echo -e "${BRED}${CROSS} Missing dependency: ${cmd}${NC}"
        echo -e "  ${Y}Run setup.sh first to install all required packages.${NC}"
        exit 1
    }
done

# ── Distro detection & setup ──────────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

install_packages() {
    local distro="$1"
    echo -e "\n${BLU}${ARROW} Installing required packages…${NC}"
    case "$distro" in
        arch|manjaro|blackarch)
            pacman -S --needed --noconfirm curl tor jq xxd 2>&1 | grep -v "^$"
            TOR_GROUP="tor" ;;
        debian|ubuntu|kali|parrot)
            apt-get update -qq && apt-get install -y curl tor jq xxd 2>&1 | grep -v "^$"
            TOR_GROUP="debian-tor" ;;
        fedora)
            dnf install -y curl tor jq xxd 2>&1 | grep -v "^$"
            TOR_GROUP="tor" ;;
        opensuse*)
            zypper install -y curl tor jq xxd 2>&1 | grep -v "^$"
            TOR_GROUP="tor" ;;
        *)
            echo -e "${BRED}${CROSS} Unsupported distro. Install curl tor jq xxd manually.${NC}"
            exit 1 ;;
    esac
    export TOR_GROUP
}

configure_tor() {
    local torrc="/etc/tor/torrc"
    local changed=0

    grep -q "^ControlPort 9051"          "$torrc" || changed=1
    grep -q "^CookieAuthentication 1"    "$torrc" || changed=1
    grep -q "^CookieAuthFileGroupReadable 1" "$torrc" || changed=1

    if [[ "$changed" -eq 1 ]]; then
        echo -e "${BLU}${ARROW} Patching ${torrc}…${NC}"
        {
            printf '\n# Adṛśya-Setu — auto-configured\n'
            echo "ControlPort 9051"
            echo "CookieAuthentication 1"
            echo "CookieAuthFileGroupReadable 1"
        } >> "$torrc"
        systemctl restart tor
        echo -e "${BGRN}${TICK} Tor restarted with ControlPort enabled.${NC}"
    else
        echo -e "${BGRN}${TICK} torrc already configured correctly.${NC}"
    fi
}

wait_for_tor() {
    local tries=12 delay=3
    echo -ne "${BLU}${ARROW} Waiting for Tor…${NC}"
    for ((i=1; i<=tries; i++)); do
        if nc -z 127.0.0.1 9051 2>/dev/null && nc -z 127.0.0.1 9050 2>/dev/null; then
            echo -e " ${BGRN}${TICK}${NC}"; return 0
        fi
        echo -ne "${DIM}.${NC}"
        sleep "$delay"
    done
    echo -e " ${BRED}${CROSS} Tor unreachable!${NC}"
    return 1
}

# ── Core: send NEWNYM ─────────────────────────────────────────────────────────
send_newnym() {
    local cookie_file="/var/run/tor/control.authcookie"
    [[ -r "$cookie_file" ]] || { echo -e "${BRED}${CROSS} Cannot read auth cookie${NC}"; return 1; }
    local cookie
    cookie=$(xxd -ps "$cookie_file" | tr -d '\n')
    local resp
    resp=$(printf 'AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n' "$cookie" \
        | nc -w 5 127.0.0.1 9051 2>/dev/null)
    echo "$resp" | grep -q "250 OK"
}

# ── Core: fetch exit IP ───────────────────────────────────────────────────────
get_tor_ip() {
    curl -s --socks5-hostname 127.0.0.1:9050 --max-time 15 \
        --retry 3 --retry-delay 2 \
        "https://check.torproject.org/api/ip" 2>/dev/null | jq -r '.IP // empty'
}

# ── Live dashboard ────────────────────────────────────────────────────────────
ROTATIONS=0
LAST_IP="—"
START_TIME=$(date +%s)
declare -a IP_HISTORY=()

draw_dashboard() {
    local now=$(date +%s)
    local elapsed=$(( now - START_TIME ))
    local hh=$(( elapsed / 3600 ))
    local mm=$(( (elapsed % 3600) / 60 ))
    local ss=$(( elapsed % 60 ))
    local uptime=$(printf "%02d:%02d:%02d" $hh $mm $ss)

    # Move cursor to top (after banner — we redraw the stats block only)
    tput cup 13 0 2>/dev/null || echo -en "\033[13;0H"

    echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}"
    printf "  ${CYN}%-18s${NC}  ${BLD}${WHT}%s${NC}\n" "Status"    "${BGRN}● RUNNING${NC}"
    printf "  ${CYN}%-18s${NC}  ${BLD}${WHT}%s${NC}\n" "Uptime"    "$uptime"
    printf "  ${CYN}%-18s${NC}  ${BLD}${WHT}%s${NC}\n" "Rotations" "$ROTATIONS"
    printf "  ${CYN}%-18s${NC}  ${BLD}${Y}%s${NC}\n"   "Current IP" "$LAST_IP"
    printf "  ${CYN}%-18s${NC}  ${DIM}%s${NC}\n"       "Interval"   "${INTERVAL}s"
    echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}"
    echo
    echo -e "  ${BLD}Recent IP History${NC}"
    local shown=0
    for (( i=${#IP_HISTORY[@]}-1; i>=0 && shown<6; i--, shown++ )); do
        printf "  ${DIM}${DOT}${NC} ${WHT}%s${NC}\n" "${IP_HISTORY[$i]}"
    done
    # Pad empty rows so layout stays stable
    for (( p=shown; p<6; p++ )); do
        printf "  ${DIM}${DOT}${NC} ${DIM}—${NC}\n"
    done
    echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}"
    echo -e "  ${DIM}Press Ctrl+C to stop${NC}"
}

rotate_once() {
    if send_newnym; then
        sleep 3   # let Tor build circuit
        local ip
        ip=$(get_tor_ip)
        if [[ -n "$ip" && "$ip" != "null" ]]; then
            LAST_IP="$ip"
            IP_HISTORY+=("$(date '+%H:%M:%S') → $ip")
            (( ROTATIONS++ ))
            draw_dashboard
        else
            draw_dashboard
            tput cup 28 0 2>/dev/null; echo -e "  ${Y}⚠  Circuit building, retry next interval…${NC}"
        fi
    else
        tput cup 28 0 2>/dev/null; echo -e "  ${BRED}${CROSS} NEWNYM failed — check Tor ControlPort${NC}"
    fi
}

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    echo
    echo -e "\n${CYN}Adṛśya-Setu stopped. Rotated ${BLD}${ROTATIONS}${NC}${CYN} times.${NC}"
    tput cnorm 2>/dev/null   # restore cursor
    exit 0
}
trap cleanup SIGINT SIGTERM

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════
banner

DISTRO=$(detect_distro)
echo -e "  ${BLU}${ARROW} Detected distro: ${WHT}${DISTRO}${NC}"
install_packages "$DISTRO"
configure_tor
wait_for_tor || exit 1

echo
read -rp "$(echo -e "  ${Y}${ARROW} IP rotation interval in seconds [default 10]: ${NC}")" INTERVAL
INTERVAL=${INTERVAL:-10}
[[ "$INTERVAL" =~ ^[0-9]+$ && "$INTERVAL" -ge 10 ]] || {
    echo -e "  ${Y}⚠  Minimum interval is 10s (Tor's NEWNYM cooldown). Using 10.${NC}"
    INTERVAL=10
}

# Hide cursor for cleaner dashboard
tput civis 2>/dev/null

banner   # re-draw with stable layout before entering loop
draw_dashboard

echo -e "\n  ${BGRN}${TICK} Adṛśya-Setu engaged. Rotating every ${INTERVAL}s…${NC}"
sleep 1

while true; do
    rotate_once
    sleep "$INTERVAL"
done