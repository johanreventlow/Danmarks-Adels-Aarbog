-- Fælles: skridtets nøglede items ligger i daa.t5_items (jsonb-tekst). capture skriver dem til :items.tmp (kalderen har
-- umask 077), som omdøbes til :items efter COMMIT (transfer_5ab_step_end.sql / _disposition.sql), så et afbrudt skridt aldrig
-- efterlader en items-fil på målstien; begge tilstande sætter :t5_sha (sha256 af den kanoniske jsonb-tekst). Inkluderes med \ir.
SELECT encode(sha256(convert_to(current_setting('daa.t5_items')::jsonb::text,'UTF8')),'hex') AS t5_sha \gset
\if :t5_replay
\else
\set t5_items_tmp :items .tmp
\o :t5_items_tmp
SELECT current_setting('daa.t5_items')::jsonb::text;
\o
\endif
