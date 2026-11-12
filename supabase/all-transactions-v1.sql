-- NOVASTRIA: unified transaction register
-- Run after admin-controller-v2.sql, admin-controller-v3.sql,
-- order-tracking-v1.sql, and wallet-v1.sql.
-- Read-only unified view: source records remain in their original tables.

CREATE OR REPLACE FUNCTION public.admin_list_all_transactions()
RETURNS TABLE(
  transaction_id TEXT,
  category TEXT,
  reference TEXT,
  customer_name TEXT,
  contact TEXT,
  description TEXT,
  amount BIGINT,
  payment_method TEXT,
  status TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.is_novastria_admin() THEN
    RAISE EXCEPTION 'Akses admin diperlukan';
  END IF;

  RETURN QUERY
  SELECT * FROM (
    SELECT
      'membership:'||mp.id::text,
      CASE WHEN mp.membership_type='referral' THEN 'Pendaftaran Referral Member' ELSE 'Pendaftaran Reseller Member' END,
      COALESCE(mp.reference_code,'-'),
      COALESCE(pr.full_name,u.email::text,'-'),
      COALESCE(pr.phone,'-'),
      'Pembayaran pendaftaran membership',
      mp.amount,
      mp.payment_method,
      mp.status,
      mp.created_at
    FROM public.membership_payments mp
    JOIN auth.users u ON u.id=mp.user_id
    LEFT JOIN public.profiles pr ON pr.id=mp.user_id

    UNION ALL

    SELECT
      'deposit:'||wd.id::text,
      'Deposit Saldo',
      COALESCE(wd.payment_reference,'-'),
      COALESCE(pr.full_name,u.email::text,'-'),
      COALESCE(pr.phone,'-'),
      'Pengisian saldo anggota — pengirim: '||wd.sender_name,
      wd.amount,
      wd.payment_method,
      wd.status,
      wd.created_at
    FROM public.wallet_deposit_requests wd
    JOIN auth.users u ON u.id=wd.user_id
    LEFT JOIN public.profiles pr ON pr.id=wd.user_id

    UNION ALL

    SELECT
      'order:'||o.id::text,
      CASE WHEN o.payment_method='Saldo reseller' THEN 'Pembelian Produk — Reseller' ELSE 'Pembelian Produk — Pelanggan' END,
      o.order_code,
      o.customer_name,
      o.customer_phone,
      o.product||' — '||o.variant||' (jumlah '||o.quantity::text||')',
      o.unit_price*o.quantity,
      o.payment_method,
      o.status,
      o.created_at
    FROM public.store_orders o

    UNION ALL

    SELECT
      'sale:'||s.id::text,
      'Penjualan Manual Admin',
      COALESCE(s.payment_reference,'-'),
      s.customer_name,
      COALESCE(s.customer_contact,'-'),
      s.product||' — '||s.variant||' (jumlah '||s.quantity::text||')',
      s.unit_price*s.quantity,
      COALESCE(s.payment_method,'-'),
      s.status,
      s.created_at
    FROM public.store_sales s

    UNION ALL

    SELECT
      'payout:'||p.id::text,
      'Pencairan Komisi Referral',
      COALESCE(p.payment_reference,'-'),
      COALESCE(pr.full_name,u.email::text,'-'),
      COALESCE(u.email::text,'-'),
      COALESCE(p.notes,'Transfer komisi referral'),
      -p.amount,
      'Transfer manual',
      p.status,
      p.paid_at
    FROM public.commission_payouts p
    JOIN auth.users u ON u.id=p.user_id
    LEFT JOIN public.profiles pr ON pr.id=p.user_id
    WHERE p.status='paid'
  ) AS all_rows
  ORDER BY created_at DESC;
END; $$;

REVOKE ALL ON FUNCTION public.admin_list_all_transactions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_all_transactions() TO authenticated;
NOTIFY pgrst,'reload schema';
