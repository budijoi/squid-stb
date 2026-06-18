# Squid Caching Proxy — X96Mini / Armbian

Jadikan STB X96Mini kamu sebagai **caching proxy server** untuk mempercepat browsing di seluruh perangkat dalam jaringan.

---

## Cara Kerja

Semua request web dari perangkat (PC, HP, laptop) akan melewati Squid di X96Mini. Halaman yang sudah pernah dikunjungi akan **disimpan (cached)** sehingga kunjungan berikutnya jauh lebih cepat — tanpa perlu download ulang.

---

## Instalasi

### 1. Persyaratan

- X96Mini sudah terinstall **Armbian** (booting dari SD Card atau eMMC)
- X96Mini terhubung ke **LAN** (kabel atau WiFi) dengan IP static
- Akses **root** via SSH

### 2. Jalankan Installer

Transfer script installer ke X96Mini:

```bash
scp install-squid.sh root@192.168.101.22:/tmp/
```

SSH ke X96Mini:

```bash
ssh root@192.168.101.22
```

Jalankan installer:

```bash
chmod +x /tmp/install-squid.sh
sudo bash /tmp/install-squid.sh
```

Installer akan:
- Mengecek versi Squid (update/hapus/fresh install jika perlu)
- Mendeteksi IP & subnet LAN secara otomatis
- Mengkonfigurasi Squid dengan tuning caching optimal
- Membuka firewall port 3128
- Verifikasi dan tes proxy berfungsi

### 3. Setting Perangkat Lain

Atur proxy di **Windows**:

1. Buka **Settings > Network & Internet > Proxy**
2. **Use a proxy server** → ON
3. Address: `192.168.101.22` (IP X96Mini)
4. Port: `3128`
5. Centang **"Bypass proxy for local addresses"**
6. Save

Atau via **PowerShell** (administrator):

```powershell
netsh winhttp set proxy 192.168.101.22:3128
```

**Chrome / Edge / Brave:**

1. Buka `chrome://settings/?search=proxy`
2. Klik "Open your computer's proxy settings"
3. Atur seperti setting Windows di atas

Atau gunakan ekstensi **Proxy SwitchyOmega**:
- Buat profile baru → HTTP Proxy → `192.168.101.22:3128`
- Aktifkan profile tersebut

---

## Verifikasi

Tes dari Windows via PowerShell:

```powershell
curl.exe -I --proxy http://192.168.101.22:3128 https://google.com
```

Response `200` atau `301` berarti proxy berfungsi.

Atau buka browser — browsing terasa lebih cepat setelah kunjungan pertama.

---

## Perintah Berguna

```bash
# Cek status
sudo systemctl status squid

# Cek log real-time
sudo tail -f /var/log/squid/access.log

# Restart service
sudo systemctl restart squid

# Stop service
sudo systemctl stop squid

# Cek isi cache
sudo squid -k info

# Hapus semua cache
sudo systemctl stop squid
sudo rm -rf /var/spool/squid/*
sudo squid -z
sudo systemctl start squid

# Tes DNS
nslookup google.com 127.0.0.1
```

---

## Troubleshooting

| Masalah | Penyebab | Solusi |
|---|---|---|
| Browser error "Proxy server refusing connections" | Squid tidak berjalan | `sudo systemctl restart squid` |
| Web tidak bisa dibuka, curl error 503 | DNS gagal | `sudo tail -f /var/log/squid/cache.log` — cek error DNS |
| Squid hanya jalan di localhost | Firewall blokir port | `sudo ufw allow 3128/tcp` |
| Koneksi lambat di awal | Cache masih kosong | Biarkan, akan cepat setelah beberapa kunjungan |
| WARNING BCP 177 violation | IPv6 loopback tidak ada | Aman diabaikan, tidak pengaruhi kinerja |

---

## Spesifikasi Kebutuhan

| Sumber Daya | Minimal | Rekomendasi |
|---|---|---|
| RAM | 512 MB | 1-2 GB (X96Mini) |
| Storage cache | 500 MB | 2 GB (dikonfigurasi) |
| Network | 100 Mbps | 100/1000 Mbps |

---

## File Structure

```
.
├── install-squid.sh     # Auto-installer script
├── README.md            # Dokumentasi ini
└── squid.conf           # Contoh konfigurasi
```
