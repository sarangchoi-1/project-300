-- LOCAL TEST FIXTURE - NOT A MIGRATION.
-- Tiny assertion helpers so the regression file reads as a list of expectations
-- rather than a wall of exception handling.

create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Fail loudly unless the condition is exactly true.
create or replace function tests.assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $$
begin
  if p_condition is not true then
    raise exception 'ASSERTION FAILED: %', p_message;
  end if;
end;
$$;

-- Assert a statement is rejected (either an error, e.g. permission denied /
-- RLS check violation / constraint violation).
create or replace function tests.assert_denied(p_sql text, p_message text)
returns void
language plpgsql
as $$
declare
  v_succeeded boolean := false;
begin
  begin
    execute p_sql;
    v_succeeded := true;
  exception
    when others then
      v_succeeded := false;
  end;

  if v_succeeded then
    raise exception 'ASSERTION FAILED: expected rejection but statement succeeded -> %', p_message;
  end if;
end;
$$;

-- Assert how many rows a write touched. RLS denies reads/writes *silently* by
-- filtering rows, so "0 rows affected" is the expected shape of most denials.
create or replace function tests.assert_affects(p_sql text, p_expected integer, p_message text)
returns void
language plpgsql
as $$
declare
  v_count integer;
begin
  execute p_sql;
  get diagnostics v_count = row_count;

  if v_count <> p_expected then
    raise exception 'ASSERTION FAILED: % (expected % row(s) affected, got %)',
      p_message, p_expected, v_count;
  end if;
end;
$$;

-- Assert how many rows a query can see through RLS.
create or replace function tests.assert_visible(p_sql text, p_expected integer, p_message text)
returns void
language plpgsql
as $$
declare
  v_count integer;
begin
  execute 'select count(*) from (' || p_sql || ') _rls_probe' into v_count;

  if v_count <> p_expected then
    raise exception 'ASSERTION FAILED: % (expected % visible row(s), got %)',
      p_message, p_expected, v_count;
  end if;
end;
$$;
