-- NOVASTRIA checkout v2: QRIS for customers, atomic reseller wallet debit.
-- Run once in Supabase Dashboard > SQL Editor after order-tracking-v1.sql and wallet-v1.sql.

-- Keep order <-> wallet ledger linkage so cancellation can refund exactly once.
ALTER TABLE public.wallet_transactions
  ADD COLUMN IF NOT EXISTS store_order_id UUID REFERENCES public.store_orders(id) ON DELETE RESTRICT;
DROP INDEX IF EXISTS public.wallet_transactions_store_order_once;
CREATE UNIQUE INDEX IF NOT EXISTS wallet_transactions_store_order_type_once
  ON public.wallet_transactions(store_order_id,transaction_type)
  WHERE store_order_id IS NOT NULL;

-- Customer order: price and stock are read from the server-side catalog, never trusted from browser.
CREATE OR REPLACE FUNCTION public.create_public_order(
  p_customer_name text, p_customer_phone text, p_product text, p_variant text,
  p_account_detail text DEFAULT NULL, p_quantity integer DEFAULT 1,
  p_unit_price bigint DEFAULT 0, p_payment_method text DEFAULT 'QRIS'
) RETURNS TABLE(order_code text, unit_price bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_code text; v_attempt integer := 0; v_price bigint; v_order_id uuid;
BEGIN
  IF length(trim(coalesce(p_customer_name,''))) < 2 THEN RAISE EXCEPTION 'Nama pelanggan wajib diisi'; END IF;
  IF length(regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')) < 8 THEN RAISE EXCEPTION 'Nomor WhatsApp tidak valid'; END IF;
  IF length(trim(coalesce(p_product,''))) = 0 OR length(trim(coalesce(p_variant,''))) = 0 THEN RAISE EXCEPTION 'Produk dan varian wajib diisi'; END IF;
  IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > 20 THEN RAISE EXCEPTION 'Jumlah tidak valid'; END IF;

  SELECT sp.public_price INTO v_price
  FROM public.store_products sp
  WHERE sp.product=trim(p_product) AND sp.variant=trim(p_variant)
    AND sp.is_active=true AND sp.in_stock=true
  FOR SHARE;
  IF NOT FOUND OR v_price IS NULL OR v_price <= 0 THEN RAISE EXCEPTION 'Produk tidak tersedia atau harga belum ditetapkan'; END IF;

  LOOP
    v_code := 'RKW-' || lpad(floor(random() * 10000000)::bigint::text,7,'0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.store_orders o WHERE o.order_code = v_code);
    v_attempt := v_attempt + 1;
    IF v_attempt > 20 THEN RAISE EXCEPTION 'Gagal membuat kode pesanan. Silakan coba lagi'; END IF;
  END LOOP;
  INSERT INTO public.store_orders(order_code,customer_name,customer_phone,product,variant,account_detail,quantity,unit_price,payment_method,status)
  VALUES(v_code,trim(p_customer_name),regexp_replace(p_customer_phone,'[^0-9]','','g'),
    trim(p_product),trim(p_variant),nullif(trim(coalesce(p_account_detail,'')),''),p_quantity,v_price,'QRIS','pending_payment')
  RETURNING id INTO v_order_id;
  RETURN QUERY SELECT v_code,v_price;
END; $$;

-- Reseller checkout: authenticated active reseller only; locks balance operation,
-- checks current catalog price/stock, creates order and debits wallet in one transaction.
CREATE OR REPLACE FUNCTION public.create_reseller_order(
  p_customer_name text, p_customer_phone text, p_product text, p_variant text,
  p_account_detail text DEFAULT NULL, p_quantity integer DEFAULT 1
) RETURNS TABLE(order_code text, unit_price bigint, total_price bigint, wallet_balance bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_user uuid; v_price bigint; v_total bigint; v_balance bigint;
        v_code text; v_attempt integer := 0; v_order_id uuid;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN RAISE EXCEPTION 'Silakan login sebagai reseller terlebih dahulu'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.memberships m WHERE m.user_id=v_user AND m.membership_type='reseller' AND m.status='active') THEN
    RAISE EXCEPTION 'Akun ini belum memiliki status Reseller aktif';
  END IF;
  IF length(trim(coalesce(p_customer_name,''))) < 2 THEN RAISE EXCEPTION 'Nama pelanggan wajib diisi'; END IF;
  IF length(regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')) < 8 THEN RAISE EXCEPTION 'Nomor WhatsApp tidak valid'; END IF;
  IF length(trim(coalesce(p_product,'')))=0 OR length(trim(coalesce(p_variant,'')))=0 THEN RAISE EXCEPTION 'Produk dan varian wajib diisi'; END IF;
  IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > 20 THEN RAISE EXCEPTION 'Jumlah tidak valid'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_user::text,0));
  SELECT sp.reseller_price INTO v_price
  FROM public.store_products sp
  WHERE sp.product=trim(p_product) AND sp.variant=trim(p_variant)
    AND sp.is_active=true AND sp.in_stock=true
  FOR SHARE;
  IF NOT FOUND OR v_price IS NULL OR v_price <= 0 THEN RAISE EXCEPTION 'Produk reseller tidak tersedia atau harga belum ditetapkan'; END IF;
  v_total := v_price * p_quantity;
  SELECT COALESCE(sum(CASE WHEN wt.direction='credit' THEN wt.amount ELSE -wt.amount END),0)
    INTO v_balance FROM public.wallet_transactions wt WHERE wt.user_id=v_user;
  IF v_balance < v_total THEN RAISE EXCEPTION 'Saldo reseller tidak cukup. Saldo tersedia Rp%, total pesanan Rp%',v_balance,v_total; END IF;

  LOOP
    v_code := 'RKW-' || lpad(floor(random() * 10000000)::bigint::text,7,'0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.store_orders o WHERE o.order_code=v_code);
    v_attempt := v_attempt + 1;
    IF v_attempt > 20 THEN RAISE EXCEPTION 'Gagal membuat kode pesanan. Silakan coba lagi'; END IF;
  END LOOP;

  INSERT INTO public.store_orders(order_code,customer_name,customer_phone,product,variant,account_detail,quantity,unit_price,payment_method,status)
  VALUES(v_code,trim(p_customer_name),regexp_replace(p_customer_phone,'[^0-9]','','g'),
    trim(p_product),trim(p_variant),nullif(trim(coalesce(p_account_detail,'')),''),p_quantity,v_price,'Saldo reseller','processing')
  RETURNING id INTO v_order_id;

  INSERT INTO public.wallet_transactions(user_id,direction,transaction_type,amount,description,store_order_id,created_by)
  VALUES(v_user,'debit','purchase',v_total,'Pembelian pesanan '||v_code,v_order_id,v_user);

  RETURN QUERY SELECT v_code,v_price,v_total,v_balance-v_total;
END; $$;

-- Admin cancellation refunds a reseller purchase exactly once.
CREATE OR REPLACE FUNCTION public.admin_update_store_order(p_order_id uuid,p_status text,p_admin_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE o public.store_orders%ROWTYPE;
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  IF p_status NOT IN ('pending_payment','pending_verification','processing','completed','cancelled') THEN RAISE EXCEPTION 'Status pesanan tidak valid'; END IF;
  SELECT * INTO o FROM public.store_orders WHERE id=p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pesanan tidak ditemukan'; END IF;
  IF o.status IN ('completed','cancelled') AND o.status<>p_status THEN RAISE EXCEPTION 'Pesanan selesai/dibatalkan tidak dapat diubah lagi'; END IF;

  IF p_status='cancelled' AND o.payment_method='Saldo reseller' THEN
    INSERT INTO public.wallet_transactions(user_id,direction,transaction_type,amount,description,store_order_id,created_by)
    SELECT wt.user_id,'credit','refund',wt.amount,'Pengembalian saldo pesanan '||o.order_code,o.id,auth.uid()
    FROM public.wallet_transactions wt
    WHERE wt.store_order_id=o.id AND wt.transaction_type='purchase'
    ON CONFLICT (store_order_id,transaction_type) WHERE store_order_id IS NOT NULL DO NOTHING;
  END IF;

  UPDATE public.store_orders SET status=p_status,admin_note=nullif(trim(coalesce(p_admin_note,'')),''),updated_at=now() WHERE id=o.id;
  PERFORM public.novastria_admin_log('store_order_'||p_status,'store_order',o.id::text,jsonb_build_object('status',p_status));
END; $$;

REVOKE ALL ON FUNCTION public.create_public_order(text,text,text,text,text,integer,bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_reseller_order(text,text,text,text,text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_store_order(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_public_order(text,text,text,text,text,integer,bigint,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_reseller_order(text,text,text,text,text,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_store_order(uuid,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
