-- NOVASTRIA: konfigurasi tujuan pembayaran manual
-- Jalankan satu kali di Supabase Dashboard > SQL Editor.
-- Nomor dan nama penerima disimpan di database, bukan repository publik.

CREATE TABLE IF NOT EXISTS public.payment_settings (
  setting_key TEXT PRIMARY KEY DEFAULT 'primary',
  payment_method TEXT NOT NULL DEFAULT 'DANA' CHECK (payment_method = 'DANA'),
  account_number TEXT NOT NULL DEFAULT '',
  account_name TEXT NOT NULL DEFAULT '',
  instructions TEXT NOT NULL DEFAULT 'Transfer sesuai nominal pesanan. Pesanan diproses setelah pembayaran diperiksa admin.',
  is_active BOOLEAN NOT NULL DEFAULT false,
  updated_by UUID REFERENCES auth.users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT payment_settings_singleton CHECK (setting_key = 'primary'),
  CONSTRAINT payment_settings_account_number_length CHECK (length(account_number) <= 40),
  CONSTRAINT payment_settings_account_name_length CHECK (length(account_name) <= 100),
  CONSTRAINT payment_settings_instructions_length CHECK (length(instructions) <= 500)
);

ALTER TABLE public.payment_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_settings FROM anon, authenticated;

INSERT INTO public.payment_settings(setting_key,payment_method,account_number,account_name,instructions,is_active)
VALUES('primary','DANA','','','Transfer sesuai nominal. Admin akan memeriksa pembayaran sebelum pesanan diproses.',false)
ON CONFLICT(setting_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_get_payment_settings()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v JSONB;
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  SELECT jsonb_build_object(
    'payment_method',payment_method,'account_number',account_number,
    'account_name',account_name,'instructions',instructions,
    'is_active',is_active,'updated_at',updated_at
  ) INTO v FROM public.payment_settings WHERE setting_key='primary';
  RETURN COALESCE(v,'{}'::jsonb);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_save_payment_settings(
  p_account_number TEXT,p_account_name TEXT,p_instructions TEXT,p_is_active BOOLEAN
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  IF length(trim(COALESCE(p_account_number,''))) > 40 THEN RAISE EXCEPTION 'Nomor akun maksimal 40 karakter'; END IF;
  IF length(trim(COALESCE(p_account_name,''))) > 100 THEN RAISE EXCEPTION 'Nama penerima maksimal 100 karakter'; END IF;
  IF length(trim(COALESCE(p_instructions,''))) > 500 THEN RAISE EXCEPTION 'Instruksi maksimal 500 karakter'; END IF;
  IF p_is_active AND (length(trim(COALESCE(p_account_number,''))) < 6 OR length(trim(COALESCE(p_account_name,''))) < 2) THEN
    RAISE EXCEPTION 'Isi nomor DANA dan nama penerima sebelum mengaktifkan pembayaran';
  END IF;
  INSERT INTO public.payment_settings(setting_key,payment_method,account_number,account_name,instructions,is_active,updated_by,updated_at)
  VALUES('primary','DANA',trim(COALESCE(p_account_number,'')),trim(COALESCE(p_account_name,'')),
    COALESCE(NULLIF(trim(COALESCE(p_instructions,'')),''),'Transfer sesuai nominal. Admin akan memeriksa pembayaran sebelum pesanan diproses.'),
    COALESCE(p_is_active,false),auth.uid(),now())
  ON CONFLICT(setting_key) DO UPDATE SET
    account_number=EXCLUDED.account_number,account_name=EXCLUDED.account_name,
    instructions=EXCLUDED.instructions,is_active=EXCLUDED.is_active,
    updated_by=auth.uid(),updated_at=now();
  PERFORM public.novastria_admin_log('payment_settings_updated','payment_settings','primary',
    jsonb_build_object('payment_method','DANA','is_active',COALESCE(p_is_active,false)));
END; $$;

-- Hanya data tujuan pembayaran yang memang diperlukan pelanggan yang dipublikasikan.
CREATE OR REPLACE FUNCTION public.get_public_payment_instructions()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT CASE WHEN is_active THEN jsonb_build_object(
    'available',true,'payment_method',payment_method,
    'account_number',account_number,'account_name',account_name,
    'instructions',instructions
  ) ELSE jsonb_build_object('available',false,'payment_method','DANA') END
  FROM public.payment_settings WHERE setting_key='primary'
  UNION ALL
  SELECT jsonb_build_object('available',false,'payment_method','DANA')
  WHERE NOT EXISTS(SELECT 1 FROM public.payment_settings WHERE setting_key='primary')
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.admin_get_payment_settings() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_save_payment_settings(TEXT,TEXT,TEXT,BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_payment_instructions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_payment_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_save_payment_settings(TEXT,TEXT,TEXT,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_payment_instructions() TO anon,authenticated;
NOTIFY pgrst,'reload schema';
