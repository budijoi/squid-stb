# Squid Caching Proxy untuk STB (X96Mini / Armbian)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Jadikan STB Android TV box (X96Mini, X96Air, dll) sebagai **caching proxy server**. Semua request web dari perangkat di rumah akan melewati Squid — halaman yang sudah dikunjungi akan di-cache, kunjungan berikutnya jadi **jauh lebih cepat**.

---

## Cara Kerja

```
Browser/App → Proxy (X96Mini:3128) → Squid Cache → Internet
                    │                       │
                    └── Cache Hit?  ←─── Cache Storage
```

- **Cache Hit** → halaman dikirim langsung dari cache (super cepat)
- **Cache Miss** → Squid ambil dari internet, simpan, lalu kirim ke client

---

## Repo Ini

| File | Fungsi |
|------|--------|
| `install-squid.sh` | Auto-installer Squid dengan konfigurasi optimal |
| `README.md` | Dokumentasi ini |

---

## Instalasi

### Persyaratan

- STB sudah terinstall **Armbian** (booting dari SD Card atau eMMC)
- Terhubung ke **LAN** dengan IP static (disarankan)
- Akses **root** via SSH

### Cara 1: Download Langsung (via curl)

SSH ke STB lalu jalankan:

```bash
curl -sL https://raw.githubusercontent.com/budijoi/squid-stb/main/install-squid.sh -o /tmp/install-squid.sh
chmod +x /tmp/install-squid.sh
sudo bash /tmp/install-squid.sh
```

### Cara 2: Clone Repo

```bash
apt install git -y
git clone https://github.com/budijoi/squid-stb.git /tmp/squid-stb
sudo bash /tmp/squid-stb/install-squid.sh
```

### Cara 3: Manual (SCP dari PC)

```bash
# Dari Windows (PowerShell)
scp install-squid.sh root@192.168.1.100:/tmp/

# SSH lalu jalankan
ssh root@192.168.1.100
sudo bash /tmp/install-squid.sh
```

### Yang Dilakukan Installer

- Deteksi IP & subnet LAN otomatis
- Update Squid ke versi terbaru (jika versi lama)
- Konfigurasi caching (256 MB RAM cache, 2 GB disk cache)
- Buka firewall port 3128
- Verifikasi proxy berfungsi

---

## Setting Perangkat Lain

### Windows 10/11

1. **Settings > Network & Internet > Proxy**
2. **Use a proxy server** → **ON**
3. Address: `192.168.101.22` (ganti dengan IP X96Mini kamu)
4. Port: `3128`
5. Centang **"Bypass proxy for local addresses"**
6. **Save**

### Windows (via PowerShell — Administrator)

```powershell
netsh winhttp set proxy 192.168.101.22:3128
```

### Chrome / Edge / Brave

1. Buka `chrome://settings/?search=proxy`
2. Klik **"Open your computer's proxy settings"**
3. Atur seperti setting Windows di atas

Atau gunakan ekstensi **Proxy SwitchyOmega**:
- Buat profile baru → HTTP Proxy → `192.168.101.22:3128`
- Aktifkan profile tersebut

### macOS

1. **System Settings > Network > Advanced > Proxies**
2. Centang **"Web Proxy (HTTP)"**
3. Isi `192.168.101.22` dan port `3128`
4. **OK > Apply**

### Android

1. **Settings > WiFi > Tap jaringan > Advanced > Proxy**
2. Pilih **"Manual"**
3. Hostname: `192.168.101.22`
4. Port: `3128`
5. **Save**

### Linux (Desktop)

```bash
# GNOME
gsettings set org.gnome.system.proxy mode 'manual'
gsettings set org.gnome.system.proxy.http host '192.168.101.22'
gsettings set org.gnome.system.proxy.http port 3128

# Atau via Settings > Network > Proxy
```

---

## Verifikasi

Tes dari perangkat lain (PC/HP) apakah proxy berfungsi:

### Windows (PowerShell)

```powershell
curl.exe -I --proxy http://192.168.101.22:3128 https://google.com
```

### Linux / macOS

```bash
curl -I --proxy http://192.168.101.22:3128 https://google.com
```

Response `HTTP/1.1 200` atau `301` berarti proxy berfungsi.

Atau buka [google.com](https://google.com) di browser — kunjungan pertama akan sedikit lebih lambat (sedang di-cache), kunjungan berikutnya akan sangat cepat.

---

## Perintah Berguna di X96Mini

```bash
sudo systemctl status squid        # Cek status
sudo tail -f /var/log/squid/access.log  # Cek log real-time
sudo systemctl restart squid       # Restart proxy
sudo systemctl stop squid          # Stop proxy
sudo squid -k info                 # Cek isi cache
```

Hapus semua cache:

```bash
sudo systemctl stop squid
sudo rm -rf /var/spool/squid/*
sudo squid -z
sudo systemctl start squid
```

---

## Troubleshooting

| Masalah | Kemungkinan | Solusi |
|---------|-------------|--------|
| Browser: "Proxy server refusing connections" | Squid tidak berjalan | `sudo systemctl restart squid` |
| `ERR_DNS_FAIL` / 503 | DNS gagal resolve | Pastikan `/etc/resolv.conf` punya `nameserver 8.8.8.8` |
| Proxy timeout terus | Cache corrupt | Hapus cache (lihat perintah di atas) |
| `WARNING BCP 177 violation` | IPv6 loopback tidak ada | Aman diabaikan |
| Koneksi lambat di awal | Cache masih kosong | Biarkan beberapa saat |
| Squid tidak listen di port | Firewall | `sudo ufw allow 3128/tcp` |

---

## Spesifikasi Hardware

| Sumber Daya | Minimal | Rekomendasi |
|-------------|---------|-------------|
| RAM | 512 MB | 1-2 GB |
| Storage cache | 500 MB | 2 GB+ |
| Network | 100 Mbps | 100/1000 Mbps |
| OS | Armbian (Debian/Ubuntu based) | Armbian 24+ |

---

## Kontribusi

Pull request dan issue selalu welcome. Silakan fork repo ini.

1. Fork repo
2. Buat branch fitur: `git checkout -b fitur-baru`
3. Commit perubahan: `git commit -m 'Tambah fitur X'`
4. Push: `git push origin fitur-baru`
5. Buat Pull Request

---

## Lisensi

[MIT](LICENSE) © Budi Joi
