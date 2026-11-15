# OGSMM

OGSMM is being prepared as a manual-order reseller panel.

## Current state
- `index.html` is a front-end preview only.
- `supabase-schema.sql` is a starter database schema for customer profiles, services, and manual order management.
- Real authentication, payments, wallet, provider API, and live fulfilment are not connected yet.
- Catalogue rates are placeholders. Do not accept real payments or promise delivery until services and fulfilment are verified.

## Setup plan
1. Create a Supabase project.
2. Open SQL Editor and run all of `supabase-schema.sql`.
3. Sign up through the future OGSMM signup page.
4. Promote the owner account to admin in SQL Editor (replace the email):
   `update public.profiles set role = 'admin' where email = 'YOUR-OWNER-EMAIL';`
5. Add the Supabase project URL and anon/public key to the frontend as environment configuration. Never put a Supabase service-role key in browser code.
6. Deploy the frontend on a host such as Vercel.

## Manual order workflow
Customers create orders. Orders enter the database with status `pending`. The admin reviews them and updates status to `processing`, `completed`, `partial`, `cancelled`, or `rejected`.

## Important
The schema does not implement wallet deposits, payment gateway verification, refunds, or automated fulfilment. Those require separate secure server-side work. The admin role must only be granted manually by the project owner; never expose a customer-facing role selector.
