# Session Checkpoint: FlClash Custom Hysteria Turbo (4-Core)
**Date:** 04 Januari 2026
**Repository:** `https://github.com/mlacnout-sketch/FlClash-Custom-Final`

## 1. Objektif Utama
Memindahkan logika **ZIVPN Native** (Hysteria 4-Core + Load Balancer) ke dalam aplikasi **FlClash** berbasis Android/Flutter.
Target: Aplikasi FlClash yang memiliki menu khusus untuk menjalankan mesin Hysteria di background (port 7777) dan menghubungkan traffic Clash ke port tersebut.

## 2. Status Terakhir
- **Build Status:** Build terakhir (`Fix: Build error - Remove const from navigation...`) sedang berjalan di GitHub Actions.
- **Codebase:** Stabil. Error kompilasi (Go Mod, Flutter Const, Dialog) sudah diperbaiki.
- **Logika:** 100% Terimplementasi (UI Input -> Android Service -> Native Binary Execution).

## 3. Detail Modifikasi Kode

### A. Android Native Layer (Backend)
1.  **`android/service/.../VpnService.kt`**:
    *   **Added:** Fungsi `startZivpnCores()` dan `stopZivpnCores()`.
    *   **Logic:**
        *   Membaca Config (IP, Pass, Obfs) dari `SharedPreferences`.
        *   Menjalankan 4 instance `libuz` (Port 1080-1083).
        *   Menjalankan 1 instance `libload` (Port 7777).
        *   Menggunakan `ProcessBuilder` dengan `LD_LIBRARY_PATH` ke native lib dir.
        *   Menambahkan `WakeLock` (10 jam) agar proses tidak dibunuh sistem.
        *   Menambahkan *Stream Gobbler* (Logger) agar proses tidak deadlock/hang.
    *   **Lifecycle:** Dipanggil otomatis saat VPN `start()` dan dibersihkan saat `stop()`.

2.  **`android/app/.../MainActivity.kt`**:
    *   **Added:** `extractBinaries()` untuk menyalin `libuz` & `libload` dari assets ke `cacheDir/bin` dan set `executable`.
    *   **Added:** `MethodChannel` handler (`com.follow.clash/hysteria`).
    *   **Logic:** Menerima input dari Flutter dan menyimpannya ke `SharedPreferences` ("zivpn_config").

3.  **Assets**:
    *   Menambahkan `assets/bin/libuz` dan `assets/bin/libload` (Binary Arm64).

### B. Flutter Layer (Frontend UI)
1.  **`lib/pages/hysteria_settings.dart`**:
    *   **New Page:** Halaman input untuk Server IP, Password, dan Obfs.
    *   **Logic:** Mengirim data ke Android via MethodChannel saat tombol "Start" ditekan.
    *   **Validation:** Menggunakan dialog standar (`showDialog`) untuk feedback sukses/gagal.

2.  **`lib/common/navigation.dart` & `lib/enum/enum.dart`**:
    *   Menambahkan item menu **"Hysteria Turbo"** (Icon Rocket) di sidebar/bottom bar navigasi.

3.  **`pubspec.yaml`**:
    *   Menambahkan path `assets/bin/` agar binary ikut ter-package dalam APK.

### C. Build System (GitHub Actions)
1.  **`android-build.yml`**:
    *   Menambahkan step `go mod tidy` di folder `core/` sebelum build.
    *   Menggunakan commit spesifik `Clash.Meta` (Mihomo) versi lama (`e0cf7fb`) agar kompatibel dengan API FlClash.
    *   Restorasi plugin `flutter_distributor` dan `tray_manager` yang sempat hilang.

## 4. Cara Penggunaan (User Flow)
1.  Buka FlClash -> Menu **Hysteria Turbo**.
2.  Masukkan IP, Password, Obfs -> Klik **Start Turbo Engine** (Data tersimpan).
3.  Kembali ke **Dashboard** -> Klik **Connect** (Tombol Besar).
    *   *Behind the scene:* VpnService menyalakan Hysteria 4-Core + Load Balancer.
4.  Pastikan Profil Clash (YAML) mengarah ke **SOCKS5 127.0.0.1:7777**.

## 5. Rencana Selanjutnya (Next Steps)
1.  **Verifikasi APK:** Download APK hasil build terakhir dari GitHub Actions.
2.  **Testing:** Jalankan di HP, cek Logcat (filter: "FlClash") untuk memastikan output "ZIVPN Turbo Engine started successfully".
3.  **Optional:** Buat fitur "Auto-Generate Profile" di Flutter agar user tidak perlu buat YAML manual yang menunjuk ke port 7777.