# SSHWS + XRAY PANEL

Auto-installer untuk VPS tunneling server: **OpenSSH-WS**, **Dropbear-WS**, **Stunnel**,
**Nginx**, **HAProxy**, **Xray-core** (VMess/VLESS/Trojan via WebSocket+TLS),
**BadVPN-UDPGW**, sertifikat SSL **Let's Encrypt** (via acme.sh), **fail2ban**, dan **vnstat**.

Bahan diambil dari repo **https://github.com/chanelog/bin** (Xray-core, acme.sh, tools
`add-ssh`/`del-ssh`/`list-ssh`/`switch-domain`/`switch-host`/`uninstall-ssh`, dan `udpgw`).
Komponen yang tidak tersedia di repo tersebut (Nginx, HAProxy, Dropbear, Stunnel, fail2ban,
vnstat, wstunnel) diambil dari paket resmi distro / rilis resmi proyek masing-masing.

## Yang dibutuhkan sebelum instalasi

1. VPS baru/bersih — **Ubuntu 20.04 / 22.04 / 24.04** atau **Debian 10 / 11 / 12**, akses root.
2. Domain yang **A record**-nya sudah diarahkan ke IP VPS (wajib untuk SSL Let's Encrypt).
3. Port berikut belum dipakai layanan lain: `22, 80, 109, 443, 444, 777, 7300`.

## Cara install

```bash
wget -O install.sh https://raw.githubusercontent.com/<upload-script-ini-ke-repo-kamu>/install.sh
chmod +x install.sh
sudo ./install.sh
```

Atau upload `install.sh` ke VPS lewat SCP/SFTP lalu jalankan `sudo bash install.sh`.
Script akan menanyakan **domain** di awal — pastikan sudah di-pointing sebelum lanjut.

Setelah selesai, buka panel dengan mengetik:

```bash
menu
```

## Arsitektur & Port

| Layanan                     | Port publik      | Keterangan                                   |
|------------------------------|------------------|-----------------------------------------------|
| OpenSSH                      | 22               | akun tunnel-only (shell `/bin/false`)         |
| Dropbear                     | 109              | akun tunnel-only                              |
| OpenSSH SSL (stunnel)        | 444              | SSH dibungkus TLS                             |
| Dropbear SSL (stunnel)       | 777              | Dropbear dibungkus TLS                        |
| SSH/Xray over WS+TLS         | 443 (HAProxy)    | diteruskan ke Nginx (path `/ssh-ws`, `/vmess`, `/vless`, `/trojan-ws`) |
| SSH/Xray over WS non-TLS     | 80 (Nginx)       | path sama seperti di atas                     |
| BadVPN UDPGW                 | 7300/udp         | forwarding UDP (game/voice di dalam tunnel)   |

Alur lalu lintas TLS: **HAProxy** (443, intip SNI) → **Nginx** (8443, pegang sertifikat asli,
proxy WebSocket) → backend masing-masing (`wstunnel` untuk SSH/Dropbear, Xray langsung untuk
VMess/VLESS/Trojan). `wstunnel` dipakai sebagai jembatan karena OpenSSH/Dropbear bicara
protokol SSH mentah dan tidak paham HTTP Upgrade — jadi tidak bisa langsung ditembak dari Nginx.

## Menu

- **Menu SSH & Dropbear** — buat/hapus/list/perpanjang akun, ganti domain/IP, uninstall modul.
- **Menu Xray** — buat/hapus/list/perpanjang akun VMess/VLESS/Trojan, lihat link config siap pakai.
- **Menu Layanan** — status semua service, restart semua/salah satu, lihat log.
- **System Tools** — info VPS lengkap, bandwidth (vnstat), speedtest, info port & path,
  perpanjang SSL, ganti domain (lengkap: SSL+Nginx+HAProxy), reboot, uninstall total.

Akun Xray otomatis dibersihkan tiap hari jam 00:05 kalau sudah kedaluwarsa (cron), sama
seperti mekanisme akun SSH (cron `userdel` terjadwal).

## Catatan jujur soal keterbatasan

Script ini sudah divalidasi seketat mungkin **tanpa VPS sungguhan**:
- Seluruh syntax bash diperiksa dengan `bash -n` dan `shellcheck` (bersih, 0 isu).
- Konfigurasi yang dihasilkan (Nginx, HAProxy, Xray) sudah divalidasi dengan **binary asli**
  masing-masing (`nginx -t`, `haproxy -c`, `xray run -test`) — semua lolos.
- Seluruh logika menu (tambah/hapus/perpanjang akun SSH & Xray, rollback saat config invalid,
  pembersihan otomatis akun expired) sudah diuji end-to-end dengan environment tiruan.
- Dua bug kompatibilitas sempat ketemu & sudah diperbaiki saat proses ini: directive
  `listen [::]:80` (gagal di VPS tanpa IPv6) dan `http2 on;` (hanya didukung Nginx ≥1.25.1,
  sementara Ubuntu/Debian target masih bawa versi lebih lama).

Yang **belum** bisa saya uji langsung: menjalankan seluruh service secara bersamaan di VPS
sungguhan dengan systemd aktif (sandbox saya tidak boot systemd). Jalankan di VPS baru/testing
dulu sebelum dipakai produksi, dan kalau ada service yang gagal start, cek:

```bash
systemctl status <nama-service>
journalctl -u <nama-service> -n 50
cat /var/log/vpn-panel-install.log
```

## Uninstall

Dari menu: **System Tools → Uninstall seluruh panel**, atau untuk uninstall modul SSH-WS saja:
**Menu SSH & Dropbear → Uninstall modul SSH-WS**.
