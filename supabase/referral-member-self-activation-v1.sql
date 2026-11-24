-- DUKUN CHEAT: free self-service Referral Member activation.
-- Does not create a membership_payments row. Referral bonus qualification
-- remains tied to verified payment records in the existing referral pipeline.

create or replace function public.member_activate_referral_membership()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_membership_id uuid;
  v_changed boolean := false;
  v_referral_code text;
begin
  if v_user_id is null then
    raise exception 'Silakan login terlebih dahulu.';
  end if;

  if exists (
    select 1 from public.member_account_restrictions
    where user_id = v_user_id and is_blocked = true
  ) then
    raise exception 'Akun Anda sedang dibatasi administrator dan tidak dapat mengaktifkan Referral Member.';
  end if;

  select p.referral_code into v_referral_code
  from public.profiles p where p.id = v_user_id;

  if v_referral_code is null or btrim(v_referral_code) = '' then
    raise exception 'Kode referral akun belum tersedia. Hubungi admin.';
  end if;

  insert into public.memberships(user_id, membership_type, status, created_at, updated_at)
  values (v_user_id, 'referral', 'active', now(), now())
  on conflict (user_id, membership_type)
  do update set status = 'active', updated_at = now()
  where public.memberships.status <> 'active'
  returning id into v_membership_id;

  if v_membership_id is not null then
    v_changed := true;
  else
    select m.id into v_membership_id
    from public.memberships m
    where m.user_id = v_user_id and m.membership_type = 'referral';
  end if;

  if v_membership_id is null then
    raise exception 'Aktivasi Referral Member gagal. Silakan coba kembali.';
  end if;

  if v_changed then
    insert into public.admin_audit_logs(admin_id, action, entity_type, entity_id, details)
    values (
      v_user_id,
      'member_self_activated_referral',
      'membership',
      v_membership_id::text,
      jsonb_build_object(
        'membership_type', 'referral',
        'status', 'active',
        'activation_method', 'self_service',
        'payment_required', false,
        'referral_code', v_referral_code
      )
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'membership_id', v_membership_id,
    'membership_type', 'referral',
    'status', 'active',
    'referral_code', v_referral_code,
    'already_active', not v_changed
  );
end;
$function$;

revoke all on function public.member_activate_referral_membership() from public;
grant execute on function public.member_activate_referral_membership() to authenticated;
