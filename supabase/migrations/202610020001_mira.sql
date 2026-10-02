-- MVP stores one versioned aggregate per user. CAS prevents silent overwrites.
create table public.mira_documents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision integer not null default 1 check (revision > 0),
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  constraint supported_schema check (payload->>'schemaVersion' = '1'),
  constraint payload_limit check (octet_length(payload::text) <= 1048576)
);
alter table public.mira_documents enable row level security;
create policy "read own document" on public.mira_documents for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.mira_documents from anon, authenticated;
grant select on public.mira_documents to authenticated;

create or replace function public.save_mira_document(new_payload jsonb, expected_revision integer, expected_user uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare current_revision integer; next_revision integer; actor uuid := auth.uid();
begin
  if actor is null or expected_user is distinct from actor then raise exception 'Wrong account' using errcode = '42501'; end if;
  if new_payload is null or new_payload->>'schemaVersion' is distinct from '1'
     or jsonb_typeof(new_payload->'profile') is distinct from 'object'
     or jsonb_typeof(new_payload->'entries') is distinct from 'array'
     or octet_length(new_payload::text) > 1048576 or expected_revision < 0 or expected_revision is null then
    raise exception 'Invalid document' using errcode = '22023';
  end if;
  select revision into current_revision from public.mira_documents where user_id = actor for update;
  if current_revision is null then
    if expected_revision <> 0 then raise exception 'Sync conflict' using errcode = '40001'; end if;
    begin
      insert into public.mira_documents(user_id, revision, payload) values(actor, 1, new_payload);
    exception when unique_violation then raise exception 'Sync conflict' using errcode = '40001'; end;
    return 1;
  end if;
  if current_revision <> expected_revision then raise exception 'Sync conflict' using errcode = '40001'; end if;
  next_revision := current_revision + 1;
  update public.mira_documents set payload = new_payload, revision = next_revision, updated_at = now() where user_id = actor;
  return next_revision;
end $$;
revoke all on function public.save_mira_document(jsonb, integer, uuid) from public, anon;
grant execute on function public.save_mira_document(jsonb, integer, uuid) to authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('wardrobe', 'wardrobe', false, 6291456, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;
create policy "read own wardrobe photos" on storage.objects for select to authenticated using (bucket_id = 'wardrobe' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "upload own wardrobe photos" on storage.objects for insert to authenticated with check (bucket_id = 'wardrobe' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "delete own wardrobe photos" on storage.objects for delete to authenticated using (bucket_id = 'wardrobe' and (storage.foldername(name))[1] = (select auth.uid())::text);

create table public.mira_ai_usage (
  user_id uuid references auth.users(id) on delete cascade,
  hour timestamptz not null,
  requests integer not null default 1,
  primary key(user_id, hour)
);
alter table public.mira_ai_usage enable row level security;
revoke all on public.mira_ai_usage from anon, authenticated;
create or replace function public.consume_mira_ai_request(actor uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare count_requests integer;
begin
  insert into public.mira_ai_usage(user_id, hour, requests) values(actor, date_trunc('hour', now()), 1)
  on conflict(user_id, hour) do update set requests = public.mira_ai_usage.requests + 1
  returning requests into count_requests;
  delete from public.mira_ai_usage where user_id = actor and hour < now() - interval '2 days';
  return count_requests <= 20;
end $$;
revoke all on function public.consume_mira_ai_request(uuid) from public, anon, authenticated;
grant execute on function public.consume_mira_ai_request(uuid) to service_role;
