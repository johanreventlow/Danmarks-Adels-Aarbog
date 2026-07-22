const rpcEvents: string[] = [];

jest.mock('../../lib/supabase', () => ({
  supabase: {
    rpc: jest.fn(async (fn: string) => {
      rpcEvents.push(fn);
      return { data: null, error: null };
    }),
  },
}));

import { buildRpcCall, describeCall, oversaetFejl, erFortrydKonflikt, FELT_FAKTATYPE, submitChange } from '../redaktionWrite';

beforeEach(() => { rpcEvents.length = 0; });

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
  it.each([
    ['daab', 'dåb'], ['begravelse', 'begravelse'], ['floruit', 'floruit'], ['naturalisering', 'naturalisering'],
  ])('%s → red_upsert_fakta m. faktatype %s + p_date_raw', (felt, faktatype) => {
    const c = { art: 'fakta', subjektType: 'person', subjektId: '7', felt, vaerdi: '1680' } as const;
    expect(buildRpcCall(c)).toEqual({
      fn: 'red_upsert_fakta',
      args: { p_subjekt_type: 'person', p_subjekt_id: 7, p_faktatype: faktatype, p_vaerdi: '1680', p_date_raw: '1680' },
    });
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
      p_kunstner: null, p_datering: null, p_byte_size: 1234, p_bredde: 100, p_hoejde: 120, p_original_filnavn: 'x.jpg',
      p_rettigheder_status: 'ukendt', p_maa_publiceres: true, p_sha256: null, p_afbildet_person_id: 42 } });
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

  it('sender sha256 til red_upload_media og bruger null for gamle payloads', () => {
    const base = { art: 'uploadMedia', subjektType: 'person', subjektId: '42',
      payload: { afbildetPersonId: '42', slags: 'foto', titel: 'Portræt',
        storagePath: 'redaktor/ab/abc-large.jpg', mimeType: 'image/jpeg' } } as const;
    expect(buildRpcCall({ ...base, payload: { ...base.payload, sha256: 'abc123' } })?.args.p_sha256)
      .toBe('abc123');
    expect(buildRpcCall(base)?.args.p_sha256).toBeNull();
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

test('oversaetFejl: mediededup bruger web-kontraktens præcise tekster før generisk unique', () => {
  expect(oversaetFejl('medie med samme indhold findes allerede (sha256=abc, media_id=91)'))
    .toBe("Billedet findes allerede i biblioteket — brug 'Tilknyt eksisterende' i stedet.");
  expect(oversaetFejl('Mediet er allerede tilknyttet dette subjekt'))
    .toBe('Mediet er allerede tilknyttet dette subjekt.');
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

describe('buildRpcCall — filside fase 1', () => {
  it('opdaterMedia sender kun tilstedeværende felter', () => {
    expect(buildRpcCall({ art: 'opdaterMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { titel: '', datering: '1701' } } as never)).toEqual({
      fn: 'red_opdater_media', args: { p_media_id: 91, p_titel: '', p_datering: '1701' },
    });
  });
  it('genopretMedia og mediaRettigheder bygger de nye RPC-kald', () => {
    expect(buildRpcCall({ art: 'genopretMedia', subjektType: 'media', subjektId: '91', mediaId: '91' } as never))
      .toEqual({ fn: 'red_genopret_media', args: { p_media_id: 91 } });
    expect(buildRpcCall({ art: 'mediaRettigheder', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { status: 'tilladelse_givet', maaPubliceres: true, gengivelsestilladelse: 'Mail 19/7' } } as never))
      .toEqual({ fn: 'red_set_media_rettigheder', args: {
        p_media_id: 91, p_status: 'tilladelse_givet', p_maa_publiceres: true,
        p_gengivelsestilladelse: 'Mail 19/7',
      } });
  });
  it('uploadMedia fører kunstner/datering/status igennem', () => {
    const call = buildRpcCall({ art: 'uploadMedia', subjektType: 'person', subjektId: '42', payload: {
      afbildetPersonId: 42, slags: 'maleri', titel: 'Portræt', storagePath: 'x.jpg', mimeType: 'image/jpeg',
      kunstner: 'Jens Juel', datering: 'ca. 1780', rettighederStatus: 'public_domain',
    } } as never);
    expect(call?.args).toMatchObject({ p_kunstner: 'Jens Juel', p_datering: 'ca. 1780', p_rettigheder_status: 'public_domain' });
  });
  it('nye domænefejl oversættes', () => {
    expect(oversaetFejl('Kan kun genoprette et fjernet medie')).toContain('kun genoprettes');
    expect(oversaetFejl('Slags kan ikke ryddes')).toBe('Slags kan ikke ryddes.');
  });
});

describe('buildRpcCall — tilknytMedia fase 2', () => {
  it('person står på subjekt-siden af GDPR-hensyn', () => {
    expect(buildRpcCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType: 'person', maalId: '7' } } as never)).toEqual({
      fn: 'red_relation', args: {
        p_subjekt_type: 'person', p_subjekt_id: 7, p_objekt_type: 'media', p_objekt_id: 91,
        p_rolle: 'afbildet', p_periode_raw: null,
      },
    });
  });

  it.each(['estate', 'coat_of_arms', 'lineage'] as const)('media står på subjekt-siden for %s', (maalType) => {
    expect(buildRpcCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType, maalId: '8' } } as never)).toEqual({
      fn: 'red_relation', args: {
        p_subjekt_type: 'media', p_subjekt_id: 91, p_objekt_type: maalType, p_objekt_id: 8,
        p_rolle: 'afbildet', p_periode_raw: null,
      },
    });
  });

  it('afviser manglende/ugyldige ider og ukendt måltype fail-closed', () => {
    const baseChange = { art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType: 'person', maalId: '7' } };
    expect(buildRpcCall({ ...baseChange, mediaId: '' } as never)).toBeNull();
    expect(buildRpcCall({ ...baseChange, payload: { ...baseChange.payload, maalId: '' } } as never)).toBeNull();
    expect(buildRpcCall({ ...baseChange, payload: { ...baseChange.payload, maalId: '0' } } as never)).toBeNull();
    expect(buildRpcCall({ ...baseChange, payload: { ...baseChange.payload, maalId: '-1' } } as never)).toBeNull();
    expect(buildRpcCall({ ...baseChange, payload: { ...baseChange.payload, maalId: '9223372036854775808' } } as never)).toBeNull();
    expect(buildRpcCall({ ...baseChange, payload: { ...baseChange.payload, maalType: 'organisation' } } as never)).toBeNull();
  });

  it('bevarer gyldige BIGINT-id-er over JavaScripts sikre heltalsgrænse som strenge', () => {
    expect(buildRpcCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91',
      mediaId: '9223372036854775807', payload: { maalType: 'person', maalId: '9007199254740992' } } as never))
      .toMatchObject({ args: { p_subjekt_id: '9007199254740992', p_objekt_id: '9223372036854775807' } });
  });

  it('oversætter red_relation-person-guarden', () => {
    expect(oversaetFejl('afbildet skal gå person→media (person kan ikke stå på objekt-siden — GDPR-gating)'))
      .toBe('En person skal stå på subjekt-siden ved billedtilknytning.');
  });
});

describe('fase 4: erstatMediaFil', () => {
  const base = {
    art: 'erstatMediaFil', subjektType: 'media', subjektId: '7', mediaId: '7',
    payload: {
      localUri: 'file:///large.jpg', storagePath: 'redaktor/ab/s-large.jpg', mimeType: 'image/jpeg',
      byteSize: 3, bredde: 2, hoejde: 1, sha256: 'abc123', originalFilnavn: 'ny.jpg',
      varianter: [{
        tier: 'thumb', uri: 'file:///thumb.jpg', storagePath: 'redaktor/ab/s-thumb.jpg',
        mimeType: 'image/jpeg', byteSize: 1, bredde: 1, hoejde: 1,
      }],
    },
  } as const;

  it('bygger red_erstat_media_fil med metadata-varianter (ALDRIG URI-referencer i args)', () => {
    const call = buildRpcCall(base as never)!;
    expect(call.fn).toBe('red_erstat_media_fil');
    expect(call.args.p_media_id).toBe(7);
    expect(call.args.p_sha256).toBe('abc123');
    expect(call.args.p_varianter).toEqual([{
      tier: 'thumb', storage_path: 'redaktor/ab/s-thumb.jpg', mime: 'image/jpeg',
      byte_size: 1, bredde: 1, hoejde: 1,
    }]);
    expect(JSON.stringify(call.args)).not.toContain('file:///');
  });

  it('afviser manglende mediaId/sha256/sti', () => {
    expect(buildRpcCall({ ...base, mediaId: undefined } as never)).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, sha256: undefined } } as never)).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, storagePath: undefined } } as never)).toBeNull();
  });

  it('dry-run uploader INTET og udfører intet RPC', async () => {
    const performUpload = jest.fn();
    const res = await submitChange(base as never, { dryRun: true }, { performUpload });
    expect(res.dryRun).toBe(true);
    expect(performUpload).not.toHaveBeenCalled();
    expect(rpcEvents).toEqual([]);
  });
});

describe('fase 4: udrensMedia', () => {
  const change = {
    art: 'udrensMedia', subjektType: 'media', subjektId: '9', mediaId: '9',
  } as const;

  it('bygger red_udrens_media', () => {
    expect(buildRpcCall(change as never)).toEqual({ fn: 'red_udrens_media', args: { p_media_id: 9 } });
    expect(buildRpcCall({ ...change, mediaId: undefined } as never)).toBeNull();
  });

  it('dry-run uploader INTET og udfører intet RPC', async () => {
    const performUpload = jest.fn();
    const res = await submitChange(change as never, { dryRun: true }, { performUpload });
    expect(res.dryRun).toBe(true);
    expect(performUpload).not.toHaveBeenCalled();
    expect(rpcEvents).toEqual([]);
  });
});

describe('fase 4: saetPortraet', () => {
  const change = {
    art: 'saetPortraet', subjektType: 'person', subjektId: '5', personId: '5', mediaId: '7',
  } as const;

  it('bygger red_saet_portraet med og uden media (NULL = ryd)', () => {
    expect(buildRpcCall(change as never))
      .toEqual({ fn: 'red_saet_portraet', args: { p_person_id: 5, p_media_id: 7 } });
    expect(buildRpcCall({ ...change, mediaId: undefined } as never))
      .toEqual({ fn: 'red_saet_portraet', args: { p_person_id: 5, p_media_id: null } });
    expect(buildRpcCall({ ...change, subjektId: '', personId: undefined } as never)).toBeNull();
  });

  it('dry-run uploader INTET og udfører intet RPC', async () => {
    const performUpload = jest.fn();
    const res = await submitChange(change as never, { dryRun: true }, { performUpload });
    expect(res.dryRun).toBe(true);
    expect(performUpload).not.toHaveBeenCalled();
    expect(rpcEvents).toEqual([]);
  });
});

describe('fase 4: oversaetFejl', () => {
  it.each([
    ['Kan kun erstatte filen på et klart medie', /kun erstattes på et klart medie/i],
    ['Filen er identisk med den nuværende', /identisk/i],
    ['Kan kun udrense et fjernet medie', /papirkurven/i],
    ['Mediet har tilknytninger og kan ikke udrenses — fjern dem først', /tilknytninger/i],
    ['Mediet er nævnt i narrativer og kan ikke udrenses — redigér omtalerne ud først', /narrativer/i],
    ['Mediet er ikke tilknyttet personen — tilknyt først', /tilknyt/i],
    ['Mediet har rettighedsdokumentation (fakta) og kan ikke udrenses — fjern den først',
      'Mediet har rettighedsdokumentation — fjern den, før det udrenses.'],
    ['Mediet er subjekt for en story og kan ikke udrenses — flyt eller slet storyen først',
      'Mediet bruges som subjekt for en story — flyt eller slet storyen, før det udrenses.'],
    ['Mediet har et tilknyttet narrativ og kan ikke udrenses — slet narrativet først',
      'Mediet har et tilknyttet narrativ — slet narrativet, før det udrenses.'],
    ['Mediet har noter og kan ikke udrenses — fjern dem først',
      'Mediet har noter — fjern dem, før det udrenses.'],
    ['Mediet har forslag i kø og kan ikke udrenses — afvis eller godkend dem først',
      'Mediet har forslag i kø — afvis eller godkend dem, før det udrenses.'],
    ['Mediet kunne ikke udrenses — tilstanden ændrede sig undervejs, prøv igen',
      'Mediet kunne ikke udrenses, fordi tilstanden ændrede sig undervejs — prøv igen.'],
    ['Media 42 findes ikke', /allerede slettet af en anden redaktør/i],
    ['Storage-sti er påkrævet', /storage-sti/i],
    ['sha256 er påkrævet', /sha256/i],
  ])('oversætter %s', (raa, forvent) => {
    expect(oversaetFejl(raa)).toMatch(forvent);
  });
});

describe('buildRpcCall — story/feed_pin (fase 3)', () => {
  it('opretStory → red_opret_story med payload-felter', () => {
    expect(buildRpcCall({ art: 'opretStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: 'En minihistorie.', titel: 'Slaget', haendelseId: 91, dateRaw: '1671' } }))
      .toEqual({ fn: 'red_opret_story', args: {
        p_subjekt_type: 'person', p_subjekt_id: 7, p_tekst: 'En minihistorie.',
        p_titel: 'Slaget', p_haendelse_id: 91, p_fact_id: null, p_relation_id: null,
        p_historical_event_id: null, p_date_min: null, p_date_max: null,
        p_date_qualifier: null, p_date_raw: '1671', p_privat: false,
      } });
    expect(buildRpcCall({ art: 'opretStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: '   ' } })).toBeNull();
  });

  it('redigerStory → red_rediger_story; kræver storyId + tekst', () => {
    expect(buildRpcCall({ art: 'redigerStory', subjektType: 'person', subjektId: '7',
      storyId: 3, payload: { tekst: 'Omskrevet.', privat: true } }))
      .toMatchObject({ fn: 'red_rediger_story',
        args: { p_story_id: 3, p_tekst: 'Omskrevet.', p_privat: true } });
    expect(buildRpcCall({ art: 'redigerStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: 'x' } })).toBeNull();
  });

  it('setStoryStatus validerer mod de fire koder', () => {
    expect(buildRpcCall({ art: 'setStoryStatus', subjektType: 'person', subjektId: '7',
      storyId: 3, storyStatus: 'publiceret' }))
      .toEqual({ fn: 'red_set_story_status', args: { p_story_id: 3, p_status: 'publiceret' } });
    expect(buildRpcCall({ art: 'setStoryStatus', subjektType: 'person', subjektId: '7',
      storyId: 3, storyStatus: 'udgivet' as never })).toBeNull();
  });

  it('sletStory / setStoryKilder / setFeedPin / fjernFeedPin', () => {
    expect(buildRpcCall({ art: 'sletStory', subjektType: 'person', subjektId: '7', storyId: 3 }))
      .toEqual({ fn: 'red_slet_story', args: { p_story_id: 3 } });
    expect(buildRpcCall({ art: 'setStoryKilder', subjektType: 'person', subjektId: '7',
      storyId: 3, kilder: [{ sourceId: 2, side: '112' }, { sourceId: 5 }] }))
      .toEqual({ fn: 'red_set_story_kilder', args: { p_story_id: 3,
        p_kilder: [{ source_id: 2, side: '112' }, { source_id: 5, side: null }] } });
    expect(buildRpcCall({ art: 'setStoryKilder', subjektType: 'person', subjektId: '7',
      storyId: 3 })).toBeNull();
    expect(buildRpcCall({ art: 'setFeedPin', subjektType: 'person', subjektId: '7',
      kortNoegle: 'portrait:12', handling: 'pin' }))
      .toEqual({ fn: 'red_set_feed_pin', args: { p_kort_noegle: 'portrait:12', p_handling: 'pin' } });
    expect(buildRpcCall({ art: 'setFeedPin', subjektType: 'person', subjektId: '7',
      kortNoegle: '  ', handling: 'pin' })).toBeNull();
    expect(buildRpcCall({ art: 'fjernFeedPin', subjektType: 'person', subjektId: '7',
      kortNoegle: 'portrait:12' }))
      .toEqual({ fn: 'red_fjern_feed_pin', args: { p_kort_noegle: 'portrait:12' } });
  });
});
