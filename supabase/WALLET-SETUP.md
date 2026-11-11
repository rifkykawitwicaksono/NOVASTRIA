# NOVASTRIA Wallet v1 — Aktivasi Supabase

## Konfigurasi yang diterapkan
- Pemilik saldo: seluruh akun NOVASTRIA yang sudah terdaftar dan login.
- Deposit: transfer manual (bank/e-wallet), diverifikasi admin.
- Minimal deposit: Rp10.000.
- Saldo dihitung dari ledger `wallet_transactions`; tidak ada kolom saldo yang dapat diedit dari browser.
- Saldo baru dikreditkan ketika admin memverifikasi deposit.
- Setiap pengajuan hanya dapat dikreditkan satu kali.

## Prasyarat
Pastikan migrasi berikut sudah dijalankan pada project Supabase yang sama:
1. `setup-auth.sql` (profil dan autentikasi).
2. `setup-admin.sql` (penetapan akun admin dan fungsi pemeriksaan admin).
3. `admin-controller-v2.sql` (fungsi audit admin).
4. `admin-controller-v3.sql` (fitur operasional sebelumnya).

## Cara mengaktifkan
1. Buka Supabase Dashboard untuk project NOVASTRIA.
2. Masuk ke **SQL Editor**.
3. Buka file `supabase/wallet-v1.sql` di repository GitHub.
4. Salin seluruh isi file, tempel ke SQL Editor, lalu klik **Run** satu kali.
5. Pastikan eksekusi selesai tanpa error.
6. Buka website NOVASTRIA, login dengan akun anggota, lalu buka area akun. Panel **Saldo NOVASTRIA** akan muncul.
7. Login ke panel admin, buka tab **Deposit Saldo**, lalu uji dengan deposit kecil Rp10.000.

## Alur transaksi
1. Anggota menghubungi admin untuk meminta rekening/e-wallet resmi.
2. Anggota transfer, lalu mengirim pengajuan melalui panel saldo dengan nominal, metode, nama pengirim, dan referensi/bukti opsional.
3. Status pengajuan menjadi **Menunggu verifikasi**. Saldo belum bertambah.
4. Admin mencocokkan mutasi rekening dan detail transaksi secara manual.
5. Admin menekan **Verifikasi & kreditkan**. Dalam satu transaksi database, pengajuan ditandai terverifikasi dan satu entri kredit dimasukkan ke ledger.
6. Jika ditolak, tidak ada kredit saldo.

## Catatan batasan saat ini
- Sistem belum menyediakan upload bukti file; anggota dapat memasukkan tautan HTTPS bukti transfer.
- Nomor rekening/QRIS resmi belum ditampilkan di website karena detail rekening belum diberikan. Anggota diarahkan menghubungi admin terlebih dahulu.
- Fitur ini mengelola deposit, saldo, dan riwayat. Pembayaran produk menggunakan saldo belum diaktifkan; pemesanan produk saat ini masih melalui WhatsApp. Jangan menganggap saldo bisa dipakai checkout sebelum modul checkout dan debit atomik dirilis.
- Jangan pernah memberikan Supabase Secret/Service Role Key ke frontend atau memasukkannya ke repository.
