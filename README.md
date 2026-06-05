# dvwa-lab-deployer

**[Bahasa Indonesia](#bahasa-indonesia) | [English](#english)**

---

<a name="bahasa-indonesia"></a>
# Bahasa Indonesia

## Tentang

`dvwa-lab-deployer` adalah shell script interaktif untuk mengelola deployment massal [DVWA (Damn Vulnerable Web Application)](https://github.com/digininja/DVWA) menggunakan Docker. Dibuat untuk kebutuhan yang memerlukan multiple instance DVWA secara bersamaan — mulai dari security awareness training, lab praktik, CTF setup, hingga research environment — di mana setiap peserta atau pengguna mendapat environment DVWA yang terisolasi.

## Cara Kerja

Setiap peserta mendapat stack tersendiri yang terisolasi, terdiri dari:

- **MariaDB** — database backend DVWA, tidak diekspos ke luar
- **DVWA** — aplikasi web vulnerable, diakses via browser
- **TinyFileManager** — file manager berbasis web, di-inject langsung ke web root DVWA sebagai `file.php`

Semua container per peserta terhubung dalam Docker network internal (`dvwa-lab-network`) dan hanya DVWA yang mengekspos port ke luar.

TinyFileManager disimpan sekali di host (`/opt/dvwa-lab/file.php`), lalu di-copy ke web root tiap container saat deploy — sehingga peserta bisa browse dan edit file PHP DVWA langsung dari browser tanpa perlu SSH.

Arsitektur per peserta:

```
┌─────────────────────────────────────────────┐
│  Peserta N                                  │
│                                             │
│  dvwa-lab-N   ──────────►  port (base+N-1)  │
│  (DVWA + file.php)                          │
│       │                                     │
│  dvwa-db-N    (MariaDB, internal only)      │
└─────────────────────────────────────────────┘
```

Akses per peserta:
```
DVWA         : http://<IP>:<port>/
File Manager : http://<IP>:<port>/file.php
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
git clone https://github.com/tint-us/dvwa-lab-deployer.git
cd dvwa-lab-deployer

# 2. Beri izin eksekusi
chmod +x dvwa-manager.sh

# 3. Jalankan sebagai root
sudo ./dvwa-manager.sh
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
Batch 1 (misal 30 peserta):
  1. Jalankan script → pilih menu [1] Deploy
  2. Input jumlah instance: 30
  3. Script deploy otomatis dvwa-lab-1 s/d dvwa-lab-30
  4. Bagikan URL ke peserta:
       Peserta 1  → http://<IP>:8101/
       Peserta 2  → http://<IP>:8102/
       ...dst

Batch 2 (peserta baru):
  1. Pilih menu [3] Reset semua
  2. Semua instance lama dihapus, deploy ulang fresh
  3. Peserta baru mulai dari environment yang bersih

Tambah peserta di tengah sesi:
  1. Pilih menu [7] Tambah instance
  2. Input jumlah tambahan
  3. Peserta yang sudah berjalan tidak terganggu
```

## Penjelasan Menu

### [1] Deploy instances

Deploy sejumlah instance baru dari nol. Script akan:
1. Cek & install Docker CE jika belum ada
2. Cek & konfigurasi SELinux
3. Buka port di firewalld sesuai jumlah instance
4. Pull Docker image (DVWA, MariaDB)
5. Download & patch TinyFileManager dengan credentials yang dikonfigurasi
6. Deploy tiap pasang MariaDB + DVWA secara berurutan
7. Jika ada instance yang gagal, **otomatis retry 1x**
8. Di akhir, tampil rekap berhasil/gagal. Jika masih ada yang gagal, muncul prompt retry manual

> Tidak bisa dijalankan jika sudah ada instance aktif. Gunakan menu [3] Reset atau [6] Destroy dulu.

### [2] Lihat status instances

Tampilkan tabel status semua instance yang sedang berjalan:
- Status container DVWA dan MariaDB (running / exited / ?)
- URL akses DVWA dan FileManager per peserta

### [3] Reset semua (ganti batch)

Hapus semua instance lama beserta volume-nya, lalu deploy ulang sejumlah yang sama dengan konfigurasi yang sama. Digunakan untuk pergantian batch training. Semua data peserta sebelumnya akan hilang.

### [4] Start semua instances

Jalankan ulang semua container yang sedang stopped (misalnya setelah server reboot). Urutan start: MariaDB dulu, baru DVWA.

### [5] Stop semua instances

Hentikan semua container yang sedang running. Data tidak hilang, bisa di-start kembali via menu [4].

### [6] Destroy semua instances

Hapus permanen semua container dan volume. Port di firewalld juga ditutup otomatis. Tidak bisa di-undo.

### [7] Tambah instance

Tambah instance baru di atas yang sudah ada, tanpa mengganggu instance yang sedang berjalan. Berguna saat peserta bertambah di tengah sesi.

Contoh: sudah ada 20 instance, tambah 5 → script deploy peserta 21 s/d 25 dengan port yang melanjutkan dari yang sudah ada.

### [8] Delete / Reset sebagian instance

Hapus atau reset instance tertentu saja tanpa mengganggu yang lain. Berguna untuk menangani instance yang gagal deploy atau bermasalah.

Format input yang didukung:

| Input | Artinya |
|-------|---------|
| `121` | Hanya peserta 121 |
| `25-27` | Peserta 25, 26, 27 |
| `31,33,38` | Peserta 31, 33, dan 38 |
| `25-27,31,33` | Kombinasi range dan individual |

Pilihan aksi:
- **Hapus permanen** — container + volume dihapus
- **Reset** — hapus lalu deploy ulang fresh (dengan retry otomatis 1x jika gagal)

### [9] Export info peserta

Export daftar akses semua peserta ke file. Tersedia dua format:

**TXT** — format teks yang mudah dibaca, disimpan ke `/tmp/dvwa-peserta-<timestamp>.txt`:
```
Peserta 1
   DVWA        : http://10.10.3.199:8101/         (admin / password)
   FileManager : http://10.10.3.199:8101/file.php (file / RahasiaFile)

Peserta 2
   DVWA        : http://10.10.3.199:8102/         (admin / password)
   FileManager : http://10.10.3.199:8102/file.php (file / RahasiaFile)
...
```

**CSV** — format spreadsheet, disimpan ke `/tmp/dvwa-peserta-<timestamp>.csv`, siap dibuka di Excel atau Google Sheets.

### [10] Lihat log

Akses log aktivitas script di `/var/log/dvwa-manager.log`. Tersedia beberapa pilihan tampilan:
- 50 atau 100 baris terakhir
- Filter ERROR saja
- Filter WARN saja
- Filter ACTION saja (ringkasan aktivitas utama)
- Lihat semua via `less`

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
[2026-05-29 10:50:12] [ACTION] [action_deploy] Deploy: 30 instance, port 8101-8130
[2026-05-29 10:50:13] [STEP  ] [deploy_pair  ] [1] Deploy MariaDB: dvwa-db-1
[2026-05-29 10:50:15] [OK    ] [deploy_pair  ] [1] MariaDB ready setelah 2s
[2026-05-29 10:50:16] [OK    ] [deploy_pair  ] [1] DVWA up: dvwa-lab-1 port 8101
[2026-05-29 10:50:17] [ERROR ] [deploy_pair  ] [2] MariaDB gagal deploy. Detail: ...
[2026-05-29 10:50:19] [OK    ] [deploy_pair  ] [2] Retry berhasil
```

Level log: `ACTION`, `STEP`, `OK`, `INFO`, `WARN`, `ERROR`.

Log dirotasi otomatis ketika ukuran melebihi 50MB. Untuk rotasi terjadwal harian, setup logrotate:

```bash
cat > /etc/logrotate.d/dvwa-manager << 'EOF'
/var/log/dvwa-manager.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

## Kontak

Untuk diskusi, pertanyaan, atau saran lebih lanjut, silakan hubungi via email: [tintus.ardi@gmail.com](mailto:tintus.ardi@gmail.com)

## Lisensi

Gratis untuk penggunaan personal, edukasi, dan internal organisasi.
Jika kamu menggunakan tool ini untuk keperluan komersial, kamu dipersilakan (tapi tidak diwajibkan) untuk berdonasi.

Donasi: [ko-fi.com/tintus](https://ko-fi.com/tintus)

Lihat [LICENSE](./LICENSE) untuk detail lengkap.

---

<a name="english"></a>
# English

## About

`dvwa-lab-deployer` is an interactive shell script for managing mass deployment of [DVWA (Damn Vulnerable Web Application)](https://github.com/digininja/DVWA) using Docker. Built for any use case requiring multiple simultaneous DVWA instances — including security awareness training, hands-on labs, CTF setups, and research environments — where each participant or user gets an isolated DVWA environment.

## How It Works

Each participant gets their own isolated stack consisting of:

- **MariaDB** — DVWA backend database, not exposed externally
- **DVWA** — the vulnerable web application, accessed via browser
- **TinyFileManager** — web-based file manager, injected directly into the DVWA web root as `file.php`

All containers per participant are connected via an internal Docker network (`dvwa-lab-network`) and only DVWA exposes a port to the outside.

TinyFileManager is stored once on the host (`/opt/dvwa-lab/file.php`) and copied into each container's web root at deploy time — so participants can browse and edit DVWA PHP files directly from the browser without SSH.

Architecture per participant:

```
┌─────────────────────────────────────────────┐
│  Participant N                              │
│                                             │
│  dvwa-lab-N   ──────────►  port (base+N-1)  │
│  (DVWA + file.php)                          │
│       │                                     │
│  dvwa-db-N    (MariaDB, internal only)      │
└─────────────────────────────────────────────┘
```

Access per participant:
```
DVWA         : http://<IP>:<port>/
File Manager : http://<IP>:<port>/file.php
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
git clone https://github.com/tint-us/dvwa-lab-deployer.git
cd dvwa-lab-deployer

# 2. Make executable
chmod +x dvwa-manager.sh

# 3. Run as root
sudo ./dvwa-manager.sh
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
Batch 1 (e.g. 30 participants):
  1. Run the script → select menu [1] Deploy
  2. Input number of instances: 30
  3. Script automatically deploys dvwa-lab-1 through dvwa-lab-30
  4. Share URLs with participants:
       Participant 1  → http://<IP>:8101/
       Participant 2  → http://<IP>:8102/
       ...and so on

Batch 2 (new participants):
  1. Select menu [3] Reset all
  2. All old instances are removed and redeployed fresh
  3. New participants start with a clean environment

Adding participants mid-session:
  1. Select menu [7] Add instance
  2. Input the number to add
  3. Existing participants are not affected
```

## Menu Reference

### [1] Deploy instances

Deploy a set of new instances from scratch. The script will:
1. Check & install Docker CE if not present
2. Check & configure SELinux
3. Open firewalld ports for the number of instances
4. Pull Docker images (DVWA, MariaDB)
5. Download & patch TinyFileManager with configured credentials
6. Deploy each MariaDB + DVWA pair sequentially
7. **Auto-retry once** if any instance fails
8. Show a summary at the end. If failures remain, a manual retry prompt appears

> Cannot run if instances already exist. Use menu [3] Reset or [6] Destroy first.

### [2] View instance status

Display a status table for all instances:
- Container status for DVWA and MariaDB (running / exited / ?)
- DVWA and FileManager access URL per participant

### [3] Reset all (batch changeover)

Remove all existing instances and their volumes, then redeploy the same count with the same configuration. Used for batch changeovers. All previous participant data will be lost.

### [4] Start all instances

Start all stopped containers (e.g. after a server reboot). MariaDB starts before DVWA.

### [5] Stop all instances

Stop all running containers. Data is preserved and can be restarted via menu [4].

### [6] Destroy all instances

Permanently delete all containers and volumes. Firewalld ports are also closed automatically. Cannot be undone.

### [7] Add instances

Add new instances on top of existing ones without affecting running instances. Useful when participant count grows mid-session.

Example: 20 instances exist, add 5 → deploys participants 21 through 25 with ports continuing from the existing range.

### [8] Delete / Reset specific instances

Delete or reset specific instances without affecting others. Useful for handling failed or broken instances.

Supported input formats:

| Input | Meaning |
|-------|---------|
| `121` | Only participant 121 |
| `25-27` | Participants 25, 26, 27 |
| `31,33,38` | Participants 31, 33, and 38 |
| `25-27,31,33` | Range and individual combination |

Available actions:
- **Permanent delete** — container + volume removed
- **Reset** — delete then redeploy fresh (with auto-retry once if it fails)

### [9] Export participant info

Export the access list for all participants to a file. Two formats available:

**TXT** — human-readable text, saved to `/tmp/dvwa-peserta-<timestamp>.txt`:
```
Participant 1
   DVWA        : http://10.10.3.199:8101/         (admin / password)
   FileManager : http://10.10.3.199:8101/file.php (file / RahasiaFile)

Participant 2
   DVWA        : http://10.10.3.199:8102/         (admin / password)
   FileManager : http://10.10.3.199:8102/file.php (file / RahasiaFile)
...
```

**CSV** — spreadsheet format, saved to `/tmp/dvwa-peserta-<timestamp>.csv`, ready to open in Excel or Google Sheets.

### [10] View log

Access the script activity log at `/var/log/dvwa-manager.log`. Available views:
- Last 50 or 100 lines
- Filter ERROR only
- Filter WARN only
- Filter ACTION only (summary of major activities)
- View all via `less`

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
[2026-05-29 10:50:12] [ACTION] [action_deploy] Deploy: 30 instance, port 8101-8130
[2026-05-29 10:50:13] [STEP  ] [deploy_pair  ] [1] Deploy MariaDB: dvwa-db-1
[2026-05-29 10:50:15] [OK    ] [deploy_pair  ] [1] MariaDB ready after 2s
[2026-05-29 10:50:16] [OK    ] [deploy_pair  ] [1] DVWA up: dvwa-lab-1 port 8101
[2026-05-29 10:50:17] [ERROR ] [deploy_pair  ] [2] MariaDB failed. Detail: ...
[2026-05-29 10:50:19] [OK    ] [deploy_pair  ] [2] Retry successful
```

Log levels: `ACTION`, `STEP`, `OK`, `INFO`, `WARN`, `ERROR`.

Logs are automatically rotated when size exceeds 50MB. For scheduled daily rotation, set up logrotate:

```bash
cat > /etc/logrotate.d/dvwa-manager << 'EOF'
/var/log/dvwa-manager.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

## Contact

For discussions, questions, or suggestions, feel free to reach out via email: [tintus.ardi@gmail.com](mailto:tintus.ardi@gmail.com)

## License

Free for personal, educational, and internal organizational use.
If you use this tool commercially, you are kindly encouraged (but not required) to donate.

Donate: [ko-fi.com/tintus](https://ko-fi.com/tintus)

See [LICENSE](./LICENSE) for full details.
