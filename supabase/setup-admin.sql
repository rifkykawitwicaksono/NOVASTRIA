-- NOVASTRIA Admin Controller
-- Jalankan setelah akun kitatopupin@gmail.com terdaftar di Supabase Auth.
-- Tidak memakai Secret Key di browser.

CREATE TABLE IF NOT EXISTS public.novastria_admins (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.novastria_admins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.novastria_admins FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_novastria_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.novastria_admins AS a
    WHERE a.user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_novastria_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_novastria_admin() TO authenticated;

-- Daftarkan akun admin berdasarkan email. Jika akun belum dibuat, query tidak
-- memasukkan baris; buat akun tersebut dahulu, lalu jalankan file ini kembali.
INSERT INTO public.novastria_admins (user_id, email)
SELECT u.id, lower(u.email)
FROM auth.users AS u
WHERE lower(u.email) = 'kitatopupin@gmail.com'
ON CONFLICT (user_id) DO UPDATE
SET email = EXCLUDED.email;

-- Admin dapat membaca seluruh profil untuk keperluan operasional.
DROP POLICY IF EXISTS "NOVASTRIA admins can read all profiles" ON public.profiles;
CREATE POLICY "NOVASTRIA admins can read all profiles"
  ON public.profiles FOR SELECT TO authenticated
  USING (public.is_novastria_admin());

-- Admin dapat membaca dan mengubah status membership.
DROP POLICY IF EXISTS "NOVASTRIA admins manage memberships" ON public.memberships;
CREATE POLICY "NOVASTRIA admins manage memberships"
  ON public.memberships FOR ALL TO authenticated
  USING (public.is_novastria_admin())
  WITH CHECK (public.is_novastria_admin());

NOTIFY pgrst, 'reload schema';
