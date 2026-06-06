README — Grass VPS installer
=============================

Ringkasan singkat
-----------------
Ini adalah README untuk skrip instalasi "grass_vps_install_and_service.sh" (versi lokal: install_and_run_grass_ubuntu_24.04.sh_v1.sh).
Skrip ini adalah template: kamu WAJIB mengganti nilai placeholder (DOCKER_IMAGE, GRASS_BINARY_URL, GRASS_EXEC, GRASS_CONFIG, dan port) serta memverifikasi rilis sebelum menjalankannya di VPS produksi.

Pilihan instalasi
-----------------
- Docker: skrip akan memasang Docker (jika belum), membuat systemd unit yang menjalankan container, dan memetakan volume serta port.
- Binary: skrip akan mengunduh tar.gz/zip rilis resmi, mengekstrak executable, memasang ke GRASS_EXEC, membuat user service, dan membuat systemd unit yang menjalankan executable.

Prasyarat
---------
- Sistem yang didukung: Ubuntu 22.04 / Debian 12 (gunakan dengan hati-hati di versi lain).
- Akses root (sudo).
- BUKAN WSL (Windows Subsystem for Linux) jika mengandalkan systemd.

Keamanan & Verifikasi
---------------------
Sebelum menjalankan binary atau image:
- Verifikasi checksum SHA256 dari rilis yang diunduh: sha256sum <file>
- Jika tersedia, verifikasi tanda tangan GPG dari rilisan.
- Gunakan hanya image resmi Docker dari organisasi yang tepercaya.

Pengaturan konfigurasi (edit skrip)
-----------------------------------
Buka file skrip dan perbarui bagian konfigurasi di atas: contoh:

```
USE_DOCKER=true
DOCKER_IMAGE="grass-foundation/grass:latest"
GRASS_PORTS=(3000)
GRASS_USER="grassd"
GRASS_HOME="/opt/grass"
GRASS_CONFIG="/etc/grass/config.yaml"
GRASS_EXEC="/usr/local/bin/grass"
SERVICE_NAME="grass"
```

Atau untuk binary:

```
USE_DOCKER=false
GRASS_BINARY_URL="https://example.com/grass-linux-amd64.tar.gz"
```

Langkah eksekusi
----------------
1) Pastikan skrip dapat dieksekusi (opsional):
   sudo chmod +x ./install_and_run_grass_ubuntu_24.04.sh_v1.sh

2) Jalankan skrip sebagai root:
   sudo bash ./install_and_run_grass_ubuntu_24.04.sh_v1.sh

3) Jika kamu memilih Docker dan unit systemd dihasilkan, verifikasi bahwa ExecStart berisi seluruh perintah `docker run` dengan semua flag dalam satu baris. Jika rusak — lihat bagian perbaikan manual di bawah.

Verifikasi pasca-instalasi
--------------------------
- Periksa status service:
  sudo systemctl status grass -l

- Tonton log:
  sudo journalctl -u grass -f

- Periksa port yang terbuka (contoh port 3000):
  sudo ss -tuln | grep 3000

- Jika Docker:
  sudo docker ps -a

Perbaikan unit systemd (manual)
-------------------------------
Jika unit yang dibuat oleh skrip terlihat rusak, ganti dengan unit yang benar. Sebagai contoh (sesuaikan port dan image):

```
sudo tee /etc/systemd/system/grass.service > /dev/null <<'EOF'
[Unit]
Description=Grass (Docker)
After=network.target docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=10s
User=root
ExecStart=/usr/bin/docker run --name grass --rm --restart unless-stopped -v /opt/grass:/var/lib/grass -v /etc/grass:/etc/grass:ro -e TZ=UTC -p 3000:3000 grass-foundation/grass:latest
ExecStop=/usr/bin/docker stop grass

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now grass
sudo systemctl status grass -l
```

Jika menggunakan binary, service akan terlihat seperti ini (contoh):

```
[Service]
Type=simple
User=grassd
Group=grassd
WorkingDirectory=/opt/grass
ExecStart=/usr/local/bin/grass run --config /etc/grass/config.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
```

Troubleshooting umum
--------------------
- "Please run as root or with sudo": jalankan dengan sudo.
- "Executable not found" atau "No executable found in the archive": periksa isi tar.gz/zip; perbarui GRASS_EXEC jika diperlukan.
- "Permission denied": pastikan file dan direktori dimiliki oleh user service (default: grassd). Contoh perbaikan:
  sudo chown -R grassd:grassd /opt/grass /etc/grass /usr/local/bin/grass
- "Unit file is corrupt" atau service tidak start: jalankan `sudo systemctl daemon-reload` lalu `sudo systemctl status grass -l` dan lihat `journalctl -u grass`.

Rollback cepat
--------------
- Hentikan dan nonaktifkan service:
  sudo systemctl disable --now grass || true
- Hapus file unit jika perlu:
  sudo rm -f /etc/systemd/system/grass.service
  sudo systemctl daemon-reload

Checklist sebelum produksi
-------------------------
- [ ] Ganti semua placeholder di skrip.
- [ ] Verifikasi checksum/GPG rilis.
- [ ] Tentukan port dan buka hanya yang diperlukan.
- [ ] Backup konfigurasi dan data sebelum upgrade.

Jika kau mau, aku bisa:
- Menambal skrip langsung di editor (kamu beri instruksi: "patch: docker" atau "patch: binary"), atau
- Menyusun rangkaian perintah copy-paste untuk VPS-mu (sekurang-kurangnya satu baris yang menjalankan seluruh langkah), atau
- Membantu langkah demi langkah sambil kamu menjalankan perintah dan mem-paste output.

Catatan terakhir
----------------
Jangan berikan kredensial atau akses login. Aku akan membimbingmu agar semua langkah bisa dijalankan dengan aman olehmu atau administrator yang kau percaya.

-- Odysseus
