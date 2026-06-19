#!/bin/bash
# Install Squid Monitor API service
# Usage: sudo bash install-monitor.sh

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Jalankan dengan sudo${NC}"; exit 1
fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
PY_SCRIPT="$SRC_DIR/squid-monitor.py"

if [ ! -f "$PY_SCRIPT" ]; then
    echo -e "${RED}File squid-monitor.py tidak ditemukan${NC}"; exit 1
fi

echo -e "${CYAN}━━━ Install Squid Monitor API ━━━${NC}"

# Copy ke /usr/local/bin
cp "$PY_SCRIPT" /usr/local/bin/squid-monitor
chmod +x /usr/local/bin/squid-monitor

# Buat systemd service
cat > /etc/systemd/system/squid-monitor.service << 'EOF'
[Unit]
Description=Squid Cache Monitor API
After=network.target squid.service
Wants=squid.service

[Service]
Type=simple
ExecStart=/usr/local/bin/squid-monitor
Restart=always
RestartSec=3
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable squid-monitor
systemctl restart squid-monitor

sleep 1
if systemctl is-active --quiet squid-monitor; then
    IP=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    ADDR=$(ip addr show "$IP" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    echo -e "${GREEN}✓ Squid Monitor API installed!${NC}"
    echo -e "  ${YELLOW}URL :${NC} http://$ADDR:8080"
    echo -e "  ${YELLOW}API :${NC} http://$ADDR:8080/api/stats"
    echo -e ""
    echo -e "  ${CYAN}Uji coba:${NC} curl -s http://$ADDR:8080/api/stats | jq ."
    echo -e "  ${CYAN}Log    :${NC} sudo journalctl -u squid-monitor -f"
else
    echo -e "${RED}Gagal. Cek: sudo journalctl -u squid-monitor --no-pager -n 20${NC}"
    exit 1
fi
