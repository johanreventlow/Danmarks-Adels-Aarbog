-- Trin 6d-3 Task 7: syntetisk mini-kilde til D/O-ceremonien (samme_som_kort_ceremoni.sql, privat_kort_ceremoni.sql) og
-- målingen (maal_trin6d3.sql). Data COMMIT'es, fordi ceremonierne kører deres egen transaktion. Opdigtede personer med
-- negative id'er; aktør a150…150 (redaktion, som 6d-2a). Kilden -630100 spiller den nye udgave (p39 = personer med
-- person_external_id i kilden); den gamle udgaves rækker er blot personer uden kilde.
--   D01: hovedperson -630101 (p39, samme_som → -630201) gift med aliaset -630111 i familie -6301 (ordinal 1).
--        Tvillingen -6311 (-630201 + -630211, hvor -630211 er alias for -630216) → mulige objekter [-630216].
--        Posten D-1 har ét ægteskab (server-nummer 1); narrativ med non-ASCII og linjeskift.
--   D02: hovedperson -630102 (p39, samme_som → -630202) gift med aliaset -630112 i familie -6302 (ordinal 2).
--        Tvillinger -6312 (-630202 + -630212, alias for -630215) og -6313 (-630202 + -630213) → [-630215,-630213].
--        Posten D-2 har to ægteskaber (server-nummer 1 og 2); kun nr. 2 hører til kortet. Ingen narrativ (null).
--        -630102 har desuden en anden ny-udgave-familie -6303 (+ -630113, ordinal 3): den er ikke tvilling (t1 ∈ p39),
--        men er selv en D-kandidat (dobbelt=3).
--   D-9: post for -630103 (p39) hvis ægteskabspåstand ikke står i klausulen (post_offset NULL; uden_position=1).
--   O1:  person -630150 med narrativ (uden kilde); skjult person -630160 er partner i -6321 (+ -630161, ordinal 1) og
--        -6322 (+ -630162, ordinal 2).
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir relation-2a.sql

DO $fix$
DECLARE v_actor uuid:='a1500000-0000-0000-0000-000000000150'; v_src bigint:=-630100; s jsonb; p jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(v_src);
  INSERT INTO public.person(id,levende,privat)
    SELECT x,false,false FROM unnest(ARRAY[-630101,-630102,-630103,-630111,-630112,-630113,-630201,-630202,-630211,-630212,
                                           -630213,-630215,-630216,-630150,-630160,-630161,-630162]::bigint[]) x;
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key)
    VALUES (-630101,v_src,'I',1,'D-1'),(-630102,v_src,'I',2,'D-2'),(-630103,v_src,'I',9,'D-9');
  -- Den gamle udgaves sammenfoldning (alias → kanonisk), før familierne (unionsvagten i triggeren).
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    ('person',-630101,'person',-630201,'samme_som'),('person',-630102,'person',-630202,'samme_som'),
    ('person',-630211,'person',-630216,'samme_som'),('person',-630212,'person',-630215,'samme_som');
  INSERT INTO public.family(id,type) VALUES (-6301,'vielse'),(-6302,'vielse'),(-6303,'vielse'),(-6311,'vielse'),(-6312,'vielse'),
    (-6313,'vielse'),(-6321,'vielse'),(-6322,'vielse');
  INSERT INTO public.family_member(family_id,person_id,rolle,ordinal) VALUES
    (-6301,-630101,'partner',1),(-6301,-630111,'partner',1),
    (-6302,-630102,'partner',2),(-6302,-630112,'partner',2),
    (-6303,-630102,'partner',3),(-6303,-630113,'partner',3),
    (-6311,-630201,'partner',1),(-6311,-630211,'partner',1),
    (-6312,-630202,'partner',1),(-6312,-630212,'partner',1),
    (-6313,-630202,'partner',2),(-6313,-630213,'partner',2),
    (-6321,-630160,'partner',1),(-6321,-630161,'partner',1),
    (-6322,-630160,'partner',2),(-6322,-630162,'partner',2);
  -- Poster med ægteskabspåstande (proposed, uden parter).
  p:=pg_temp.f5b_post(v_src,s,'D-1','Hovedperson Ét. Gift med Åse Ørsted, datter af »Bo«.',
       ARRAY['Hovedperson Ét.','Gift med Åse Ørsted, datter af »Bo«.'],-630101,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(v_src,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Åse Ørsted, datter af »Bo«.');
  p:=pg_temp.f5b_post(v_src,s,'D-2','Hovedperson To. g. 1° m. Karen Æbelø. g. 2° m. Else "Lille" Bøg\Hansen.',
       ARRAY['Hovedperson To.','g. 1° m. Karen Æbelø.','g. 2° m. Else "Lille" Bøg\Hansen.'],-630102,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(v_src,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. 1° m. Karen Æbelø.');
  PERFORM pg_temp.f5b_claim(v_src,s,'relation.marriage',(p->'clauses'->>2)::uuid,'g. 2° m. Else "Lille" Bøg\Hansen.');
  p:=pg_temp.f5b_post(v_src,s,'D-9','Hovedperson Ni. gift m. Ingen.',ARRAY['Hovedperson Ni.','gift m. Ingen.'],-630103,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(v_src,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Nogen Andre.');
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst) VALUES
    ('person',-630101,v_src,'501',E'Opdigtet biografi om hovedperson Ét – født på Ærø.\nAnden linje med "citat" og \\.'),
    ('person',-630150,NULL,'502','Opdigtet levn (22 tegn).');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
END $fix$;
COMMIT;
