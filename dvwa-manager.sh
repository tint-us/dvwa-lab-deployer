
#!/bin/bash

# ============================================================
#  DVWA Lab Manager v2
#  Deploy & reset multiple DVWA + MariaDB instances
#  TinyFileManager di-inject ke web root DVWA (file.php)
#  Optimized for Rocky / Alma Linux (Container Permission Fix)
# ============================================================

set -uo pipefail

# --- Config ---
DVWA_IMAGE="ghcr.io/digininja/dvwa:latest"
DB_IMAGE="mariadb:10.11"
TFM_URL="https://raw.githubusercontent.com/prasathmani/tinyfilemanager/master/tinyfilemanager.php"
BASE_PORT_DVWA=8101
NETWORK_NAME="dvwa-lab-network"
DVWA_PREFIX="dvwa-lab"
DB_PREFIX="dvwa-db"
VOL_PREFIX="dvwa-vol"
DB_VOL_PREFIX="dvwa-db-vol"
DB_ROOT_PASS="dvwaroot"
DB_USER="dvwa"
DB_PASS="p@ssw0rd"
DB_NAME="dvwa"
TFM_USER="file"
TFM_PASS="RahasiaFile"
TFM_FILENAME="file.php"
TZ="Asia/Jakarta"
LOG_FILE="/var/log/dvwa-manager.log"
LOG_MAX_SIZE_MB=50

# TinyFileManager disimpan sementara di host sebelum di-inject
TFM_HOST_PATH="/opt/dvwa-lab/file.php"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
# LOGGING
# ============================================================

log_init() {
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 640 "$LOG_FILE"
    fi
    local size_mb
    size_mb=$(du -m "$LOG_FILE" 2>/dev/null | awk '{print $1}')
    if (( size_mb >= LOG_MAX_SIZE_MB )); then
        local rotated="${LOG_FILE}.$(date +%Y%m%d_%H%M%S).old"
        mv "$LOG_FILE" "$rotated"
        touch "$LOG_FILE"
        chmod 640 "$LOG_FILE"
        log "INFO" "Log dirotate ke $rotated"
    fi
}

log() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${FUNCNAME[1]:-main}"
    printf '[%s] [%-6s] [%s] %s\n' "$ts" "$level" "$caller" "$msg" >> "$LOG_FILE"
}

log_info()   { log "INFO"   "$1"; echo -e "${CYAN}$1${NC}"; }
log_ok()     { log "OK"     "$1"; echo -e "${GREEN}OK: $1${NC}"; }
log_warn()   { log "WARN"   "$1"; echo -e "${YELLOW}WARN: $1${NC}"; }
log_error()  { log "ERROR"  "$1"; echo -e "${RED}ERROR: $1${NC}"; }
log_action() { log "ACTION" "$1"; echo -e "${BOLD}$1${NC}"; }
log_step()   { log "STEP"   "$1"; echo -e "   $1"; }

# ============================================================
# HELPERS
# ============================================================

print_banner() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║           DVWA Lab Manager v2                          ║"
    echo "║   Security Awareness Training - Lab Deployer           ║"
    echo "║   DVWA + MariaDB + TinyFileManager (file.php)          ║"
    echo "║   Rocky / Alma Linux                                   ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────────${NC}"
}

confirm() {
    local prompt="$1"
    local answer
    echo -e "${YELLOW}PERHATIAN: $prompt${NC}"
    read -rp "   Ketik 'yes' untuk lanjut: " answer
    log "INFO" "Konfirmasi: '$prompt' — jawaban: '$answer'"
    [[ "$answer" == "yes" ]]
}

# ============================================================
# GET VM IP
# ============================================================

get_vm_ip() {
    local ip
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [[ -z "$ip" ]]; then
        ip="<IP_VM>"
    fi
    echo "$ip"
}

# ============================================================
# DOCKER SETUP
# ============================================================

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}Script ini harus dijalankan sebagai root (sudo ./dvwa-manager-v2.sh)${NC}"
        exit 1
    fi
}

setup_docker() {
    print_separator
    log_action "CEK & SETUP DOCKER"
    print_separator

    if command -v docker &>/dev/null; then
        local ver
        ver=$(docker --version 2>/dev/null)
        log_ok "Docker sudah terinstall: $ver"
    else
        log_warn "Docker belum ada, install sekarang..."
        dnf -y install dnf-plugins-core > /dev/null 2>&1
        dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo > /dev/null 2>&1
        dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null 2>&1
        log_ok "Docker berhasil diinstall."
    fi

    if ! systemctl is-active --quiet docker; then
        log_warn "Docker service belum aktif, menjalankan..."
        systemctl enable docker --now > /dev/null 2>&1
        log_ok "Docker service aktif."
    else
        log_ok "Docker service sudah running."
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker daemon tidak merespons. Cek: systemctl status docker"
        exit 1
    fi

    log "INFO" "Docker version: $(docker info --format '{{.ServerVersion}}' 2>/dev/null)"
}

# ============================================================
# FIREWALLD & SELINUX MANAGEMENT
# ============================================================

setup_firewalld_ports() {
    local dvwa_start="$1"
    local count="$2"
    local dvwa_end=$((dvwa_start + count - 1))

    print_separator
    log_action "CEK FIREWALLD"
    print_separator

    if ! command -v firewall-cmd &>/dev/null; then
        log_warn "firewalld tidak ditemukan, skip."
        return
    fi

    if ! systemctl is-active --quiet firewalld; then
        log_warn "firewalld tidak aktif, skip."
        return
    fi

    local ports_open=true
    for port in $(seq "$dvwa_start" "$dvwa_end"); do
        if ! firewall-cmd --query-port="${port}/tcp" --quiet 2>/dev/null; then
            ports_open=false; break
        fi
    done

    if $ports_open; then
        log_ok "Port $dvwa_start-$dvwa_end sudah terbuka."
    else
        log "STEP" "Membuka port $dvwa_start-$dvwa_end"
        firewall-cmd --permanent --add-port="${dvwa_start}-${dvwa_end}/tcp" > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_ok "Port $dvwa_start-$dvwa_end dibuka."
    fi
}

close_firewalld_ports() {
    local dvwa_start="$1"
    local count="$2"
    local dvwa_end=$((dvwa_start + count - 1))

    if ! command -v firewall-cmd &>/dev/null; then return; fi
    if ! systemctl is-active --quiet firewalld; then return; fi

    log_info "Menutup port di firewalld..."
    firewall-cmd --permanent --remove-port="${dvwa_start}-${dvwa_end}/tcp" > /dev/null 2>&1 || true
    firewall-cmd --reload > /dev/null 2>&1
    log_ok "Port $dvwa_start-$dvwa_end ditutup."
}

check_selinux() {
    print_separator
    log_action "CEK & DISABLE SELINUX PERMANEN"
    print_separator

    if ! command -v getenforce &>/dev/null; then
        log_warn "SELinux tools tidak ditemukan, skip."
        return
    fi

    local selinux_status
    selinux_status=$(getenforce 2>/dev/null || echo "Unknown")
    log "INFO" "SELinux status saat ini: $selinux_status"

    if [[ "$selinux_status" != "Disabled" ]]; then
        log_warn "SELinux terdeteksi aktif ($selinux_status). Menonaktifkan secara permanen..."
        setenforce 0 2>/dev/null || true
        
        if [[ -f /etc/selinux/config ]]; then
            sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
            log_ok "Konfigurasi /etc/selinux/config telah diubah ke 'disabled'."
        fi
    else
        log_ok "SELinux sudah berstatus Disabled (Aman)."
    fi
}

# ============================================================
# PREPARE TINYFILEMANAGER
# ============================================================

prepare_tinyfilemanager() {
    print_separator
    log_action "PERSIAPAN TINYFILEMANAGER"
    print_separator

    mkdir -p "$(dirname "$TFM_HOST_PATH")"

    # Download jika belum ada
    if [[ ! -f "$TFM_HOST_PATH" ]]; then
        log_info "Download TinyFileManager dari GitHub..."
        if command -v curl &>/dev/null; then
            curl -fsSL "$TFM_URL" -o "$TFM_HOST_PATH" 2>/dev/null
        elif command -v wget &>/dev/null; then
            wget -q "$TFM_URL" -O "$TFM_HOST_PATH" 2>/dev/null
        else
            log_error "curl atau wget tidak ditemukan. Install salah satu dulu."
            exit 1
        fi
        log_ok "TinyFileManager berhasil didownload."
    else
        log_ok "TinyFileManager sudah ada di $TFM_HOST_PATH"
    fi

    # Inject credentials — generate password hash & patch file
    log_info "Meng-inject credentials ke TinyFileManager..."

    # Generate bcrypt hash untuk password
    local pass_hash
    if command -v php &>/dev/null; then
        pass_hash=$(php -r "echo password_hash('${TFM_PASS}', PASSWORD_DEFAULT);")
    else
        log_warn "PHP tidak ada, install php-cli untuk generate hash..."
        dnf install -y php-cli > /dev/null 2>&1 || true
        pass_hash=$(php -r "echo password_hash('${TFM_PASS}', PASSWORD_DEFAULT);")
    fi

    if [[ -z "$pass_hash" ]]; then
        log_error "Gagal generate password hash."
        exit 1
    fi

    log "INFO" "Password hash generated untuk user: $TFM_USER"

    # Patch $auth_users di tinyfilemanager.php
    python3 - << PYEOF
import re

with open('${TFM_HOST_PATH}', 'r') as f:
    content = f.read()

new_auth = r"""\$auth_users = array(
    '${TFM_USER}' => '${pass_hash}',
);"""

pattern = r'\\\$auth_users\s*=\s*array\s*\(.*?\);'
content = re.sub(pattern, new_auth.replace('\\\\', '\\\\\\\\'), content, flags=re.DOTALL)

content = re.sub(
    r'\\\$readonly_users\s*=\s*array\s*\(.*?\);',
    '\$readonly_users = array();',
    content,
    flags=re.DOTALL
)

with open('${TFM_HOST_PATH}', 'w') as f:
    f.write(content)

print("OK")
PYEOF

    if [[ $? -eq 0 ]]; then
        log_ok "Credentials berhasil di-inject ke TinyFileManager."
    else
        log_error "Gagal patch TinyFileManager."
        exit 1
    fi
}

# ============================================================
# DOCKER NETWORK & IMAGES
# ============================================================

ensure_network() {
    if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
        log_info "Membuat Docker network: ${NETWORK_NAME}"
        docker network create "$NETWORK_NAME" > /dev/null
        log_ok "Network $NETWORK_NAME dibuat."
    else
        log "INFO" "Network $NETWORK_NAME sudah ada."
    fi
}

pull_images() {
    log_info "Pulling DVWA image: $DVWA_IMAGE"
    docker pull "$DVWA_IMAGE"
    log_info "Pulling MariaDB image: $DB_IMAGE"
    docker pull "$DB_IMAGE"
    log_ok "Semua image siap."
}

# ============================================================
# INSTANCE HELPERS
# ============================================================

get_all_dvwa() {
    docker ps -a --filter "name=${DVWA_PREFIX}-" --format "{{.Names}}" 2>/dev/null \
        | grep -E "^${DVWA_PREFIX}-[0-9]+$" | sort -t'-' -k3 -n || true
}

get_running_dvwa() {
    docker ps --filter "name=${DVWA_PREFIX}-" --format "{{.Names}}" 2>/dev/null \
        | grep -E "^${DVWA_PREFIX}-[0-9]+$" | sort -t'-' -k3 -n || true
}

get_dvwa_base_port() {
    docker inspect "${DVWA_PREFIX}-1" \
        --format='{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}}{{end}}' \
        2>/dev/null || echo "$BASE_PORT_DVWA"
}

# ============================================================
# DEPLOY SINGLE PAIR (MariaDB + DVWA dengan file.php)
# ============================================================

deploy_pair() {
    local i="$1"
    local dvwa_port="$2"
    local vm_ip="$3"

    local dvwa_name="${DVWA_PREFIX}-${i}"
    local db_name="${DB_PREFIX}-${i}"
    local vol_name="${VOL_PREFIX}-${i}"
    local db_vol_name="${DB_VOL_PREFIX}-${i}"

    # Buat volumes
    log "STEP" "[$i] Membuat volumes"
    docker volume create "$vol_name"    > /dev/null 2>&1
    docker volume create "$db_vol_name" > /dev/null 2>&1

    # --- 1. Deploy MariaDB ---
    log "STEP" "[$i] Deploy MariaDB: $db_name"
    if ! docker run -d \
        --name "$db_name" \
        --network "$NETWORK_NAME" \
        -v "${db_vol_name}:/var/lib/mysql" \
        -e "MYSQL_ROOT_PASSWORD=${DB_ROOT_PASS}" \
        -e "MYSQL_DATABASE=${DB_NAME}" \
        -e "MYSQL_USER=${DB_USER}" \
        -e "MYSQL_PASSWORD=${DB_PASS}" \
        -e "TZ=${TZ}" \
        --restart unless-stopped \
        "$DB_IMAGE" > /dev/null 2>&1; then
        log "ERROR" "[$i] MariaDB gagal deploy"
        echo -e "   ${RED}Peserta $i — MariaDB gagal${NC}"
        return 1
    fi
    log "OK" "[$i] MariaDB up: $db_name"

    # Tunggu MariaDB ready
    log "STEP" "[$i] Menunggu MariaDB ready..."
    local attempts=0
    until docker exec "$db_name" mariadb-admin ping -u root -p"${DB_ROOT_PASS}" --silent 2>/dev/null; do
        ((attempts++))
        if (( attempts >= 30 )); then
            log "ERROR" "[$i] MariaDB timeout setelah 30 detik"
            echo -e "   ${RED}Peserta $i — MariaDB timeout${NC}"
            docker rm -f "$db_name" > /dev/null 2>&1 || true
            return 1
        fi
        sleep 1
    done
    log "OK" "[$i] MariaDB ready setelah ${attempts}s"

    # --- 2. Deploy DVWA (Tanpa bind mount file.php di runtime docker run) ---
    log "STEP" "[$i] Deploy DVWA: $dvwa_name port $dvwa_port"
    if ! docker run -d \
        --name "$dvwa_name" \
        --network "$NETWORK_NAME" \
        -p "0.0.0.0:${dvwa_port}:80" \
        -v "${vol_name}:/var/www/html" \
        -e "DB_SERVER=${db_name}" \
        -e "DB_DATABASE=${DB_NAME}" \
        -e "DB_USER=${DB_USER}" \
        -e "DB_PASSWORD=${DB_PASS}" \
        -e "DB_PORT=3306" \
        -e "TZ=${TZ}" \
        --restart unless-stopped \
        "$DVWA_IMAGE" > /dev/null 2>&1; then
        log "ERROR" "[$i] DVWA gagal deploy"
        echo -e "   ${RED}Peserta $i — DVWA gagal${NC}"
        docker rm -f "$db_name" > /dev/null 2>&1 || true
        return 1
    fi

    # --- 3. INJEKSI FILE DARI DALAM CONTAINER (Solusi Hak Akses POSIX) ---
    log "STEP" "[$i] Meng-copy file.php langsung ke dalam volume kontainer..."
    docker cp "$TFM_HOST_PATH" "${dvwa_name}:/var/www/html/${TFM_FILENAME}"
    
    log "STEP" "[$i] Memperbaiki kepemilikan user www-data di dalam kontainer..."
    docker exec -u 0 "$dvwa_name" chown www-data:www-data "/var/www/html/${TFM_FILENAME}"
    docker exec -u 0 "$dvwa_name" chmod 644 "/var/www/html/${TFM_FILENAME}"

    log "OK" "[$i] DVWA & TinyFileManager up: $dvwa_name port $dvwa_port"

    echo -e "   ${GREEN}Peserta $i${NC}"
    echo -e "      DVWA        : http://${vm_ip}:${dvwa_port}/           (admin / password)"
    echo -e "      FileManager : http://${vm_ip}:${dvwa_port}/file.php   (${TFM_USER} / ${TFM_PASS})"
    return 0
}

# ============================================================
# DESTROY SINGLE PAIR
# ============================================================

destroy_pair() {
    local i="$1"
    local keep_volume="${2:-false}"

    local dvwa_name="${DVWA_PREFIX}-${i}"
    local db_name="${DB_PREFIX}-${i}"
    local vol_name="${VOL_PREFIX}-${i}"
    local db_vol_name="${DB_VOL_PREFIX}-${i}"

    log "STEP" "[$i] Menghapus containers"
    docker rm -f "$dvwa_name" > /dev/null 2>&1 || true
    docker rm -f "$db_name"   > /dev/null 2>&1 || true

    if [[ "$keep_volume" == "false" ]]; then
        log "STEP" "[$i] Menghapus volumes"
        docker volume rm "$vol_name"    > /dev/null 2>&1 || true
        docker volume rm "$db_vol_name" > /dev/null 2>&1 || true
    fi
}

# ============================================================
# MENU: DEPLOY
# ============================================================

action_deploy() {
    print_separator
    log_action "DEPLOY DVWA + MARIADB INSTANCES"
    print_separator

    local existing
    existing=$(get_all_dvwa)
    if [[ -n "$existing" ]]; then
        local n
        n=$(echo "$existing" | grep -c . || true)
        log_warn "Ada $n instance yang sudah ada. Gunakan Reset atau Destroy dulu."
        return
    fi

    local count
    while true; do
        read -rp "$(echo -e "${BOLD}Mau deploy berapa instance? ${NC}")" count
        if [[ "$count" =~ ^[1-9][0-9]*$ ]] && (( count <= 100 )); then
            break
        fi
        echo -e "${RED}Input angka 1-100 ya.${NC}"
    done

    local base_dvwa
    read -rp "$(echo -e "${BOLD}Base port DVWA? (default: ${BASE_PORT_DVWA}): ${NC}")" base_dvwa
    base_dvwa=${base_dvwa:-$BASE_PORT_DVWA}
    [[ "$base_dvwa" =~ ^[0-9]+$ ]] || base_dvwa=$BASE_PORT_DVWA

    local vm_ip
    vm_ip=$(get_vm_ip)

    log "ACTION" "Deploy: $count instance, port $base_dvwa-$((base_dvwa+count-1)), IP $vm_ip"

    print_separator
    echo -e "${CYAN}Summary deploy:${NC}"
    echo "   Jumlah instance  : $count"
    echo "   Port range       : $base_dvwa - $((base_dvwa + count - 1))"
    echo "   VM IP            : $vm_ip"
    echo "   Akses DVWA       : http://${vm_ip}:<port>/"
    echo "   Akses FileManager: http://${vm_ip}:<port>/file.php"
    echo "   Timezone         : $TZ"
    print_separator

    confirm "Deploy $count instance sekarang?" || {
        log "INFO" "Deploy dibatalkan"
        echo "Dibatalkan."
        return
    }

    setup_docker
    check_selinux
    setup_firewalld_ports "$base_dvwa" "$count"
    ensure_network
    pull_images
    prepare_tinyfilemanager

    echo ""
    log_action "Menjalankan containers..."
    echo ""

    local success=0
    local fail=0

    for i in $(seq 1 "$count"); do
        local dvwa_port=$((base_dvwa + i - 1))
        if deploy_pair "$i" "$dvwa_port" "$vm_ip"; then
            ((success++))
        else
            ((fail++))
        fi
    done

    echo ""
    print_separator
    log_ok "Deploy selesai. Berhasil: $success / Gagal: $fail dari $count instance."
    [[ $fail -gt 0 ]] && log_error "Gagal: $fail instance"
    print_separator
    echo ""
    echo -e "${YELLOW}Tips peserta:${NC}"
    echo "  ┌──────────────┬───────────────────────────────────────────────────┐"
    echo "  │ DVWA         │ Login: admin / password                           │"
    echo "  │              │ Lalu: Setup DVWA > Create/Reset Database          │"
    echo "  ├──────────────┼───────────────────────────────────────────────────┤"
    echo "  │ File Manager │ Akses: http://<IP>:<port>/file.php                │"
    echo "  │              │ Login: ${TFM_USER} / ${TFM_PASS}                          │"
    echo "  └──────────────┴───────────────────────────────────────────────────┘"
}

# ============================================================
# MENU: STATUS
# ============================================================

action_status() {
    print_separator
    log_action "STATUS INSTANCES"
    print_separator

    local all
    all=$(get_all_dvwa)

    if [[ -z "$all" ]]; then
        log_warn "Belum ada instance yang di-deploy."
        return
    fi

    local vm_ip
    vm_ip=$(get_vm_ip)

    printf "   %-5s %-10s %-10s %-35s %-35s\n" \
        "NO" "DVWA" "MariaDB" "DVWA URL" "FileManager URL"
    echo "   ──────────────────────────────────────────────────────────────────────────────────────────"

    local running_count=0
    local total_count=0

    while IFS= read -r dvwa_name; do
        local i
        i=$(echo "$dvwa_name" | grep -oE '[0-9]+$')
        local db_name="${DB_PREFIX}-${i}"
        ((total_count++))

        local dvwa_status db_status dvwa_port
        dvwa_status=$(docker inspect "$dvwa_name" --format='{{.State.Status}}' 2>/dev/null || echo "?")
        db_status=$(docker inspect   "$db_name"   --format='{{.State.Status}}' 2>/dev/null || echo "?")
        dvwa_port=$(docker inspect "$dvwa_name" \
            --format='{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}}{{end}}' \
            2>/dev/null || echo "?")

        log "INFO" "Instance $i — DVWA: $dvwa_status ($dvwa_port) | DB: $db_status"
        [[ "$dvwa_status" == "running" ]] && ((running_count++))

        local dc dbc
        [[ "$dvwa_status" == "running" ]] && dc=$GREEN || dc=$RED
        [[ "$db_status"   == "running" ]] && dbc=$GREEN || dbc=$RED

        printf "   %-5s " "$i"
        echo -ne "${dc}$(printf '%-10s' "$dvwa_status")${NC} "
        echo -ne "${dbc}$(printf '%-10s' "$db_status")${NC} "
        printf "%-35s %-35s\n" \
            "http://${vm_ip}:${dvwa_port}/" \
            "http://${vm_ip}:${dvwa_port}/file.php"
    done <<< "$all"

    echo ""
    echo -e "   ${GREEN}DVWA Running: $running_count${NC} / Total: $total_count"
    log "INFO" "Status: $running_count running dari $total_count total"
}

# ============================================================
# MENU: RESET
# ============================================================

action_reset() {
    print_separator
    log_action "RESET SEMUA INSTANCES (Ganti Batch)"
    print_separator

    local all
    all=$(get_all_dvwa)

    if [[ -z "$all" ]]; then
        log_warn "Tidak ada instance untuk di-reset."
        return
    fi

    local count
    count=$(echo "$all" | grep -c . || true)
    local base_dvwa
    base_dvwa=$(get_dvwa_base_port)
    local vm_ip
    vm_ip=$(get_vm_ip)

    log "ACTION" "Reset: $count instance"

    echo -e "${CYAN}Akan reset $count instance (DVWA + MariaDB + volumes):${NC}"
    echo -e "${YELLOW}Semua data peserta (DB + file DVWA) akan terhapus. Fresh start.${NC}"
    echo ""

    confirm "Reset $count instance untuk batch berikutnya?" || {
        log "INFO" "Reset dibatalkan"
        echo "Dibatalkan."
        return
    }

    echo ""
    log_info "Menghapus containers & volumes lama..."
    for i in $(seq 1 "$count"); do
        destroy_pair "$i" "false"
        log_step "Peserta $i — dihapus"
    done

    echo ""
    log_info "Deploy ulang $count instance..."
    echo ""

    local success=0
    local fail=0

    for i in $(seq 1 "$count"); do
        local dvwa_port=$((base_dvwa + i - 1))
        if deploy_pair "$i" "$dvwa_port" "$vm_ip"; then
            ((success++))
        else
            ((fail++))
        fi
    done

    echo ""
    print_separator
    log_ok "Reset selesai! $success instance siap untuk batch berikutnya."
    [[ $fail -gt 0 ]] && log_error "Gagal redeploy: $fail instance"
    echo -e "${YELLOW}Remind peserta baru: DVWA > Setup DVWA > Create/Reset Database${NC}"
    print_separator
}

# ============================================================
# MENU: TAMBAH INSTANCE
# ============================================================

action_add_instances() {
    print_separator
    log_action "TAMBAH INSTANCE BARU"
    print_separator

    local all
    all=$(get_all_dvwa)

    if [[ -z "$all" ]]; then
        log_warn "Belum ada instance. Gunakan menu Deploy untuk mulai dari awal."
        return
    fi

    local last_i
    last_i=$(echo "$all" | grep -oE '[0-9]+$' | sort -n | tail -1)
    local base_dvwa
    base_dvwa=$(get_dvwa_base_port)
    local next_i=$((last_i + 1))
    local vm_ip
    vm_ip=$(get_vm_ip)
    local existing_count
    existing_count=$(echo "$all" | grep -c . || true)

    echo -e "${CYAN}Instance saat ini : $existing_count (terakhir: peserta $last_i)${NC}"
    echo -e "${CYAN}Instance baru mulai dari: peserta $next_i${NC}"
    echo ""

    local add_count
    while true; do
        read -rp "$(echo -e "${BOLD}Tambah berapa instance? ${NC}")" add_count
        if [[ "$add_count" =~ ^[1-9][0-9]*$ ]] && (( add_count <= 100 )); then
            break
        fi
        echo -e "${RED}Input angka 1-100 ya.${NC}"
    done

    local last_new_i=$((last_i + add_count))
    local new_start_port=$((base_dvwa + last_i))
    local new_end_port=$((base_dvwa + last_new_i - 1))

    print_separator
    echo -e "${CYAN}Summary tambah instance:${NC}"
    echo "   Instance baru   : peserta $next_i s/d $last_new_i ($add_count instance)"
    echo "   Port baru       : $new_start_port - $new_end_port"
    echo "   Instance lama   : tetap jalan, tidak terganggu"
    print_separator

    confirm "Tambah $add_count instance baru (peserta $next_i-$last_new_i)?" || {
        log "INFO" "Tambah instance dibatalkan"
        echo "Dibatalkan."
        return
    }

    log "ACTION" "Tambah $add_count instance: peserta $next_i-$last_new_i"
    setup_firewalld_ports "$new_start_port" "$add_count"

    echo ""
    log_action "Menjalankan containers baru..."
    echo ""

    local success=0
    local fail=0

    for i in $(seq "$next_i" "$last_new_i"); do
        local dvwa_port=$((base_dvwa + i - 1))

        if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${DVWA_PREFIX}-${i}$"; then
            log_warn "Peserta $i sudah ada, skip."
            continue
        fi

        if deploy_pair "$i" "$dvwa_port" "$vm_ip"; then
            ((success++))
        else
            ((fail++))
        fi
    done

    echo ""
    print_separator
    log_ok "Tambah instance selesai. Berhasil: $success / Gagal: $fail"
    [[ $fail -gt 0 ]] && log_error "Gagal: $fail instance"
    echo -e "${CYAN}Total instance aktif sekarang: $((existing_count + success))${NC}"
    print_separator
}

# ============================================================
# MENU: START ALL
# ============================================================

action_start() {
    print_separator
    log_action "START SEMUA INSTANCES"
    print_separator

    local all
    all=$(get_all_dvwa)

    if [[ -z "$all" ]]; then
        log_warn "Tidak ada instance. Deploy dulu."
        return
    fi

    while IFS= read -r dvwa_name; do
        local i
        i=$(echo "$dvwa_name" | grep -oE '[0-9]+$')
        local db_name="${DB_PREFIX}-${i}"

        for cname in "$db_name" "$dvwa_name"; do
            local st
            st=$(docker inspect "$cname" --format='{{.State.Status}}' 2>/dev/null || echo "?")
            if [[ "$st" != "running" ]]; then
                docker start "$cname" > /dev/null 2>&1 \
                    && { log "OK" "[$i] $cname started"; echo -e "   ${GREEN}$cname started${NC}"; } \
                    || { log "ERROR" "[$i] Gagal start $cname"; echo -e "   ${RED}Gagal start $cname${NC}"; }
            else
                echo -e "   ${CYAN}$cname sudah running${NC}"
            fi
        done
    done <<< "$all"

    log_ok "Start selesai."
}

# ============================================================
# MENU: STOP ALL
# ============================================================

action_stop() {
    print_separator
    log_action "STOP SEMUA INSTANCES"
    print_separator

    local running
    running=$(get_running_dvwa)

    if [[ -z "$running" ]]; then
        log_warn "Tidak ada instance yang sedang running."
        return
    fi

    confirm "Stop semua DVWA + MariaDB containers?" || {
        log "INFO" "Stop dibatalkan"
        echo "Dibatalkan."
        return
    }

    while IFS= read -r dvwa_name; do
        local i
        i=$(echo "$dvwa_name" | grep -oE '[0-9]+$')
        local db_name="${DB_PREFIX}-${i}"

        for cname in "$dvwa_name" "$db_name"; do
            docker stop "$cname" > /dev/null 2>&1 \
                && { log "OK" "[$i] $cname stopped"; echo -e "   ${YELLOW}$cname stopped${NC}"; } \
                || log "WARN" "[$i] Gagal stop $cname"
        done
    done <<< "$running"

    log_ok "Semua instance dihentikan."
}

# ============================================================
# MENU: DESTROY ALL
# ============================================================

action_destroy() {
    print_separator
    log_action "DESTROY SEMUA INSTANCES"
    print_separator

    local all
    all=$(get_all_dvwa)

    if [[ -z "$all" ]]; then
        log_warn "Tidak ada instance untuk dihapus."
        return
    fi

    local count
    count=$(echo "$all" | grep -c . || true)
    local base_dvwa
    base_dvwa=$(get_dvwa_base_port)

    log "ACTION" "Destroy: $count instance"

    echo -e "${RED}Yang akan DIHAPUS PERMANEN ($count instance):${NC}"
    echo "   DVWA containers    (${DVWA_PREFIX}-1 s/d ${DVWA_PREFIX}-${count})"
    echo "   MariaDB containers (${DB_PREFIX}-1 s/d ${DB_PREFIX}-${count})"
    echo "   Semua volumes"
    echo ""

    confirm "HAPUS PERMANEN semua containers & volumes? (tidak bisa di-undo)" || {
        log "INFO" "Destroy dibatalkan"
        echo "Dibatalkan."
        return
    }

    for i in $(seq 1 "$count"); do
        destroy_pair "$i" "false"
        echo -e "   ${RED}Peserta $i dihapus${NC}"
    done

    close_firewalld_ports "$base_dvwa" "$count"
    log_ok "Semua instance & volume dihapus, port firewall ditutup."
}

# ============================================================
# MENU: LIHAT LOG
# ============================================================

action_view_log() {
    print_separator
    log_action "LOG VIEWER"
    print_separator

    if [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${YELLOW}File log belum ada: $LOG_FILE${NC}"
        return
    fi

    local total_lines
    total_lines=$(wc -l < "$LOG_FILE")
    echo -e "${CYAN}Log file : $LOG_FILE${NC}"
    echo -e "${CYAN}Total    : $total_lines baris${NC}"
    echo ""
    echo "  [1] Lihat 50 baris terakhir"
    echo "  [2] Lihat 100 baris terakhir"
    echo "  [3] Filter ERROR saja"
    echo "  [4] Filter WARN saja"
    echo "  [5] Filter ACTION saja (ringkasan aktivitas)"
    echo "  [6] Lihat semua (less)"
    echo "  [b] Kembali"
    echo ""
    read -rp "$(echo -e "${BOLD}Pilih: ${NC}")" log_choice

    case "$log_choice" in
        1) tail -50 "$LOG_FILE" ;;
        2) tail -100 "$LOG_FILE" ;;
        3) grep '\[ERROR \]' "$LOG_FILE" || echo "Tidak ada error." ;;
        4) grep '\[WARN  \]' "$LOG_FILE" || echo "Tidak ada warning." ;;
        5) grep '\[ACTION\]' "$LOG_FILE" || echo "Tidak ada action." ;;
        6) less "$LOG_FILE" ;;
        b|B) return ;;
        *) echo -e "${RED}Pilihan tidak valid.${NC}" ;;
    esac
}

# ============================================================
# MAIN MENU LOOP
# ============================================================

main() {
    check_root
    log_init
    log "INFO" "===== DVWA Lab Manager v2 dijalankan (PID $$, user: $(whoami)) ====="
    log "INFO" "VM IP: $(get_vm_ip)"
    log "INFO" "Script version: $(date -r "$0" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown')"

    print_banner

    local vm_ip
    vm_ip=$(get_vm_ip)
    echo -e "   ${CYAN}VM IP terdeteksi : ${BOLD}${vm_ip}${NC}"
    echo -e "   ${CYAN}Port mapping     : DVWA ${BASE_PORT_DVWA}+${NC}"
    echo -e "   ${CYAN}Stack            : MariaDB + DVWA per peserta${NC}"
    echo -e "   ${CYAN}FileManager      : http://<IP>:<port>/file.php${NC}"
    echo -e "   ${CYAN}Timezone         : ${TZ}${NC}"
    echo -e "   ${CYAN}Log file         : ${LOG_FILE}${NC}"
    echo ""

    while true; do
        echo -e "${BOLD}MENU UTAMA${NC}"
        print_separator
        echo "  [1] Deploy instances (MariaDB + DVWA)"
        echo "  [2] Lihat status instances"
        echo "  [3] Reset semua (untuk batch berikutnya)"
        echo "  [4] Start semua instances"
        echo "  [5] Stop semua instances"
        echo "  [6] Destroy semua instances (hapus permanen)"
        echo "  [7] Tambah instance"
        echo "  [8] Lihat log"
        echo "  [q] Keluar"
        print_separator
        read -rp "$(echo -e "${BOLD}Pilih menu: ${NC}")" choice

        log "INFO" "Menu dipilih: [$choice]"
        echo ""
        case "$choice" in
            1) action_deploy  ;;
            2) action_status  ;;
            3) action_reset   ;;
            4) action_start   ;;
            5) action_stop    ;;
            6) action_destroy ;;
            7) action_add_instances ;;
            8) action_view_log ;;
            q|Q)
                log "INFO" "===== DVWA Lab Manager v2 keluar (PID $$) ====="
                echo -e "${CYAN}Bye! Good luck dengan trainingnya!${NC}"
                exit 0
                ;;
            *)
                log "WARN" "Pilihan tidak valid: '$choice'"
                echo -e "${RED}Pilihan tidak valid.${NC}"
                ;;
        esac

        echo ""
        read -rp "Tekan Enter untuk kembali ke menu..."
        echo ""
    done
}

main "$@"
