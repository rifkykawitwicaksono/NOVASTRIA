-- NOVASTRIA public daily store activity v1
-- Counts only actual product orders that have reached processing/completed.
-- Uses Asia/Jakarta calendar days and exposes no customer identity or contact data.

CREATE OR REPLACE FUNCTION public.get_public_store_activity()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_start TIMESTAMPTZ;
  v_end TIMESTAMPTZ;
  v_total BIGINT;
  v_activities JSONB;
BEGIN
  v_start := (timezone('Asia/Jakarta', now())::date::timestamp AT TIME ZONE 'Asia/Jakarta');
  v_end := v_start + interval '1 day';

  SELECT
    COALESCE(sum(o.quantity), 0),
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'product', o.product,
          'variant', o.variant,
          'quantity', o.quantity,
          'created_at', o.created_at
        )
        ORDER BY o.created_at DESC
      ),
      '[]'::jsonb
    )
  INTO v_total, v_activities
  FROM public.store_orders o
  WHERE o.created_at >= v_start
    AND o.created_at < v_end
    AND o.status IN ('processing', 'completed');

  RETURN jsonb_build_object(
    'date', timezone('Asia/Jakarta', now())::date,
    'total_sold', v_total,
    'activities', v_activities
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_store_activity() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_store_activity() TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
