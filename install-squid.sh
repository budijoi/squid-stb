#!/bin/bash
# Squid Caching Proxy Auto-Installer for Armbian
# Repo: https://github.com/budijoi/squid-stb
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
    [ "$CUR_STEP" -eq "$TOTAL_STEPS" ] && echo ""
}

spinner() {
    local pid=$1 msg=$2 spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}%c${NC} %s" "${spin:$i:1}" "$msg"
        i=$(( (i + 1) % 10 ))
        sleep 0.1
    done
    printf "\r${GREEN}✓${NC} %s\n" "$msg"
}

run_spinner() {
    local msg=$1; shift
    ("$@" > /dev/null 2>&1) &
    spinner $! "$msg"
    wait $!
}

# === BANNER ===
clear
echo ""
echo -e "  ${CYAN}╔═══════════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}░▀▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌▀░${NC}  ${BOLD}${YELLOW}SQUID CACHE PROXY${NC}     ${CYAN}║${NC}"
echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}▄█▓▒░SQUID░▒▓█▄${NC}       ${BOLD}${YELLOW}For Armbian${NC}   ${CYAN}║${NC}"
echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}▀▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌▀${NC}  ${BOLD}${YELLOW}by budijoi${NC}        ${CYAN}║${NC}"
echo -e "  ${CYAN}╚═══════════════════════════════════════════╝${NC}"
echo ""

# === SISTEM INFO ===
echo -e "${BLUE}${BOLD}━━━ SYSTEM INFORMATION ━━━${NC}"
echo -e "  ${DIM}Hostname :${NC} $(hostname)"
echo -e "  ${DIM}Kernel   :${NC} $(uname -r)"
echo -e "  ${DIM}Arch     :${NC} $(uname -m)"
echo -e "  ${DIM}Memory   :${NC} $(free -h | awk '/^Mem:/ {print $2}')"
echo -e "  ${DIM}Disk     :${NC} $(df -h / | awk 'NR==2 {print $4}') free"
echo ""

# === PRE-FLIGHT ===
echo -e "${BLUE}${BOLD}━━━ PRE-INSTALL CHECKS ━━━${NC}"

IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
IP_ADDR=$(ip addr show "$IFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
SUBNET=$(ip route 2>/dev/null | grep -oP "${IP_ADDR%.[0-9]*}\.\d+/\d+" | head -1)
[ -z "$SUBNET" ] && SUBNET="$(echo $IP_ADDR | sed 's/\.[0-9]*$/.0\/24/')"

echo -e "  ${DIM}Interface :${NC} $IFACE"
echo -e "  ${DIM}IP Address:${NC} ${GREEN}$IP_ADDR${NC}"
echo -e "  ${DIM}Subnet LAN :${NC} $SUBNET"

echo -ne "  ${DIM}Internet  :${NC} "
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "${GREEN}Connected${NC}"
else
    echo -e "${RED}No connection${NC}"
    echo -e "  ${YELLOW}⚠ Pastikan STB terhubung ke internet.${NC}"
fi
echo ""

# === SQUID STATUS ===
echo -e "${BLUE}${BOLD}━━━ SQUID STATUS ━━━${NC}"

SQUID_INSTALLED=false
SQUID_VERSION=""
SQUID_RUNNING=false
SQUID_LATEST=""

if command -v squid &> /dev/null; then
    SQUID_INSTALLED=true
    SQUID_VERSION=$(squid -v 2>/dev/null | grep -oP 'Version \K[0-9.]+')
    systemctl is-active --quiet squid 2>/dev/null && SQUID_RUNNING=true
    echo -e "  ${DIM}Terinstal :${NC} Squid ${GREEN}$SQUID_VERSION${NC}"
    echo -e "  ${DIM}Running   :${NC} $([ "$SQUID_RUNNING" = true ] && echo "${GREEN}● Yes${NC}" || echo "${RED}○ No${NC}")"
else
    echo -e "  ${DIM}Terinstal :${NC} ${YELLOW}Belum terinstal${NC}"
fi

# Cek versi repo
echo -ne "  ${DIM}Mengecek repo${NC} "
apt update -qq 2>/dev/null
SQUID_LATEST=$(apt-cache show squid 2>/dev/null | grep "^Version:" | head -1 | awk '{print $2}')
sleep 0.3
echo -e "\r  ${DIM}Repo terbaru:${NC} Squid ${CYAN}$SQUID_LATEST${NC}"

# === MENU AKSI ===
NEED_FRESH=false
DO_INSTALL=true

if [ "$SQUID_INSTALLED" = true ]; then
    # Bandingkan versi major.minor.patch
    VER_CUR=$(echo "$SQUID_VERSION" | awk -F. '{printf "%d%03d%03d", $1,$2,$3}')
    VER_REPO=$(echo "$SQUID_LATEST" | awk -F. '{printf "%d%03d%03d", $1,$2,$3}')

    if [ "$VER_CUR" -lt "$VER_REPO" ] 2>/dev/null; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}⚠  Versi squid di system (${SQUID_VERSION}) lebih lama dari repo (${SQUID_LATEST}).${NC}"
        echo ""
        echo -e "  ${BOLD}Pilih tindakan:${NC}"
        echo -e "    ${CYAN}[1]${NC} ${GREEN}Update${NC} Squid ke versi terbaru"
        echo -e "    ${CYAN}[2]${NC} ${RED}Hapus${NC} Squid total dari system"
        echo -e "    ${CYAN}[3]${NC} ${YELLOW}Fresh Install${NC} (hapus + install ulang)"
        echo -e "    ${CYAN}[4]${NC} ${DIM}Lewati${NC} — konfigurasi ulang saja"
        echo ""
        read -p "$(echo -e "  ${CYAN}▶${NC} Masukkan pilihan [1-4]: ")" action_choice

        case $action_choice in
            1)
                echo -e "  ${GREEN}→ Update Squid ke $SQUID_LATEST...${NC}"
                run_spinner "Mengupdate Squid" apt install --only-upgrade squid -y
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
                echo -e "  ${YELLOW}→ Fresh Install...${NC}"
                systemctl stop squid 2>/dev/null || true
                run_spinner "Menghapus squid lama" apt remove --purge squid -y
                run_spinner "Membersihkan" apt autoremove -y
                rm -rf /var/spool/squid /var/log/squid /etc/squid/squid.conf
                NEED_FRESH=true
                ;;
            4|*)
                echo -e "  ${DIM}→ Melewati update.${NC}"
                DO_INSTALL=false
                ;;
        esac
    else
        echo -e "  ${GREEN}${BOLD}✓ Squid sudah versi terbaru.${NC}"
        DO_INSTALL=false
    fi
fi

echo ""

# === INSTALL ===
if [ "$DO_INSTALL" = true ] || [ "$NEED_FRESH" = true ]; then
    echo -e "${BLUE}${BOLD}━━━ INSTALLATION ━━━${NC}"
    run_spinner "Menginstall Squid" apt install -y squid
    echo ""
fi

# === KONFIGURASI ===
echo -e "${BLUE}${BOLD}━━━ CONFIGURATION ━━━${NC}"
init_progress 6

[ -f /etc/squid/squid.conf ] && \
    cp /etc/squid/squid.conf "/etc/squid/squid.conf.bak.$(date +%Y%m%d%H%M%S)"
show_progress "Backup config"

show_progress "Menulis konfigurasi baru"

cat > /etc/squid/squid.conf << EOF
# === Auto-generated Squid Config ===
# Repo: https://github.com/budijoi/squid-stb
# LAN: $SUBNET | IP: $IP_ADDR

acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src $SUBNET
acl localnet src fc00::/7
acl localnet src fe80::/10

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

http_port 3128

cache_mem 256 MB
maximum_object_size_in_memory 512 KB
minimum_object_size 0 KB
maximum_object_size 64 MB
cache_dir ufs /var/spool/squid 2048 16 256

memory_replacement_policy heap GDSF
cache_replacement_policy heap LFUDA

access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
coredump_dir /var/spool/squid

refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
EOF

show_progress "Membuat direktori cache & log"
mkdir -p /var/log/squid
chown proxy:proxy /var/log/squid 2>/dev/null || true

show_progress "Inisialisasi cache"
squid -z > /dev/null 2>&1 || true

show_progress "Memulai service"
systemctl restart squid 2>/dev/null || systemctl start squid 2>/dev/null || true
systemctl enable squid 2>/dev/null || true

show_progress "Firewall port 3128"
if command -v ufw &> /dev/null; then
    ufw allow 3128/tcp comment 'Squid Proxy' > /dev/null 2>&1 || true
fi

# === VERIFIKASI ===
echo ""
echo -e "${BLUE}${BOLD}━━━ VERIFICATION ━━━${NC}"
sleep 1

if systemctl is-active --quiet squid 2>/dev/null; then
    CACHE_SIZE=$(du -sh /var/spool/squid 2>/dev/null | awk '{print $1}')
    echo -e "  ${GREEN}${BOLD}●${NC} ${GREEN}Service  :${NC} ${BOLD}Running${NC} ${GREEN}✓${NC}"
    echo -e "  ${DIM}  Proxy    :${NC} ${CYAN}http://$IP_ADDR:3128${NC}"
    echo -e "  ${DIM}  Cache    :${NC} $CACHE_SIZE / 2.0G"

    echo -ne "  ${DIM}  Test     :${NC} "
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --proxy http://127.0.0.1:3128 http://example.com 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "304" ]; then
        echo -e "${GREEN}✓ Proxy OK (HTTP $HTTP_CODE)${NC}"
    else
        echo -e "${YELLOW}⚠ Proxy respon ${HTTP_CODE} — cek log: sudo journalctl -u squid -n 20${NC}"
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}${BOLD}       INSTALASI BERHASIL!${NC}"
    echo -e "  ${GREEN}${BOLD}══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Setting Proxy di Perangkat Lain:${NC}"
    echo -e "    ${DIM}Address:${NC} ${CYAN}$IP_ADDR${NC}   ${DIM}Port:${NC} ${CYAN}3128${NC}"
    echo ""
    echo -e "  ${BOLD}Perintah:${NC}"
    echo -e "    ${DIM}Status :${NC} sudo systemctl status squid"
    echo -e "    ${DIM}Log    :${NC} sudo tail -f /var/log/squid/access.log"
    echo -e "    ${DIM}Restart:${NC} sudo systemctl restart squid"
    echo ""
    echo -e "  ${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}  ${YELLOW}STB sekarang adalah${NC}           ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}  ${YELLOW}caching proxy server!${NC}              ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo ""
else
    echo -e "  ${RED}${BOLD}●${NC} ${RED}Service : GAGAL${NC}"
    echo ""
    echo -e "  ${YELLOW}Diagnosa:${NC}"
    echo -e "    ${DIM}1.${NC} sudo journalctl -u squid --no-pager -n 30"
    echo -e "    ${DIM}2.${NC} sudo squid -N -d1"
    exit 1
fi
