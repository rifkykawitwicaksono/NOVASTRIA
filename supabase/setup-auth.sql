-- NOVASTRIA: setup profil otomatis untuk Supabase Auth
-- Jalankan seluruh file ini satu kali di Supabase Dashboard > SQL Editor.
-- Tidak memerlukan Secret Key di frontend.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS phone TEXT;

CREATE OR REPLACE FUNCTION public.handle_new_novastria_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_referral_code TEXT;
  v_referrer_id UUID;
  v_invite_code TEXT;
BEGIN
  v_invite_code := upper(nullif(trim(new.raw_user_meta_data ->> 'referral_code'), ''));

  IF v_invite_code IS NOT NULL THEN
    SELECT p.id
      INTO v_referrer_id
      FROM public.profiles AS p
     WHERE upper(p.referral_code) = v_invite_code
       AND p.id <> new.id
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
    new.id,
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'phone'), ''),
    v_referral_code,
    v_referrer_id
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_novastria_auth_user_created ON auth.users;
CREATE TRIGGER on_novastria_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_novastria_user();

-- Anggota hanya boleh mengubah nama dan nomor WhatsApp miliknya sendiri.
DROP POLICY IF EXISTS "Members can update own profile details" ON public.profiles;
CREATE POLICY "Members can update own profile details"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

REVOKE UPDATE ON TABLE public.profiles FROM anon, authenticated;
GRANT UPDATE (full_name, phone) ON TABLE public.profiles TO authenticated;

-- Tidak ada kebijakan INSERT/UPDATE untuk memberships/payments/commissions
-- dari browser. Status keanggotaan wajib diubah oleh proses server/admin tepercaya.
