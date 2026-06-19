#!/bin/bash
# Install Squid Monitor API service
# Usage: sudo bash install-monitor.sh
# Repo: https://github.com/budijoi/squid-stb

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
REPO_RAW="https://raw.githubusercontent.com/budijoi/squid-stb/main"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Jalankan dengan sudo${NC}"; exit 1
fi

# Cari file squid-monitor.py
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
PY_SCRIPT="$SRC_DIR/squid-monitor.py"

if [ ! -f "$PY_SCRIPT" ]; then
    echo -e "${YELLOW}squid-monitor.py tidak ditemukan di direktori lokal.${NC}"
    echo -e "${YELLOW}Mendownload dari GitHub...${NC}"
    curl -sL "$REPO_RAW/monitor/squid-monitor.py" -o /tmp/squid-monitor.py
    if [ $? -ne 0 ] || [ ! -s /tmp/squid-monitor.py ]; then
        echo -e "${RED}Gagal mendownload squid-monitor.py dari GitHub.${NC}"
        echo -e "${YELLOW}Coba clone repo: git clone https://github.com/budijoi/squid-stb.git${NC}"
        exit 1
    fi
    PY_SCRIPT="/tmp/squid-monitor.py"
fi

echo -e "${CYAN}━━━ Install Squid Monitor API ━━━${NC}"

cp "$PY_SCRIPT" /usr/local/bin/squid-monitor
chmod +x /usr/local/bin/squid-monitor

cat > /etc/systemd/system/squid-monitor.service << 'SVC'
[Unit]
Description=Squid Cache Monitor API
After=network.target squid.service
Wants=squid.service

[Service]
Type=simple
ExecStart=/usr/local/bin/squid-monitor
Restart=always
RestartSec=3
# Monitor perlu membaca /var/log/squid/access.log — jalankan sebagai root
User=root
Group=root

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable squid-monitor
systemctl restart squid-monitor

sleep 1
if systemctl is-active --quiet squid-monitor; then
    IP=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    ADDR=$(ip addr show "$IP" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    [ -z "$ADDR" ] && ADDR=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}✓ Squid Monitor API installed!${NC}"
    echo -e "  ${YELLOW}URL :${NC} http://$ADDR:8080"
    echo -e "  ${YELLOW}API :${NC} http://$ADDR:8080/api/stats"
    echo ""
    echo -e "  ${CYAN}Uji coba:${NC} curl -s http://127.0.0.1:8080/api/stats"
    echo -e "  ${CYAN}Log    :${NC} sudo journalctl -u squid-monitor -f"
else
    echo -e "${RED}Gagal. Cek log: sudo journalctl -u squid-monitor --no-pager -n 20${NC}"
    exit 1
fi
