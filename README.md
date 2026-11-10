# NOVASTRIA — Premium Digital Store

Website NOVASTRIA dengan katalog digital, pencarian, filter, harga publik/reseller, pemesanan WhatsApp, Supabase Auth, dan Admin Controller.

## Struktur penting
- `index.html` — halaman toko.
- `admin.html` — dashboard admin.
- `assets/app.js` — katalog, autentikasi, profil, dan pemesanan.
- `assets/admin.js` — pemeriksaan admin dan pengelolaan status keanggotaan.
- `assets/style.css` — desain responsif.
- `assets/products.json` — data katalog dan harga.
- `supabase/setup-auth.sql` — trigger profil otomatis dan backfill akun lama.
- `supabase/setup-admin.sql` — otorisasi admin dan kebijakan RLS.

## Setup Supabase

1. Jalankan seluruh `supabase/setup-auth.sql` di Supabase SQL Editor.
2. Pastikan akun `kitatopupin@gmail.com` sudah terdaftar di NOVASTRIA / Supabase Auth.
3. Jalankan seluruh `supabase/setup-admin.sql` di SQL Editor untuk memberikan hak Admin Utama kepada akun tersebut.
4. Pastikan query selesai tanpa error.
5. Login dengan akun admin, lalu buka `https://rifkykawitwicaksono.github.io/NOVASTRIA/admin.html`.

## Admin Controller tahap pertama
- Memeriksa hak admin melalui fungsi database `is_novastria_admin()`.
- Menampilkan daftar profil anggota.
- Mencari anggota berdasarkan nama, nomor WhatsApp, dan kode referral.
- Menampilkan status Referral dan Reseller.
- Mengaktifkan atau menonaktifkan status yang sudah memiliki baris pada tabel `memberships`.

**Verifikasi pembayaran tetap manual.** Aktifkan status hanya setelah bukti pembayaran diperiksa. Dashboard ini belum memproses pembayaran, membuat membership yang belum ada, mencatat komisi, atau mengirim payout.

## Keamanan
- Browser menggunakan Supabase Publishable Key; jangan memasukkan Secret Key atau service-role key ke HTML/JavaScript.
- Hak admin ditentukan oleh tabel `public.novastria_admins` dan fungsi database, bukan berdasarkan email yang diketik di browser.
- Kebijakan RLS membatasi operasi admin. Jangan memberikan akses admin ke akun lain tanpa verifikasi.
- Status keanggotaan tidak boleh diubah dari browser anggota biasa.

## Katalog dan kontak
Nomor WhatsApp admin diatur pada konstanta `ADMIN_WA` dalam `assets/app.js`. Data harga dan ketersediaan ada di `assets/products.json`; verifikasi dengan supplier sebelum menerima pesanan.
