-- OGSMM secure manual UPI payment-proof setup.
-- Run this file in Supabase SQL Editor after the base schema is already installed.
-- Payment approval remains manual; a screenshot alone is not proof of payment.

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
