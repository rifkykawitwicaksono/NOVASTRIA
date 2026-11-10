# NOVASTRIA — Premium Digital Store

Website NOVASTRIA menggunakan HTML/CSS/JavaScript, Supabase Auth, PostgreSQL, dan GitHub Pages.

## Struktur utama
- `index.html` — halaman toko.
- `admin.html` — Admin Control Center.
- `assets/app.js` — katalog, autentikasi, profil, dan pemesanan.
- `assets/admin.js` — dashboard admin, pembayaran membership, komisi, payout, katalog, laporan, dan audit.
- `assets/style.css` — desain responsif.
- `assets/products.json` — fallback katalog statis.
- `supabase/setup-auth.sql` — trigger profil dan referral code.
- `supabase/setup-admin.sql` — identitas admin dan RLS dasar.
- `supabase/admin-controller-v2.sql` — tabel operasional, RPC admin aman, seed 59 produk, komisi, payout, laporan, dan audit.
- `supabase/admin-controller-v3.sql` — buku penjualan produk, permintaan pencairan komisi anggota, persetujuan admin, dan pencatatan transfer selesai.

## Setup database
Jalankan berurutan melalui Supabase Dashboard → SQL Editor:
1. `supabase/setup-auth.sql` (jika belum pernah dijalankan).
2. `supabase/setup-admin.sql` (jika belum pernah dijalankan).
3. `supabase/admin-controller-v2.sql` (wajib untuk Admin Control Center versi 2).
4. `supabase/admin-controller-v3.sql` (wajib untuk modul Penjualan dan Pengajuan Komisi terbaru).

Pastikan akun `kitatopupin@gmail.com` sudah ada di Authentication → Users sebelum menjalankan setup-admin.sql. Verifikasi:
```sql
SELECT email,user_id FROM public.novastria_admins
WHERE email='kitatopupin@gmail.com';
```

## Modul Admin Control Center
- Dashboard ringkasan anggota, membership aktif, pembayaran menunggu, pendapatan membership terverifikasi, komisi, payout, dan jumlah katalog.
- Anggota: pencarian nama, email, WhatsApp, kode referral; status Referral dan Reseller; waktu pendaftaran.
- Pembayaran: admin mencatat pembayaran manual sebagai pending, menautkan bukti/referensi, lalu memverifikasi atau menolak. Verifikasi mengaktifkan membership.
- Referral & Komisi: saat pembayaran Referral Member Rp150.000 diverifikasi, pengundang yang tercatat menerima komisi Rp100.000. Pembayaran Reseller Member Rp100.000 tidak menghasilkan komisi.
- Pencairan: anggota dapat mengajukan pencairan dari area akun; saldo tersedia dihitung dan dikunci di database. Admin menyetujui/menolak, lalu mencatat transfer yang benar-benar selesai.
- Penjualan: admin mencatat transaksi WhatsApp, modal per unit, harga jual, dan status; laporan menghitung pendapatan serta estimasi laba kotor dari transaksi dibayar/selesai.
- Produk & Harga: edit, tambah, sembunyikan, aktifkan stok, dan atur harga publik/reseller. Toko membaca katalog aktif dari Supabase setelah migrasi v2 dijalankan.
- Laporan: rekap pembayaran membership terverifikasi per bulan.
- Audit: riwayat aksi sensitif admin.

## Batasan operasional yang harus dipahami
- Pembayaran belum terhubung ke iPaymu. Admin memasukkan pembayaran manual setelah memeriksa bukti/konfirmasi.
- Bukti pembayaran berupa URL opsional; unggah file bukti belum dibuat.
- Penjualan produk tetap dicatat manual oleh admin setelah pesanan diterima; belum ada checkout otomatis atau sinkronisasi WhatsApp.
- Laporan penjualan hanya seakurat harga jual dan modal yang dimasukkan admin; biaya gateway, refund, dan biaya operasional lain belum dihitung.
- Jangan mengaktifkan membership sebelum pembayaran benar-benar diterima.
- Katalog harga harus diverifikasi dengan pemasok sebelum dipublikasikan.

## Keamanan
- Browser menggunakan Supabase Publishable Key. Jangan pernah menaruh Secret Key atau service-role key di HTML/JavaScript.
- Fungsi admin melakukan validasi hak akses di PostgreSQL; jangan mengandalkan pemeriksaan email di frontend.
- Simpan SQL migration di repository dan jalankan hanya pada project Supabase NOVASTRIA.
