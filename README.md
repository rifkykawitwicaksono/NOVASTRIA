# NOVASTRIA — Premium Digital Store

Website statis dengan katalog 59 varian produk, pencarian, filter, harga publik/reseller, pemesanan WhatsApp, dan dua alur pendaftaran anggota yang terpisah.

## Struktur
- `index.html` — halaman utama.
- `assets/style.css` — desain responsif.
- `assets/app.js` — interaksi katalog, akun demo, pesanan, dan pendaftaran.
- `assets/products.json` — data katalog dan harga.

## Aktifkan GitHub Pages
1. Buka tab **Settings** pada repository.
2. Pilih **Pages**.
3. Di **Build and deployment**, pilih **Deploy from a branch**.
4. Pilih branch `main` dan folder `/(root)`, lalu klik **Save**.
5. Tunggu proses deployment, kemudian buka URL Pages yang diberikan GitHub.

## Pengaturan
Nomor WhatsApp admin ada pada konstanta `ADMIN_WA` di `assets/app.js`. Formatnya kode negara tanpa `+`.
Data harga dan ketersediaan ada di `assets/products.json`. Harga sekarang hanya nilai awal: markup reseller +3% dan publik +7%, dibulatkan ke Rp1.000. Verifikasi harga dan stok dengan supplier sebelum menerima pesanan.

## Program anggota
- Referral member: Rp150.000; pengundang langsung menerima Rp100.000 dan NOVASTRIA Rp50.000 setelah pembayaran tervalidasi.
- Reseller member: Rp100.000 sekali bayar untuk akses harga reseller setelah diverifikasi.
- Kedua status terpisah. Membayar satu program tidak otomatis mengaktifkan program lainnya.

## Batasan penting
Ini masih frontend statis/demo. Profil dan status anggota disimpan di `localStorage` browser, bukan akun aman di server. Pengunjung dapat mengubah data lokalnya sendiri. Form hanya membuka WhatsApp; tidak ada pembayaran otomatis, database pusat, verifikasi pembayaran, pembukuan komisi, atau dashboard admin. Jangan mengaktifkan status anggota atau membayar komisi berdasarkan status di browser.

Untuk produksi dibutuhkan backend, database, autentikasi, pencatatan transaksi, dan webhook pembayaran yang diverifikasi di server. Jangan menyimpan API key, password, atau secret di file frontend publik.