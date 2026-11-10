# NOVASTRIA — Supabase setup

## 1. Autentikasi dan profil
1. Buka Supabase Dashboard → SQL Editor.
2. Jalankan seluruh file `supabase/setup-auth.sql`.
3. Pastikan provider Email aktif pada Authentication → Sign In / Providers.
4. Atur Site URL menjadi `https://rifkykawitwicaksono.github.io/NOVASTRIA/` dan Redirect URL `https://rifkykawitwicaksono.github.io/NOVASTRIA/**`.

## 2. Admin utama
1. Pastikan `kitatopupin@gmail.com` sudah terdaftar pada Authentication → Users.
2. Jalankan seluruh `supabase/setup-admin.sql`.
3. Verifikasi:
   ```sql
   SELECT email,user_id FROM public.novastria_admins
   WHERE email='kitatopupin@gmail.com';
   ```
   Harus mengembalikan satu baris.

## 3. Upgrade Admin Control Center v2
Jalankan seluruh file `supabase/admin-controller-v2.sql` satu kali di SQL Editor. File ini:
- Membuat tabel pembayaran membership, komisi referral, pencairan komisi, audit log, dan katalog produk.
- Memasukkan 59 produk dari katalog yang saat ini tersimpan di repository.
- Membuat fungsi RPC yang memeriksa hak admin di database.
- Membuat aturan RLS untuk data operasional dan katalog.
- Menyambungkan katalog toko ke tabel produk Supabase.

Setelah berhasil, logout lalu login kembali di website dan buka:
`https://rifkykawitwicaksono.github.io/NOVASTRIA/admin.html`

## 4. Upgrade operasional v3
Setelah v2 berhasil, jalankan seluruh `supabase/admin-controller-v3.sql` satu kali. Migrasi ini menambah tabel penjualan produk dan pengajuan pencairan komisi anggota.

## 5. Alur operasional admin
### Mencatat pembayaran
1. Buka menu Pembayaran.
2. Pilih anggota dan jenis membership.
3. Masukkan nominal tetap: Referral Rp150.000 atau Reseller Rp100.000.
4. Masukkan metode, referensi, URL bukti (opsional), dan catatan.
5. Simpan sebagai Menunggu.
6. Periksa bukti transfer secara manual, lalu klik Verifikasi atau Tolak.
7. Verifikasi akan mengaktifkan membership secara otomatis.

### Komisi referral
- Hanya pembayaran Referral Member yang diverifikasi yang menghasilkan komisi.
- Jika profil pembeli memiliki `referred_by`, pengundang mendapat komisi Rp100.000.
- Pembayaran Reseller Member tidak menghasilkan komisi.
- Tanpa pengundang yang valid, komisi tidak dibuat.
- Jangan menjanjikan komisi sebelum pembayaran berhasil diverifikasi.

### Pengajuan dan pencairan komisi
1. Anggota login, buka area akun, lalu mengisi nominal dan tujuan transfer.
2. Sistem menolak pengajuan melebihi saldo komisi yang belum dibayarkan atau sedang dipesan pengajuan lain.
3. Admin buka tab Pengajuan Komisi, lalu setujui atau tolak.
4. Setelah transfer benar-benar dilakukan, klik Catat transfer selesai dan isi referensi. Sistem membuat catatan payout serta menandai pengajuan sebagai dibayar dalam satu transaksi database.
5. Alternatif: pencairan manual tanpa pengajuan tetap tersedia pada tab Referral & Komisi.

### Penjualan produk
1. Buka tab Penjualan untuk mencatat pesanan yang masuk melalui WhatsApp.
2. Isi pelanggan, produk, varian, jumlah, harga jual per unit, dan modal per unit.
3. Gunakan status Menunggu saat belum dibayar; ubah menjadi Dibayar atau Selesai setelah pembayaran/pemenuhan benar-benar terjadi.
4. Laporan menampilkan omzet, modal, dan estimasi laba kotor untuk transaksi Dibayar/Selesai.

### Produk dan harga
- Edit harga/varian pada menu Produk & Harga.
- Stok dan visibilitas bisa diubah terpisah.
- Perubahan katalog tersimpan di Supabase dan dibaca oleh halaman toko.
- Jika tabel katalog aktif kosong, toko menampilkan katalog kosong; file JSON hanya dipakai sebagai fallback jika tabel Supabase belum tersedia.

## 6. Batasan saat ini
- Belum ada integrasi iPaymu atau verifikasi transfer otomatis.
- Bukti pembayaran belum diunggah ke Supabase Storage; admin dapat menyimpan URL bukti yang sudah diunggah di tempat tepercaya.
- Penjualan produk dicatat manual oleh admin; belum ada checkout otomatis atau sinkronisasi pesanan WhatsApp.
- Laporan penjualan merupakan estimasi berdasarkan data harga jual/modal yang dimasukkan admin, belum termasuk biaya gateway, refund, atau biaya operasional lain.
- SMTP khusus Supabase disarankan untuk email verifikasi produksi.

## 7. Keamanan
- Gunakan hanya Publishable Key di frontend.
- Jangan menaruh Secret Key/service-role key atau password database di repository.
- Jangan mengaktifkan membership sebelum dana benar-benar diterima.
