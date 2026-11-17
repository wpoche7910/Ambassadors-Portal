-- =====================================================================
-- Ambassadors Portal: database setup
-- Run this ONCE in Supabase: SQL Editor -> New query -> paste -> Run.
-- It is safe to run again; it only adds what is missing.
-- =====================================================================

-- ---------- who may use the portal -----------------------------------
create table if not exists public.staff (
  id             bigint generated always as identity primary key,
  user_id        uuid unique references auth.users(id) on delete set null,
  email          text,
  name           text not null check (char_length(btrim(name)) between 1 and 80),
  role           text not null check (role in ('officer', 'moderator')),
  active         boolean not null default true,
  invite_hash    text unique,            -- sha-256 of the secret invite code (the code itself is never stored)
  invite_expires timestamptz,
  created_at     timestamptz not null default now()
);

-- ---------- portal data ----------------------------------------------
create table if not exists public.members (
  id              bigint generated always as identity primary key,
  first_name      text not null check (char_length(btrim(first_name)) between 1 and 60),
  last_name       text not null default '' check (char_length(last_name) <= 80),
  position        text not null default '' check (char_length(position) <= 60),
  email           text not null default '' check (char_length(email) <= 120),
  phone           text not null default '' check (char_length(phone) <= 40),
  notes           text not null default '' check (char_length(notes) <= 2000),
  status          text not null default 'active' check (status in ('active', 'guest')),
  reminder_status text not null default 'not_sent' check (reminder_status in ('not_sent', 'sent', 'confirmed')),
  created_at      timestamptz not null default now()
);

create table if not exists public.categories (
  id         bigint generated always as identity primary key,
  name       text not null check (char_length(btrim(name)) between 1 and 40),
  kind       text not null default 'checkbox' check (kind in ('checkbox', 'text')),
  created_at timestamptz not null default now()
);
create unique index if not exists categories_name_unique on public.categories (lower(name));

create table if not exists public.member_categories (
  member_id   bigint not null references public.members(id) on delete cascade,
  category_id bigint not null references public.categories(id) on delete cascade,
  value       text not null check (value <> '' and char_length(value) <= 200),
  primary key (member_id, category_id)
);

create table if not exists public.events (
  id                 bigint generated always as identity primary key,
  title              text not null check (char_length(btrim(title)) between 1 and 120),
  event_date         date,
  start_time         text not null default '' check (start_time = '' or start_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  location           text not null default '' check (char_length(location) <= 200),
  description        text not null default '' check (char_length(description) <= 2000),
  setup_email        boolean not null default false,
  main_email         boolean not null default false,
  groupme            boolean not null default false,
  reminder_posted_at timestamptz,
  created_at         timestamptz not null default now()
);

create table if not exists public.signups (
  event_id  bigint not null references public.events(id) on delete cascade,
  member_id bigint not null references public.members(id) on delete cascade,
  role      text not null default 'participant' check (role in ('officer', 'setup', 'main', 'participant')),
  attended  boolean not null default true,
  note      text not null default '' check (char_length(note) <= 200),
  primary key (event_id, member_id)
);

create table if not exists public.activity_log (
  id         bigint generated always as identity primary key,
  user_id    uuid,
  user_name  text not null default 'System',
  action     text not null check (char_length(action) <= 120),
  detail     text not null default '' check (char_length(detail) <= 500),
  created_at timestamptz not null default now()
);

create index if not exists signups_member_idx   on public.signups (member_id);
create index if not exists events_date_idx      on public.events (event_date);
create index if not exists activity_created_idx on public.activity_log (id desc);

-- The t-shirt category is the first tracking category.
insert into public.categories (name, kind)
select 'T-shirt purchased', 'checkbox'
where not exists (select 1 from public.categories where lower(name) = 't-shirt purchased');

-- ---------- helper: is the person logged in an active officer/moderator? ----
create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff s where s.user_id = auth.uid() and s.active);
$$;

-- ---------- invitations (no email needed: a secret link does the job) -------
create or replace function public.create_invite(p_name text, p_role text) returns text
language plpgsql security definer set search_path = public as $$
declare code text;
begin
  if not public.is_staff() then raise exception 'Not allowed'; end if;
  if p_role not in ('officer', 'moderator') then raise exception 'Choose officer or moderator'; end if;
  if char_length(btrim(coalesce(p_name, ''))) = 0 then raise exception 'Please enter a name'; end if;
  code := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.staff (name, role, invite_hash, invite_expires)
  values (btrim(p_name), p_role, encode(sha256(convert_to(code, 'utf8')), 'hex'), now() + interval '7 days');
  return code;
end $$;

create or replace function public.reissue_invite(p_staff_id bigint) returns text
language plpgsql security definer set search_path = public as $$
declare code text;
begin
  if not public.is_staff() then raise exception 'Not allowed'; end if;
  code := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  update public.staff
     set invite_hash = encode(sha256(convert_to(code, 'utf8')), 'hex'),
         invite_expires = now() + interval '7 days'
   where id = p_staff_id and user_id is null;
  if not found then raise exception 'That person already has an account.'; end if;
  return code;
end $$;

create or replace function public.claim_invite(p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); target bigint;
begin
  if uid is null then raise exception 'Please log in first'; end if;
  if exists (select 1 from public.staff where user_id = uid) then return; end if;  -- already linked
  select id into target from public.staff
   where user_id is null
     and invite_hash = encode(sha256(convert_to(coalesce(p_code, ''), 'utf8')), 'hex')
     and invite_expires > now()
   for update;
  if target is null then raise exception 'This invite link is not valid or has expired.'; end if;
  update public.staff
     set user_id = uid, email = lower(coalesce(auth.jwt() ->> 'email', '')),
         invite_hash = null, invite_expires = null
   where id = target;
end $$;

-- Never leave the portal without an active officer or moderator.
create or replace function public.guard_last_staff() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if OLD.active and OLD.user_id is not null
     and (TG_OP = 'DELETE' or NEW.active is false or NEW.user_id is distinct from OLD.user_id) then
    if not exists (select 1 from public.staff where active and user_id is not null and id <> OLD.id) then
      raise exception 'At least one active officer or moderator account has to remain.';
    end if;
  end if;
  if TG_OP = 'DELETE' then return OLD; end if;
  return NEW;
end $$;
drop trigger if exists staff_guard on public.staff;
create trigger staff_guard before update or delete on public.staff
  for each row execute function public.guard_last_staff();

-- ---------- activity log: the database fills in who did it -------------------
create or replace function public.activity_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if auth.uid() is not null then
    select name into who from public.staff where user_id = auth.uid() and active;
    if who is null then raise exception 'Not allowed'; end if;
    new.user_id := auth.uid();
    new.user_name := who;
  end if;
  new.created_at := now();
  return new;
end $$;
drop trigger if exists activity_fill on public.activity_log;
create trigger activity_fill before insert on public.activity_log
  for each row execute function public.activity_before_insert();

-- ---------- row-level security: only active staff can touch anything --------
alter table public.staff             enable row level security;
alter table public.members           enable row level security;
alter table public.categories        enable row level security;
alter table public.member_categories enable row level security;
alter table public.events            enable row level security;
alter table public.signups           enable row level security;
alter table public.activity_log      enable row level security;

do $$
declare t text;
begin
  foreach t in array array['members', 'categories', 'member_categories', 'events', 'signups'] loop
    execute format('drop policy if exists staff_all on public.%I', t);
    execute format('create policy staff_all on public.%I for all to authenticated using (public.is_staff()) with check (public.is_staff())', t);
  end loop;
end $$;

drop policy if exists staff_read   on public.staff;
drop policy if exists staff_update on public.staff;
drop policy if exists staff_delete on public.staff;
create policy staff_read   on public.staff for select to authenticated using (public.is_staff());
create policy staff_update on public.staff for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy staff_delete on public.staff for delete to authenticated using (public.is_staff());

drop policy if exists log_read   on public.activity_log;
drop policy if exists log_insert on public.activity_log;
create policy log_read   on public.activity_log for select to authenticated using (public.is_staff());
create policy log_insert on public.activity_log for insert to authenticated with check (public.is_staff());

-- ---------- privileges: nothing for anonymous visitors ----------------------
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all tables    in schema public from authenticated;

grant select, insert, update, delete on public.members, public.categories, public.member_categories,
                                        public.events, public.signups to authenticated;
grant select (id, user_id, email, name, role, active, invite_expires, created_at) on public.staff to authenticated;
grant update (name, role, active) on public.staff to authenticated;
grant delete on public.staff to authenticated;
grant select, insert on public.activity_log to authenticated;   -- the log can never be edited or deleted
grant usage, select on all sequences in schema public to authenticated;

revoke execute on function public.is_staff(), public.create_invite(text, text), public.reissue_invite(bigint),
                           public.claim_invite(text) from public, anon;
grant  execute on function public.is_staff(), public.create_invite(text, text), public.reissue_invite(bigint),
                           public.claim_invite(text) to authenticated;
