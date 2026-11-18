-- NOVASTRIA Referral Anti-Fraud v1
-- Jalankan SEKALI setelah setup-auth.sql, setup-admin.sql, dan admin-controller-v2.sql.
-- Sinyal risiko bersifat indikatif, bukan bukti fraud. Keputusan tetap oleh admin.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.referral_risk_signals (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  related_user_id UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  signal_type TEXT NOT NULL CHECK (signal_type IN ('shared_device_token','duplicate_phone')),
  severity TEXT NOT NULL DEFAULT 'medium' CHECK (severity IN ('low','medium','high')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','cleared','confirmed')),
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES auth.users(id),
  review_note TEXT
);
CREATE INDEX IF NOT EXISTS referral_risk_user_status_idx
  ON public.referral_risk_signals(user_id,status,created_at DESC);
CREATE INDEX IF NOT EXISTS referral_risk_status_idx
  ON public.referral_risk_signals(status,created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS referral_risk_dedupe_idx
  ON public.referral_risk_signals(user_id,COALESCE(related_user_id,'00000000-0000-0000-0000-000000000000'::uuid),signal_type)
  WHERE status='open';

ALTER TABLE public.referral_risk_signals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.referral_risk_signals FROM anon,authenticated;

-- Simpan hash token instalasi, bukan token mentah. Token ini hanya sinyal,
-- bukan fingerprint perangkat yang tidak dapat diubah.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS device_token_hash TEXT;

CREATE OR REPLACE FUNCTION public.capture_referral_risk_signals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_token TEXT;
  v_hash TEXT;
  v_phone TEXT;
  v_existing RECORD;
BEGIN
  v_token := NULLIF(trim(COALESCE(
    (SELECT raw_user_meta_data->>'device_token' FROM auth.users WHERE id=NEW.id), ''
  )), '');
  v_phone := regexp_replace(COALESCE(NEW.phone,''),'[^0-9]','','g');

  IF v_token IS NOT NULL THEN
    v_hash := encode(extensions.digest(v_token,'sha256'),'hex');
    UPDATE public.profiles SET device_token_hash=v_hash WHERE id=NEW.id;

    FOR v_existing IN
      SELECT id FROM public.profiles
      WHERE device_token_hash=v_hash AND id<>NEW.id
    LOOP
      INSERT INTO public.referral_risk_signals(user_id,related_user_id,signal_type,severity,details)
      VALUES
        (NEW.id,v_existing.id,'shared_device_token','high',jsonb_build_object('reason','Installation token appears on multiple accounts')),
        (v_existing.id,NEW.id,'shared_device_token','high',jsonb_build_object('reason','Installation token appears on multiple accounts'))
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;

  IF v_phone<>'' THEN
    FOR v_existing IN
      SELECT id FROM public.profiles
      WHERE regexp_replace(COALESCE(phone,''),'[^0-9]','','g')=v_phone AND id<>NEW.id
    LOOP
      INSERT INTO public.referral_risk_signals(user_id,related_user_id,signal_type,severity,details)
      VALUES
        (NEW.id,v_existing.id,'duplicate_phone','medium',jsonb_build_object('reason','Phone number appears on multiple accounts')),
        (v_existing.id,NEW.id,'duplicate_phone','medium',jsonb_build_object('reason','Phone number appears on multiple accounts'))
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS novastria_profile_referral_risk ON public.profiles;
CREATE TRIGGER novastria_profile_referral_risk
AFTER INSERT ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.capture_referral_risk_signals();

-- Admin-only queue; no direct table access from browser.
CREATE OR REPLACE FUNCTION public.admin_list_referral_risks()
RETURNS TABLE(
  id BIGINT,user_id UUID,email TEXT,full_name TEXT,phone TEXT,
  related_user_id UUID,related_email TEXT,signal_type TEXT,severity TEXT,
  status TEXT,details JSONB,created_at TIMESTAMPTZ,review_note TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  RETURN QUERY
  SELECT r.id,r.user_id,u.email::text,p.full_name,p.phone,
    r.related_user_id,ru.email::text,r.signal_type,r.severity,r.status,r.details,r.created_at,r.review_note
  FROM public.referral_risk_signals r
  JOIN auth.users u ON u.id=r.user_id
  LEFT JOIN public.profiles p ON p.id=r.user_id
  LEFT JOIN auth.users ru ON ru.id=r.related_user_id
  ORDER BY CASE r.status WHEN 'open' THEN 0 ELSE 1 END,
    CASE r.severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
    r.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_review_referral_risk(
  p_signal_id BIGINT,p_decision TEXT,p_note TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  IF p_decision NOT IN ('cleared','confirmed') THEN RAISE EXCEPTION 'Keputusan tidak valid'; END IF;
  UPDATE public.referral_risk_signals
  SET status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),
      review_note=NULLIF(trim(COALESCE(p_note,'')),'')
  WHERE id=p_signal_id AND status='open';
  IF NOT FOUND THEN RAISE EXCEPTION 'Sinyal tidak ditemukan atau sudah ditinjau'; END IF;
  INSERT INTO public.admin_audit_logs(admin_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'referral_risk_'||p_decision,'referral_risk_signal',p_signal_id::text,
    jsonb_build_object('note',p_note));
END;
$$;

-- Cegah pencairan selama penerima memiliki sinyal risiko yang masih terbuka.
-- Berlaku juga jika payout dicoba melalui jalur SQL lain.
CREATE OR REPLACE FUNCTION public.guard_referral_commission_payout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.referral_risk_signals
    WHERE user_id=NEW.user_id AND status='open'
  ) THEN
    RAISE EXCEPTION 'Pencairan ditahan: terdapat sinyal anti-fraud yang belum ditinjau admin';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_referral_commission_payout_before_insert ON public.commission_payouts;
CREATE TRIGGER guard_referral_commission_payout_before_insert
BEFORE INSERT ON public.commission_payouts
FOR EACH ROW EXECUTE FUNCTION public.guard_referral_commission_payout();

REVOKE ALL ON FUNCTION public.capture_referral_risk_signals() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_referral_risks() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_review_referral_risk(BIGINT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_referral_commission_payout() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_referral_risks() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_referral_risk(BIGINT,TEXT,TEXT) TO authenticated;

NOTIFY pgrst,'reload schema';
