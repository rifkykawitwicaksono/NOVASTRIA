-- NOVASTRIA operational extensions v3
-- Run AFTER admin-controller-v2.sql. Adds manual sales ledger and member payout requests.

CREATE TABLE IF NOT EXISTS public.store_sales (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
 customer_name TEXT NOT NULL, customer_contact TEXT, product TEXT NOT NULL, variant TEXT NOT NULL,
 quantity INTEGER NOT NULL DEFAULT 1 CHECK(quantity>0),
 unit_price BIGINT NOT NULL CHECK(unit_price>=0), cost_price BIGINT NOT NULL DEFAULT 0 CHECK(cost_price>=0),
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','paid','fulfilled','cancelled')),
 payment_method TEXT, payment_reference TEXT, notes TEXT,
 created_by UUID REFERENCES auth.users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS store_sales_created_idx ON public.store_sales(created_at DESC);
ALTER TABLE public.store_sales ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.store_sales FROM anon,authenticated;
GRANT SELECT ON public.store_sales TO authenticated;
DROP POLICY IF EXISTS "NOVASTRIA admins read sales" ON public.store_sales;
CREATE POLICY "NOVASTRIA admins read sales" ON public.store_sales FOR SELECT TO authenticated USING(public.is_novastria_admin());

CREATE TABLE IF NOT EXISTS public.commission_payout_requests (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 amount BIGINT NOT NULL CHECK(amount>0), payout_method TEXT NOT NULL, payout_account TEXT NOT NULL,
 notes TEXT, status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
 admin_notes TEXT, reviewed_by UUID REFERENCES auth.users(id), reviewed_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS payout_requests_user_idx ON public.commission_payout_requests(user_id,created_at DESC);
ALTER TABLE public.commission_payout_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commission_payout_requests FROM anon,authenticated;
GRANT SELECT ON public.commission_payout_requests TO authenticated;
DROP POLICY IF EXISTS "Members read own payout requests" ON public.commission_payout_requests;
CREATE POLICY "Members read own payout requests" ON public.commission_payout_requests FOR SELECT TO authenticated USING(user_id=auth.uid());
DROP POLICY IF EXISTS "Admins read payout requests" ON public.commission_payout_requests;
CREATE POLICY "Admins read payout requests" ON public.commission_payout_requests FOR SELECT TO authenticated USING(public.is_novastria_admin());

CREATE OR REPLACE FUNCTION public.member_request_commission_payout(p_amount BIGINT,p_method TEXT,p_account TEXT,p_notes TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_available BIGINT; v_reserved BIGINT; v_id UUID;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Silakan login terlebih dahulu'; END IF;
 IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Nominal harus lebih dari nol'; END IF;
 IF length(trim(COALESCE(p_method,'')))=0 OR length(trim(COALESCE(p_account,'')))<4 THEN RAISE EXCEPTION 'Metode dan detail rekening wajib diisi'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 SELECT COALESCE(sum(amount),0) INTO v_available FROM public.referral_commissions WHERE referrer_id=auth.uid();
 SELECT COALESCE(sum(amount),0) INTO v_reserved FROM public.commission_payouts WHERE user_id=auth.uid() AND status='paid';
 v_available:=v_available-v_reserved;
 SELECT v_available-COALESCE(sum(amount),0) INTO v_available FROM public.commission_payout_requests WHERE user_id=auth.uid() AND status IN ('pending','approved');
 IF p_amount>GREATEST(v_available,0) THEN RAISE EXCEPTION 'Saldo yang dapat diajukan tidak cukup. Tersedia: %',GREATEST(v_available,0); END IF;
 INSERT INTO public.commission_payout_requests(user_id,amount,payout_method,payout_account,notes)
 VALUES(auth.uid(),p_amount,trim(p_method),trim(p_account),NULLIF(trim(COALESCE(p_notes,'')),'')) RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.member_list_commission_payout_requests()
RETURNS TABLE(id UUID,amount BIGINT,payout_method TEXT,payout_account TEXT,status TEXT,admin_notes TEXT,created_at TIMESTAMPTZ,reviewed_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Silakan login terlebih dahulu'; END IF;
 RETURN QUERY SELECT r.id,r.amount,r.payout_method,r.payout_account,r.status,r.admin_notes,r.created_at,r.reviewed_at
 FROM public.commission_payout_requests r WHERE r.user_id=auth.uid() ORDER BY r.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_payout_requests()
RETURNS TABLE(id UUID,user_id UUID,email TEXT,full_name TEXT,amount BIGINT,payout_method TEXT,payout_account TEXT,notes TEXT,status TEXT,admin_notes TEXT,created_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 RETURN QUERY SELECT r.id,r.user_id,u.email::text,p.full_name,r.amount,r.payout_method,r.payout_account,r.notes,r.status,r.admin_notes,r.created_at
 FROM public.commission_payout_requests r JOIN auth.users u ON u.id=r.user_id LEFT JOIN public.profiles p ON p.id=r.user_id ORDER BY r.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_payout_request(p_request_id UUID,p_decision TEXT,p_notes TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.commission_payout_requests%ROWTYPE; v_available BIGINT;
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 IF p_decision NOT IN ('approved','rejected') THEN RAISE EXCEPTION 'Keputusan tidak valid'; END IF;
 SELECT * INTO r FROM public.commission_payout_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND OR r.status<>'pending' THEN RAISE EXCEPTION 'Pengajuan tidak ditemukan atau sudah diproses'; END IF;
 IF p_decision='approved' THEN
  PERFORM pg_advisory_xact_lock(hashtextextended(r.user_id::text,0));
  SELECT COALESCE((SELECT sum(amount) FROM public.referral_commissions WHERE referrer_id=r.user_id),0)
   -COALESCE((SELECT sum(amount) FROM public.commission_payouts WHERE user_id=r.user_id AND status='paid'),0)
   -COALESCE((SELECT sum(amount) FROM public.commission_payout_requests WHERE user_id=r.user_id AND status IN ('pending','approved') AND id<>r.id),0)
  INTO v_available;
  IF r.amount>GREATEST(v_available,0) THEN RAISE EXCEPTION 'Saldo tersedia tidak mencukupi untuk menyetujui pengajuan'; END IF;
 END IF;
 UPDATE public.commission_payout_requests SET status=p_decision,admin_notes=NULLIF(p_notes,''),reviewed_by=auth.uid(),reviewed_at=now() WHERE id=r.id;
 PERFORM public.novastria_admin_log('payout_request_'||p_decision,'commission_payout_request',r.id::text,jsonb_build_object('user_id',r.user_id,'amount',r.amount));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_sales()
RETURNS TABLE(id UUID,user_id UUID,customer_name TEXT,customer_contact TEXT,product TEXT,variant TEXT,quantity INTEGER,unit_price BIGINT,cost_price BIGINT,status TEXT,payment_method TEXT,payment_reference TEXT,notes TEXT,created_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 RETURN QUERY SELECT s.id,s.user_id,s.customer_name,s.customer_contact,s.product,s.variant,s.quantity,s.unit_price,s.cost_price,s.status,s.payment_method,s.payment_reference,s.notes,s.created_at FROM public.store_sales s ORDER BY s.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_create_sale(p_user_id UUID,p_customer_name TEXT,p_contact TEXT,p_product TEXT,p_variant TEXT,p_quantity INTEGER,p_unit_price BIGINT,p_cost_price BIGINT,p_status TEXT,p_method TEXT,p_reference TEXT,p_notes TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id UUID;
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 IF length(trim(COALESCE(p_customer_name,'')))=0 OR length(trim(COALESCE(p_product,'')))=0 OR length(trim(COALESCE(p_variant,'')))=0 THEN RAISE EXCEPTION 'Nama pelanggan, produk, dan varian wajib diisi'; END IF;
 IF p_quantity IS NULL OR p_quantity<1 OR p_unit_price<0 OR p_cost_price<0 THEN RAISE EXCEPTION 'Jumlah dan harga tidak valid'; END IF;
 IF p_status NOT IN ('pending','paid','fulfilled','cancelled') THEN RAISE EXCEPTION 'Status penjualan tidak valid'; END IF;
 IF p_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_user_id) THEN RAISE EXCEPTION 'Akun pelanggan tidak ditemukan'; END IF;
 INSERT INTO public.store_sales(user_id,customer_name,customer_contact,product,variant,quantity,unit_price,cost_price,status,payment_method,payment_reference,notes,created_by)
 VALUES(p_user_id,trim(p_customer_name),NULLIF(trim(COALESCE(p_contact,'')),''),trim(p_product),trim(p_variant),p_quantity,p_unit_price,p_cost_price,p_status,NULLIF(trim(COALESCE(p_method,'')),''),NULLIF(trim(COALESCE(p_reference,'')),''),NULLIF(trim(COALESCE(p_notes,'')),''),auth.uid()) RETURNING id INTO v_id;
 PERFORM public.novastria_admin_log('sale_created','store_sale',v_id::text,jsonb_build_object('product',p_product,'variant',p_variant,'quantity',p_quantity,'status',p_status));
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_sale_status(p_sale_id UUID,p_status TEXT,p_notes TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 IF p_status NOT IN ('pending','paid','fulfilled','cancelled') THEN RAISE EXCEPTION 'Status tidak valid'; END IF;
 UPDATE public.store_sales SET status=p_status,notes=COALESCE(NULLIF(p_notes,''),notes),updated_at=now() WHERE id=p_sale_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Penjualan tidak ditemukan'; END IF;
 PERFORM public.novastria_admin_log('sale_status_'||p_status,'store_sale',p_sale_id::text,'{}'::jsonb);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_get_sales_summary()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v JSONB;
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 SELECT jsonb_build_object('orders',(SELECT count(*) FROM public.store_sales WHERE status<>'cancelled'),
  'pending',(SELECT count(*) FROM public.store_sales WHERE status='pending'),
  'revenue',(SELECT COALESCE(sum(quantity*unit_price),0) FROM public.store_sales WHERE status IN ('paid','fulfilled')),
  'cost',(SELECT COALESCE(sum(quantity*cost_price),0) FROM public.store_sales WHERE status IN ('paid','fulfilled')),
  'profit',(SELECT COALESCE(sum(quantity*(unit_price-cost_price)),0) FROM public.store_sales WHERE status IN ('paid','fulfilled'))) INTO v;
 RETURN v;
END; $$;

REVOKE ALL ON FUNCTION public.member_request_commission_payout(BIGINT,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.member_list_commission_payout_requests() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_payout_requests() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_review_payout_request(UUID,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_sales() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_create_sale(UUID,TEXT,TEXT,TEXT,TEXT,INTEGER,BIGINT,BIGINT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_sale_status(UUID,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_get_sales_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.member_request_commission_payout(BIGINT,TEXT,TEXT,TEXT),public.member_list_commission_payout_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_payout_requests(),public.admin_review_payout_request(UUID,TEXT,TEXT),public.admin_list_sales(),public.admin_create_sale(UUID,TEXT,TEXT,TEXT,TEXT,INTEGER,BIGINT,BIGINT,TEXT,TEXT,TEXT,TEXT),public.admin_update_sale_status(UUID,TEXT,TEXT),public.admin_get_sales_summary() TO authenticated;
NOTIFY pgrst,'reload schema';


-- Finalisasi transfer pengajuan yang sudah disetujui.
-- Satu transaksi: catat payout ledger + ubah status request menjadi paid.
CREATE OR REPLACE FUNCTION public.admin_complete_payout_request(p_request_id UUID,p_reference TEXT DEFAULT NULL,p_notes TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.commission_payout_requests%ROWTYPE; v_id UUID; v_available BIGINT;
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 SELECT * INTO r FROM public.commission_payout_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND OR r.status<>'approved' THEN RAISE EXCEPTION 'Pengajuan harus berstatus disetujui sebelum ditandai dibayar'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(r.user_id::text,0));
 SELECT COALESCE((SELECT sum(amount) FROM public.referral_commissions WHERE referrer_id=r.user_id),0)
  -COALESCE((SELECT sum(amount) FROM public.commission_payouts WHERE user_id=r.user_id AND status='paid'),0)
 INTO v_available;
 IF r.amount>GREATEST(v_available,0) THEN RAISE EXCEPTION 'Saldo komisi tidak mencukupi'; END IF;
 INSERT INTO public.commission_payouts(user_id,amount,payment_reference,notes,paid_by)
 VALUES(r.user_id,r.amount,NULLIF(p_reference,''),COALESCE(NULLIF(p_notes,''),'Pencairan dari pengajuan anggota'),auth.uid())
 RETURNING id INTO v_id;
 UPDATE public.commission_payout_requests SET status='paid',admin_notes=COALESCE(NULLIF(p_notes,''),admin_notes),reviewed_by=auth.uid(),reviewed_at=now() WHERE id=r.id;
 PERFORM public.novastria_admin_log('payout_request_paid','commission_payout_request',r.id::text,jsonb_build_object('payout_id',v_id,'amount',r.amount));
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.admin_complete_payout_request(UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_complete_payout_request(UUID,TEXT,TEXT) TO authenticated;
NOTIFY pgrst,'reload schema';
