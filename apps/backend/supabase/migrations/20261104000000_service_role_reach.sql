-- The service role's reach, stated for every object hardening never saw.
--
-- 20261030120400_hardening.sql hands the service role (edge functions, the
-- partner's reports) its rights with blanket grants over both schemas - but a
-- blanket grant covers only the objects that exist when it runs. Everything
-- created after it (the Home Fund loans, cover plans, inspections, needs
-- reviews, grants, restructures, the open books, ...) fell back on Supabase's
-- default privileges, and those differ between Supabase images: CI's image
-- (supabase/postgres 17.11.0.011) hands `service_role` full table rights and
-- function execute, while the one a local CLI 2.109 stack ran (17.6.1.143)
-- hands new tables only TRUNCATE/REFERENCES/TRIGGER/MAINTAIN and new
-- functions nothing. On that
-- stack a service call answered `permission denied for table fund_loans`
-- before its own guard could speak, and an append-only trigger's refusal
-- ("grants is append-only") was pre-empted by the ACL.
--
-- This migration states the same reach in hardening's own words, for every
-- object that exists now, and makes it the default for objects later
-- migrations create (they run as postgres), so the service's reach never
-- rests on an image's defaults again. The client roles are not touched: anon
-- and authenticated keep exactly the explicit grants each migration gave them.
-- The guards still apply to the service: append-only triggers, the status and
-- payout guards, and each function's own `private.is_service()` / auth checks.

grant usage on schema private to service_role;

grant select, insert, update, delete on all tables in schema public, private to service_role;
grant usage, select on all sequences in schema public, private to service_role;
grant execute on all functions in schema public, private to service_role;

alter default privileges for role postgres in schema public, private
  grant select, insert, update, delete on tables to service_role;
alter default privileges for role postgres in schema public, private
  grant usage, select on sequences to service_role;
alter default privileges for role postgres in schema public, private
  grant execute on functions to service_role;
