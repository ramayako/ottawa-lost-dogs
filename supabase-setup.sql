-- Ottawa Lost & Found Dogs: database setup for Supabase
-- Paste this whole file into Supabase > SQL Editor > New query, then press Run. Safe to run again.

create extension if not exists pgcrypto;

-- ---------- Reports ----------
create table if not exists public.reports (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  type          text not null check (type in ('lost','found')),
  status        text not null default 'open' check (status in ('open','reunited')),
  dog_name      text default '' check (char_length(dog_name) <= 60),
  breed         text default '' check (char_length(breed) <= 80),
  colour        text default '' check (char_length(colour) <= 80),
  size          text default 'unknown' check (size in ('small','medium','large','unknown')),
  sex           text default 'unknown' check (sex in ('male','female','unknown')),
  age           text default 'unknown' check (age in ('puppy','adult','senior','unknown')),
  id_type       text default 'unknown' check (id_type in ('tag','microchip','tattoo','none','unknown')),
  id_details    text default '' check (char_length(id_details) <= 120),
  traits        text[] not null default '{}',
  situation     text default '' check (situation in ('','with_me','seen_only','shelter')),
  neighbourhood text not null check (char_length(neighbourhood) between 2 and 60),
  address       text default '' check (char_length(address) <= 120),
  lat           double precision check (lat is null or lat between 45.15 and 45.60),
  lng           double precision check (lng is null or lng between -76.10 and -75.25),
  event_date    date not null,
  event_time    text default '' check (char_length(event_time) <= 5),
  description   text default '' check (char_length(description) <= 800),
  contact_name  text not null check (char_length(contact_name) between 1 and 60),
  contact_phone text not null check (char_length(contact_phone) between 7 and 30),
  contact_email text default '' check (char_length(contact_email) <= 100),
  photo         text default '' check (char_length(photo) <= 120),
  match_ids     uuid[] not null default '{}',
  matches       jsonb not null default '[]',
  reunited_at   timestamptz,
  hidden        boolean not null default false,
  manage_code   text not null default encode(gen_random_bytes(6),'hex'),
  ip_hash       text default ''
);
create index if not exists reports_created_idx on public.reports (created_at desc);
create index if not exists reports_match_idx on public.reports using gin (match_ids);
alter table public.reports enable row level security;   -- no direct access; everything goes through the functions and views below

-- ---------- Visits (traffic metrics, no personal data) ----------
create table if not exists public.visits (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  path       text default '/',
  referrer   text default '',
  device     text default '',
  visitor    text default ''   -- random id kept in the visitor's browser, not linked to a person
);
create index if not exists visits_created_idx on public.visits (created_at);
alter table public.visits enable row level security;

-- ---------- Contact reveals (phone numbers are never in the public data) ----------
create table if not exists public.contact_reveals (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  report_id  uuid,
  ip_hash    text
);
create index if not exists reveals_ip_idx on public.contact_reveals (ip_hash, created_at);
alter table public.contact_reveals enable row level security;

-- ---------- Public read-only view of reports (no phone, email, name, codes or spam) ----------
drop view if exists public.reports_public;
create view public.reports_public as
  select id, created_at, type, status, dog_name, breed, colour, size, sex, age, id_type, id_details,
         traits, situation, neighbourhood, address, lat, lng, event_date, event_time, description,
         right(regexp_replace(contact_phone, '\D', '', 'g'), 2) as phone_hint,
         (contact_email <> '') as has_email,
         photo, match_ids, matches, reunited_at
  from public.reports where not hidden;

-- ---------- Show one report's contact, rate-limited per connection ----------
create or replace function public.reveal_contact(p_id uuid)
returns table (contact_name text, contact_phone text, contact_email text)
language plpgsql security definer set search_path = public as $$
declare
  ip text := coalesce(split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1), '');
  h  text := encode(digest(ip || 'odf-salt', 'sha256'), 'hex');
  n_hour int; n_day int;
begin
  select count(*) filter (where created_at > now() - interval '1 hour'), count(*) into n_hour, n_day
    from public.contact_reveals where ip_hash = h and created_at > now() - interval '1 day';
  if n_hour >= 12 or n_day >= 40 then
    raise exception 'You have viewed many phone numbers. Please try again later.';
  end if;
  insert into public.contact_reveals (report_id, ip_hash) values (p_id, h);
  return query select r.contact_name, r.contact_phone, r.contact_email from public.reports r where r.id = p_id and not r.hidden;
end $$;

-- ---------- Submit a report ----------
create or replace function public.submit_report(p jsonb)
returns table (id uuid, manage_code text)
language plpgsql security definer set search_path = public as $$
declare
  ip text := coalesce(split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1), '');
  h  text := encode(digest(ip || 'odf-salt', 'sha256'), 'hex');
  recent int;
  r public.reports;
begin
  select count(*) into recent from public.reports x where x.ip_hash = h and x.created_at > now() - interval '1 hour';
  if recent >= 6 then raise exception 'Too many reports from this connection. Try again in an hour.'; end if;
  if (p->>'event_date')::date > (now() at time zone 'America/Toronto')::date + 1 then raise exception 'Date is in the future.'; end if;
  insert into public.reports (type, dog_name, breed, colour, size, sex, age, id_type, id_details, traits, situation,
    neighbourhood, address, lat, lng, event_date, event_time, description, contact_name, contact_phone, contact_email,
    photo, match_ids, matches, ip_hash)
  values (p->>'type', coalesce(p->>'dog_name',''), coalesce(p->>'breed',''), coalesce(p->>'colour',''),
    coalesce(p->>'size','unknown'), coalesce(p->>'sex','unknown'), coalesce(p->>'age','unknown'),
    coalesce(p->>'id_type','unknown'), coalesce(p->>'id_details',''),
    coalesce(array(select jsonb_array_elements_text(p->'traits')), '{}'), coalesce(p->>'situation',''),
    p->>'neighbourhood', coalesce(p->>'address',''), (p->>'lat')::double precision, (p->>'lng')::double precision,
    (p->>'event_date')::date, coalesce(p->>'event_time',''), coalesce(p->>'description',''),
    p->>'contact_name', p->>'contact_phone', coalesce(p->>'contact_email',''), coalesce(p->>'photo',''),
    coalesce(array(select jsonb_array_elements_text(p->'match_ids'))::uuid[], '{}'), coalesce(p->'matches','[]'::jsonb), h)
  returning * into r;
  return query select r.id, r.manage_code;
end $$;

-- ---------- Reporter actions (need the private code given after posting) ----------
create or replace function public.mark_reunited(p_id uuid, p_code text)
returns boolean language sql security definer set search_path = public as $$
  update public.reports set status = 'reunited', reunited_at = now()
  where id = p_id and manage_code = p_code returning true;
$$;
create or replace function public.remove_report(p_id uuid, p_code text)
returns boolean language sql security definer set search_path = public as $$
  update public.reports set hidden = true where id = p_id and manage_code = p_code returning true;
$$;

-- ---------- Log a page view ----------
create or replace function public.log_visit(p_path text, p_referrer text, p_device text, p_visitor text)
returns void language sql security definer set search_path = public as $$
  insert into public.visits (path, referrer, device, visitor)
  values (left(coalesce(p_path,'/'),80), left(coalesce(p_referrer,''),120), left(coalesce(p_device,''),10), left(coalesce(p_visitor,''),40));
$$;

-- ---------- Metrics ----------
drop view if exists public.stats_daily;
create view public.stats_daily as
with days as (
  select generate_series((now() at time zone 'America/Toronto')::date - 89, (now() at time zone 'America/Toronto')::date, '1 day')::date as day
),
c as (select (created_at at time zone 'America/Toronto')::date d, count(*) contacts from public.contact_reveals group by 1),
v as (select (created_at at time zone 'America/Toronto')::date d, count(*) views, count(distinct visitor) visitors from public.visits group by 1),
r as (select (created_at at time zone 'America/Toronto')::date d,
             count(*) filter (where type='lost') new_lost, count(*) filter (where type='found') new_found
      from public.reports where not hidden group by 1),
u as (select (reunited_at at time zone 'America/Toronto')::date d, count(*) reunited from public.reports where reunited_at is not null group by 1)
select days.day, coalesce(v.views,0) page_views, coalesce(v.visitors,0) visitors,
       coalesce(r.new_lost,0) new_lost, coalesce(r.new_found,0) new_found, coalesce(u.reunited,0) reunited, coalesce(c.contacts,0) contacts_viewed
from days left join v on v.d = days.day left join c on c.d = days.day left join r on r.d = days.day left join u on u.d = days.day
order by days.day;

create or replace view public.stats_totals as
select
  (select count(*) from public.visits) total_page_views,
  (select count(distinct visitor) from public.visits) total_visitors,
  (select count(distinct visitor) from public.visits where created_at > now() - interval '30 days') visitors_30d,
  (select count(*) from public.reports where not hidden and type='lost' and status='open') open_lost,
  (select count(*) from public.reports where not hidden and type='found' and status='open') open_found,
  (select count(*) from public.reports where status='reunited') total_reunited,
  (select count(*) from public.reports where not hidden) total_reports;

create or replace view public.stats_referrers as
select coalesce(nullif(referrer,''),'(direct)') source, count(*) views
from public.visits where created_at > now() - interval '30 days'
group by 1 order by 2 desc limit 20;

create or replace view public.stats_neighbourhoods as
select neighbourhood, count(*) filter (where type='lost') lost, count(*) filter (where type='found') found
from public.reports where not hidden and created_at > now() - interval '90 days'
group by 1 order by count(*) desc;

-- ---------- Permissions for the public website key ----------
revoke all on public.reports, public.visits, public.contact_reveals from anon, authenticated;
grant select on public.reports_public, public.stats_daily, public.stats_totals, public.stats_referrers, public.stats_neighbourhoods to anon, authenticated;
grant execute on function public.submit_report(jsonb), public.reveal_contact(uuid), public.mark_reunited(uuid,text), public.remove_report(uuid,text),
  public.log_visit(text,text,text,text) to anon, authenticated;

-- ---------- Photo storage ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 1048576, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "Anyone can upload dog photos" on storage.objects;
create policy "Anyone can upload dog photos" on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'photos');
