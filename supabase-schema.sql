-- OGSMM starter database schema for Supabase/Postgres.
-- Run this in Supabase SQL Editor. Promote the owner account to admin only
-- after signing up, using the separate UPDATE statement in README.md.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
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
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  service_id uuid not null references public.services(id) on delete restrict,
  target_url text not null,
  quantity integer not null check (quantity > 0),
  unit_rate numeric(12,2) not null,
  charge numeric(12,2) not null,
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
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.set_order_price()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare svc public.services%rowtype;
begin
  select * into svc from public.services where id = new.service_id and active = true;
  if not found then raise exception 'Service is unavailable'; end if;
  if new.quantity < svc.min_quantity or new.quantity > svc.max_quantity then
    raise exception 'Quantity is outside the allowed range';
  end if;
  new.unit_rate := svc.rate_per_1000;
  new.charge := round((svc.rate_per_1000 * new.quantity / 1000.0)::numeric, 2);
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists before_order_insert on public.orders;
create trigger before_order_insert before insert on public.orders
for each row execute procedure public.set_order_price();

alter table public.profiles enable row level security;
alter table public.services enable row level security;
alter table public.orders enable row level security;

-- SECURITY DEFINER avoids recursive RLS lookups when checking the admin role.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$;


drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles for select to authenticated
using (id = (select auth.uid()) or public.is_admin());

drop policy if exists "Admins update profiles" on public.profiles;
create policy "Admins update profiles" on public.profiles for update to authenticated
using (public.is_admin())
with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));

drop policy if exists "Anyone reads active services" on public.services;
create policy "Anyone reads active services" on public.services for select
using (active = true or exists (
  select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'
));

drop policy if exists "Admins manage services" on public.services;
create policy "Admins manage services" on public.services for all to authenticated
using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));

drop policy if exists "Customers read own orders" on public.orders;
create policy "Customers read own orders" on public.orders for select to authenticated
using (user_id = (select auth.uid()) or exists (
  select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'
));

drop policy if exists "Customers create own orders" on public.orders;
create policy "Customers create own orders" on public.orders for insert to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "Admins update orders" on public.orders;
create policy "Admins update orders" on public.orders for update to authenticated
using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));

-- Seed catalogue examples. Replace these placeholders before taking real orders.
insert into public.services (platform, name, description, rate_per_1000)
values
('Instagram','Instagram followers','Placeholder service; confirm compliant fulfilment first',85),
('Instagram','Instagram likes','Placeholder service; confirm compliant fulfilment first',18),
('Instagram','Instagram reel views','Placeholder service; confirm compliant fulfilment first',12),
('YouTube','YouTube views','Placeholder service; confirm compliant fulfilment first',95),
('YouTube','YouTube subscribers','Placeholder service; confirm compliant fulfilment first',240),
('Telegram','Telegram members','Placeholder service; confirm compliant fulfilment first',110)
on conflict do nothing;
