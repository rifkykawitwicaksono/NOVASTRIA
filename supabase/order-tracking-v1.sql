-- NOVASTRIA order tracking v1
-- Run once in Supabase Dashboard > SQL Editor.
CREATE TABLE IF NOT EXISTS public.store_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_code text NOT NULL UNIQUE CHECK (order_code ~ '^RKW-[0-9]{7}$'),
  customer_name text NOT NULL,
  customer_phone text NOT NULL,
  product text NOT NULL,
  variant text NOT NULL,
  account_detail text,
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price bigint NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  payment_method text NOT NULL DEFAULT 'QRIS',
  status text NOT NULL DEFAULT 'pending_payment'
    CHECK (status IN ('pending_payment','pending_verification','processing','completed','cancelled')),
  admin_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS store_orders_created_idx ON public.store_orders(created_at DESC);
CREATE INDEX IF NOT EXISTS store_orders_status_idx ON public.store_orders(status);
ALTER TABLE public.store_orders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.store_orders FROM anon, authenticated;
GRANT SELECT ON public.store_orders TO authenticated;
DROP POLICY IF EXISTS "NOVASTRIA admins read store orders" ON public.store_orders;
CREATE POLICY "NOVASTRIA admins read store orders" ON public.store_orders
  FOR SELECT TO authenticated USING (public.is_novastria_admin());

CREATE OR REPLACE FUNCTION public.create_public_order(
  p_customer_name text, p_customer_phone text, p_product text, p_variant text,
  p_account_detail text DEFAULT NULL, p_quantity integer DEFAULT 1,
  p_unit_price bigint DEFAULT 0, p_payment_method text DEFAULT 'QRIS'
) RETURNS TABLE(order_code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_code text; v_attempt integer := 0;
BEGIN
  IF length(trim(coalesce(p_customer_name,''))) < 2 THEN RAISE EXCEPTION 'Nama pelanggan wajib diisi'; END IF;
  IF length(regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')) < 8 THEN RAISE EXCEPTION 'Nomor WhatsApp tidak valid'; END IF;
  IF length(trim(coalesce(p_product,''))) = 0 OR length(trim(coalesce(p_variant,''))) = 0 THEN RAISE EXCEPTION 'Produk dan varian wajib diisi'; END IF;
  IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > 20 OR p_unit_price IS NULL OR p_unit_price < 0 THEN RAISE EXCEPTION 'Jumlah atau harga tidak valid'; END IF;
  LOOP
    v_code := 'RKW-' || lpad(floor(random() * 10000000)::bigint::text,7,'0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.store_orders o WHERE o.order_code = v_code);
    v_attempt := v_attempt + 1;
    IF v_attempt > 20 THEN RAISE EXCEPTION 'Gagal membuat kode pesanan. Silakan coba lagi'; END IF;
  END LOOP;
  INSERT INTO public.store_orders(order_code,customer_name,customer_phone,product,variant,account_detail,quantity,unit_price,payment_method)
  VALUES(v_code,trim(p_customer_name),regexp_replace(p_customer_phone,'[^0-9]','','g'),
    trim(p_product),trim(p_variant),nullif(trim(coalesce(p_account_detail,'')),''),p_quantity,p_unit_price,
    coalesce(nullif(trim(p_payment_method),''),'QRIS'));
  RETURN QUERY SELECT v_code;
END; $$;

CREATE OR REPLACE FUNCTION public.lookup_public_order(p_order_code text,p_customer_phone text)
RETURNS TABLE(order_code text,product text,variant text,quantity integer,unit_price bigint,status text,created_at timestamptz,updated_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN QUERY
  SELECT o.order_code,o.product,o.variant,o.quantity,o.unit_price,o.status,o.created_at,o.updated_at
  FROM public.store_orders o
  WHERE upper(trim(o.order_code)) = upper(trim(coalesce(p_order_code,'')))
    AND o.customer_phone = regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')
  LIMIT 1;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_store_orders()
RETURNS TABLE(id uuid,order_code text,customer_name text,customer_phone text,product text,variant text,account_detail text,quantity integer,unit_price bigint,payment_method text,status text,admin_note text,created_at timestamptz,updated_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  RETURN QUERY SELECT o.id,o.order_code,o.customer_name,o.customer_phone,o.product,o.variant,o.account_detail,o.quantity,o.unit_price,o.payment_method,o.status,o.admin_note,o.created_at,o.updated_at
  FROM public.store_orders o ORDER BY o.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_store_order(p_order_id uuid,p_status text,p_admin_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  IF p_status NOT IN ('pending_payment','pending_verification','processing','completed','cancelled') THEN RAISE EXCEPTION 'Status pesanan tidak valid'; END IF;
  UPDATE public.store_orders SET status=p_status,admin_note=nullif(trim(coalesce(p_admin_note,'')),''),updated_at=now() WHERE id=p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pesanan tidak ditemukan'; END IF;
  PERFORM public.novastria_admin_log('store_order_'||p_status,'store_order',p_order_id::text,jsonb_build_object('status',p_status));
END; $$;

REVOKE ALL ON FUNCTION public.create_public_order(text,text,text,text,text,integer,bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lookup_public_order(text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_store_orders() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_store_order(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_public_order(text,text,text,text,text,integer,bigint,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_public_order(text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_store_orders(),public.admin_update_store_order(uuid,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
