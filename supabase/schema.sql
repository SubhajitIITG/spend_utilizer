-- Spend Utilizer: cloud storage for cross-device sync.
-- Run this once in the Supabase dashboard: SQL Editor → New query → paste → Run.

create table if not exists public.records (
  user_id    uuid        not null default auth.uid()
                         references auth.users (id) on delete cascade,
  kind       text        not null check (kind in ('account', 'txn', 'reminder')),
  id         text        not null,
  data       jsonb,
  deleted    boolean     not null default false,
  -- When the record was last edited on a device (used to pick the newest edit).
  updated_at timestamptz not null,
  -- When the server last received it (used by devices to download changes).
  synced_at  timestamptz not null default clock_timestamp(),
  primary key (user_id, kind, id)
);

create index if not exists records_user_synced_idx
  on public.records (user_id, synced_at);

-- The server, not the device, decides synced_at. An upload that is older
-- than what the server already has (a device that was offline) is ignored,
-- so the newest edit always wins.
create or replace function public.records_set_synced_at()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null; -- skip this row; keep the newer version
  end if;
  new.synced_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists records_set_synced_at on public.records;
create trigger records_set_synced_at
  before insert or update on public.records
  for each row execute function public.records_set_synced_at();

-- Row-level security: every user (including guests) can only read and write
-- their own rows.
alter table public.records enable row level security;

drop policy if exists "Users manage their own records" on public.records;
create policy "Users manage their own records"
  on public.records
  for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
