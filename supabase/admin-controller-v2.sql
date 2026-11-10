-- NOVASTRIA Admin Controller v2
-- Jalankan SEKALI di Supabase SQL Editor setelah setup-auth.sql dan setup-admin.sql.
-- Menambah modul pembayaran manual, komisi referral, pencairan, katalog dinamis, laporan, audit.
-- Semua operasi sensitif divalidasi di PostgreSQL; tidak ada Secret Key di browser.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1) Tabel operasional
CREATE TABLE IF NOT EXISTS public.membership_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  membership_type TEXT NOT NULL CHECK (membership_type IN ('referral','reseller')),
  amount BIGINT NOT NULL CHECK (amount > 0),
  payment_method TEXT NOT NULL DEFAULT 'manual',
  reference_code TEXT,
  proof_url TEXT,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','verified','rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS membership_payments_created_idx ON public.membership_payments(created_at DESC);
CREATE INDEX IF NOT EXISTS membership_payments_status_idx ON public.membership_payments(status);

CREATE TABLE IF NOT EXISTS public.referral_commissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id UUID NOT NULL UNIQUE REFERENCES public.membership_payments(id) ON DELETE RESTRICT,
  referrer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  referred_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  amount BIGINT NOT NULL CHECK (amount > 0),
  status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available','paid','void')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS referral_commissions_referrer_idx ON public.referral_commissions(referrer_id);

CREATE TABLE IF NOT EXISTS public.commission_payouts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  amount BIGINT NOT NULL CHECK (amount > 0),
  payment_reference TEXT,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'paid' CHECK (status IN ('paid','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_by UUID REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  admin_id UUID REFERENCES auth.users(id),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS admin_audit_logs_created_idx ON public.admin_audit_logs(created_at DESC);

CREATE TABLE IF NOT EXISTS public.store_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product TEXT NOT NULL,
  variant TEXT NOT NULL,
  public_price BIGINT CHECK (public_price IS NULL OR public_price >= 0),
  reseller_price BIGINT CHECK (reseller_price IS NULL OR reseller_price >= 0),
  in_stock BOOLEAN NOT NULL DEFAULT true,
  is_active BOOLEAN NOT NULL DEFAULT true,
  sort_order INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(product, variant)
);
ALTER TABLE public.store_products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public can read active NOVASTRIA products" ON public.store_products;
CREATE POLICY "Public can read active NOVASTRIA products"
  ON public.store_products FOR SELECT TO anon, authenticated USING (is_active = true);
DROP POLICY IF EXISTS "NOVASTRIA admins manage products" ON public.store_products;
CREATE POLICY "NOVASTRIA admins manage products"
  ON public.store_products FOR ALL TO authenticated
  USING (public.is_novastria_admin())
  WITH CHECK (public.is_novastria_admin());
GRANT SELECT ON public.store_products TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.store_products TO authenticated;

-- Seed katalog awal dari assets/products.json; aman dijalankan ulang.
INSERT INTO public.store_products(product,variant,public_price,reseller_price,in_stock,sort_order)
VALUES
  ('Drip Client Apk Mod', '1 Hari', 11000, 5000, true, 0),
  ('Drip Client Apk Mod', '3 Hari', 22000, 11000, true, 1),
  ('Drip Client Apk Mod', '7 Hari', 43000, 21000, true, 2),
  ('Drip Client Apk Mod', '15 Hari', 75000, 37000, true, 3),
  ('Drip Client Apk Mod', '30 Hari', 86000, 57000, true, 4),
  ('Drip Client Root', '1 Hari', NULL, 6000, true, 5),
  ('Drip Client Root', '7 Hari', 49000, 21000, true, 6),
  ('Drip Client Root', '30 Hari', 86000, 47000, true, 7),
  ('Hg Cheats Apk Mod', '1 Hari', 14000, 8000, true, 8),
  ('Hg Cheats Apk Mod', '7 Hari', 38000, 21000, true, 9),
  ('Hg Cheats Apk Mod', '10 Hari', 49000, 31000, true, 10),
  ('Hg Cheats Apk Mod', '30 Hari', 86000, 57000, true, 11),
  ('Pato Team Orange & Blue', '3 Hari Orange', 49000, 29000, true, 12),
  ('Pato Team Orange & Blue', '3 Hari Blue', NULL, NULL, false, 13),
  ('Pato Team Orange & Blue', '7 Hari Orange', 81000, 47000, true, 14),
  ('Pato Team Orange & Blue', '7 Hari Blue', 70000, 37000, true, 15),
  ('Pato Team Orange & Blue', '15 Hari Orange', 107000, 76000, true, 16),
  ('Pato Team Orange & Blue', '15 Hari Blue', 129000, 52000, true, 17),
  ('Pato Team Orange & Blue', '30 Hari Orange', 161000, 109000, true, 18),
  ('Pato Team Orange & Blue', '30 Hari Blue', 161000, 73000, true, 19),
  ('Prime Hook Apk Mod', '1 Hari', 8000, 5000, true, 20),
  ('Prime Hook Apk Mod', '3 Hari', 19000, 14000, true, 21),
  ('Prime Hook Apk Mod', '7 Hari', 38000, 26000, true, 22),
  ('Silent Cheats Apk Mod', '1 Hari', 17000, 9000, true, 23),
  ('Silent Cheats Apk Mod', '3 Hari', 27000, 18000, true, 24),
  ('Silent Cheats Apk Mod', '7 Hari', NULL, NULL, false, 25),
  ('Silent Cheats Apk Mod', '15 Hari', NULL, NULL, false, 26),
  ('Silent Cheats Apk Mod', '28 Hari', NULL, NULL, false, 27),
  ('Certificate Gbox / Esign', '1 Tahun (Garansi 30 Hari)', 81000, 52000, true, 28),
  ('Migul', '1 Hari', 43000, 21000, true, 29),
  ('Migul', '7 Hari', 129000, 73000, true, 30),
  ('Migul', '30 Hari', 375000, 145000, true, 31),
  ('Drip Client Wire iOS & Android', '6 Jam', 8000, 4000, true, 32),
  ('Drip Client Wire iOS & Android', '12 Jam', 13000, 9000, true, 33),
  ('Drip Client Wire iOS & Android', '1 Hari', 22000, 13000, true, 34),
  ('Drip Client Wire iOS & Android', '7 Hari', 43000, 31000, true, 35),
  ('Drip Client Wire iOS & Android', '30 Hari', 107000, 73000, true, 36),
  ('Phantom iOS & Android', '1 Jam', 5000, 3000, true, 37),
  ('Phantom iOS & Android', '3 Jam', 7000, 5000, true, 38),
  ('Phantom iOS & Android', '6 Jam', 13000, 8000, true, 39),
  ('Phantom iOS & Android', '12 Jam', 17000, 10000, true, 40),
  ('Phantom iOS & Android', '1 Hari', 22000, 13000, true, 41),
  ('Phantom iOS & Android', '3 Hari', 38000, 21000, true, 42),
  ('Phantom iOS & Android', '7 Hari', 75000, 37000, true, 43),
  ('Phantom iOS & Android', '30 Hari', 129000, 73000, true, 44),
  ('Xreg iOS & Android', '1 Jam', 6000, 4000, true, 45),
  ('Xreg iOS & Android', '3 Jam', 9000, 5000, true, 46),
  ('Xreg iOS & Android', '6 Jam', 13000, 8000, true, 47),
  ('Xreg iOS & Android', '12 Jam', 17000, 11000, true, 48),
  ('Xreg iOS & Android', '1 Hari', 22000, 16000, true, 49),
  ('Xreg iOS & Android', '3 Hari', 43000, 29000, true, 50),
  ('NEXORA iOS & Android', '1 Jam', 5000, 3000, true, 51),
  ('NEXORA iOS & Android', '3 Jam', 7000, 5000, true, 52),
  ('NEXORA iOS & Android', '6 Jam', 13000, 9000, true, 53),
  ('NEXORA iOS & Android', '12 Jam', 17000, 11000, true, 54),
  ('NEXORA iOS & Android', '1 Hari', 22000, 15000, true, 55),
  ('NEXORA iOS & Android', '3 Hari', 43000, 27000, true, 56),
  ('NEXORA iOS & Android', '7 Hari', 107000, 73000, true, 57),
  ('NEXORA iOS & Android', '30 Hari', 140000, 98000, true, 58)
ON CONFLICT (product,variant) DO UPDATE SET
  public_price=EXCLUDED.public_price,
  reseller_price=EXCLUDED.reseller_price,
  in_stock=EXCLUDED.in_stock,
  sort_order=EXCLUDED.sort_order,
  is_active=true,
  updated_at=now();

-- 2) RLS untuk data privat. Semua operasi admin melalui pemeriksaan database.
ALTER TABLE public.membership_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_commissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commission_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.membership_payments, public.referral_commissions, public.commission_payouts, public.admin_audit_logs FROM anon, authenticated;
GRANT SELECT ON public.membership_payments, public.referral_commissions, public.commission_payouts, public.admin_audit_logs TO authenticated;

DROP POLICY IF EXISTS "NOVASTRIA admins read payments" ON public.membership_payments;
CREATE POLICY "NOVASTRIA admins read payments" ON public.membership_payments FOR SELECT TO authenticated USING (public.is_novastria_admin());
DROP POLICY IF EXISTS "NOVASTRIA admins read commissions" ON public.referral_commissions;
CREATE POLICY "NOVASTRIA admins read commissions" ON public.referral_commissions FOR SELECT TO authenticated USING (public.is_novastria_admin());
DROP POLICY IF EXISTS "NOVASTRIA admins read payouts" ON public.commission_payouts;
CREATE POLICY "NOVASTRIA admins read payouts" ON public.commission_payouts FOR SELECT TO authenticated USING (public.is_novastria_admin());
DROP POLICY IF EXISTS "NOVASTRIA admins read audit" ON public.admin_audit_logs;
CREATE POLICY "NOVASTRIA admins read audit" ON public.admin_audit_logs FOR SELECT TO authenticated USING (public.is_novastria_admin());

-- 3) Helper: audit log, hanya dipanggil fungsi SECURITY DEFINER di bawah.
CREATE OR REPLACE FUNCTION public.novastria_admin_log(p_action TEXT,p_entity TEXT,p_id TEXT,p_details JSONB DEFAULT '{}'::jsonb)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  INSERT INTO public.admin_audit_logs(admin_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),p_action,p_entity,p_id,COALESCE(p_details,'{}'::jsonb));
END; $$;

-- 4) Daftar anggota termasuk email Auth (email tidak tersedia di tabel profiles).
CREATE OR REPLACE FUNCTION public.admin_list_members()
RETURNS TABLE(id UUID,email TEXT,full_name TEXT,phone TEXT,referral_code TEXT,referred_by UUID,created_at TIMESTAMPTZ,referral_status TEXT,reseller_status TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  RETURN QUERY
  SELECT p.id, u.email::text, p.full_name, p.phone, p.referral_code, p.referred_by, u.created_at,
    COALESCE((SELECT m.status::text FROM public.memberships m WHERE m.user_id=p.id AND m.membership_type='referral' LIMIT 1),'none'),
    COALESCE((SELECT m.status::text FROM public.memberships m WHERE m.user_id=p.id AND m.membership_type='reseller' LIMIT 1),'none')
  FROM public.profiles p JOIN auth.users u ON u.id=p.id
  ORDER BY u.created_at DESC;
END; $$;

-- 5) Ringkasan dashboard.
CREATE OR REPLACE FUNCTION public.admin_get_overview()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v JSONB;
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  SELECT jsonb_build_object(
    'members',(SELECT count(*) FROM public.profiles),
    'referral_active',(SELECT count(*) FROM public.memberships WHERE membership_type='referral' AND status='active'),
    'reseller_active',(SELECT count(*) FROM public.memberships WHERE membership_type='reseller' AND status='active'),
    'pending_payments',(SELECT count(*) FROM public.membership_payments WHERE status='pending'),
    'verified_revenue',(SELECT COALESCE(sum(amount),0) FROM public.membership_payments WHERE status='verified'),
    'available_commission',(SELECT COALESCE(sum(c.amount),0) FROM public.referral_commissions c WHERE c.status='available'),
    'paid_commission',(SELECT COALESCE(sum(amount),0) FROM public.commission_payouts WHERE status='paid')
  ) INTO v;
  RETURN v;
END; $$;

-- 6) Pembayaran: admin membuat catatan pending, lalu verifikasi/reject.
CREATE OR REPLACE FUNCTION public.admin_create_payment(p_user_id UUID,p_type TEXT,p_amount BIGINT,p_method TEXT DEFAULT 'manual',p_reference TEXT DEFAULT NULL,p_proof_url TEXT DEFAULT NULL,p_notes TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  IF p_type NOT IN ('referral','reseller') THEN RAISE EXCEPTION 'Jenis membership tidak valid'; END IF;
  IF p_amount <= 0 THEN RAISE EXCEPTION 'Nominal harus lebih dari nol'; END IF;
  IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_user_id) THEN RAISE EXCEPTION 'Anggota tidak ditemukan'; END IF;
  INSERT INTO public.membership_payments(user_id,membership_type,amount,payment_method,reference_code,proof_url,notes)
  VALUES(p_user_id,p_type,p_amount,COALESCE(NULLIF(p_method,''),'manual'),NULLIF(p_reference,''),NULLIF(p_proof_url,''),NULLIF(p_notes,''))
  RETURNING id INTO v_id;
  PERFORM public.novastria_admin_log('payment_created','membership_payment',v_id::text,jsonb_build_object('user_id',p_user_id,'type',p_type,'amount',p_amount));
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_payment(p_payment_id UUID,p_decision TEXT,p_notes TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE p public.membership_payments%ROWTYPE; v_referrer UUID; v_commission BIGINT;
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  IF p_decision NOT IN ('verified','rejected') THEN RAISE EXCEPTION 'Keputusan tidak valid'; END IF;
  SELECT * INTO p FROM public.membership_payments WHERE id=p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pembayaran tidak ditemukan'; END IF;
  IF p.status <> 'pending' THEN RAISE EXCEPTION 'Pembayaran sudah diproses'; END IF;
  UPDATE public.membership_payments SET status=p_decision,notes=COALESCE(NULLIF(p_notes,''),notes),
    verified_at=now(),verified_by=auth.uid() WHERE id=p_payment_id;
  IF p_decision='verified' THEN
    UPDATE public.memberships SET status='active'
      WHERE user_id=p.user_id AND membership_type=p.membership_type;
    IF NOT FOUND THEN
      INSERT INTO public.memberships(user_id,membership_type,status) VALUES(p.user_id,p.membership_type,'active');
    END IF;
    IF p.membership_type='referral' THEN
      SELECT referred_by INTO v_referrer FROM public.profiles WHERE id=p.user_id;
      IF v_referrer IS NOT NULL AND v_referrer<>p.user_id THEN
        v_commission := LEAST(p.amount,100000);
        IF v_commission>0 THEN
          INSERT INTO public.referral_commissions(payment_id,referrer_id,referred_user_id,amount)
          VALUES(p.id,v_referrer,p.user_id,v_commission)
          ON CONFLICT(payment_id) DO NOTHING;
        END IF;
      END IF;
    END IF;
  END IF;
  PERFORM public.novastria_admin_log('payment_'||p_decision,'membership_payment',p.id::text,jsonb_build_object('user_id',p.user_id,'type',p.membership_type,'amount',p.amount));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_payments()
RETURNS TABLE(id UUID,user_id UUID,email TEXT,full_name TEXT,membership_type TEXT,amount BIGINT,payment_method TEXT,reference_code TEXT,proof_url TEXT,notes TEXT,status TEXT,created_at TIMESTAMPTZ,verified_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 RETURN QUERY SELECT p.id,p.user_id,u.email::text,pr.full_name,p.membership_type,p.amount,p.payment_method,p.reference_code,p.proof_url,p.notes,p.status,p.created_at,p.verified_at
 FROM public.membership_payments p JOIN auth.users u ON u.id=p.user_id LEFT JOIN public.profiles pr ON pr.id=p.user_id
 ORDER BY p.created_at DESC;
END; $$;

-- 7) Komisi dan pencairan. Komisi Rp100.000 hanya dibuat untuk referral yang berhasil diverifikasi.
CREATE OR REPLACE FUNCTION public.admin_list_commissions()
RETURNS TABLE(id UUID,referrer_id UUID,email TEXT,full_name TEXT,referred_user_id UUID,referred_email TEXT,amount BIGINT,status TEXT,created_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 RETURN QUERY SELECT c.id,c.referrer_id,ru.email::text,rp.full_name,c.referred_user_id,bu.email::text,c.amount,c.status,c.created_at
 FROM public.referral_commissions c JOIN auth.users ru ON ru.id=c.referrer_id
 JOIN auth.users bu ON bu.id=c.referred_user_id LEFT JOIN public.profiles rp ON rp.id=c.referrer_id
 ORDER BY c.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_payouts()
RETURNS TABLE(id UUID,user_id UUID,email TEXT,full_name TEXT,amount BIGINT,payment_reference TEXT,notes TEXT,status TEXT,created_at TIMESTAMPTZ,paid_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 RETURN QUERY SELECT po.id,po.user_id,u.email::text,p.full_name,po.amount,po.payment_reference,po.notes,po.status,po.created_at,po.paid_at
 FROM public.commission_payouts po JOIN auth.users u ON u.id=po.user_id LEFT JOIN public.profiles p ON p.id=po.user_id
 ORDER BY po.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_record_payout(p_user_id UUID,p_amount BIGINT,p_reference TEXT,p_notes TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_available BIGINT; v_id UUID;
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 IF p_amount<=0 THEN RAISE EXCEPTION 'Nominal pencairan harus lebih dari nol'; END IF;
 SELECT COALESCE((SELECT sum(amount) FROM public.referral_commissions WHERE referrer_id=p_user_id AND status='available'),0)
   - COALESCE((SELECT sum(amount) FROM public.commission_payouts WHERE user_id=p_user_id AND status='paid'),0)
 INTO v_available;
 IF p_amount>v_available THEN RAISE EXCEPTION 'Saldo komisi tidak mencukupi. Tersedia: %',v_available; END IF;
 INSERT INTO public.commission_payouts(user_id,amount,payment_reference,notes,paid_by)
 VALUES(p_user_id,p_amount,NULLIF(p_reference,''),NULLIF(p_notes,''),auth.uid()) RETURNING id INTO v_id;
 -- Tandai komisi secara FIFO sampai nilai pencairan terpenuhi; jika parsial, pecah baris komisi.
 DECLARE
   c RECORD;
   remaining BIGINT := p_amount;
 BEGIN
   FOR c IN SELECT id,amount FROM public.referral_commissions WHERE referrer_id=p_user_id AND status='available' ORDER BY created_at,id FOR UPDATE LOOP
     EXIT WHEN remaining<=0;
     IF c.amount<=remaining THEN
       UPDATE public.referral_commissions SET status='paid' WHERE id=c.id;
       remaining:=remaining-c.amount;
     ELSE
       UPDATE public.referral_commissions SET amount=amount-remaining WHERE id=c.id;
       INSERT INTO public.referral_commissions(payment_id,referrer_id,referred_user_id,amount,status)
       SELECT payment_id,referrer_id,referred_user_id,remaining,'paid' FROM public.referral_commissions WHERE id=c.id;
       remaining:=0;
     END IF;
   END LOOP;
 END;
 PERFORM public.novastria_admin_log('commission_payout','commission_payout',v_id::text,jsonb_build_object('user_id',p_user_id,'amount',p_amount));
 RETURN v_id;
END; $$;

-- 8) Produk: tabel dapat dibaca publik, perubahan hanya admin.
CREATE OR REPLACE FUNCTION public.admin_list_products()
RETURNS TABLE(id UUID,product TEXT,variant TEXT,public_price BIGINT,reseller_price BIGINT,in_stock BOOLEAN,is_active BOOLEAN,sort_order INTEGER,updated_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 RETURN QUERY SELECT sp.id,sp.product,sp.variant,sp.public_price,sp.reseller_price,sp.in_stock,sp.is_active,sp.sort_order,sp.updated_at
 FROM public.store_products sp ORDER BY sp.sort_order,sp.product,sp.variant;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_save_product(p_id UUID,p_product TEXT,p_variant TEXT,p_public_price BIGINT,p_reseller_price BIGINT,p_in_stock BOOLEAN,p_is_active BOOLEAN,p_sort_order INTEGER)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id UUID;
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 IF length(trim(p_product))=0 OR length(trim(p_variant))=0 THEN RAISE EXCEPTION 'Nama produk dan varian wajib diisi'; END IF;
 IF p_public_price<0 OR p_reseller_price<0 THEN RAISE EXCEPTION 'Harga tidak boleh negatif'; END IF;
 IF p_id IS NULL THEN
   INSERT INTO public.store_products(product,variant,public_price,reseller_price,in_stock,is_active,sort_order)
   VALUES(trim(p_product),trim(p_variant),p_public_price,p_reseller_price,p_in_stock,p_is_active,COALESCE(p_sort_order,0))
   ON CONFLICT(product,variant) DO UPDATE SET public_price=EXCLUDED.public_price,reseller_price=EXCLUDED.reseller_price,
     in_stock=EXCLUDED.in_stock,is_active=EXCLUDED.is_active,sort_order=EXCLUDED.sort_order,updated_at=now()
   RETURNING id INTO v_id;
 ELSE
   UPDATE public.store_products SET product=trim(p_product),variant=trim(p_variant),public_price=p_public_price,
     reseller_price=p_reseller_price,in_stock=p_in_stock,is_active=p_is_active,sort_order=COALESCE(p_sort_order,0),updated_at=now()
   WHERE id=p_id RETURNING id INTO v_id;
   IF v_id IS NULL THEN RAISE EXCEPTION 'Produk tidak ditemukan'; END IF;
 END IF;
 PERFORM public.novastria_admin_log('product_saved','store_product',v_id::text,jsonb_build_object('product',p_product,'variant',p_variant));
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_delete_product(p_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 UPDATE public.store_products SET is_active=false,updated_at=now() WHERE id=p_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Produk tidak ditemukan'; END IF;
 PERFORM public.novastria_admin_log('product_archived','store_product',p_id::text,'{}'::jsonb);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_audit()
RETURNS TABLE(id BIGINT,admin_email TEXT,action TEXT,entity_type TEXT,entity_id TEXT,details JSONB,created_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 RETURN QUERY SELECT l.id,u.email::text,l.action,l.entity_type,l.entity_id,l.details,l.created_at
 FROM public.admin_audit_logs l LEFT JOIN auth.users u ON u.id=l.admin_id ORDER BY l.created_at DESC LIMIT 300;
END; $$;

-- 9) Hak eksekusi RPC hanya untuk pengguna terautentikasi; fungsi memvalidasi admin di dalamnya.
REVOKE ALL ON FUNCTION public.novastria_admin_log(TEXT,TEXT,TEXT,JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_members() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_get_overview() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_create_payment(UUID,TEXT,BIGINT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_review_payment(UUID,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_payments() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_commissions() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_payouts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_record_payout(UUID,BIGINT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_products() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_save_product(UUID,TEXT,TEXT,BIGINT,BIGINT,BOOLEAN,BOOLEAN,INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_delete_product(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_audit() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_members(),public.admin_get_overview(),public.admin_create_payment(UUID,TEXT,BIGINT,TEXT,TEXT,TEXT,TEXT),public.admin_review_payment(UUID,TEXT,TEXT),public.admin_list_payments(),public.admin_list_commissions(),public.admin_list_payouts(),public.admin_record_payout(UUID,BIGINT,TEXT,TEXT),public.admin_list_products(),public.admin_save_product(UUID,TEXT,TEXT,BIGINT,BIGINT,BOOLEAN,BOOLEAN,INTEGER),public.admin_delete_product(UUID),public.admin_list_audit() TO authenticated;

NOTIFY pgrst,'reload schema';
