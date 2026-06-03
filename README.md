# dvwa-lab-deployer

**[Bahasa Indonesia](#bahasa-indonesia) | [English](#english)**

---

<a name="bahasa-indonesia"></a>
# Bahasa Indonesia

## Tentang

`dvwa-lab-deployer` adalah shell script interaktif untuk mengelola deployment massal [DVWA (Damn Vulnerable Web Application)](https://github.com/digininja/DVWA) menggunakan Docker. Dibuat untuk kebutuhan security awareness training di mana setiap peserta mendapat environment DVWA yang terisolasi.

Fitur utama:
- Deploy N instance DVWA sekaligus, masing-masing dengan MariaDB dan TinyFileManager
- Setiap peserta mendapat 1 port unik (peserta 1 → port 8101, peserta 2 → port 8102, dst)
- File manager berbasis web (`file.php`) terintegrasi langsung di web root DVWA — peserta bisa browse dan edit file PHP tanpa perlu SSH
- Reset massal untuk pergantian batch training tanpa konfigurasi ulang
- Tambah instance di tengah sesi tanpa mengganggu peserta yang sudah berjalan
- Logging verbose ke `/var/log/dvwa-manager.log` dengan auto-rotate
- Auto-setup Docker CE, firewalld, dan SELinux

## Arsitektur

Per peserta:

```
┌─────────────────────────────────────────────┐
│  Peserta N                                  │
│                                             │
│  dvwa-lab-N   ──────────►  port 810N        │
│  (DVWA + file.php)                          │
│       │                                     │
│  dvwa-db-N    (MariaDB, internal only)      │
└─────────────────────────────────────────────┘
```

Akses per peserta:
```
DVWA         : http://<IP>:810N/
File Manager : http://<IP>:810N/file.php
```

## Prasyarat

- OS: Rocky Linux 8/9 atau AlmaLinux 8/9
- Akses root
- Koneksi internet (untuk pull Docker image dan download TinyFileManager)
- `python3` (biasanya sudah terinstall)
- `php-cli` (akan diinstall otomatis jika belum ada)
- `curl` atau `wget`

> Docker CE akan diinstall otomatis jika belum ada.

## Instalasi & Penggunaan

```bash
# 1. Clone repository
git clone https://github.com/tintus/dvwa-lab-deployer.git
cd dvwa-lab-deployer

# 2. Beri izin eksekusi
chmod +x dvwa-manager-v2.sh

# 3. Jalankan sebagai root
sudo ./dvwa-manager-v2.sh
```

## Konfigurasi

Edit bagian config di awal script sebelum deploy:

```bash
# --- Config ---
BASE_PORT_DVWA=8101        # Port awal DVWA
TFM_USER="file"            # Username TinyFileManager
TFM_PASS="RahasiaFile"     # Password TinyFileManager
TZ="Asia/Jakarta"          # Timezone
DB_ROOT_PASS="dvwaroot"    # MariaDB root password
DB_USER="dvwa"             # MariaDB DVWA user
DB_PASS="p@ssw0rd"         # MariaDB DVWA password
```

## Alur Training

```
Batch 1 (misal 20 peserta):
  1. Jalankan script → pilih menu [1] Deploy
  2. Input jumlah instance: 20
  3. Script deploy otomatis dvwa-lab-1 s/d dvwa-lab-20
  4. Bagikan URL ke peserta:
       Peserta 1 → http://<IP>:8101/
       Peserta 2 → http://<IP>:8102/
       ...dst

Batch 2 (peserta baru):
  1. Pilih menu [3] Reset
  2. Semua instance lama dihapus, deploy ulang fresh
  3. Peserta baru mulai dari environment yang bersih

Tambah peserta di tengah sesi:
  1. Pilih menu [7] Tambah instance
  2. Input jumlah tambahan
  3. Peserta yang sudah berjalan tidak terganggu
```

## Menu

| Menu | Fungsi |
|------|--------|
| `[1]` | Deploy instances baru |
| `[2]` | Lihat status semua instance |
| `[3]` | Reset semua (ganti batch) |
| `[4]` | Start semua instance |
| `[5]` | Stop semua instance |
| `[6]` | Destroy semua (hapus permanen) |
| `[7]` | Tambah instance baru |
| `[8]` | Lihat log |
| `[q]` | Keluar |

## Akses Peserta

**DVWA**

| | |
|--|--|
| URL | `http://<IP>:<port>/` |
| Username | `admin` |
| Password | `password` |
| Setup awal | Login → Setup DVWA → Create/Reset Database |

**TinyFileManager**

| | |
|--|--|
| URL | `http://<IP>:<port>/file.php` |
| Username | sesuai config `TFM_USER` |
| Password | sesuai config `TFM_PASS` |
| Root dir | `/var/www/html` (web root DVWA) |

## Log

Log disimpan di `/var/log/dvwa-manager.log` dengan format:

```
[2026-05-29 10:50:12] [ACTION] [action_deploy] Deploy: 20 instance, port 8101-8120
[2026-05-29 10:50:13] [STEP  ] [deploy_pair  ] [1] Deploy MariaDB: dvwa-db-1
[2026-05-29 10:50:15] [OK    ] [deploy_pair  ] [1] MariaDB ready setelah 2s
[2026-05-29 10:50:16] [OK    ] [deploy_pair  ] [1] DVWA & TinyFileManager up: dvwa-lab-1 port 8101
```

Log dirotasi otomatis ketika ukuran melebihi 50MB.

## Lisensi

Gratis untuk penggunaan personal, edukasi, dan internal organisasi.
Jika kamu menggunakan tool ini untuk keperluan komersial, kamu dipersilakan (tapi tidak diwajibkan) untuk berdonasi.

Donasi: [ko-fi.com/tintus](https://ko-fi.com/tintus)

Lihat [LICENSE](./LICENSE) untuk detail lengkap.

---

<a name="english"></a>
# English

## About

`dvwa-lab-deployer` is an interactive shell script for managing mass deployment of [DVWA (Damn Vulnerable Web Application)](https://github.com/digininja/DVWA) using Docker. Built for security awareness training where each participant gets an isolated DVWA environment.

Key features:
- Deploy N DVWA instances at once, each with its own MariaDB and TinyFileManager
- Each participant gets a unique port (participant 1 → port 8101, participant 2 → port 8102, etc.)
- Web-based file manager (`file.php`) integrated directly into the DVWA web root — participants can browse and edit PHP files without SSH
- Mass reset for batch changeovers without reconfiguration
- Add instances mid-session without disrupting existing participants
- Verbose logging to `/var/log/dvwa-manager.log` with auto-rotate
- Auto-setup for Docker CE, firewalld, and SELinux

## Architecture

Per participant:

```
┌─────────────────────────────────────────────┐
│  Participant N                              │
│                                             │
│  dvwa-lab-N   ──────────►  port 810N        │
│  (DVWA + file.php)                          │
│       │                                     │
│  dvwa-db-N    (MariaDB, internal only)      │
└─────────────────────────────────────────────┘
```

Access per participant:
```
DVWA         : http://<IP>:810N/
File Manager : http://<IP>:810N/file.php
```

## Prerequisites

- OS: Rocky Linux 8/9 or AlmaLinux 8/9
- Root access
- Internet connection (to pull Docker images and download TinyFileManager)
- `python3` (usually pre-installed)
- `php-cli` (will be installed automatically if missing)
- `curl` or `wget`

> Docker CE will be installed automatically if not present.

## Installation & Usage

```bash
# 1. Clone repository
git clone https://github.com/tintus/dvwa-lab-deployer.git
cd dvwa-lab-deployer

# 2. Make executable
chmod +x dvwa-manager-v2.sh

# 3. Run as root
sudo ./dvwa-manager-v2.sh
```

## Configuration

Edit the config section at the top of the script before deploying:

```bash
# --- Config ---
BASE_PORT_DVWA=8101        # Starting DVWA port
TFM_USER="file"            # TinyFileManager username
TFM_PASS="RahasiaFile"     # TinyFileManager password
TZ="Asia/Jakarta"          # Timezone
DB_ROOT_PASS="dvwaroot"    # MariaDB root password
DB_USER="dvwa"             # MariaDB DVWA user
DB_PASS="p@ssw0rd"         # MariaDB DVWA password
```

## Training Flow

```
Batch 1 (e.g. 20 participants):
  1. Run the script → select menu [1] Deploy
  2. Input number of instances: 20
  3. Script automatically deploys dvwa-lab-1 through dvwa-lab-20
  4. Share URLs with participants:
       Participant 1 → http://<IP>:8101/
       Participant 2 → http://<IP>:8102/
       ...and so on

Batch 2 (new participants):
  1. Select menu [3] Reset
  2. All old instances are removed and redeployed fresh
  3. New participants start with a clean environment

Adding participants mid-session:
  1. Select menu [7] Add instance
  2. Input the number to add
  3. Existing participants are not affected
```

## Menu

| Menu | Function |
|------|----------|
| `[1]` | Deploy new instances |
| `[2]` | View status of all instances |
| `[3]` | Reset all (batch changeover) |
| `[4]` | Start all instances |
| `[5]` | Stop all instances |
| `[6]` | Destroy all (permanent delete) |
| `[7]` | Add new instances |
| `[8]` | View log |
| `[q]` | Quit |

## Participant Access

**DVWA**

| | |
|--|--|
| URL | `http://<IP>:<port>/` |
| Username | `admin` |
| Password | `password` |
| First-time setup | Login → Setup DVWA → Create/Reset Database |

**TinyFileManager**

| | |
|--|--|
| URL | `http://<IP>:<port>/file.php` |
| Username | as configured in `TFM_USER` |
| Password | as configured in `TFM_PASS` |
| Root dir | `/var/www/html` (DVWA web root) |

## Log

Logs are saved to `/var/log/dvwa-manager.log` in the following format:

```
[2026-05-29 10:50:12] [ACTION] [action_deploy] Deploy: 20 instance, port 8101-8120
[2026-05-29 10:50:13] [STEP  ] [deploy_pair  ] [1] Deploy MariaDB: dvwa-db-1
[2026-05-29 10:50:15] [OK    ] [deploy_pair  ] [1] MariaDB ready after 2s
[2026-05-29 10:50:16] [OK    ] [deploy_pair  ] [1] DVWA & TinyFileManager up: dvwa-lab-1 port 8101
```

Logs are automatically rotated when size exceeds 50MB.

## License

Free for personal, educational, and internal organizational use.
If you use this tool commercially, you are kindly encouraged (but not required) to donate.

Donate: [ko-fi.com/tintus](https://ko-fi.com/tintus)

See [LICENSE](./LICENSE) for full details.
