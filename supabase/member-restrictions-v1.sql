-- Safe member restriction workflow for referral anti-fraud.
-- Additive only: preserves auth.users, profiles, memberships, payments, commissions and orders.

CREATE TABLE IF NOT EXISTS public.member_account_restrictions (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  is_blocked BOOLEAN NOT NULL DEFAULT TRUE,
  block_reason TEXT NOT NULL,
  blocked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  blocked_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  unblocked_at TIMESTAMPTZ,
  unblocked_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT member_account_restrictions_reason_nonempty CHECK (length(trim(block_reason)) > 0)
);

CREATE INDEX IF NOT EXISTS member_account_restrictions_active_idx
  ON public.member_account_restrictions(is_blocked, blocked_at DESC);

ALTER TABLE public.member_account_restrictions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.member_account_restrictions FROM anon, authenticated;

-- Return risk queue plus restriction state without exposing the restriction table.
DROP FUNCTION IF EXISTS public.admin_list_referral_risks();
CREATE FUNCTION public.admin_list_referral_risks()
RETURNS TABLE(
  id BIGINT,user_id UUID,email TEXT,full_name TEXT,phone TEXT,
  related_user_id UUID,related_email TEXT,signal_type TEXT,severity TEXT,
  status TEXT,details JSONB,created_at TIMESTAMPTZ,review_note TEXT,
  is_blocked BOOLEAN,block_reason TEXT,blocked_at TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  RETURN QUERY
  SELECT r.id,r.user_id,u.email::text,p.full_name,p.phone,
    r.related_user_id,ru.email::text,r.signal_type,r.severity,r.status,r.details,r.created_at,r.review_note,
    COALESCE(ar.is_blocked,false),ar.block_reason,ar.blocked_at
  FROM public.referral_risk_signals r
  JOIN auth.users u ON u.id=r.user_id
  LEFT JOIN public.profiles p ON p.id=r.user_id
  LEFT JOIN auth.users ru ON ru.id=r.related_user_id
  LEFT JOIN public.member_account_restrictions ar ON ar.user_id=r.user_id
  ORDER BY CASE r.status WHEN 'open' THEN 0 ELSE 1 END,
    CASE r.severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
    r.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_block_referral_member(
  p_user_id UUID,p_signal_id BIGINT,p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_reason TEXT;
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  v_reason := NULLIF(trim(COALESCE(p_reason,'')),'');
  IF v_reason IS NULL OR length(v_reason)<5 THEN
    RAISE EXCEPTION 'Alasan blokir wajib diisi minimal 5 karakter';
  END IF;
  IF p_user_id IS NULL OR p_user_id=auth.uid() THEN
    RAISE EXCEPTION 'Target akun tidak valid';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=p_user_id) THEN
    RAISE EXCEPTION 'Anggota tidak ditemukan';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.referral_risk_signals
    WHERE id=p_signal_id AND user_id=p_user_id AND status='confirmed'
  ) THEN
    RAISE EXCEPTION 'Blokir hanya dapat dilakukan pada akun dengan sinyal fraud terkonfirmasi';
  END IF;
  INSERT INTO public.member_account_restrictions(
    user_id,is_blocked,block_reason,blocked_at,blocked_by,unblocked_at,unblocked_by,updated_at
  ) VALUES(p_user_id,true,v_reason,now(),auth.uid(),NULL,NULL,now())
  ON CONFLICT(user_id) DO UPDATE SET
    is_blocked=true,block_reason=EXCLUDED.block_reason,
    blocked_at=now(),blocked_by=auth.uid(),
    unblocked_at=NULL,unblocked_by=NULL,updated_at=now();
  INSERT INTO public.admin_audit_logs(admin_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'member_blocked','auth_user',p_user_id::text,
    jsonb_build_object('reason',v_reason,'risk_signal_id',p_signal_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_unblock_referral_member(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_reason TEXT;
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  UPDATE public.member_account_restrictions
  SET is_blocked=false,unblocked_at=now(),unblocked_by=auth.uid(),updated_at=now()
  WHERE user_id=p_user_id AND is_blocked=true
  RETURNING block_reason INTO v_reason;
  IF NOT FOUND THEN RAISE EXCEPTION 'Akun tidak ditemukan dalam status diblokir'; END IF;
  INSERT INTO public.admin_audit_logs(admin_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'member_unblocked','auth_user',p_user_id::text,
    jsonb_build_object('previous_block_reason',v_reason));
END;
$$;

-- Member-facing status RPC. A blocked user can only learn that their own account is restricted.
CREATE OR REPLACE FUNCTION public.member_is_account_blocked()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.member_account_restrictions
    WHERE user_id=auth.uid() AND is_blocked=true
  );
$$;

-- Prevent an admin or other trusted RPC from reactivating membership while the restriction is active.
CREATE OR REPLACE FUNCTION public.guard_blocked_member_membership()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NEW.status='active' AND EXISTS (
    SELECT 1 FROM public.member_account_restrictions
    WHERE user_id=NEW.user_id AND is_blocked=true
  ) THEN
    RAISE EXCEPTION 'Akun anggota diblokir karena keputusan Anti-Fraud Referral';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS guard_blocked_member_membership_before_write ON public.memberships;
CREATE TRIGGER guard_blocked_member_membership_before_write
BEFORE INSERT OR UPDATE OF status,user_id ON public.memberships
FOR EACH ROW EXECUTE FUNCTION public.guard_blocked_member_membership();

-- Preserve the existing payout guard and add a hard block check at database level.
CREATE OR REPLACE FUNCTION public.guard_referral_commission_payout()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.member_account_restrictions
    WHERE user_id=NEW.user_id AND is_blocked=true
  ) THEN
    RAISE EXCEPTION 'Pencairan ditahan: akun penerima diblokir oleh Anti-Fraud Referral';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.referral_risk_signals
    WHERE user_id=NEW.user_id AND status IN ('open','confirmed')
  ) THEN
    RAISE EXCEPTION 'Pencairan ditahan: terdapat sinyal anti-fraud yang belum ditinjau admin';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_block_referral_member(UUID,BIGINT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_unblock_referral_member(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.member_is_account_blocked() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_blocked_member_membership() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_referral_risks() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_block_referral_member(UUID,BIGINT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_unblock_referral_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.member_is_account_blocked() TO authenticated;

NOTIFY pgrst,'reload schema';

-- Additional database guards for member-originated operations.
-- Updates to existing requests (e.g. admin review) remain possible because the
-- triggers run only on INSERT or a change to user_id.
CREATE OR REPLACE FUNCTION public.guard_blocked_member_activity()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NEW.user_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.member_account_restrictions
    WHERE user_id=NEW.user_id AND is_blocked=true
  ) THEN
    RAISE EXCEPTION 'Akun diblokir oleh administrator melalui Anti-Fraud Referral';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_blocked_commission_request ON public.commission_payout_requests;
CREATE TRIGGER guard_blocked_commission_request
BEFORE INSERT OR UPDATE OF user_id ON public.commission_payout_requests
FOR EACH ROW EXECUTE FUNCTION public.guard_blocked_member_activity();

DROP TRIGGER IF EXISTS guard_blocked_referral_payout_request ON public.referral_payouts;
CREATE TRIGGER guard_blocked_referral_payout_request
BEFORE INSERT OR UPDATE OF user_id ON public.referral_payouts
FOR EACH ROW EXECUTE FUNCTION public.guard_blocked_member_activity();

DROP TRIGGER IF EXISTS guard_blocked_wallet_deposit_request ON public.wallet_deposit_requests;
CREATE TRIGGER guard_blocked_wallet_deposit_request
BEFORE INSERT OR UPDATE OF user_id ON public.wallet_deposit_requests
FOR EACH ROW EXECUTE FUNCTION public.guard_blocked_member_activity();

DROP TRIGGER IF EXISTS guard_blocked_member_order ON public.orders;
CREATE TRIGGER guard_blocked_member_order
BEFORE INSERT OR UPDATE OF user_id ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_blocked_member_activity();

REVOKE ALL ON FUNCTION public.guard_blocked_member_activity() FROM PUBLIC;
