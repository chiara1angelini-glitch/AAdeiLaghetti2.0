-- =====================================================================
-- Database dell'app Azienda Agricola dei Laghetti (Supabase / PostgreSQL)
-- Incolla tutto questo file in Supabase: SQL Editor -> New query -> Run.
-- =====================================================================

-- Cavalieri massimi per lezione (tienilo uguale a maxPerSlot in config.js)
create or replace function max_per_slot() returns int language sql immutable as $$ select 4 $$;

-- ---------- tabelle ----------
create table if not exists profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null,
  email text,
  role text not null default 'cliente' check (role in ('cliente','admin')),
  created_at timestamptz not null default now()
);

create table if not exists carnets (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  size int not null default 10 check (size > 0),
  created_at timestamptz not null default now()
);

create table if not exists bookings (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  day date not null,
  slot text not null,                       -- '17:00', '09:00'... oppure 'extra' (timbro fuori agenda)
  status text not null default 'prenotata' check (status in ('prenotata','annullata','svolta','assente')),
  carnet_id bigint references carnets(id) on delete set null,
  stamped_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists bookings_day_idx on bookings(day, slot);
create index if not exists bookings_user_idx on bookings(user_id);

-- ---------- chi è gestore ----------
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin')
$$;

-- ---------- profilo creato in automatico alla registrazione ----------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name, email)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'name', ''), 'Allievo'), new.email);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ---------- sicurezza: ognuno vede i propri dati, i gestori vedono tutto ----------
alter table profiles enable row level security;
alter table carnets  enable row level security;
alter table bookings enable row level security;

drop policy if exists "profili: propri o gestore" on profiles;
create policy "profili: propri o gestore" on profiles for select using (id = auth.uid() or is_admin());
drop policy if exists "profili: modifica gestore" on profiles;
create policy "profili: modifica gestore" on profiles for update using (is_admin());

drop policy if exists "carnet: propri o gestore" on carnets;
create policy "carnet: propri o gestore" on carnets for select using (user_id = auth.uid() or is_admin());
drop policy if exists "carnet: crea gestore" on carnets;
create policy "carnet: crea gestore" on carnets for insert with check (is_admin());
drop policy if exists "carnet: modifica gestore" on carnets;
create policy "carnet: modifica gestore" on carnets for update using (is_admin());
drop policy if exists "carnet: elimina gestore" on carnets;
create policy "carnet: elimina gestore" on carnets for delete using (is_admin());

drop policy if exists "prenotazioni: proprie o gestore" on bookings;
create policy "prenotazioni: proprie o gestore" on bookings for select using (user_id = auth.uid() or is_admin());
drop policy if exists "prenotazioni: modifica gestore" on bookings;
create policy "prenotazioni: modifica gestore" on bookings for update using (is_admin());
-- gli allievi prenotano e annullano solo tramite le funzioni qui sotto

-- ---------- posti occupati per ogni lezione (senza mostrare i nomi) ----------
create or replace function slot_counts(d_from date, d_to date)
returns table(day date, slot text, n bigint)
language sql stable security definer set search_path = public as $$
  select b.day, b.slot, count(*) from bookings b
  where b.day between d_from and d_to and b.status <> 'annullata'
  group by b.day, b.slot
$$;

-- lezioni ancora disponibili sul carnet di un allievo
create or replace function carnet_free(p_user uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select sum(greatest(c.size - (select count(*) from bookings b where b.carnet_id = c.id and b.status = 'svolta'), 0))
                   from carnets c where c.user_id = p_user), 0)::int
       - (select count(*) from bookings where user_id = p_user and status = 'prenotata' and day >= current_date)::int
$$;

-- ---------- prenota una lezione ----------
create or replace function book_slot(p_day date, p_slot text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  dow int := extract(dow from p_day);
  allowed text[];
begin
  if uid is null then raise exception 'Devi accedere per prenotare'; end if;
  allowed := case dow
    when 0 then array['09:00','10:00','11:00']
    when 6 then array['15:00','16:00','17:00','18:00']
    when 1 then array[]::text[]
    else array['17:00','18:00'] end;
  if dow = 1 then raise exception 'Il lunedì siamo chiusi'; end if;
  if not (p_slot = any(allowed)) then raise exception 'Orario non disponibile'; end if;
  if (p_day + p_slot::time) < (now() at time zone 'Europe/Rome') then raise exception 'Questo orario è già passato'; end if;
  if exists (select 1 from bookings where user_id = uid and day = p_day and slot = p_slot and status <> 'annullata') then
    raise exception 'Hai già prenotato questa lezione'; end if;
  perform pg_advisory_xact_lock(hashtext(p_day::text || p_slot));
  if (select count(*) from bookings where day = p_day and slot = p_slot and status <> 'annullata') >= max_per_slot() then
    raise exception 'Lezione al completo'; end if;
  if carnet_free(uid) <= 0 then raise exception 'Carnet esaurito: chiedi un nuovo carnet in segreteria'; end if;
  insert into bookings (user_id, day, slot) values (uid, p_day, p_slot);
end $$;

-- ---------- annulla una propria prenotazione ----------
create or replace function cancel_booking(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update bookings set status = 'annullata'
  where id = p_id and user_id = auth.uid() and status = 'prenotata' and day >= current_date;
  if not found then raise exception 'Prenotazione non trovata'; end if;
end $$;

-- ---------- timbra una lezione sul carnet (solo gestori) ----------
create or replace function stamp_booking(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u uuid; cid bigint;
begin
  if not is_admin() then raise exception 'Solo i gestori possono timbrare'; end if;
  select user_id into u from bookings where id = p_id;
  if u is null then raise exception 'Prenotazione non trovata'; end if;
  select c.id into cid from carnets c
   where c.user_id = u and (select count(*) from bookings b where b.carnet_id = c.id and b.status = 'svolta') < c.size
   order by c.id limit 1;
  if cid is null then raise exception 'NO_CARNET'; end if;
  update bookings set status = 'svolta', carnet_id = cid, stamped_at = now() where id = p_id;
end $$;

-- timbro senza prenotazione (lezione di oggi fuori agenda)
create or replace function manual_stamp(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare bid bigint;
begin
  if not is_admin() then raise exception 'Solo i gestori possono timbrare'; end if;
  if not exists (select 1 from carnets c where c.user_id = p_user
                 and (select count(*) from bookings b where b.carnet_id = c.id and b.status = 'svolta') < c.size) then
    raise exception 'NO_CARNET'; end if;
  insert into bookings (user_id, day, slot) values (p_user, current_date, 'extra') returning id into bid;
  perform stamp_booking(bid);
end $$;

grant execute on function slot_counts(date, date), book_slot(date, text), cancel_booking(bigint),
  stamp_booking(bigint), manual_stamp(uuid), carnet_free(uuid), is_admin() to authenticated;

-- ---------------------------------------------------------------------
-- DOPO che Umberto e Pamela si sono registrati dall'app, rendili gestori:
--   update profiles set role = 'admin' where email in ('email-di-umberto@...', 'email-di-pamela@...');
-- ---------------------------------------------------------------------
