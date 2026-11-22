-- NOVASTRIA: penanda produk rekomendasi
-- Jalankan sekali di Supabase SQL Editor pada project tuwthcllamszebhizayk.
-- Tidak membuat transaksi atau mengubah harga/stok/visibilitas.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS is_recommended boolean NOT NULL DEFAULT false;

UPDATE public.products
SET is_recommended = true
WHERE lower(trim(product)) IN (
  'rezzx ios & android',
  'drip client wire ios & android'
);

-- Verifikasi hasil:
SELECT product, variant, is_recommended
FROM public.products
WHERE is_recommended = true
ORDER BY product, variant;
