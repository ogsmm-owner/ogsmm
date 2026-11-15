-- OGSMM starter schema for Supabase/PostgreSQL.
-- Review before running in Supabase SQL Editor. Never expose service_role keys.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text not null default '',
  role text not null default 'customer' check (role in ('customer','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  platform text not null,
  name text not null,
  description text,
  rate_per_1000 numeric(12,2) not null check (rate_per_1000 >= 0),
  min_quantity integer not null default 10 check (min_quantity > 0),
  max_quantity integer not null default 100000 check (max_quantity >= min_quantity),
  active boolean not null default false,
  created_at timestamptz not null default now(),
  unique (platform, name)
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  service_id uuid not null references public.services(id) on delete restrict,
  target_url text not null,
  quantity integer not null check (quantity > 0),
  unit_rate numeric(12,2) not null default 0,
  charge numeric(12,2) not null default 0,
  status text not null default 'pending'
    check (status in ('pending','processing','completed','partial','cancelled','rejected')),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists orders_user_created_idx on public.orders(user_id, created_at desc);
create index if not exists orders_status_created_idx on public.orders(status, created_at desc);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

create or replace function public.prepare_new_order()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare svc public.services%rowtype;
begin
  if new.user_id <> (select auth.uid()) then
    raise exception 'You can only create orders for your own account';
  end if;
  select * into svc from public.services where id = new.service_id and active = true;
  if not found then raise exception 'Service is unavailable'; end if;
  if new.quantity < svc.min_quantity or new.quantity > svc.max_quantity then
    raise exception 'Quantity is outside the allowed range';
  end if;
  if new.target_url !~ '^https?://' then
    raise exception 'A valid public HTTP(S) URL is required';
  end if;
  new.unit_rate := svc.rate_per_1000;
  new.charge := round((svc.rate_per_1000 * new.quantity / 1000.0)::numeric, 2);
  new.status := 'pending';
  new.admin_note := null;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists before_order_insert on public.orders;
create trigger before_order_insert before insert on public.orders
for each row execute procedure public.prepare_new_order();

alter table public.profiles enable row level security;
alter table public.services enable row level security;
alter table public.orders enable row level security;

drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles
for select to authenticated using (id = (select auth.uid()) or public.is_admin());

drop policy if exists "Anyone reads active services" on public.services;
create policy "Anyone reads active services" on public.services
for select using (active = true or public.is_admin());

drop policy if exists "Admins manage services" on public.services;
create policy "Admins manage services" on public.services
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Customers read own orders" on public.orders;
create policy "Customers read own orders" on public.orders
for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "Customers create own orders" on public.orders;
create policy "Customers create own orders" on public.orders
for insert to authenticated with check (user_id = (select auth.uid()) and status = 'pending');

drop policy if exists "Admins update orders" on public.orders;
create policy "Admins update orders" on public.orders
for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- Sample entries are inactive until owner verifies compliant fulfilment.
insert into public.services (platform, name, description, rate_per_1000, active)
values
('Instagram','Instagram followers','Placeholder only; verify fulfilment first',85,false),
('Instagram','Instagram likes','Placeholder only; verify fulfilment first',18,false),
('Instagram','Instagram reel views','Placeholder only; verify fulfilment first',12,false),
('YouTube','YouTube views','Placeholder only; verify fulfilment first',95,false),
('YouTube','YouTube subscribers','Placeholder only; verify fulfilment first',240,false),
('Telegram','Telegram members','Placeholder only; verify fulfilment first',110,false)
on conflict (platform, name) do nothing;

-- After owner signup, promote the owner manually in Supabase SQL Editor:
-- update public.profiles set role = 'admin' where email = 'YOUR-OWNER-EMAIL';

-- Secure manual UPI payment-proof workflow (no automatic payment approval).
-- Create a private bucket for customer payment screenshots.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','application/pdf'];

create table if not exists public.payment_submissions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  utr text not null check (length(utr) between 6 and 80),
  proof_path text not null,
  amount numeric(12,2) not null check (amount > 0),
  status text not null default 'pending'
    check (status in ('pending','verified','rejected')),
  admin_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create index if not exists payment_submissions_user_created_idx
  on public.payment_submissions(user_id, created_at desc);
create index if not exists payment_submissions_status_created_idx
  on public.payment_submissions(status, created_at desc);

alter table public.payment_submissions enable row level security;

drop policy if exists "Customers submit own payment proof" on public.payment_submissions;
create policy "Customers submit own payment proof" on public.payment_submissions
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and status = 'pending'
  and admin_note is null
  and reviewed_at is null
  and exists (
    select 1 from public.orders o
    where o.id = order_id and o.user_id = (select auth.uid())
      and o.charge = amount
  )
  and proof_path like (select auth.uid())::text || '/' || order_id::text || '/%'
);

drop policy if exists "Customers read own payment submissions" on public.payment_submissions;
create policy "Customers read own payment submissions" on public.payment_submissions
for select to authenticated
using (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists "Admins review payment submissions" on public.payment_submissions;
create policy "Admins review payment submissions" on public.payment_submissions
for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Customers upload own payment proof files" on storage.objects;
create policy "Customers upload own payment proof files" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'payment-proofs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.orders o
    where o.id::text = (storage.foldername(name))[2]
      and o.user_id = (select auth.uid())
  )
);

drop policy if exists "Customers read own payment proof files" on storage.objects;
create policy "Customers read own payment proof files" on storage.objects
for select to authenticated
using (
  bucket_id = 'payment-proofs'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_admin()
  )
);
