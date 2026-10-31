-- Trin 6b (plan Task 10/15): serverens kanoniske hash af en inputkopis input-objekt (samme funktion som
-- red_record_identity_candidates' drift-kontrol). Udskriver kun hashen.
-- Brug: psql -X -q -At -d <base> -v input_file=<kopi>.inner.json -f …
\set ON_ERROR_STOP on
\set content `cat :input_file`
SET default_transaction_read_only=on;
SELECT private.reimport_canonical_json_sha256(:'content'::jsonb);
