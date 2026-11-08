# Setting up login & sync (Supabase)

Spend Utilizer uses [Supabase](https://supabase.com) (free tier is enough) for:

- **Login** with email + password, a phone (SMS) code, or as a **guest**
- **Sync** of transactions, accounts and reminders across Android, Windows,
  macOS and Linux

Without this setup the app still works, but data stays on a single device.

---

## 1. Create a project

1. Sign up at <https://supabase.com> and click **New project**.
2. Choose a name (e.g. `spend-utilizer`), a database password (save it
   somewhere safe) and a region close to you (e.g. **Mumbai**).

## 2. Create the database table

1. In the project, open **SQL Editor**, then **New query**.
2. Paste the whole of [`supabase/schema.sql`](supabase/schema.sql) and click **Run**.

This creates one table, `records`. **Row-level security** makes sure each
user (guests included) can only ever read and write their own data.

## 3. Turn on the login methods

Go to **Authentication** → **Sign In / Providers**:

| Login | What to do |
|---|---|
| **Email** | On by default. Turn **Confirm email** OFF (see below). |
| **Guest** | Turn on **Allow anonymous sign-ins**. |
| **Phone** | Turn on **Phone** and connect an SMS provider (Twilio, MessageBird, Vonage or Textlocal). SMS costs money, and Indian numbers need DLT registration with the provider. Skip this to begin with: email and guest work without it. |

### Turn off "Confirm email"

The app signs in with **email + password**. On the free plan Supabase can't
send custom emails without your own SMTP server, so turn off email
confirmation: **Authentication** → **Sign In / Providers** → **Email** →
switch **Confirm email** OFF → **Save**.

(If you later add your own SMTP server under **Authentication** → **Emails**
→ **SMTP Settings**, you can turn it back on.)

## 4. Connect the app

In **Project Settings** → **API Keys**, copy:

- the **Project URL** (`https://xxxx.supabase.co`)
- the **publishable key** (`sb_publishable_...`), or the legacy **anon** key

Both are safe to put in the app. **Never** use the *secret* or
*service_role* key.

**For the apps built by GitHub Actions:** in the GitHub repo go to
**Settings** → **Secrets and variables** → **Actions** → **New repository
secret** and add `SUPABASE_URL` and `SUPABASE_KEY`. The next build will have
login and sync turned on.

**For running locally:**

```bash
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_KEY=sb_publishable_xxxx
```

## How sync works

- Every change (new transaction, edit, delete, renamed card…) is saved on the
  device immediately and uploaded a few seconds later. The app also syncs
  every 2 minutes and when you tap **Sync now** (cloud icon, then **Account & sync**).
- Offline? Changes wait on the device and upload when you're back online.
- If the same item is edited on two devices, the **most recent edit wins**.
- Chat history stays on each device. Transactions, accounts and reminders
  are what sync.
- Guests sync too. Add an email + password (or phone) under **Account & sync** to keep the
  same data when you sign in on another device. **Signing out of a guest
  account deletes its data permanently.**
