import { buildRpcCall, describeCall, oversaetFejl, erFortrydKonflikt, FELT_FAKTATYPE } from '../redaktionWrite';

test('buildRpcCall — haendelseStatus', () => {
  expect(buildRpcCall({ art: 'haendelseStatus', subjektType: 'person', subjektId: '7',
    haendelseId: 91, status: 'interessant' })).toEqual({
      fn: 'red_set_haendelse_status', args: { p_haendelse_id: 91, p_status: 'interessant' },
    });
  expect(buildRpcCall({ art: 'haendelseStatus', subjektType: 'person', subjektId: '7', status: 'skjult' })).toBeNull();
});

describe('buildRpcCall — samme_som (identitets-links)', () => {
  it('sammeSom → red_samme_som(p_alias_id,p_objekt_id)', () => {
    const call = buildRpcCall({ art: 'sammeSom', subjektType: 'person', subjektId: '255',
      payload: { aliasId: '255', objektId: '392' } } as never);
    expect(call).toEqual({ fn: 'red_samme_som', args: { p_alias_id: 255, p_objekt_id: 392 } });
  });
  it('fjernSammeSom → red_fjern_samme_som(p_relation_id)', () => {
    const call = buildRpcCall({ art: 'fjernSammeSom', subjektType: 'person', subjektId: '392',
      relationId: '972' } as never);
    expect(call).toEqual({ fn: 'red_fjern_samme_som', args: { p_relation_id: 972 } });
  });
  it('sammeSom uden payload → null', () => {
    expect(buildRpcCall({ art: 'sammeSom', subjektType: 'person', subjektId: '255' } as never)).toBeNull();
  });
});

describe('buildRpcCall — narrativ (source-nøglet)', () => {
  it('sender p_source_id fra payload + p_side', () => {
    const call = buildRpcCall({ art: 'narrativ', subjektType: 'person', subjektId: '5',
      vaerdi: 'bio', payload: { privat: false, sourceId: 2, side: '12' } } as never);
    expect(call).toMatchObject({ fn: 'red_upsert_narrativ', args: { p_source_id: 2, p_side: '12', p_privat: false } });
  });
  it('defaulter p_source_id til 1 (primær DAA-udgave) når payload mangler kilde', () => {
    const call = buildRpcCall({ art: 'narrativ', subjektType: 'person', subjektId: '5',
      vaerdi: 'bio', payload: { privat: true } } as never);
    expect(call?.args).toMatchObject({ p_source_id: 1, p_side: null, p_privat: true });
  });
});

describe('buildRpcCall', () => {
  it('mapper foedt → red_upsert_fakta m. faktatype fødsel', () => {
    const c = { art: 'fakta', subjektType: 'person', subjektId: '7', felt: 'foedt',
                vaerdi: '1671', kildeFritekst: 'DAA' } as const;
    expect(buildRpcCall(c)).toEqual({
      fn: 'red_upsert_fakta',
      args: { p_subjekt_type: 'person', p_subjekt_id: 7, p_faktatype: 'fødsel',
              p_vaerdi: '1671', p_date_raw: '1671', p_kilde_fritekst: 'DAA' },
    });
  });
  it('koen → red_set_koen (ikke et fact)', () => {
    const c = { art: 'fakta', subjektType: 'person', subjektId: '7', felt: 'koen', vaerdi: 'mand' } as const;
    expect(buildRpcCall(c)).toEqual({ fn: 'red_set_koen', args: { p_person_id: 7, p_koen: 'mand' } });
  });
  it('navn → faktatype navn, intet date_raw', () => {
    const c = { art: 'fakta', subjektType: 'person', subjektId: '3', felt: 'navn', vaerdi: 'Conrad' } as const;
    expect(buildRpcCall(c)?.args.p_faktatype).toBe('navn');
    expect(buildRpcCall(c)?.args.p_date_raw).toBeUndefined();
  });
  it('FELT_FAKTATYPE har ikke koen (special-case)', () => {
    expect(FELT_FAKTATYPE.koen).toBeUndefined();
  });
});

describe('describeCall', () => {
  it('formatterer fn + pæn JSON', () => {
    const s = describeCall({ fn: 'red_set_koen', args: { p_person_id: 7, p_koen: 'mand' } });
    expect(s).toContain('rpc red_set_koen');
    expect(s).toContain('"p_koen": "mand"');
  });
});

test('redigerOplysning → red_edit_oplysning', () => {
  expect(buildRpcCall({ art: 'redigerOplysning', subjektType: 'person', subjektId: '1',
    assertionId: '100', vaerdi: 'Konrad', kildeFritekst: 'DAA 2018' }))
    .toEqual({ fn: 'red_edit_oplysning',
      args: { p_assertion_id: 100, p_vaerdi: 'Konrad', p_kilde_fritekst: 'DAA 2018' } });
});

test('setKonklusion → red_set_konklusion', () => {
  expect(buildRpcCall({ art: 'setKonklusion', subjektType: 'person', subjektId: '1', assertionId: '100' }))
    .toEqual({ fn: 'red_set_konklusion', args: { p_assertion_id: 100 } });
});

test('setPrivat → red_set_privat', () => {
  expect(buildRpcCall({ art: 'setPrivat', subjektType: 'person', subjektId: '1', payload: { privat: true } }))
    .toEqual({ fn: 'red_set_privat', args: { p_person_id: 1, p_privat: true } });
});

test('sletPerson → red_slet_person', () => {
  expect(buildRpcCall({ art: 'sletPerson', subjektType: 'person', subjektId: '1' }))
    .toEqual({ fn: 'red_slet_person', args: { p_person_id: 1 } });
});

test('oversaetFejl: rolle-gating → dansk', () => {
  expect(oversaetFejl('Kun redaktion')).toBe('Kræver redaktør-rettigheder.');
});

test('sletOplysning → red_slet_oplysning', () => {
  expect(buildRpcCall({ art: 'sletOplysning', subjektType: 'person', subjektId: '1', assertionId: '100' }))
    .toEqual({ fn: 'red_slet_oplysning', args: { p_assertion_id: 100 } });
});

test('redigerOplysning med dato-felt → inkluderer p_date_raw', () => {
  expect(buildRpcCall({ art: 'redigerOplysning', subjektType: 'person', subjektId: '1',
    assertionId: '100', felt: 'foedt', vaerdi: 'ca. 1644' }))
    .toEqual({ fn: 'red_edit_oplysning', args: { p_assertion_id: 100, p_vaerdi: 'ca. 1644', p_date_raw: 'ca. 1644' } });
});

test('sletOplysning uden assertionId → null', () => {
  expect(buildRpcCall({ art: 'sletOplysning', subjektType: 'person', subjektId: '1' }))
    .toBeNull();
});

// FJERN "forældre ukendt"-markering (review 26 HIGH 2): tilbagetræk fakta-slottets konklusion via
// red_tilbagetraek_fakta — IKKE red_slet_oplysning (som genopliver markeringen efter Markér→Opdatér→Fjern).
test('tilbagetraekFakta → red_tilbagetraek_fakta m. fact-id', () => {
  expect(buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210', factId: '55' }))
    .toEqual({ fn: 'red_tilbagetraek_fakta', args: { p_fact_id: 55 } });
});

test('tilbagetraekFakta uden factId → null', () => {
  expect(buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210' }))
    .toBeNull();
});

test('tilbagetraekFakta med ugyldigt (tomt/ikke-numerisk) factId → null (NaN-guard, review 27)', () => {
  expect(buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210', factId: '' })).toBeNull();
  expect(buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210', factId: 'x' })).toBeNull();
});

// Operation A: tilføj oplysning til eksisterende fact (fact-målrettet).
test('tilfoejOplysning → red_tilfoej_oplysning m. fact_id', () => {
  expect(buildRpcCall({ art: 'tilfoejOplysning', subjektType: 'person', subjektId: '1',
    factId: '607', felt: 'titel', vaerdi: 'kammerherre', kildeFritekst: 'DAA' }))
    .toEqual({ fn: 'red_tilfoej_oplysning',
      args: { p_fact_id: 607, p_vaerdi: 'kammerherre', p_kilde_fritekst: 'DAA' } });
});

test('tilfoejOplysning uden factId → null', () => {
  expect(buildRpcCall({ art: 'tilfoejOplysning', subjektType: 'person', subjektId: '1', vaerdi: 'x' }))
    .toBeNull();
});

test('tilfoejOplysning dato-felt → inkluderer p_date_raw', () => {
  expect(buildRpcCall({ art: 'tilfoejOplysning', subjektType: 'person', subjektId: '1',
    factId: '11', felt: 'foedt', vaerdi: 'ca. 1644' }))
    .toEqual({ fn: 'red_tilfoej_oplysning', args: { p_fact_id: 11, p_vaerdi: 'ca. 1644', p_date_raw: 'ca. 1644' } });
});

// Operation B: opret nyt distinkt fact (fx ny titel).
test('opretFakta → red_opret_fakta m. faktatype', () => {
  expect(buildRpcCall({ art: 'opretFakta', subjektType: 'person', subjektId: '1',
    felt: 'titel', vaerdi: 'greve', kildeFritekst: 'DAA' }))
    .toEqual({ fn: 'red_opret_fakta',
      args: { p_subjekt_type: 'person', p_subjekt_id: 1, p_faktatype: 'titel', p_vaerdi: 'greve', p_kilde_fritekst: 'DAA' } });
});

test('sletRelation → red_slet_relation', () => {
  expect(buildRpcCall({ art: 'sletRelation', subjektType: 'person', subjektId: '1', relationId: '100' }))
    .toEqual({ fn: 'red_slet_relation', args: { p_relation_id: 100 } });
});

test('tilfoejRelation → red_tilfoej_relation fra payload', () => {
  expect(buildRpcCall({ art: 'tilfoejRelation', subjektType: 'person', subjektId: '7',
    payload: { objektType: 'estate', objektId: '5', rolle: 'ejer', periodeRaw: '1700' } }))
    .toEqual({ fn: 'red_tilfoej_relation',
      args: { p_subjekt_id: 7, p_objekt_type: 'estate', p_objekt_id: 5, p_rolle: 'ejer', p_periode_raw: '1700' } });
});

test('sletRelation uden relationId → null', () => {
  expect(buildRpcCall({ art: 'sletRelation', subjektType: 'person', subjektId: '1' })).toBeNull();
});

// --- Task 5: familie-cases ---
test('opretUnion → red_opret_union', () => {
  expect(buildRpcCall({ art: 'opretUnion', subjektType: 'person', subjektId: '7',
    payload: { partnerA: '7', partnerB: '1', type: 'vielse', ordinal: 1 } }))
    .toEqual({ fn: 'red_opret_union', args: { p_partner_a: 7, p_partner_b: 1, p_type: 'vielse', p_ordinal: 1 } });
});
test('tilfoejBarn → red_tilfoej_barn', () => {
  expect(buildRpcCall({ art: 'tilfoejBarn', subjektType: 'person', subjektId: '7',
    payload: { familyId: '10', barnId: '3', rolle: 'barn', konfidens: 'sikker' } }))
    .toEqual({ fn: 'red_tilfoej_barn', args: { p_family_id: 10, p_barn_id: 3, p_rolle: 'barn', p_konfidens: 'sikker' } });
});
test('setFamilieKonfidens → red_set_familie_konfidens (NULL ryd)', () => {
  expect(buildRpcCall({ art: 'setFamilieKonfidens', subjektType: 'person', subjektId: '7',
    familyId: '10', personId: '1', rolle: 'partner', konfidens: null }))
    .toEqual({ fn: 'red_set_familie_konfidens', args: { p_family_id: 10, p_person_id: 1, p_rolle: 'partner', p_konfidens: null } });
});
test('sletFamilieLink → red_slet_familie_link', () => {
  expect(buildRpcCall({ art: 'sletFamilieLink', subjektType: 'person', subjektId: '7',
    familyId: '10', personId: '3', rolle: 'barn' }))
    .toEqual({ fn: 'red_slet_familie_link', args: { p_family_id: 10, p_person_id: 3, p_rolle: 'barn' } });
});
test('opretUnion uden påkrævet payload → null', () => {
  expect(buildRpcCall({ art: 'opretUnion', subjektType: 'person', subjektId: '7', payload: { partnerA: '7' } as never })).toBeNull();
});

// --- brugerfund 2026-07-02: søskende-rækkefølge + flyt barn mellem forhold ---
test('setFamilieOrdinal → red_set_familie_ordinal', () => {
  expect(buildRpcCall({ art: 'setFamilieOrdinal', subjektType: 'person', subjektId: '7',
    familyId: '10', personId: '3', rolle: 'barn', ordinal: 5 }))
    .toEqual({ fn: 'red_set_familie_ordinal', args: { p_family_id: 10, p_person_id: 3, p_rolle: 'barn', p_ordinal: 5 } });
});
test('setFamilieOrdinal uden ordinal → null', () => {
  expect(buildRpcCall({ art: 'setFamilieOrdinal', subjektType: 'person', subjektId: '7',
    familyId: '10', personId: '3', rolle: 'barn' })).toBeNull();
});
test('flytBarn → red_flyt_barn', () => {
  expect(buildRpcCall({ art: 'flytBarn', subjektType: 'person', subjektId: '7',
    familyId: '10', tilFamilyId: '20', personId: '3', rolle: 'barn' }))
    .toEqual({ fn: 'red_flyt_barn', args: { p_fra_family_id: 10, p_til_family_id: 20, p_barn_id: 3, p_rolle: 'barn' } });
});
test('flytBarn uden tilFamilyId → null', () => {
  expect(buildRpcCall({ art: 'flytBarn', subjektType: 'person', subjektId: '7',
    familyId: '10', personId: '3', rolle: 'barn' })).toBeNull();
});

describe('buildRpcCall opret-arter', () => {
  it('opretPerson → red_opret_person, kun udfyldte args, ingen p_privat', () => {
    const c = { art: 'opretPerson', subjektType: 'person', subjektId: '',
      payload: { navn: 'Conrad', koen: 'mand', levende: false,
                 foedtRaw: '1700', doedRaw: '', titelRaw: 'greve' } } as const;
    expect(buildRpcCall(c)).toEqual({ fn: 'red_opret_person', args: {
      p_navn: 'Conrad', p_koen: 'mand', p_levende: false,
      p_foedt_raw: '1700', p_titel_raw: 'greve' } });   // doedRaw='' udeladt; p_privat fjernet
  });
  it('opretPerson uden navn → null', () => {
    expect(buildRpcCall({ art: 'opretPerson', subjektType: 'person', subjektId: '',
      payload: { navn: '' } } as const)).toBeNull();
  });
  it('opretEstate → red_opret_estate', () => {
    expect(buildRpcCall({ art: 'opretEstate', subjektType: 'estate', subjektId: '',
      payload: { navn: 'Brahetrolleborg', slags: 'gods' } } as const))
      .toEqual({ fn: 'red_opret_estate', args: { p_navn: 'Brahetrolleborg', p_slags: 'gods' } });
  });
  it('opretKilde → red_opret_kilde', () => {
    expect(buildRpcCall({ art: 'opretKilde', subjektType: 'source', subjektId: '',
      payload: { titel: 'DAA 2018-20', slags: 'DAA-udgave', ekstern: false } } as const))
      .toEqual({ fn: 'red_opret_kilde', args: { p_titel: 'DAA 2018-20', p_slags: 'DAA-udgave', p_ekstern: false } });
  });
  it('opretOrganisation → red_opret_organisation', () => {
    expect(buildRpcCall({ art: 'opretOrganisation', subjektType: 'organisation', subjektId: '',
      payload: { navn: 'Livgarden', slags: 'regiment' } } as const))
      .toEqual({ fn: 'red_opret_organisation', args: { p_navn: 'Livgarden', p_slags: 'regiment' } });
  });
});

describe('buildRpcCall — uploadMedia (mediehåndtering Slice 0g)', () => {
  it('portræt (afbildetPersonId) → red_upload_media med p_afbildet_person_id', () => {
    const c = { art: 'uploadMedia', subjektType: 'person', subjektId: '42',
      payload: { afbildetPersonId: '42', slags: 'foto', titel: 'Portræt', maaPubliceres: true,
        localUri: 'file:///x.jpg', storagePath: 'redaktor/x.jpg', mimeType: 'image/jpeg',
        byteSize: 1234, bredde: 100, hoejde: 120, originalFilnavn: 'x.jpg' } } as const;
    expect(buildRpcCall(c)).toEqual({ fn: 'red_upload_media', args: {
      p_slags: 'foto', p_titel: 'Portræt', p_storage_path: 'redaktor/x.jpg', p_mime: 'image/jpeg',
      p_byte_size: 1234, p_bredde: 100, p_hoejde: 120, p_original_filnavn: 'x.jpg',
      p_rettigheder_status: 'ukendt', p_maa_publiceres: true, p_afbildet_person_id: 42 } });
  });
  it('objekt-foto (objektType/objektId) → red_upload_media med p_objekt_type/p_objekt_id, ingen p_afbildet_person_id', () => {
    const c = { art: 'uploadMedia', subjektType: 'estate', subjektId: '7',
      payload: { objektType: 'estate', objektId: '7', slags: 'foto', titel: 'Godset', maaPubliceres: false,
        localUri: 'file:///y.jpg', storagePath: 'redaktor/y.jpg', mimeType: 'image/jpeg' } } as const;
    const call = buildRpcCall(c);
    expect(call?.fn).toBe('red_upload_media');
    expect(call?.args.p_objekt_type).toBe('estate');
    expect(call?.args.p_objekt_id).toBe(7);
    expect(call?.args.p_afbildet_person_id).toBeUndefined();
  });
  it('mangler titel → null (p_titel har intet DEFAULT i RPC-signaturen)', () => {
    expect(buildRpcCall({ art: 'uploadMedia', subjektType: 'person', subjektId: '42',
      payload: { afbildetPersonId: '42', slags: 'foto', titel: '',
        storagePath: 'redaktor/x.jpg', mimeType: 'image/jpeg' } } as const)).toBeNull();
  });
});

describe('buildRpcCall — fjernMedia (mediehåndtering Slice 0h)', () => {
  it('fjernMedia → red_fjern_media med p_media_id', () => {
    const c = { art: 'fjernMedia', subjektType: 'person', subjektId: '42', mediaId: '91' } as const;
    expect(buildRpcCall(c)).toEqual({ fn: 'red_fjern_media', args: { p_media_id: 91 } });
  });
  it('mangler mediaId → null', () => {
    expect(buildRpcCall({ art: 'fjernMedia', subjektType: 'person', subjektId: '42' } as const)).toBeNull();
  });
});

test('fortryd → red_fortryd_change_set m. force', () => {
  const c = { art: 'fortryd', subjektType: 'person', subjektId: '7',
              payload: { changeSetId: 12, force: true } } as const;
  expect(buildRpcCall(c)).toEqual({
    fn: 'red_fortryd_change_set', args: { p_change_set_id: 12, p_force: true },
  });
});

test('fortryd uden force-flag → p_force=false', () => {
  const c = { art: 'fortryd', subjektType: 'person', subjektId: '7',
              payload: { changeSetId: 12 } } as const;
  expect(buildRpcCall(c)).toEqual({
    fn: 'red_fortryd_change_set', args: { p_change_set_id: 12, p_force: false },
  });
});

test('fortryd uden changeSetId → null', () => {
  const c = { art: 'fortryd', subjektType: 'person', subjektId: '7', payload: {} } as const;
  expect(buildRpcCall(c)).toBeNull();
});

test('oversaetFejl: allerede fortrudt → dansk (review10 H2, defensiv fallback)', () => {
  expect(oversaetFejl('FEJL: change_set 12 er allerede fortrudt')).toBe('Denne ændring er allerede fortrudt.');
});

test('erFortrydKonflikt: matcher en statisk kopi af DB-RAISE-teksten (red_fortryd_change_set B9)', () => {
  // Fastlåser regex-adfærden mod et hardkodet eksempel — IKKE en levende kobling til
  // schema.sql/db-migrations.sql. Drifter den faktiske RAISE-tekst, fanger denne test det ikke;
  // hold matchen manuelt i sync (altitude-fund cycle 10).
  expect(erFortrydKonflikt("FEJL: nyere ændring rører fact/{\"id\":1} — afvist (brug force)")).toBe(true);
  expect(erFortrydKonflikt('FEJL: change_set 12 er allerede fortrudt')).toBe(false);
});

describe('buildRpcCall — forældrefamilie (Problem 2)', () => {
  it('foraeldrePaastand → red_tilfoej_foraeldre_paastand med alle valgfrie args', () => {
    expect(buildRpcCall({ art: 'foraeldrePaastand', subjektType: 'person', subjektId: '50',
      payload: { barnId: 50, familyId: 12, sourceId: 3, side: 's.490', citat: 'udg. citat' } })).toEqual({
      fn: 'red_tilfoej_foraeldre_paastand', args: { p_barn_id: 50, p_family_id: 12, p_source_id: 3, p_side: 's.490', p_citat: 'udg. citat' } });
  });
  it('foraeldrePaastand minimal → kun p_barn_id/p_family_id', () => {
    expect(buildRpcCall({ art: 'foraeldrePaastand', subjektType: 'person', subjektId: '50',
      payload: { barnId: 50, familyId: 12 } })).toEqual({ fn: 'red_tilfoej_foraeldre_paastand', args: { p_barn_id: 50, p_family_id: 12 } });
  });
  it('vaelgForaeldre → red_vaelg_foraeldre(p_assertion_id, p_konfidens)', () => {
    expect(buildRpcCall({ art: 'vaelgForaeldre', subjektType: 'person', subjektId: '50',
      payload: { assertionId: 88, konfidens: 'sikker' } })).toEqual({ fn: 'red_vaelg_foraeldre', args: { p_assertion_id: 88, p_konfidens: 'sikker' } });
  });
  it('vaelgForaeldre uden assertion → null', () => {
    expect(buildRpcCall({ art: 'vaelgForaeldre', subjektType: 'person', subjektId: '50', payload: {} } as never)).toBeNull();
  });
});
