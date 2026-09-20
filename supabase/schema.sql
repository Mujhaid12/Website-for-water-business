-- ClearDrop Water: Phase 1 database, roles, RLS, and secure order functions.
-- Run this whole file once in Supabase Dashboard > SQL Editor > New query.

create extension if not exists pgcrypto;

create type public.user_role as enum ('customer', 'rider', 'admin');
create type public.order_status as enum ('pending', 'assigned', 'out_for_delivery', 'delivered', 'cancelled');
create type public.order_priority as enum ('normal', 'high', 'urgent');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.user_role not null default 'customer',
  full_name text,
  phone text,
  default_address text,
  is_active boolean not null default true,
  last_auto_assigned_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  price numeric(10,2) not null check (price >= 0),
  unit_label text not null default 'can',
  image_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.inventory (
  product_id uuid primary key references public.products(id) on delete cascade,
  quantity integer not null default 0 check (quantity >= 0),
  reserved_quantity integer not null default 0 check (reserved_quantity >= 0 and reserved_quantity <= quantity),
  reorder_level integer not null default 5 check (reorder_level >= 0),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  assigned_rider_id uuid references public.profiles(id),
  assignment_source text not null default 'automatic' check (assignment_source in ('automatic', 'manual')),
  status public.order_status not null default 'pending',
  priority public.order_priority not null default 'normal',
  deliver_before timestamptz,
  queue_position integer not null default 0 check (queue_position >= 0),
  delivery_name text not null,
  delivery_phone text not null,
  delivery_address text not null,
  notes text,
  subtotal numeric(10,2) not null check (subtotal >= 0),
  delivery_fee numeric(10,2) not null default 0 check (delivery_fee >= 0),
  total numeric(10,2) not null check (total >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  delivered_at timestamptz
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_name text not null,
  unit_price numeric(10,2) not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now()
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id),
  change_quantity integer not null check (change_quantity <> 0),
  reason text not null,
  order_id uuid references public.orders(id),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create index orders_customer_id_idx on public.orders(customer_id);
create index orders_assigned_rider_id_idx on public.orders(assigned_rider_id);
create index order_items_order_id_idx on public.order_items(order_id);

create or replace function public.set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger products_updated_at before update on public.products for each row execute function public.set_updated_at();
create trigger inventory_updated_at before update on public.inventory for each row execute function public.set_updated_at();
create trigger orders_updated_at before update on public.orders for each row execute function public.set_updated_at();

-- Every Auth user gets a customer profile. User-supplied metadata can never grant a role.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, role, full_name) values (new.id, 'customer', coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.protect_profile_role() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role <> old.role
    and current_setting('app.bootstrap_first_admin', true) is distinct from 'true'
    and not public.is_admin() then raise exception 'Only an admin can change roles'; end if;
  return new;
end;
$$;
create trigger protect_profile_role before update on public.profiles for each row execute function public.protect_profile_role();

-- SQL Editor only: securely promotes the first owner, then refuses to run again.
create or replace function public.bootstrap_first_admin(target_email text)
returns void language plpgsql security definer set search_path = public as $$
declare target_id uuid;
begin
  if exists (select 1 from public.profiles where role = 'admin') then raise exception 'An admin already exists'; end if;
  select id into target_id from auth.users where lower(email) = lower(target_email);
  if target_id is null then raise exception 'No website account was found for this email'; end if;
  perform set_config('app.bootstrap_first_admin', 'true', true);
  update public.profiles set role = 'admin' where id = target_id;
end;
$$;
revoke all on function public.bootstrap_first_admin(text) from public, anon, authenticated;

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.inventory enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.inventory_movements enable row level security;

create policy "users read own profile" on public.profiles for select to authenticated using (id = auth.uid());
create policy "users update own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "admins manage profiles" on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "anyone reads active products" on public.products for select using (is_active or public.is_admin());
create policy "admins manage products" on public.products for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins manage inventory" on public.inventory for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "customers read own orders" on public.orders for select to authenticated using (customer_id = auth.uid());
create policy "riders read assigned orders" on public.orders for select to authenticated using (assigned_rider_id = auth.uid());
create policy "admins manage orders" on public.orders for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "customers read own order items" on public.order_items for select to authenticated using (exists (select 1 from public.orders o where o.id = order_id and o.customer_id = auth.uid()));
create policy "riders read assigned order items" on public.order_items for select to authenticated using (exists (select 1 from public.orders o where o.id = order_id and o.assigned_rider_id = auth.uid()));
create policy "admins manage order items" on public.order_items for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins read inventory history" on public.inventory_movements for select to authenticated using (public.is_admin());

-- This is the only customer-facing way to make an order. Prices come from the database,
-- available stock is reserved atomically, and an active rider with the lowest workload is selected.
create or replace function public.create_order(items jsonb, delivery_name text, delivery_phone text, delivery_address text, notes text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare order_uuid uuid := gen_random_uuid(); item jsonb; product_row public.products%rowtype; item_quantity integer; order_subtotal numeric := 0; chosen_rider_id uuid;
begin
  if auth.uid() is null then raise exception 'You must sign in first'; end if;
  if jsonb_typeof(items) <> 'array' or jsonb_array_length(items) = 0 then raise exception 'Your cart is empty'; end if;
  -- Serialising this small calculation makes a tie fair even when two customers order at once.
  perform pg_advisory_xact_lock(739104);
  for item in select * from jsonb_array_elements(items) loop
    item_quantity := (item ->> 'quantity')::integer;
    if item_quantity is null or item_quantity < 1 then raise exception 'Invalid item quantity'; end if;
    select * into product_row from public.products where id = (item ->> 'product_id')::uuid and is_active;
    if not found then raise exception 'A product is unavailable'; end if;
    order_subtotal := order_subtotal + product_row.price * item_quantity;
  end loop;
  select rider.id into chosen_rider_id
  from public.profiles rider
  left join public.orders open_order on open_order.assigned_rider_id = rider.id and open_order.status not in ('delivered', 'cancelled')
  where rider.role = 'rider' and rider.is_active
  group by rider.id, rider.last_auto_assigned_at
  order by count(open_order.id), rider.last_auto_assigned_at nulls first, rider.id
  limit 1;
  insert into public.orders (id, customer_id, assigned_rider_id, status, delivery_name, delivery_phone, delivery_address, notes, subtotal, total)
  values (order_uuid, auth.uid(), chosen_rider_id, case when chosen_rider_id is null then 'pending'::public.order_status else 'assigned'::public.order_status end, delivery_name, delivery_phone, delivery_address, notes, order_subtotal, order_subtotal);
  if chosen_rider_id is not null then update public.profiles set last_auto_assigned_at = now() where id = chosen_rider_id; end if;
  for item in select * from jsonb_array_elements(items) loop
    select * into product_row from public.products where id = (item ->> 'product_id')::uuid;
    update public.inventory
      set reserved_quantity = reserved_quantity + (item ->> 'quantity')::integer
      where product_id = product_row.id
        and quantity - reserved_quantity >= (item ->> 'quantity')::integer;
    if not found then raise exception 'Not enough stock is available for %', product_row.name; end if;
    insert into public.order_items (order_id, product_id, product_name, unit_price, quantity)
    values (order_uuid, product_row.id, product_row.name, product_row.price, (item ->> 'quantity')::integer);
  end loop;
  return order_uuid;
end;
$$;
grant execute on function public.create_order(jsonb, text, text, text, text) to authenticated;

-- Admin overrides always win. Phase 3 will call this function from its assignment form.
create or replace function public.assign_order(order_uuid uuid, rider_uuid uuid, new_priority public.order_priority default 'normal', new_deliver_before timestamptz default null, new_queue_position integer default 0)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Only an admin can assign orders'; end if;
  if not exists (select 1 from public.profiles where id = rider_uuid and role = 'rider' and is_active) then raise exception 'Choose an active rider'; end if;
  if new_queue_position < 0 then raise exception 'Queue position cannot be negative'; end if;
  update public.orders
    set assigned_rider_id = rider_uuid, assignment_source = 'manual', status = case when status = 'pending' then 'assigned'::public.order_status else status end,
        priority = new_priority, deliver_before = new_deliver_before, queue_position = new_queue_position
    where id = order_uuid and status not in ('delivered', 'cancelled');
  if not found then raise exception 'This order cannot be assigned'; end if;
end;
$$;
grant execute on function public.assign_order(uuid, uuid, public.order_priority, timestamptz, integer) to authenticated;

-- Riders can only advance the status of an order assigned to them. Admins can also correct a status.
create or replace function public.update_order_status(order_uuid uuid, next_status public.order_status)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() and not exists (select 1 from public.orders where id = order_uuid and assigned_rider_id = auth.uid()) then raise exception 'This order is not assigned to you'; end if;
  if not public.is_admin() and next_status not in ('out_for_delivery', 'delivered') then raise exception 'Riders may only mark an order out for delivery or delivered'; end if;
  update public.orders set status = next_status, delivered_at = case when next_status = 'delivered' then now() else delivered_at end where id = order_uuid;
end;
$$;
grant execute on function public.update_order_status(uuid, public.order_status) to authenticated;

-- An order holds stock at creation; delivery converts that hold into a permanent stock decrease.
-- A cancellation releases its hold. This prevents over-selling during busy periods.
create or replace function public.apply_inventory_for_order_status() returns trigger language plpgsql security definer set search_path = public as $$
declare line record;
begin
  if old.status in ('cancelled', 'delivered') and new.status <> old.status then
    raise exception 'Cancelled and delivered orders cannot be reopened';
  end if;
  if new.status = 'delivered' and old.status <> 'delivered' then
    for line in select product_id, quantity from public.order_items where order_id = new.id loop
      update public.inventory
        set quantity = quantity - line.quantity, reserved_quantity = reserved_quantity - line.quantity
        where product_id = line.product_id and quantity >= line.quantity and reserved_quantity >= line.quantity;
      if not found then raise exception 'Not enough inventory to deliver this order'; end if;
      insert into public.inventory_movements (product_id, change_quantity, reason, order_id, created_by) values (line.product_id, -line.quantity, 'Delivered order', new.id, auth.uid());
    end loop;
  elsif new.status = 'cancelled' and old.status not in ('cancelled', 'delivered') then
    for line in select product_id, quantity from public.order_items where order_id = new.id loop
      update public.inventory set reserved_quantity = reserved_quantity - line.quantity where product_id = line.product_id and reserved_quantity >= line.quantity;
      if not found then raise exception 'Inventory reservation is inconsistent'; end if;
    end loop;
  end if;
  return new;
end;
$$;
create trigger apply_inventory_after_order_status before update of status on public.orders for each row execute function public.apply_inventory_for_order_status();

-- Public product photos, but only admins can upload/change/delete them.
insert into storage.buckets (id, name, public) values ('product-images', 'product-images', true) on conflict (id) do update set public = true;
create policy "public product image viewing" on storage.objects for select using (bucket_id = 'product-images');
create policy "admins upload product images" on storage.objects for insert to authenticated with check (bucket_id = 'product-images' and public.is_admin());
create policy "admins update product images" on storage.objects for update to authenticated using (bucket_id = 'product-images' and public.is_admin()) with check (bucket_id = 'product-images' and public.is_admin());
create policy "admins delete product images" on storage.objects for delete to authenticated using (bucket_id = 'product-images' and public.is_admin());

-- AFTER creating your first account, run this single line once in SQL Editor, replacing the email.
-- select public.bootstrap_first_admin('YOUR_EMAIL@example.com');
