# OGSMM — Social Growth Panel

OGSMM is a dark, responsive starter UI for a manual-order social marketing panel.

## What is currently in the repository
- `index.html`: responsive dashboard, sample service catalogue, demo order form and order history.
- `supabase-schema.sql`: starter Supabase schema for profiles, services and manual order management.
- Demo orders persist in the same browser using localStorage. They are not stored in a database and will not appear on another device/browser.

## Important current limitations
- No live Supabase connection or real user authentication is wired into the page.
- No payment gateway, customer wallet, SMM provider API, automated fulfilment, or production admin console is connected.
- Catalogue prices are placeholders and demo orders do not get sent to any provider.
- Do not accept real payments or promise delivery until secure server-side workflows and vetted provider terms are implemented.

## Supabase setup
1. Create a Supabase project.
2. Open **SQL Editor** and review/run `supabase-schema.sql`.
3. Sign up a real owner account after the authentication UI is implemented.
4. Promote the owner account to admin using the safe admin-only process you establish for your project. Do not expose an admin role selector to customers.
5. Add the Supabase project URL and anon/public key through frontend configuration. Never put a service-role key or provider API key in browser code.

## Manual order workflow
The intended workflow is customer submits an order, it is stored as `pending`, and an admin reviews it and updates the status. This is a database foundation only; a secure authenticated app and admin UI still need to be connected.

## Production checklist
- Implement Supabase Auth and verify email/session handling.
- Add server-side order creation with server-side price calculation and quantity validation.
- Add audit-safe wallet/payment flows only after payment webhook verification.
- Add admin-only server operations and rate limiting.
- Integrate only providers and promotion methods that comply with relevant platform terms.
- Test RLS policies with customer and admin accounts before launch.
