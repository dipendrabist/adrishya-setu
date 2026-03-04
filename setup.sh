#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Adṛśya-Setu — The Invisible Bridge  v2.0
#  Installer & Service Deployment Script
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'   BRED='\033[1;31m'
G='\033[0;32m'   BGRN='\033[1;32m'
Y='\033[1;33m'   CYN='\033[0;36m'
BLU='\033[0;34m' WHT='\033[1;37m'
DIM='\033[2m'    BLD='\033[1m'
NC='\033[0m'

TICK="✦"  CROSS="✘"  ARROW="➤"  WARN="⚠"

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
    echo -e "${DIM}${WHT}        Installer  v2.0${NC}"
    echo
    echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}"
    echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}\n"
}

# ── Step logger ───────────────────────────────────────────────────────────────
step()  { echo -e "\n${BLU}${ARROW} $*${NC}"; }
ok()    { echo -e "  ${BGRN}${TICK} $*${NC}"; }
warn()  { echo -e "  ${Y}${WARN}  $*${NC}"; }
fail()  { echo -e "  ${BRED}${CROSS} $*${NC}"; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────
banner

[[ "$UID" -ne 0 ]] && fail "Please run as root: sudo $0"

# Capture the real user (even when sudo)
REAL_USER="${SUDO_USER:-$USER}"
INSTALL_DIR="/home/${REAL_USER}"

# ── Distro detection ──────────────────────────────────────────────────────────
step "Detecting Linux distribution…"
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO="$ID"
    ok "Detected: ${PRETTY_NAME:-$DISTRO}"
else
    fail "Cannot determine Linux distribution."
fi

# ── Package installation ──────────────────────────────────────────────────────
step "Installing required packages (curl tor jq xxd)…"
case "$DISTRO" in
    arch|manjaro|blackarch)
        pacman -S --needed --noconfirm curl tor jq xxd
        TOR_GROUP="tor" ;;
    debian|ubuntu|kali|parrot)
        apt-get update -qq
        apt-get install -y curl tor jq xxd
        TOR_GROUP="debian-tor" ;;
    fedora)
        dnf install -y curl tor jq xxd
        TOR_GROUP="tor" ;;
    opensuse*)
        zypper install -y curl tor jq xxd
        TOR_GROUP="tor" ;;
    *)
        fail "Unsupported distro '${DISTRO}'. Install curl tor jq xxd manually, then re-run." ;;
esac
ok "Packages ready."

# ── Group membership ──────────────────────────────────────────────────────────
step "Verifying group membership (${TOR_GROUP})…"
if ! getent group "$TOR_GROUP" &>/dev/null; then
    warn "Group '${TOR_GROUP}' not found — creating it."
    groupadd "$TOR_GROUP"
fi

if ! id -nG "$REAL_USER" | grep -qw "$TOR_GROUP"; then
    usermod -aG "$TOR_GROUP" "$REAL_USER"
    ok "User '${REAL_USER}' added to group '${TOR_GROUP}'."
    warn "You may need to log out & back in for group changes to take effect."
else
    ok "User '${REAL_USER}' is already in group '${TOR_GROUP}'."
fi

# ── Tor configuration ─────────────────────────────────────────────────────────
step "Configuring Tor (/etc/tor/torrc)…"
TORRC="/etc/tor/torrc"
CHANGED=0

grep -q "^ControlPort 9051"              "$TORRC" || CHANGED=1
grep -q "^CookieAuthentication 1"        "$TORRC" || CHANGED=1
grep -q "^CookieAuthFileGroupReadable 1" "$TORRC" || CHANGED=1

if [[ "$CHANGED" -eq 1 ]]; then
    cp "$TORRC" "${TORRC}.bak.$(date +%s)"
    {
        printf '\n# ── Adṛśya-Setu (auto-configured %s) ──\n' "$(date '+%Y-%m-%d')"
        echo "ControlPort 9051"
        echo "CookieAuthentication 1"
        echo "CookieAuthFileGroupReadable 1"
    } >> "$TORRC"
    systemctl restart tor
    ok "torrc updated and Tor restarted. (Backup saved as ${TORRC}.bak.*)"
else
    ok "torrc already contains required settings. No changes needed."
fi

# ── Interval prompt ───────────────────────────────────────────────────────────
echo
echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}"
echo -e "  ${Y}Tor enforces a 10-second minimum between NEWNYM signals.${NC}"
read -rp "$(echo -e "  ${CYN}${ARROW} Enter IP rotation interval in seconds [default 10]: ${NC}")" TIME_INTERVAL
TIME_INTERVAL="${TIME_INTERVAL:-10}"

if ! [[ "$TIME_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$TIME_INTERVAL" -lt 10 ]]; then
    warn "Value must be an integer ≥ 10. Defaulting to 10."
    TIME_INTERVAL=10
fi
ok "Rotation interval set to ${TIME_INTERVAL}s."

# ── Deploy files ──────────────────────────────────────────────────────────────
step "Deploying Adṛśya-Setu files to ${INSTALL_DIR}…"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Core rotation script
CORE_SCRIPT="${INSTALL_DIR}/change_tor_ip.sh"
cp "${SCRIPT_DIR}/change_tor_ip.sh" "$CORE_SCRIPT"
sed -i "s|HOME|${INSTALL_DIR}|g" "$CORE_SCRIPT"
chmod +x "$CORE_SCRIPT"
chown "${REAL_USER}:${REAL_USER}" "$CORE_SCRIPT"
ok "Core script → ${CORE_SCRIPT}"

# Interactive mode script
INTERACTIVE_SCRIPT="${INSTALL_DIR}/ip-changer.sh"
cp "${SCRIPT_DIR}/ip-changer.sh" "$INTERACTIVE_SCRIPT"
chmod +x "$INTERACTIVE_SCRIPT"
chown "${REAL_USER}:${REAL_USER}" "$INTERACTIVE_SCRIPT"
ok "Interactive script → ${INTERACTIVE_SCRIPT}"

# Systemd service
SERVICE_SRC="${SCRIPT_DIR}/adrishya-setu.service"
SERVICE_DEST="/etc/systemd/system/adrishya-setu.service"
cp "$SERVICE_SRC" "$SERVICE_DEST"
# Patch placeholders
sed -i "s|HOME|${INSTALL_DIR}|g"       "$SERVICE_DEST"
sed -i "s/RestartSec=.*/RestartSec=${TIME_INTERVAL}/" "$SERVICE_DEST"
sed -i "s|^ExecStart=.*|ExecStart=${CORE_SCRIPT}|"    "$SERVICE_DEST"
ok "Service file → ${SERVICE_DEST}"

# ── Enable & start services ───────────────────────────────────────────────────
step "Enabling and starting services…"
systemctl daemon-reload
systemctl enable --now tor.service
systemctl enable --now adrishya-setu.service
ok "tor.service enabled and started."
ok "adrishya-setu.service enabled and started."

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}"
echo -e "${BGRN}  ${TICK}  Adṛśya-Setu deployed successfully!${NC}"
echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}"
echo
echo -e "  ${CYN}Rotation interval :${NC} ${WHT}${TIME_INTERVAL}s${NC}"
echo -e "  ${CYN}Install directory :${NC} ${WHT}${INSTALL_DIR}${NC}"
echo -e "  ${CYN}Log file          :${NC} ${WHT}${INSTALL_DIR}/adrishya_setu.log${NC}"
echo -e "  ${CYN}Stats file        :${NC} ${WHT}${INSTALL_DIR}/adrishya_setu.stats${NC}"
echo
echo -e "  ${DIM}Useful commands:${NC}"
echo -e "  ${Y}systemctl status adrishya-setu${NC}   — check service status"
echo -e "  ${Y}journalctl -fu adrishya-setu${NC}     — follow live logs"
echo -e "  ${Y}tail -f ${INSTALL_DIR}/adrishya_setu.log${NC}"
echo -e "  ${Y}sudo ${INSTALL_DIR}/ip-changer.sh${NC}         — interactive mode"
echo
echo -e "${DIM}${WHT}$(printf '%.0s─' {1..54})${NC}\n"