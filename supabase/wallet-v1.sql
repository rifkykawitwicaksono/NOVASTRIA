-- NOVASTRIA Wallet v1
-- Run once in Supabase Dashboard > SQL Editor after admin-controller-v2.sql and admin-controller-v3.sql.
-- All wallet balances are derived from an append-only ledger. Clients cannot write ledger rows.

CREATE TABLE IF NOT EXISTS public.wallet_deposit_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  amount BIGINT NOT NULL CHECK (amount >= 10000),
  payment_method TEXT NOT NULL CHECK (length(trim(payment_method)) BETWEEN 2 AND 40),
  sender_name TEXT NOT NULL CHECK (length(trim(sender_name)) BETWEEN 2 AND 100),
  payment_reference TEXT,
  proof_url TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','verified','rejected')),
  admin_notes TEXT,
  reviewed_by UUID REFERENCES auth.users(id),
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS wallet_deposit_user_created_idx
  ON public.wallet_deposit_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS wallet_deposit_status_created_idx
  ON public.wallet_deposit_requests(status, created_at ASC);

CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  direction TEXT NOT NULL CHECK (direction IN ('credit','debit')),
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('deposit','purchase','admin_adjustment','refund')),
  amount BIGINT NOT NULL CHECK (amount > 0),
  description TEXT NOT NULL,
  deposit_request_id UUID UNIQUE REFERENCES public.wallet_deposit_requests(id) ON DELETE RESTRICT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((transaction_type = 'deposit' AND direction = 'credit' AND deposit_request_id IS NOT NULL)
      OR (transaction_type <> 'deposit' AND deposit_request_id IS NULL))
);
CREATE INDEX IF NOT EXISTS wallet_transactions_user_created_idx
  ON public.wallet_transactions(user_id, created_at DESC);

ALTER TABLE public.wallet_deposit_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wallet_deposit_requests FROM anon, authenticated;
REVOKE ALL ON public.wallet_transactions FROM anon, authenticated;
GRANT SELECT ON public.wallet_deposit_requests, public.wallet_transactions TO authenticated;

DROP POLICY IF EXISTS "Members read own wallet deposit requests" ON public.wallet_deposit_requests;
CREATE POLICY "Members read own wallet deposit requests"
  ON public.wallet_deposit_requests FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_novastria_admin());

DROP POLICY IF EXISTS "Members read own wallet transactions" ON public.wallet_transactions;
CREATE POLICY "Members read own wallet transactions"
  ON public.wallet_transactions FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_novastria_admin());

CREATE OR REPLACE FUNCTION public.member_create_wallet_deposit(
  p_amount BIGINT, p_method TEXT, p_sender_name TEXT,
  p_reference TEXT DEFAULT NULL, p_proof_url TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Silakan login terlebih dahulu'; END IF;
  IF p_amount IS NULL OR p_amount < 10000 THEN RAISE EXCEPTION 'Minimal deposit adalah Rp10.000'; END IF;
  IF length(trim(COALESCE(p_method,''))) NOT BETWEEN 2 AND 40 THEN RAISE EXCEPTION 'Metode pembayaran wajib dipilih'; END IF;
  IF length(trim(COALESCE(p_sender_name,''))) NOT BETWEEN 2 AND 100 THEN RAISE EXCEPTION 'Nama pengirim wajib diisi'; END IF;
  IF NULLIF(trim(COALESCE(p_proof_url,'')),'') IS NOT NULL
     AND trim(p_proof_url) !~* '^https://[^[:space:]]+$' THEN
    RAISE EXCEPTION 'Tautan bukti harus menggunakan HTTPS';
  END IF;
  INSERT INTO public.wallet_deposit_requests(user_id,amount,payment_method,sender_name,payment_reference,proof_url)
  VALUES(auth.uid(),p_amount,trim(p_method),trim(p_sender_name),
    NULLIF(trim(COALESCE(p_reference,'')),''),NULLIF(trim(COALESCE(p_proof_url,'')),'')) RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.member_get_wallet()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_balance BIGINT; v_transactions JSONB; v_requests JSONB;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Silakan login terlebih dahulu'; END IF;
  SELECT COALESCE(sum(CASE WHEN direction='credit' THEN amount ELSE -amount END),0)
    INTO v_balance FROM public.wallet_transactions WHERE user_id=auth.uid();
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC),'[]'::jsonb)
    INTO v_transactions
    FROM (SELECT id,direction,transaction_type,amount,description,created_at
          FROM public.wallet_transactions WHERE user_id=auth.uid()
          ORDER BY created_at DESC LIMIT 50) t;
  SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.created_at DESC),'[]'::jsonb)
    INTO v_requests
    FROM (SELECT id,amount,payment_method,sender_name,payment_reference,proof_url,status,admin_notes,created_at,reviewed_at
          FROM public.wallet_deposit_requests WHERE user_id=auth.uid()
          ORDER BY created_at DESC LIMIT 50) d;
  RETURN jsonb_build_object('balance',v_balance,'transactions',v_transactions,'deposits',v_requests);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_wallet_deposits()
RETURNS TABLE(
  id UUID,user_id UUID,email TEXT,full_name TEXT,phone TEXT,amount BIGINT,
  payment_method TEXT,sender_name TEXT,payment_reference TEXT,proof_url TEXT,
  status TEXT,admin_notes TEXT,created_at TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  RETURN QUERY
  SELECT d.id,d.user_id,u.email::text,p.full_name,p.phone,d.amount,d.payment_method,
         d.sender_name,d.payment_reference,d.proof_url,d.status,d.admin_notes,d.created_at
  FROM public.wallet_deposit_requests d
  JOIN auth.users u ON u.id=d.user_id
  LEFT JOIN public.profiles p ON p.id=d.user_id
  ORDER BY CASE WHEN d.status='pending' THEN 0 ELSE 1 END,d.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_review_wallet_deposit(
  p_request_id UUID,p_decision TEXT,p_notes TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE d public.wallet_deposit_requests%ROWTYPE;
BEGIN
  IF NOT public.is_novastria_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan'; END IF;
  IF p_decision NOT IN ('verified','rejected') THEN RAISE EXCEPTION 'Keputusan deposit tidak valid'; END IF;
  SELECT * INTO d FROM public.wallet_deposit_requests WHERE id=p_request_id FOR UPDATE;
  IF NOT FOUND OR d.status<>'pending' THEN RAISE EXCEPTION 'Deposit tidak ditemukan atau sudah diproses'; END IF;

  IF p_decision='verified' THEN
    -- The unique deposit_request_id prevents duplicate credits even under retries.
    INSERT INTO public.wallet_transactions(user_id,direction,transaction_type,amount,description,deposit_request_id,created_by)
    VALUES(d.user_id,'credit','deposit',d.amount,'Deposit saldo terverifikasi ('||d.payment_method||')',d.id,auth.uid());
  END IF;

  UPDATE public.wallet_deposit_requests
  SET status=p_decision,admin_notes=NULLIF(trim(COALESCE(p_notes,'')), ''),
      reviewed_by=auth.uid(),reviewed_at=now()
  WHERE id=d.id;

  PERFORM public.novastria_admin_log(
    'wallet_deposit_'||p_decision,'wallet_deposit_request',d.id::text,
    jsonb_build_object('user_id',d.user_id,'amount',d.amount,'payment_method',d.payment_method)
  );
END; $$;

REVOKE ALL ON FUNCTION public.member_create_wallet_deposit(BIGINT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.member_get_wallet() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_wallet_deposits() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_review_wallet_deposit(UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.member_create_wallet_deposit(BIGINT,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.member_get_wallet() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_wallet_deposits() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_wallet_deposit(UUID,TEXT,TEXT) TO authenticated;

NOTIFY pgrst,'reload schema';
