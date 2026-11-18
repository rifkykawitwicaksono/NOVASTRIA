-- NOVASTRIA product details v1. Run once in Supabase SQL Editor.
CREATE TABLE IF NOT EXISTS public.store_product_details (
 product TEXT PRIMARY KEY, platform TEXT NOT NULL DEFAULT '',
 operational_status TEXT NOT NULL DEFAULT 'unknown' CHECK (operational_status IN ('online','offline','unknown')),
 file_url TEXT, description TEXT NOT NULL DEFAULT '', instructions TEXT NOT NULL DEFAULT '',
 requirements TEXT NOT NULL DEFAULT '', warranty TEXT NOT NULL DEFAULT '', additional_info TEXT NOT NULL DEFAULT '',
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.store_product_details ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public can read details for active products" ON public.store_product_details;
CREATE POLICY "Public can read details for active products" ON public.store_product_details FOR SELECT TO anon, authenticated
 USING (EXISTS (SELECT 1 FROM public.store_products sp WHERE sp.product=store_product_details.product AND sp.is_active=true));
DROP POLICY IF EXISTS "NOVASTRIA admins manage product details" ON public.store_product_details;
CREATE POLICY "NOVASTRIA admins manage product details" ON public.store_product_details FOR ALL TO authenticated
 USING (public.is_novastria_admin()) WITH CHECK (public.is_novastria_admin());
GRANT SELECT ON public.store_product_details TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.store_product_details TO authenticated;
CREATE OR REPLACE FUNCTION public.admin_save_product_details(
 p_product TEXT,p_platform TEXT DEFAULT '',p_operational_status TEXT DEFAULT 'unknown',p_file_url TEXT DEFAULT NULL,
 p_description TEXT DEFAULT '',p_instructions TEXT DEFAULT '',p_requirements TEXT DEFAULT '',p_warranty TEXT DEFAULT '',p_additional_info TEXT DEFAULT ''
) RETURNS TEXT LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
 IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
 IF NULLIF(trim(p_product),'') IS NULL THEN RAISE EXCEPTION 'Nama produk wajib diisi'; END IF;
 IF p_operational_status NOT IN ('online','offline','unknown') THEN RAISE EXCEPTION 'Status operasional tidak valid'; END IF;
 IF p_file_url IS NOT NULL AND p_file_url !~ '^https?://' THEN RAISE EXCEPTION 'URL file harus http atau https'; END IF;
 INSERT INTO public.store_product_details(product,platform,operational_status,file_url,description,instructions,requirements,warranty,additional_info,updated_at)
 VALUES(trim(p_product),COALESCE(p_platform,''),p_operational_status,p_file_url,COALESCE(p_description,''),COALESCE(p_instructions,''),COALESCE(p_requirements,''),COALESCE(p_warranty,''),COALESCE(p_additional_info,''),now())
 ON CONFLICT(product) DO UPDATE SET platform=EXCLUDED.platform,operational_status=EXCLUDED.operational_status,file_url=EXCLUDED.file_url,description=EXCLUDED.description,instructions=EXCLUDED.instructions,requirements=EXCLUDED.requirements,warranty=EXCLUDED.warranty,additional_info=EXCLUDED.additional_info,updated_at=now();
 RETURN trim(p_product);
END; $$;
REVOKE ALL ON FUNCTION public.admin_save_product_details(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_save_product_details(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;
NOTIFY pgrst,'reload schema';
