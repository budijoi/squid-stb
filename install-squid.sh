#!/bin/bash
# Squid Caching Proxy Auto-Installer for Armbian (X96Mini)
# Usage: sudo bash install-squid.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[!] Jalankan dengan sudo: sudo bash $0${NC}"
    exit 1
fi

# === PROGRESS BAR ===
BAR_LEN=40
TOTAL_STEPS=0
CUR_STEP=0

init_progress() {
    TOTAL_STEPS=$1
    CUR_STEP=0
}

show_progress() {
    CUR_STEP=$((CUR_STEP + 1))
    local pct=$((CUR_STEP * 100 / TOTAL_STEPS))
    local filled=$((pct * BAR_LEN / 100))
    local empty=$((BAR_LEN - filled))
    local bar
    bar=$(printf "${GREEN}%${filled}s${NC}" | tr ' ' '█')
    bar+=$(printf "${DIM}%${empty}s${NC}" | tr ' ' '░')
    echo -ne "\r${CYAN}${BOLD}[${NC}${bar}${CYAN}${BOLD}] ${pct}%${NC} ${1}"
    if [ "$CUR_STEP" -eq "$TOTAL_STEPS" ]; then
        echo ""
    fi
}

spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}%c${NC} %s" "${spin:$i:1}" "$msg"
        i=$(( (i + 1) % 10 ))
        sleep 0.1
    done
    printf "\r${GREEN}✓${NC} %s\n" "$msg"
}

run_spinner() {
    local msg=$1
    shift
    ("$@" > /dev/null 2>&1) &
    local pid=$!
    spinner "$pid" "$msg"
    wait "$pid"
    return $?
}

# === BANNER ===
clear
echo ""
echo -e "  ${CYAN}╔═══════════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}░▀▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌▀░${NC}  ${BOLD}${YELLOW}SQUID CACHE PROXY${NC}     ${CYAN}║${NC}"
echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}▄█▓▒░SQUID░▒▓█▄${NC}       ${BOLD}${YELLOW}Auto Installer${NC}   ${CYAN}║${NC}"
echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}▀▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌▀${NC}  ${BOLD}${YELLOW}for Armbian${NC}        ${CYAN}║${NC}"
echo -e "  ${CYAN}╚═══════════════════════════════════════════╝${NC}"
echo ""

# === DETEKSI SISTEM ===
echo -e "${BLUE}${BOLD}━━━ SYSTEM INFORMATION ━━━${NC}"
echo -e "  ${DIM}Hostname :${NC} $(hostname)"
echo -e "  ${DIM}Kernel   :${NC} $(uname -r)"
echo -e "  ${DIM}Arch     :${NC} $(uname -m)"
echo -e "  ${DIM}Memory   :${NC} $(free -h | awk '/^Mem:/ {print $2}')"
echo -e "  ${DIM}Disk     :${NC} $(df -h / | awk 'NR==2 {print $4}') free"
echo ""

# === PRE-FLIGHT CHECKS ===
echo -e "${BLUE}${BOLD}━━━ PRE-FLIGHT CHECKS ━━━${NC}"

# Detect LAN
IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
IP_ADDR=$(ip addr show "$IFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
SUBNET=$(ip route 2>/dev/null | grep -E "link src $IP_ADDR|$IFACE.*proto kernel" | grep -oP '\d+\.\d+\.\d+\.\d+/\d+' | head -1)
[ -z "$SUBNET" ] && SUBNET=$(ip route 2>/dev/null | grep "$IFACE" | grep -oP '\d+\.\d+\.\d+\.\d+/\d+' | head -1)
[ -z "$SUBNET" ] && SUBNET="192.168.1.0/24"

echo -e "  ${DIM}Interface :${NC} $IFACE"
echo -e "  ${DIM}IP Address:${NC} ${GREEN}$IP_ADDR${NC}"
echo -e "  ${DIM}Subnet LAN :${NC} $SUBNET"

# Internet check
echo -ne "  ${DIM}Internet  :${NC} "
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "${GREEN}Connected${NC}"
else
    echo -e "${RED}No connection${NC}"
    echo -e "  ${YELLOW}⚠ Pastikan X96Mini terhubung ke internet.${NC}"
fi
echo ""

# === DETEKSI SQUID EXISTING ===
echo -e "${BLUE}${BOLD}━━━ SQUID STATUS ━━━${NC}"

SQUID_INSTALLED=false
SQUID_VERSION=""
SQUID_RUNNING=false
SQUID_LATEST=""

if command -v squid &> /dev/null; then
    SQUID_INSTALLED=true
    SQUID_VERSION=$(squid -v 2>/dev/null | head -1 | grep -oP 'Version \K[0-9.]+')
    if systemctl is-active --quiet squid 2>/dev/null; then
        SQUID_RUNNING=true
    fi
    echo -e "  ${DIM}Terinstal :${NC} Squid ${GREEN}$SQUID_VERSION${NC}"
    echo -e "  ${DIM}Running   :${NC} $([ "$SQUID_RUNNING" = true ] && echo "${GREEN}● Yes${NC}" || echo "${RED}○ No${NC}")"
else
    echo -e "  ${DIM}Terinstal :${NC} ${YELLOW}Belum terinstal${NC}"
fi

# Ambil versi repo
APT_UPDATE_DONE=false

get_latest_version() {
    if [ "$APT_UPDATE_DONE" = false ]; then
        apt update -qq 2>/dev/null
        APT_UPDATE_DONE=true
    fi
    apt-cache policy squid 2>/dev/null | grep Candidate | awk '{print $2}'
}

echo -ne "  ${DIM}Mengecek repo${NC} "
SQUID_LATEST=$(get_latest_version)
echo -e "\r  ${DIM}Repo terbaru:${NC} Squid ${CYAN}$SQUID_LATEST${NC}"

# === MENU AKSI ===
NEED_FRESH=false
DO_INSTALL=true
DO_CONFIGURE=true

if [ "$SQUID_INSTALLED" = true ]; then
    if [ "$SQUID_VERSION" != "$SQUID_LATEST" ] && [ -n "$SQUID_LATEST" ]; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}⚠  Versi squid di system (${SQUID_VERSION}) lebih lama dari repo (${SQUID_LATEST}).${NC}"
        echo ""
        echo -e "  ${BOLD}Pilih tindakan:${NC}"
        echo -e "    ${CYAN}[1]${NC} ${GREEN}Update${NC} Squid ke versi terbaru"
        echo -e "    ${CYAN}[2]${NC} ${RED}Hapus${NC} Squid total dari system"
        echo -e "    ${CYAN}[3]${NC} ${YELLOW}Fresh Install${NC} (hapus + install ulang dengan konfigurasi baru)"
        echo -e "    ${CYAN}[4]${NC} ${DIM}Lewati${NC} — konfigurasi ulang saja, tanpa update"
        echo ""
        read -p "  $(echo -e ${CYAN})▶${NC} Masukkan pilihan [1-4]: " action_choice

        case $action_choice in
            1)
                echo -e "  ${GREEN}→ Update Squid ke versi $SQUID_LATEST...${NC}"
                run_spinner "Mengupdate Squid" apt install --only-upgrade squid -y
                DO_CONFIGURE=true
                ;;
            2)
                echo -e "  ${RED}→ Menghapus Squid...${NC}"
                systemctl stop squid 2>/dev/null || true
                run_spinner "Menghapus Squid" apt remove --purge squid -y
                run_spinner "Membersihkan" apt autoremove -y
                rm -rf /var/spool/squid /var/log/squid
                echo ""
                echo -e "  ${GREEN}${BOLD}✓ Squid berhasil dihapus.${NC}"
                exit 0
                ;;
            3)
                echo -e "  ${YELLOW}→ Fresh Install: menghapus squid lama...${NC}"
                systemctl stop squid 2>/dev/null || true
                run_spinner "Menghapus squid lama" apt remove --purge squid -y
                run_spinner "Membersihkan" apt autoremove -y
                rm -rf /var/spool/squid /var/log/squid /etc/squid/squid.conf
                NEED_FRESH=true
                echo -e "  ${GREEN}→ Menginstall squid baru...${NC}"
                ;;
            4)
                echo -e "  ${DIM}→ Melewati update. Konfigurasi ulang saja.${NC}"
                DO_INSTALL=false
                DO_CONFIGURE=true
                ;;
            *)
                echo -e "  ${RED}Pilihan tidak valid. Melanjutkan dengan konfigurasi ulang.${NC}"
                DO_INSTALL=false
                DO_CONFIGURE=true
                ;;
        esac
    else
        echo -e "  ${GREEN}${BOLD}✓ Squid sudah versi terbaru.${NC}"
        if [ "$SQUID_RUNNING" = true ]; then
            echo -e "  ${GREEN}● Service sudah berjalan.${NC}"
            DO_INSTALL=false
        else
            echo -e "  ${YELLOW}○ Service belum berjalan. Akan di-start.${NC}"
            DO_INSTALL=false
            DO_CONFIGURE=true
        fi
    fi
fi

echo ""

# === INSTALASI ===
STEPS_CONFIG=7

if [ "$DO_INSTALL" = true ] || [ "$NEED_FRESH" = true ]; then
    echo -e "${BLUE}${BOLD}━━━ INSTALLATION ━━━${NC}"
    init_progress 4

    (
        apt install -y squid > /dev/null 2>&1
    ) &
    spinner $! "Menginstall Squid..."
    show_progress "Installasi selesai"
    sleep 0.3

    # Fix: hapus dns_order jika ada dari template lama
    squid -k parse 2>/dev/null | grep -q "unrecognized.*dns_order" && \
        sed -i '/^dns_order/d' /etc/squid/squid.conf 2>/dev/null || true
    show_progress "Validasi konfigurasi"
    sleep 0.3
fi

echo -e "${BLUE}${BOLD}━━━ CONFIGURATION ━━━${NC}"
init_progress $STEPS_CONFIG

# Backup config lama
if [ -f /etc/squid/squid.conf ]; then
    BACKUP_FILE="/etc/squid/squid.conf.bak.$(date +%Y%m%d%H%M%S)"
    cp /etc/squid/squid.conf "$BACKUP_FILE"
    show_progress "Backup config → $BACKUP_FILE"
    sleep 0.2
else
    show_progress "Tidak ada config lama untuk di-backup"
    sleep 0.2
fi

# Tulis konfigurasi baru
show_progress "Menulis konfigurasi baru..."
sleep 0.3
cat > /etc/squid/squid.conf << 'EOF'
# === Auto-generated Squid Config ===
EOF
echo "# LAN: $SUBNET | IP: $IP_ADDR" >> /etc/squid/squid.conf
cat >> /etc/squid/squid.conf << 'EOF'

# ACL subnet lokal
acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10
EOF
echo "acl localnet src $SUBNET" >> /etc/squid/squid.conf
cat >> /etc/squid/squid.conf << 'EOF'

# Port aman
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow localhost
http_access deny to_localhost
http_access deny to_linklocal
http_access allow localnet
http_access deny all

# Port proxy
http_port 3128

# Cache settings
cache_mem 256 MB
maximum_object_size_in_memory 512 KB
minimum_object_size 0 KB
maximum_object_size 64 MB
cache_dir ufs /var/spool/squid 2048 16 256

# DNS
dns_nameservers 1.1.1.1 8.8.8.8

# Performance
memory_replacement_policy heap GDSF
cache_replacement_policy heap LFUDA

# Logging
access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
coredump_dir /var/spool/squid

# Refresh pattern
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
EOF

show_progress "Membuat direktori cache & log"
sleep 0.2
mkdir -p /var/log/squid
chown proxy:proxy /var/log/squid 2>/dev/null || true

show_progress "Inisialisasi cache"
squid -z > /dev/null 2>&1 || true

show_progress "Memulai service Squid"
systemctl restart squid 2>/dev/null || systemctl start squid 2>/dev/null || true

show_progress "Mengaktifkan auto-start"
systemctl enable squid 2>/dev/null || true

show_progress "Firewall: membuka port 3128"
if command -v ufw &> /dev/null; then
    ufw allow 3128/tcp comment 'Squid Proxy' > /dev/null 2>&1 || true
fi

# === FINAL ===
echo ""
echo -e "${BLUE}${BOLD}━━━ VERIFICATION ━━━${NC}"
sleep 1

if systemctl is-active --quiet squid 2>/dev/null; then
    CACHE_DIR_SIZE=$(du -sh /var/spool/squid 2>/dev/null | awk '{print $1}')
    echo -e "  ${GREEN}${BOLD}●${NC} ${GREEN}Service  :${NC} ${BOLD}Running${NC} ${GREEN}✓${NC}"
    echo -e "  ${DIM}  Proxy    :${NC} ${CYAN}http://$IP_ADDR:3128${NC}"
    echo -e "  ${DIM}  Cache    :${NC} $CACHE_DIR_SIZE / 2.0G"
    echo ""

    # Tes proxy lokal
    echo -ne "  ${DIM}  Test     :${NC} "
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --proxy http://127.0.0.1:3128 http://example.com 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo -e "${GREEN}✓ Proxy berfungsi (HTTP $HTTP_CODE)${NC}"
    else
        echo -e "${YELLOW}⚠ Proxy merespon tapi tidak dapat mengakses web (kode: $HTTP_CODE)${NC}"
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}${BOLD}       INSTALASI BERHASIL!${NC}"
    echo -e "  ${GREEN}${BOLD}══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}☕ Setting Proxy di Perangkat Lain:${NC}"
    echo -e "    ${DIM}Address:${NC} ${CYAN}$IP_ADDR${NC}"
    echo -e "    ${DIM}Port   :${NC} ${CYAN}3128${NC}"
    echo ""
    echo -e "  ${BOLD}☕ Perintah Berguna:${NC}"
    echo -e "    ${DIM}Cek status :${NC} sudo systemctl status squid"
    echo -e "    ${DIM}Cek log    :${NC} sudo tail -f /var/log/squid/access.log"
    echo -e "    ${DIM}Restart    :${NC} sudo systemctl restart squid"
    echo -e "    ${DIM}Cek cache  :${NC} sudo squid -k info"
    echo ""
    echo -e "  ${BOLD}☕ Tes dari Windows (PowerShell):${NC}"
    echo -e "    ${DIM}PS >${NC} curl.exe -I --proxy http://$IP_ADDR:3128 https://google.com"
    echo ""
    echo -e "  ${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}  ${YELLOW}Selamat!  X96Mini kamu sekarang${NC}    ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}  ${YELLOW}adalah caching proxy server!${NC}       ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""
else
    echo -e "  ${RED}${BOLD}●${NC} ${RED}Service : GAGAL${NC}"
    echo ""
    echo -e "  ${YELLOW}Diagnosa cepat:${NC}"
    echo -e "    ${DIM}1.${NC} sudo journalctl -u squid --no-pager -n 30"
    echo -e "    ${DIM}2.${NC} sudo squid -N -d1"
    echo -e "    ${DIM}3.${NC} sudo ls -la /var/log/squid/"
    exit 1
fi
