DO $$
DECLARE
  u RECORD;
  v_referral_code TEXT;
  v_referrer_id UUID;
  v_invite_code TEXT;
BEGIN
  FOR u IN
    SELECT au.id, au.raw_user_meta_data
      FROM auth.users AS au
     WHERE NOT EXISTS (
       SELECT 1 FROM public.profiles AS p WHERE p.id = au.id
     )
  LOOP
    v_invite_code := upper(nullif(trim(u.raw_user_meta_data ->> 'referral_code'), ''));
    v_referrer_id := NULL;

    IF v_invite_code IS NOT NULL THEN
      SELECT p.id
        INTO v_referrer_id
        FROM public.profiles AS p
       WHERE upper(p.referral_code) = v_invite_code
         AND p.id <> u.id
       LIMIT 1;
    END IF;

    LOOP
      v_referral_code := 'NVA' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
      EXIT WHEN NOT EXISTS (
        SELECT 1 FROM public.profiles AS p
         WHERE p.referral_code = v_referral_code
      );
    END LOOP;

    INSERT INTO public.profiles (id, full_name, phone, referral_code, referred_by)
    VALUES (
      u.id,
      nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(u.raw_user_meta_data ->> 'phone'), ''),
      v_referral_code,
      v_referrer_id
    )
    ON CONFLICT (id) DO NOTHING;
  END LOOP;
END;
$$;
