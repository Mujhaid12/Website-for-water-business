# ClearDrop Water — Phase 1

This is the secure foundation for a water-delivery site. It includes a React starter, Supabase login, database tables, Row Level Security (RLS), a locked-down product image bucket, stock reservations, and automatic rider assignment. A reservation holds available stock at order time, so the shop cannot accept more cans than it can supply. A new order goes to the active rider with the fewest unfinished orders; when tied, the rider who was auto-assigned least recently is selected.

## Important login decision

Use **email and password** for Phase 1. Supabase can provide the login system on its free tier, but phone OTP needs an SMS company configured to actually send the code. That third party normally charges per SMS, and Indian delivery must also comply with TRAI/DLT rules. We will store phone numbers now and can add a service such as MSG91 later without replacing the database.

## One-time setup

1. Install [Node.js LTS](https://nodejs.org/) if `npm --version` does not work in a new PowerShell window.
2. Create a free project at [Supabase](https://supabase.com/dashboard). Save its database password somewhere private.
3. In Supabase, open **SQL Editor** > **New query**, paste the entire contents of `supabase/schema.sql`, and click **Run**.
4. Open **Project Settings** > **API**. Copy the Project URL and the **publishable** key (not the secret/service-role key).
5. In this folder, copy `.env.example` to a new file named `.env.local`. Replace its two placeholder values. Never commit this file.
6. In Supabase, open **Authentication** > **Providers** > **Email** and leave Email enabled. For testing, you may temporarily turn off “Confirm email”; turn it back on before launch.
7. Run `npm install`, then `npm run dev`. Open the localhost address that PowerShell prints.
8. Create your owner account through the page. Back in Supabase SQL Editor, run the last commented `select public.bootstrap_first_admin...` line from `supabase/schema.sql`, replacing the email with the owner account email. This makes that account the one admin.

## Verify security before continuing

1. Register two normal test accounts. In **Table Editor** > `profiles`, both must have role `customer`.
2. Sign into each account and verify it can see only its own profile when later screens use the database.
3. In Supabase **Storage**, verify the `product-images` bucket exists and is public. The SQL policies allow only the admin account to upload or modify images.
4. Use **Authentication** > **Users** to create a rider for testing. In SQL Editor, set its role to `rider` using the same `update` pattern. Rider access is limited to orders that an admin assigns.

## Git and GitHub — save your first working version

1. Create an empty private repository at [GitHub](https://github.com/new). Do not add a README there because this folder already has one.
2. In PowerShell in this folder, run:
   ```powershell
   git add .
   git commit -m "Phase 1 - secure Supabase foundation"
   git branch -M main
   git remote add origin https://github.com/YOUR-GITHUB-USERNAME/YOUR-REPOSITORY-NAME.git
   git push -u origin main
   ```
3. At the end of every phase, use `git add .`, then `git commit -m "short description"`, then `git push`.

`git commit` saves a named snapshot on your computer; `git push` copies that snapshot to your private GitHub repository.

## Do not expose secrets

The browser only receives the project URL and publishable key. RLS enforces what each signed-in person can read or change. Do **not** place a Supabase service-role key, database password, or future Razorpay secret in `.env.local` exposed to the browser or in GitHub.
