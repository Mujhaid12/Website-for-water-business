-- Phase 2 testing only: run once in Supabase SQL Editor while signed in as the project owner.
-- Phase 3 replaces this manual step with the Admin product-management screen.

with new_product as (
  insert into public.products (name, description, price, unit_label, is_active)
  values (
    'Clear Water 20 L Can',
    'Purified drinking water in a returnable 20-litre can.',
    80.00,
    '20 litre can',
    true
  )
  returning id
)
insert into public.inventory (product_id, quantity, reorder_level)
select id, 20, 5 from new_product;
