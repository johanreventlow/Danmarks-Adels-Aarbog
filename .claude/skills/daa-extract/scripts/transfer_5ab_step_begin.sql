-- Fælles indgang for 5a+5b-skridt-SQL (plan B1 Task 3a/3b; inkluderes med \ir). Variabler: src, mode=capture|replay,
-- items=<sti> [fault]. Åbner skridtets transaktion (REPEATABLE READ, så items-sammenligningen og RPC'en ser samme
-- snapshot), låser sessionsindstillingerne, vælger aktøren (første profil med rolle='redaktion', ORDER BY id) og
-- indlæser i replay pakkens items klientside (aldrig pg_read_file). Printer intet.
\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
\if :{?src}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: -v src mangler'; END $$;
\endif
\if :{?items}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: -v items mangler'; END $$;
\endif
\if :{?mode}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: -v mode mangler'; END $$;
\endif
SELECT :'mode' IN ('capture','replay') AS t5_mode_ok, :'mode'='replay' AS t5_replay \gset
\if :t5_mode_ok
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: mode skal være capture eller replay'; END $$;
\endif
\if :t5_replay
\set t5_pack_items `cat :items`
\endif
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO, MDY';
SET LOCAL IntervalStyle='postgres';
SET LOCAL extra_float_digits=1;
SET LOCAL search_path TO pg_catalog, public;
SELECT id::text AS t5_actor FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 1 \gset
\if :{?t5_actor}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_NO_ACTOR'; END $$;
\endif
SELECT set_config('request.jwt.claim.sub', :'t5_actor', true) \g /dev/null
SELECT set_config('daa.t5_step', :'t5_step', true) \g /dev/null
\if :t5_replay
SELECT set_config('daa.t5_pack_items', :'t5_pack_items', true) \g /dev/null
\endif
\set t5_extra ''
