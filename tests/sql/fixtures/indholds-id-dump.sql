-- Indholds-id (#151, spec 2026-10-21-trin5ab-indholds-id-design.md §5.1): det, der simulerer restoren (D1).
-- Indlæses som ejer efter relation-5b.sql og relation-2a.sql i harnessets transaktion (ingen BEGIN/COMMIT her).
-- Kun base A kører filen; base B får rækkerne med COPY, så alle tilfældige id'er her er ens i begge baser.
-- Intet af det, kæden skriver (ægtefællepersonas, kandidater, kontrol, afgørelser), ligger her. Opdigtede navne.
DO $dump$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-000000025001'; s jsonb; p jsonb; c jsonb; v_fam bigint; i int; t int;
  v_f bigint; v_a bigint;
  -- Collation-følsomme titler (Review Focus 1): C, en_US og ICU-da sorterer dem forskelligt.
  v_titles text[]:=ARRAY['aaben','Zobel','Ærø','baron','Baron'];
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-25001);
  INSERT INTO person(id,levende,privat,status)
    SELECT g,false,false,'5b' FROM generate_series(-25020,-25001) g;
  -- Leveår: hovedpersoner, ægtefæller, barnet og kandidaterne (ingen er tidsumulige for hinanden).
  PERFORM pg_temp.f5b_life(-25001,1795,1850); PERFORM pg_temp.f5b_life(-25002,1800,1860);
  PERFORM pg_temp.f5b_life(-25003,1810,1880); PERFORM pg_temp.f5b_life(-25004,1800,1870);
  PERFORM pg_temp.f5b_life(-25005,1805,1875); PERFORM pg_temp.f5b_life(-25006,1830,1890);
  FOR i IN 10..20 LOOP PERFORM pg_temp.f5b_life(-25000-i,1800,1870); END LOOP;
  -- Tre titler pr. kandidat i blandet rækkefølge (identity_control_rows.sql's titelliste).
  FOR i IN SELECT unnest(ARRAY[-25002,-25003,-25005,-25010,-25011,-25012,-25013]) LOOP
    FOR t IN 0..2 LOOP
      INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',i,'titel') RETURNING id INTO v_f;
      INSERT INTO assertion(target_type,target_id,vaerdi_tekst) VALUES ('fact',v_f,v_titles[1+((abs(i)+t*2) % 5)]) RETURNING id INTO v_a;
      INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_f,v_a,'afklaret');
    END LOOP;
  END LOOP;

  -- Post 'aa-1': to ægteskaber; bogens 1° står mod familiens 2 (ordinal_afvigelse i 2a).
  p:=pg_temp.f5b_post(-25001,s,'aa-1','Anna Alfa. Gift 1° m. Bo Beta f. 1800. Gift 2° m. Cia Ceta f. 1810.',
     ARRAY['Anna Alfa.','Gift 1° m. Bo Beta f. 1800.','Gift 2° m. Cia Ceta f. 1810.'],-25001,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(-25001,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1° m. Bo Beta f. 1800.');
  PERFORM pg_temp.f5b_claim(-25001,s,'relation.marriage',(p->'clauses'->>2)::uuid,'Gift 2° m. Cia Ceta f. 1810.');
  PERFORM pg_temp.f5b_family(-25001,-25002,2);
  PERFORM pg_temp.f5b_family(-25001,-25003,1);

  -- Post 'Ab-2': ét ægteskab.
  p:=pg_temp.f5b_post(-25001,s,'Ab-2','Ab Abe. Gift m. Dy Delta f. 1805.',ARRAY['Ab Abe.','Gift m. Dy Delta f. 1805.'],-25004,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(-25001,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift m. Dy Delta f. 1805.');
  v_fam:=pg_temp.f5b_family(-25004,-25005,1);

  -- Post 'Zz-3': barn i Ab-2's familie med en uafgjort forælderpåstand → ét forældrekort i kontrolkørslen
  -- (præcis én strukturel kandidat: -25004 er hovedperson-persona i 'Ab-2', -25005 er ikke).
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,-25006,'barn');
  p:=pg_temp.f5b_post(-25001,s,'Zz-3','Zz Zeta. Søn af Ea Eta.',ARRAY['Zz Zeta.','Søn af Ea Eta.'],-25006,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-25001,s,'relation.parent',(p->'clauses'->>1)::uuid,'Søn af Ea Eta.');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(p->>'principal')::uuid,9,'relation_persona',gen_random_uuid());

  -- Post 'Bc-4' (Review: §5.1 »rækkefilerne for alle ark i §4«): ægteskab 1 skrives af writeren og afgøres
  -- new_person_needed (v3's genafgørelsesrække); ægteskab 2 skrives ikke (v2/v3-rækker); en børnepåstand (børnearket).
  p:=pg_temp.f5b_post(-25001,s,'Bc-4','Bent Bo. Gift 1° m. Fie Fot f. 1815. Gift 2° m. Gry Gal f. 1825. Børn: se nedenfor.',
     ARRAY['Bent Bo.','Gift 1° m. Fie Fot f. 1815.','Gift 2° m. Gry Gal f. 1825.','Børn: se nedenfor.'],-25007,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(-25001,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1° m. Fie Fot f. 1815.');
  PERFORM pg_temp.f5b_claim(-25001,s,'relation.marriage',(p->'clauses'->>2)::uuid,'Gift 2° m. Gry Gal f. 1825.');
  c:=pg_temp.f5b_claim(-25001,s,'relation.child',(p->'clauses'->>3)::uuid,'Børn: se nedenfor.');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(p->>'principal')::uuid,64,'relation_persona',gen_random_uuid());

  -- Kilde -25002: #244-verden (ægtefælleparternes numre byttet) til nummerarket; afgøres og bindes af kæden.
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'5b' FROM generate_series(-25033,-25031) g;
  PERFORM pg_temp.f244_post(-25002,pg_temp.f5b_source(-25002),'A-1',-25031,-25032,-25033,v_actor);
END $dump$;
