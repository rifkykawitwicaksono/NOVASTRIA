-- NOVASTRIA: manual delivery-code workflow for store orders
-- Admin enters supplier voucher code; customer can read it only through
-- order code + matching WhatsApp number, and only after status = completed.

alter table public.store_orders
  add column if not exists delivery_code text;

alter table public.store_orders
  add constraint store_orders_delivery_code_length_check
  check (delivery_code is null or length(trim(delivery_code)) between 1 and 200);

create or replace function public.admin_complete_store_order(
  p_order_id uuid,
  p_delivery_code text,
  p_admin_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.store_orders%rowtype;
  v_code text := trim(coalesce(p_delivery_code, ''));
begin
  if not public.is_novastria_admin() then
    raise exception 'Akses admin diperlukan';
  end if;
  if length(v_code) < 3 or length(v_code) > 200 then
    raise exception 'Kode voucher wajib diisi (3 sampai 200 karakter)';
  end if;
  select * into v_order from public.store_orders where id = p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  if v_order.status <> 'processing' then
    raise exception 'Pesanan harus berstatus Diproses sebelum diselesaikan';
  end if;
  update public.store_orders
  set delivery_code = v_code,
      status = 'completed',
      admin_note = nullif(trim(coalesce(p_admin_note, '')), ''),
      updated_at = now()
  where id = v_order.id;
  perform public.novastria_admin_log('store_order_completed_with_code','store_order',v_order.id::text,
    jsonb_build_object('status','completed','delivery_code_added',true));
end;
$function$;
revoke all on function public.admin_complete_store_order(uuid, text, text) from public;
grant execute on function public.admin_complete_store_order(uuid, text, text) to authenticated;

drop function if exists public.lookup_public_order(text, text);
create function public.lookup_public_order(p_order_code text, p_customer_phone text)
returns table(order_code text, product text, variant text, quantity integer, unit_price bigint,
  status text, created_at timestamptz, updated_at timestamptz, delivery_code text)
language sql stable security definer set search_path = ''
as $function$
  select o.order_code,o.product,o.variant,o.quantity,o.unit_price,o.status,o.created_at,o.updated_at,
    case when o.status='completed' and o.delivery_code is not null then o.delivery_code else null end
  from public.store_orders o
  where upper(trim(o.order_code))=upper(trim(coalesce(p_order_code,'')))
    and o.customer_phone=regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')
  limit 1;
$function$;
revoke all on function public.lookup_public_order(text, text) from public;
grant execute on function public.lookup_public_order(text, text) to anon, authenticated;

-- Prevent admins from bypassing voucher entry by directly setting completed.
create or replace function public.admin_update_store_order(
  p_order_id uuid,
  p_status text,
  p_admin_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  o public.store_orders%rowtype;
begin
  if not public.is_novastria_admin() then raise exception 'Akses admin diperlukan'; end if;
  if p_status not in ('pending_payment','pending_verification','processing','completed','cancelled') then
    raise exception 'Status pesanan tidak valid';
  end if;
  if p_status = 'completed' then
    raise exception 'Pesanan hanya dapat diselesaikan setelah kode voucher dimasukkan melalui admin_complete_store_order';
  end if;
  select * into o from public.store_orders where id=p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  if o.status in ('completed','cancelled') and o.status<>p_status then
    raise exception 'Pesanan selesai/dibatalkan tidak dapat diubah lagi';
  end if;
  if p_status='cancelled' and o.payment_method='Saldo reseller' then
    insert into public.wallet_transactions(user_id,direction,transaction_type,amount,description,store_order_id,created_by)
    select wt.user_id,'credit','refund',wt.amount,'Pengembalian saldo pesanan '||o.order_code,o.id,auth.uid()
    from public.wallet_transactions wt
    where wt.store_order_id=o.id and wt.transaction_type='purchase'
    on conflict (store_order_id,transaction_type) where store_order_id is not null do nothing;
  end if;
  update public.store_orders set status=p_status,admin_note=nullif(trim(coalesce(p_admin_note,'')),''),updated_at=now() where id=o.id;
  perform public.novastria_admin_log('store_order_'||p_status,'store_order',o.id::text,jsonb_build_object('status',p_status));
end;
$function$;
