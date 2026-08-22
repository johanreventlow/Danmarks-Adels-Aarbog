\set ON_ERROR_STOP on

-- Disposable-database runner for the complete canonical db-verify.sql suite.
-- db-verify contains legacy integration checks that intentionally operate on
-- one existing person/source and a fixed synthetic redaction subject. Provide
-- only those exact prerequisites here; individual feature fixtures stay in
-- db-verify and this runner removes its prerequisites after a green run.
-- Never run this wrapper against production.

DELETE FROM lineage WHERE id IN (-987659904,-987659903);
DELETE FROM source WHERE id=-987659902;
DELETE FROM person WHERE id=-987659901;
DELETE FROM profiles WHERE id='00000000-0000-0000-0000-000000000001';
DELETE FROM auth.users WHERE id='00000000-0000-0000-0000-000000000001';

INSERT INTO auth.users(id,email)
VALUES ('00000000-0000-0000-0000-000000000001',
        'db-verify-runner@example.invalid');
INSERT INTO profiles(id,rolle,email)
VALUES ('00000000-0000-0000-0000-000000000001',
        'redaktion','db-verify-runner@example.invalid');
INSERT INTO person(id,levende,privat,status)
VALUES (-987659901,false,false,'db-verify synthetic prerequisite');
INSERT INTO source(id,slags,titel,import_key)
VALUES (-987659902,'test','db-verify synthetic prerequisite',
        'db-verify-synthetic-prerequisite');
INSERT INTO lineage(id,source_id,kode,navn,slaegtsnavn,parent_lineage_id) VALUES
  (-987659903,NULL,NULL,'db-verify synthetic family root','Verify-slægt',NULL),
  (-987659904,-987659902,'I','db-verify synthetic branch',NULL,-987659903);

CREATE TEMP TABLE task3_db_verify_seeded_vocab(code text PRIMARY KEY);
WITH inserted AS (
  INSERT INTO vocab(scheme,code,label) VALUES
    ('faktatype','fødsel','Fødsel'),
    ('faktatype','dåb','Dåb'),
    ('faktatype','død','Død'),
    ('faktatype','begravelse','Begravelse'),
    ('faktatype','floruit','Floruit'),
    ('faktatype','naturalisering','Naturalisation'),
    ('faktatype','introduktion_ridderhus','Introduktion på ridderhus')
  ON CONFLICT (scheme,code) DO NOTHING
  RETURNING code
)
INSERT INTO task3_db_verify_seeded_vocab(code)
SELECT code FROM inserted;

\ir ../../db-verify.sql

DELETE FROM vocab v
USING task3_db_verify_seeded_vocab s
WHERE v.scheme='faktatype' AND v.code=s.code;
DELETE FROM lineage WHERE id IN (-987659904,-987659903);
DELETE FROM source WHERE id=-987659902;
DELETE FROM person WHERE id=-987659901;
DELETE FROM profiles WHERE id='00000000-0000-0000-0000-000000000001';
DELETE FROM auth.users WHERE id='00000000-0000-0000-0000-000000000001';

DO $$ BEGIN
  RAISE NOTICE 'OK: full db-verify.sql completed with disposable prerequisites removed';
END $$;
