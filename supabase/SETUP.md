# NOVASTRIA — Supabase Auth setup

Kode frontend menggunakan Supabase Auth email/password. Jalankan langkah berikut sebelum menguji pendaftaran.

## 1. Jalankan SQL database

1. Buka https://supabase.com/dashboard dan pilih project NOVASTRIA.
2. Buka SQL Editor.
3. Buka file supabase/setup-auth.sql pada repository ini.
4. Salin seluruh isi file, tempel ke SQL Editor, lalu tekan Run.
5. Pastikan query selesai tanpa error.

SQL tersebut menambahkan kolom nomor WhatsApp, trigger pembuatan profil dan kode referral otomatis, serta izin update terbatas untuk nama dan nomor WhatsApp. Trigger dibuat dengan SECURITY DEFINER dan search_path yang dikunci. Browser tidak diberi izin untuk mengubah status membership, pembayaran, atau komisi.

## 2. Aktifkan email/password

Di Supabase Dashboard:

1. Buka Authentication → Sign In / Providers → Email.
2. Pastikan provider Email aktif.
3. Aktifkan Confirm email agar email pendaftar diverifikasi sebelum login.

## 3. Atur alamat redirect

Buka Authentication → URL Configuration:

- Site URL: https://rifkykawitwicaksono.github.io/NOVASTRIA/
- Redirect URLs: tambahkan https://rifkykawitwicaksono.github.io/NOVASTRIA/**

Simpan perubahan.

## 4. Uji alur autentikasi

1. Tunggu GitHub Pages selesai menerbitkan commit terbaru.
2. Buka website NOVASTRIA dan pilih Masuk / Daftar.
3. Pilih Daftar sekarang, isi nama, nomor WhatsApp, email aktif, password minimal 8 karakter, dan kode referral pengundang bila ada.
4. Buka email dan klik tautan verifikasi.
5. Kembali ke website, lalu login.
6. Pastikan profil dan kode referral pribadi tampil. Di Supabase, cek Authentication → Users dan tabel public.profiles.

## Catatan penting

- Publishable Key di frontend memang dirancang untuk aplikasi browser. Jangan pernah memasukkan sb_secret_... atau service-role key ke repository.
- Status Referral dan Reseller tetap belum aktif sampai ada pembayaran yang diverifikasi dan status di database diubah oleh proses admin/server yang tepercaya.
- Tombol pendaftaran program saat ini masih mengirim permintaan instruksi ke WhatsApp admin. Integrasi pembayaran iPaymu belum diaktifkan oleh perubahan autentikasi ini.
- Untuk pengiriman email produksi, konfigurasi SMTP khusus di Supabase disarankan; layanan email bawaan memiliki batas pengiriman.
- Pengguna yang sudah dibuat sebelum trigger dipasang mungkin belum memiliki baris profil. Buat akun uji baru setelah SQL dijalankan.
