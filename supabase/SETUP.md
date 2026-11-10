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

## 4. Alur operasional admin
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

### Pencairan komisi
1. Pastikan transfer kepada anggota benar-benar sudah dilakukan.
2. Buka Referral & Komisi.
3. Pilih penerima dan masukkan nominal serta referensi transfer.
4. Simpan. Database menolak pencairan melebihi saldo tersedia.

### Produk dan harga
- Edit harga/varian pada menu Produk & Harga.
- Stok dan visibilitas bisa diubah terpisah.
- Perubahan katalog tersimpan di Supabase dan dibaca oleh halaman toko.
- Jika tabel katalog aktif kosong, toko menampilkan katalog kosong; file JSON hanya dipakai sebagai fallback jika tabel Supabase belum tersedia.

## 5. Batasan saat ini
- Belum ada integrasi iPaymu atau verifikasi transfer otomatis.
- Bukti pembayaran belum diunggah ke Supabase Storage; admin dapat menyimpan URL bukti yang sudah diunggah di tempat tepercaya.
- Belum ada formulir anggota untuk mengajukan pencairan komisi. Admin mencatat payout yang telah dilakukan.
- Laporan keuangan hanya mencakup pembayaran membership. Penjualan produk melalui WhatsApp belum masuk database transaksi.
- SMTP khusus Supabase disarankan untuk email verifikasi produksi.

## 6. Keamanan
- Gunakan hanya Publishable Key di frontend.
- Jangan menaruh Secret Key/service-role key atau password database di repository.
- Jangan mengaktifkan membership sebelum dana benar-benar diterima.
