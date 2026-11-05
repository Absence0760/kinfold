-- The service role's reach (20261104000000_service_role_reach.sql).
--
-- Properties this file pins:
--   * every table and view in `public` and `private` grants the service role
--     select, insert, update and delete - so a service call meets the object's
--     own guard (an append-only trigger, the status guard), never a bare
--     `permission denied` that depends on which Supabase image built the stack;
--   * every sequence grants it usage, and every function grants it execute;
--   * objects later migrations create get the same rights by default, for
--     both schemas.
-- A migration that adds an object the service can't reach fails here by name,
-- on any CLI version, instead of only on a stack whose defaults stop granting.
begin;
select plan(5);

select is(
  array(
    select n.nspname || '.' || c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'private') and c.relkind in ('r', 'p', 'v', 'm')
      and not (has_table_privilege('service_role', c.oid, 'select')
           and has_table_privilege('service_role', c.oid, 'insert')
           and has_table_privilege('service_role', c.oid, 'update')
           and has_table_privilege('service_role', c.oid, 'delete'))
    order by 1),
  '{}'::text[],
  'every table and view in public and private is reachable by the service role'
);

select is(
  array(
    select n.nspname || '.' || c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    -- The CASE keeps the privilege check off non-sequences: the planner may
    -- evaluate it before the relkind filter, and it errors on an index.
    where n.nspname in ('public', 'private') and c.relkind = 'S'
      and case when c.relkind = 'S' then not has_sequence_privilege('service_role', c.oid, 'usage') else false end
    order by 1),
  '{}'::text[],
  'every sequence in public and private is usable by the service role'
);

select is(
  array(
    select p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and not has_function_privilege('service_role', p.oid, 'execute')
    order by 1),
  '{}'::text[],
  'every function in public and private is executable by the service role'
);

-- The defaults: what postgres creates later in either schema is the service's too.
select is(
  array(
    select d.defaclnamespace::regnamespace::text || ':' || d.defaclobjtype::text
    from pg_default_acl d
    where d.defaclrole = 'postgres'::regrole
      and d.defaclnamespace in ('public'::regnamespace, 'private'::regnamespace)
      and exists (
        select 1 from aclexplode(d.defaclacl) a
        where a.grantee = 'service_role'::regrole
        group by a.grantee
        having (d.defaclobjtype = 'r' and array_agg(a.privilege_type::text) @> '{SELECT,INSERT,UPDATE,DELETE}'::text[])
            or (d.defaclobjtype = 'S' and array_agg(a.privilege_type::text) @> '{USAGE,SELECT}'::text[])
            or (d.defaclobjtype = 'f' and array_agg(a.privilege_type::text) @> '{EXECUTE}'::text[]))
    order by (d.defaclnamespace::regnamespace::text || ':' || d.defaclobjtype::text) collate "C"),
  array['private:S', 'private:f', 'private:r', 'public:S', 'public:f', 'public:r'],
  'new tables, sequences and functions in public and private default to the service role'
);

-- The client roles are not widened: anon still writes no table in public.
select is(
  array(
    select c.relname::text
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
      and (has_table_privilege('anon', c.oid, 'insert')
        or has_table_privilege('anon', c.oid, 'update')
        or has_table_privilege('anon', c.oid, 'delete'))
    order by 1),
  '{}'::text[],
  'anon is handed no table write in public'
);

select * from finish();
rollback;
