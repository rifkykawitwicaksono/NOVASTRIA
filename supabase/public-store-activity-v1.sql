-- NOVASTRIA public daily store activity v1
-- Counts only real product orders once they are verified / moved to processing.
-- Day boundaries use Asia/Jakarta. No customer identity or contact data is exposed.

ALTER TABLE public.store_orders
  ADD COLUMN IF NOT EXISTS activity_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.capture_store_order_activity_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.status IN ('processing', 'completed') AND NEW.activity_at IS NULL THEN
    NEW.activity_at := COALESCE(NEW.updated_at, NEW.created_at, now());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS store_orders_capture_activity_at ON public.store_orders;
CREATE TRIGGER store_orders_capture_activity_at
BEFORE INSERT OR UPDATE OF status ON public.store_orders
FOR EACH ROW
EXECUTE FUNCTION public.capture_store_order_activity_at();

-- Backfill already verified orders so today's existing activity is not lost.
UPDATE public.store_orders
SET activity_at = COALESCE(updated_at, created_at)
WHERE status IN ('processing', 'completed')
  AND activity_at IS NULL;

CREATE INDEX IF NOT EXISTS store_orders_activity_at_idx
  ON public.store_orders(activity_at DESC)
  WHERE activity_at IS NOT NULL;

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
          'activity_at', o.activity_at
        )
        ORDER BY o.activity_at DESC
      ),
      '[]'::jsonb
    )
  INTO v_total, v_activities
  FROM public.store_orders o
  WHERE o.activity_at >= v_start
    AND o.activity_at < v_end
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
