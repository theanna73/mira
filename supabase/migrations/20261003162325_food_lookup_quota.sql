-- No product catalogue or user diary data is stored here.
create schema if not exists mira_internal;
revoke all on schema mira_internal from public, anon, authenticated;
grant usage on schema mira_internal to service_role;

create table mira_internal.food_lookup_quota (
  singleton boolean primary key default true check (singleton),
  next_allowed_at timestamptz not null
);
alter table mira_internal.food_lookup_quota enable row level security;
revoke all on mira_internal.food_lookup_quota from public, anon, authenticated;
grant select, update on mira_internal.food_lookup_quota to service_role;
insert into mira_internal.food_lookup_quota values (true, '-infinity');

-- At most one upstream lookup every six seconds across ALL function instances:
-- a rolling-window limit stays safe even at minute boundaries.
create function public.consume_food_lookup_request()
returns boolean language sql security invoker set search_path = '' as $$
  with consumed as (
    update mira_internal.food_lookup_quota
    set next_allowed_at = clock_timestamp() + interval '6 seconds'
    where singleton and next_allowed_at <= clock_timestamp()
    returning singleton
  ) select exists(select 1 from consumed);
$$;
revoke all on function public.consume_food_lookup_request() from public, anon, authenticated;
grant execute on function public.consume_food_lookup_request() to service_role;
