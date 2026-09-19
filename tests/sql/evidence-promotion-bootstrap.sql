-- Mindste Supabase-kompatible forudsætninger for schema.sql i ren PostgreSQL 17.
--
-- Dette er bevidst ikke et sikkerheds-stub: anon/authenticated får ingen schema-,
-- tabel- eller funktionsgrants her. Dermed kan promotion-testen stadig opdage, hvis
-- schema.sql eller db-rls.sql fejlagtigt åbner private objekter.

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

DO $bootstrap_roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    CREATE ROLE anon NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
    CREATE ROLE service_role NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT BYPASSRLS;
  END IF;
END $bootstrap_roles$;

CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY,
  email text
);

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;

-- Storage-shim: mindste spejl af Supabase Storage-katalogen, så db-rls.sql's
-- storage-blok (der er pakket ind i "if exists storage.objects") faktisk opretter
-- politikkerne, og db-verify.sql's Task 12b faktisk KØRER i CI i stedet for at
-- skrive "SPRINGER OVER". Uden shimmen var de to gæstevendte storage-politikker
-- utestede overalt undtagen i prod (medie-indkapslingen 2026-09-19).
--
-- Bevidste afvigelser fra rigtig Supabase (kendt og dokumenteret, ikke overset):
--   · ingen storage.protect_delete()-trigger — direkte DELETE er tilladt her
--   · ingen grants til anon/authenticated (Task 12b giver dem selv i sin egen
--     transaktion og ruller dem tilbage), så et fejlagtigt åbent objekt stadig
--     kan opdages af de øvrige tests.
CREATE SCHEMA IF NOT EXISTS storage;

CREATE TABLE IF NOT EXISTS storage.buckets (
  id         text PRIMARY KEY,
  name       text,
  public     boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id  text REFERENCES storage.buckets(id),
  name       text,
  owner      uuid,
  metadata   jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (bucket_id, name)
);

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Privat bucket, som i prod. 'public=false' er ikke kosmetik: en offentlig bucket
-- ville gøre hele RLS-laget ligegyldigt (bytes serveres da uden politik-tjek).
INSERT INTO storage.buckets(id, name, public)
VALUES ('media','media',false)
ON CONFLICT (id) DO NOTHING;
