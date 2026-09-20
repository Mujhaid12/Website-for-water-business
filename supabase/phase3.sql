-- Phase 3: run once in Supabase SQL Editor before using the Admin dashboard.
-- Atomic product creation prevents a product being created without its inventory record.
create or replace function public.admin_create_product(
  product_name text,
  product_description text,
  product_price numeric,
  product_unit_label text,
  product_image_path text,
  opening_quantity integer,
  product_reorder_level integer default 5
) returns uuid language plpgsql security definer set search_path = public as $$
declare new_product_id uuid;
begin
  if not public.is_admin() then raise exception 'Only an admin can create products'; end if;
  if opening_quantity < 0 or product_reorder_level < 0 then raise exception 'Inventory values cannot be negative'; end if;
  insert into public.products (name, description, price, unit_label, image_path)
  values (product_name, nullif(product_description, ''), product_price, product_unit_label, nullif(product_image_path, ''))
  returning id into new_product_id;
  insert into public.inventory (product_id, quantity, reorder_level)
  values (new_product_id, opening_quantity, product_reorder_level);
  return new_product_id;
end;
$$;
grant execute on function public.admin_create_product(text, text, numeric, text, text, integer, integer) to authenticated;
