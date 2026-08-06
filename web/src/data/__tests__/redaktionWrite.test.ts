import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  buildResumeMediaUploadPlan, buildRpcCall, buildSuggestCall, FELT_FAKTATYPE,
  oversaetFejl, planCall, submitChange, type Change,
} from '../redaktionWrite';

vi.mock('../../supabase', () => ({
  supabase: { rpc: vi.fn(), auth: { onAuthStateChange: vi.fn() } },
}));
vi.mock('../mediaUpload', () => ({ performUpload: vi.fn() }));

beforeEach(() => {
  vi.clearAllMocks();
});

test('fakta-art med felt overhoved mapper til red_upsert_fakta med faktatype overhoved', () => {
  const c = { art: 'fakta', subjektType: 'person', subjektId: '7',
    felt: 'overhoved', vaerdi: 'II linje, 1. gren' } as const;
  expect(buildRpcCall(c)).toEqual({
    fn: 'red_upsert_fakta',
    args: { p_subjekt_type: 'person', p_subjekt_id: 7, p_faktatype: 'overhoved',
      p_vaerdi: 'II linje, 1. gren' },
  });
});

describe('buildRpcCall — udvidede rygrad-felter (dåb/begravelse/floruit/naturalisering)', () => {
  it.each([
    ['daab', 'dåb'], ['begravelse', 'begravelse'], ['floruit', 'floruit'], ['naturalisering', 'naturalisering'],
  ])('%s → red_upsert_fakta m. faktatype %s + p_date_raw', (felt, faktatype) => {
    const c = { art: 'fakta', subjektType: 'person', subjektId: '7', felt, vaerdi: '1680' } as const;
    expect(buildRpcCall(c)).toEqual({
      fn: 'red_upsert_fakta',
      args: { p_subjekt_type: 'person', p_subjekt_id: 7, p_faktatype: faktatype, p_vaerdi: '1680', p_date_raw: '1680' },
    });
  });
  it('FELT_FAKTATYPE dækker de fire nye felter', () => {
    expect(FELT_FAKTATYPE).toMatchObject({
      daab: 'dåb', begravelse: 'begravelse', floruit: 'floruit', naturalisering: 'naturalisering',
    });
  });
});

describe('buildRpcCall — haendelseStatus', () => {
  it('bygger status-RPC og afviser manglende id', () => {
    expect(buildRpcCall({ art: 'haendelseStatus', subjektType: 'person', subjektId: '7',
      haendelseId: 91, status: 'skjult' })).toEqual({
        fn: 'red_set_haendelse_status', args: { p_haendelse_id: 91, p_status: 'skjult' },
      });
    expect(buildRpcCall({ art: 'haendelseStatus', subjektType: 'person', subjektId: '7', status: 'kandidat' })).toBeNull();
    expect(planCall({ art: 'haendelseStatus', subjektType: 'person', subjektId: '7', haendelseId: 91, status: 'skjult' }, 'medlem'))
      .toMatchObject({ fn: 'red_suggest', args: { p_payload: { haendelseId: 91, status: 'skjult' } } });
  });
});

// Web-spejl af mobile-testen for de samme_som-arter (identitets-links, spec 2026-07-02).
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

// K2 selektiv publicering (§7.20): publicér udvalgte person-id'er uden at rydde staged for hele kilden.
describe('buildRpcCall — publicerPersoner (K2 selektiv publicering)', () => {
  it('publicerPersoner → red_publicer_personer(p_person_ids)', () => {
    const call = buildRpcCall({ art: 'publicerPersoner', subjektType: 'person', subjektId: '255',
      payload: { personIds: ['255', '392'] } } as never);
    expect(call).toEqual({ fn: 'red_publicer_personer', args: { p_person_ids: [255, 392] } });
  });
  it('tom personIds-liste → null', () => {
    expect(buildRpcCall({ art: 'publicerPersoner', subjektType: 'person', subjektId: '255',
      payload: { personIds: [] } } as never)).toBeNull();
  });
  it('ugyldigt id i listen → null', () => {
    expect(buildRpcCall({ art: 'publicerPersoner', subjektType: 'person', subjektId: '255',
      payload: { personIds: ['255', 'ikke-et-id'] } } as never)).toBeNull();
  });
  it('manglende payload → null', () => {
    expect(buildRpcCall({ art: 'publicerPersoner', subjektType: 'person', subjektId: '255' } as never)).toBeNull();
  });
});

describe('buildRpcCall — publicerUdgave (K2 bulk-publicering)', () => {
  it('publicerUdgave → red_publicer_udgave(p_source_id)', () => {
    expect(buildRpcCall({
      art: 'publicerUdgave', subjektType: 'source', subjektId: '7',
    } as never)).toEqual({
      fn: 'red_publicer_udgave', args: { p_source_id: 7 },
    });
  });

  it('ugyldigt source-id → null', () => {
    expect(buildRpcCall({
      art: 'publicerUdgave', subjektType: 'source', subjektId: 'ikke-et-id',
    } as never)).toBeNull();
  });
});

// Web-spejl af mobile-testen for uploadMedia (mediehåndtering Slice 0g).
describe('buildRpcCall — uploadMedia (mediehåndtering Slice 0g)', () => {
  it('portræt (afbildetPersonId) → red_upload_media med p_afbildet_person_id', () => {
    const c = { art: 'uploadMedia', subjektType: 'person', subjektId: '42',
      payload: { afbildetPersonId: '42', slags: 'foto', titel: 'Portræt', maaPubliceres: true,
        storagePath: 'redaktor/x.jpg', mimeType: 'image/jpeg',
        byteSize: 1234, originalFilnavn: 'x.jpg' } } as never;
    expect(buildRpcCall(c)).toEqual({ fn: 'red_upload_media', args: {
      p_slags: 'foto', p_titel: 'Portræt', p_storage_path: 'redaktor/x.jpg', p_mime: 'image/jpeg',
      p_kunstner: null, p_datering: null, p_byte_size: 1234, p_bredde: null, p_hoejde: null, p_original_filnavn: 'x.jpg',
      p_rettigheder_status: 'ukendt', p_maa_publiceres: true, p_sha256: null, p_afbildet_person_id: 42 } });
  });
  it('sender sha256 til oprettelses-RPC, når den er kendt', () => {
    const c = { art: 'uploadMedia', subjektType: 'person', subjektId: '42',
      payload: { afbildetPersonId: '42', slags: 'foto', titel: 'Portræt',
        storagePath: 'redaktor/aa/hash-large.jpg', mimeType: 'image/jpeg', sha256: 'a'.repeat(64) } } as never;
    expect(buildRpcCall(c)?.args.p_sha256).toBe('a'.repeat(64));
  });
  it('objekt-foto (objektType/objektId) → p_objekt_type/p_objekt_id, ingen p_afbildet_person_id', () => {
    const c = { art: 'uploadMedia', subjektType: 'estate', subjektId: '7',
      payload: { objektType: 'estate', objektId: '7', slags: 'foto', titel: 'Godset',
        storagePath: 'redaktor/y.jpg', mimeType: 'image/jpeg' } } as never;
    const call = buildRpcCall(c);
    expect(call?.fn).toBe('red_upload_media');
    expect(call?.args.p_objekt_type).toBe('estate');
    expect(call?.args.p_objekt_id).toBe(7);
    expect(call?.args.p_afbildet_person_id).toBeUndefined();
  });
  it('mangler titel → null (p_titel har intet DEFAULT i RPC-signaturen)', () => {
    expect(buildRpcCall({ art: 'uploadMedia', subjektType: 'person', subjektId: '42',
      payload: { afbildetPersonId: '42', slags: 'foto', titel: '',
        storagePath: 'redaktor/x.jpg', mimeType: 'image/jpeg' } } as never)).toBeNull();
  });
});

describe('genoptag af eksisterende mediekladde', () => {
  it('planlægger alle uploads/variantregistreringer før sidste bekræftelse mod samme media-id', () => {
    const largeFile = new Blob(['large'], { type: 'image/jpeg' });
    const thumbFile = new Blob(['thumb'], { type: 'image/jpeg' });
    const mediumFile = new Blob(['medium'], { type: 'image/jpeg' });
    expect(buildResumeMediaUploadPlan('91',
      { tier: 'large', file: largeFile, storagePath: 'large.jpg', mimeType: 'image/jpeg', byteSize: 5, bredde: 1200, hoejde: 800 },
      [
        { tier: 'thumb', file: thumbFile, storagePath: 'thumb.jpg', mimeType: 'image/jpeg', byteSize: 5, bredde: 300, hoejde: 200 },
        { tier: 'medium', file: mediumFile, storagePath: 'medium.jpg', mimeType: 'image/jpeg', byteSize: 6, bredde: 900, hoejde: 600 },
      ],
    )).toEqual([
      { kind: 'upload', file: largeFile, storagePath: 'large.jpg' },
      { kind: 'upload', file: thumbFile, storagePath: 'thumb.jpg' },
      { kind: 'rpc', fn: 'red_registrer_media_variant', args: {
        p_media_id: 91, p_tier: 'thumb', p_storage_path: 'thumb.jpg', p_mime: 'image/jpeg',
        p_byte_size: 5, p_bredde: 300, p_hoejde: 200,
      } },
      { kind: 'upload', file: mediumFile, storagePath: 'medium.jpg' },
      { kind: 'rpc', fn: 'red_registrer_media_variant', args: {
        p_media_id: 91, p_tier: 'medium', p_storage_path: 'medium.jpg', p_mime: 'image/jpeg',
        p_byte_size: 6, p_bredde: 900, p_hoejde: 600,
      } },
      { kind: 'rpc', fn: 'red_bekraeft_media_upload', args: { p_media_id: 91 } },
    ]);
  });
});

// Web-spejl af mobile-testen for fjernMedia (mediehåndtering Slice 0h).
describe('buildRpcCall — fjernMedia (mediehåndtering Slice 0h)', () => {
  it('fjernMedia → red_fjern_media med p_media_id', () => {
    const c = { art: 'fjernMedia', subjektType: 'person', subjektId: '42', mediaId: '91' } as never;
    expect(buildRpcCall(c)).toEqual({ fn: 'red_fjern_media', args: { p_media_id: 91 } });
  });
  it('mangler mediaId → null', () => {
    expect(buildRpcCall({ art: 'fjernMedia', subjektType: 'person', subjektId: '42' } as never)).toBeNull();
  });
  it('bevarer et bigint media-id som streng', () => {
    expect(buildRpcCall({ art: 'fjernMedia', subjektType: 'media', subjektId: '9223372036854775807', mediaId: '9223372036854775807' } as never))
      .toEqual({ fn: 'red_fjern_media', args: { p_media_id: '9223372036854775807' } });
  });
});

describe('buildRpcCall — sletRelation med bigint', () => {
  it('bevarer et bigint relation-id som streng', () => {
    expect(buildRpcCall({ art: 'sletRelation', subjektType: 'media', subjektId: '91', relationId: '9223372036854775807' } as never))
      .toEqual({ fn: 'red_slet_relation', args: { p_relation_id: '9223372036854775807' } });
  });

  it('medieflet bruger den atomiske evidensbevarende RPC uden at ændre almindelig sletRelation', () => {
    expect(buildRpcCall({
      art: 'sletMediaRelationUdenEvidens', subjektType: 'media', subjektId: '91', relationId: '81',
    } as never)).toEqual({
      fn: 'red_slet_medierelation_uden_evidens', args: { p_relation_id: 81 },
    });
    expect(buildRpcCall({
      art: 'sletRelation', subjektType: 'media', subjektId: '91', relationId: '81',
    } as never)).toEqual({ fn: 'red_slet_relation', args: { p_relation_id: 81 } });
  });
});

describe('buildRpcCall — forældre ukendt-markering (docs/reviews/25)', () => {
  it('markerForaeldreUkendt → red_upsert_fakta med faktatype forældre_ukendt + grad + kilde', () => {
    const call = buildRpcCall({
      art: 'markerForaeldreUkendt', subjektType: 'person', subjektId: '210',
      vaerdi: 'forælder ukendt', kildeFritekst: 'DAA 1939 s.97',
    } as never);
    expect(call).toEqual({ fn: 'red_upsert_fakta', args: {
      p_subjekt_type: 'person', p_subjekt_id: 210,
      p_faktatype: 'forældre_ukendt', p_vaerdi: 'forælder ukendt', p_kilde_fritekst: 'DAA 1939 s.97',
    } });
  });

  it('markerForaeldreUkendt uden grad (vaerdi) → null (grad er påkrævet)', () => {
    expect(buildRpcCall({ art: 'markerForaeldreUkendt', subjektType: 'person', subjektId: '210' } as never)).toBeNull();
  });

  it('markerForaeldreUkendt uden kilde → p_kilde_fritekst null', () => {
    const call = buildRpcCall({
      art: 'markerForaeldreUkendt', subjektType: 'person', subjektId: '5', vaerdi: 'ingen forbindelse angivet',
    } as never);
    expect(call?.args.p_kilde_fritekst).toBeNull();
  });

  // FJERN markering (review 26 HIGH 2): tilbagetræk fakta-slottets konklusion via
  // red_tilbagetraek_fakta — IKKE red_slet_oplysning (som re-peger til ældste påstand og
  // genopliver markeringen efter Markér→Opdatér→Fjern). Målretter fact-id'et, ikke en assertion.
  it('tilbagetraekFakta → red_tilbagetraek_fakta med fact-id (fjern markering korrekt)', () => {
    const call = buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210', factId: '55' } as never);
    expect(call).toEqual({ fn: 'red_tilbagetraek_fakta', args: { p_fact_id: 55 } });
  });

  it('tilbagetraekFakta uden fact-id → null', () => {
    expect(buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210' } as never)).toBeNull();
  });

  it('tilbagetraekFakta med ugyldigt (ikke-numerisk/tomt) fact-id → null (NaN-guard, review 27)', () => {
    expect(buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210', factId: '' } as never)).toBeNull();
    expect(buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210', factId: 'x' } as never)).toBeNull();
  });
});

describe('buildRpcCall — forældrefamilie (Problem 2)', () => {
  it('foraeldrePaastand → red_tilfoej_foraeldre_paastand med alle valgfrie args', () => {
    const call = buildRpcCall({ art: 'foraeldrePaastand', subjektType: 'person', subjektId: '50',
      payload: { barnId: 50, familyId: 12, sourceId: 3, side: 's.490', citat: 'udg. citat' } });
    expect(call).toEqual({ fn: 'red_tilfoej_foraeldre_paastand', args: {
      p_barn_id: 50, p_family_id: 12, p_source_id: 3, p_side: 's.490', p_citat: 'udg. citat' } });
  });
  it('foraeldrePaastand minimal (kun barn+familie) → kun p_barn_id/p_family_id', () => {
    const call = buildRpcCall({ art: 'foraeldrePaastand', subjektType: 'person', subjektId: '50',
      payload: { barnId: 50, familyId: 12 } });
    expect(call).toEqual({ fn: 'red_tilfoej_foraeldre_paastand', args: { p_barn_id: 50, p_family_id: 12 } });
  });
  it('foraeldrePaastand uden barn/familie → null', () => {
    expect(buildRpcCall({ art: 'foraeldrePaastand', subjektType: 'person', subjektId: '50', payload: { barnId: 50 } } as never)).toBeNull();
  });
  it('vaelgForaeldre → red_vaelg_foraeldre(p_assertion_id, p_konfidens)', () => {
    expect(buildRpcCall({ art: 'vaelgForaeldre', subjektType: 'person', subjektId: '50',
      payload: { assertionId: 88, konfidens: 'sikker' } })).toEqual({
      fn: 'red_vaelg_foraeldre', args: { p_assertion_id: 88, p_konfidens: 'sikker' } });
  });
  it('vaelgForaeldre uden konfidens → kun p_assertion_id', () => {
    expect(buildRpcCall({ art: 'vaelgForaeldre', subjektType: 'person', subjektId: '50',
      payload: { assertionId: 88 } })).toEqual({ fn: 'red_vaelg_foraeldre', args: { p_assertion_id: 88 } });
  });
  it('vaelgForaeldre uden assertion → null', () => {
    expect(buildRpcCall({ art: 'vaelgForaeldre', subjektType: 'person', subjektId: '50', payload: {} } as never)).toBeNull();
  });
});

describe('buildRpcCall — filside fase 1', () => {
  it('opdaterMedia sender kun de payload-felter der faktisk er til stede', () => {
    expect(buildRpcCall({ art: 'opdaterMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { titel: '', kunstner: 'Anna' } } as never)).toEqual({
      fn: 'red_opdater_media', args: { p_media_id: 91, p_titel: '', p_kunstner: 'Anna' },
    });
    expect(buildRpcCall({ art: 'opdaterMedia', subjektType: 'media', subjektId: '91' } as never)).toBeNull();
  });

  it('genopretMedia kræver mediaId', () => {
    expect(buildRpcCall({ art: 'genopretMedia', subjektType: 'media', subjektId: '91', mediaId: '91' } as never))
      .toEqual({ fn: 'red_genopret_media', args: { p_media_id: 91 } });
    expect(buildRpcCall({ art: 'genopretMedia', subjektType: 'media', subjektId: '91' } as never)).toBeNull();
  });

  it('mediaRettigheder sender gate + udfyldt dokumentation', () => {
    expect(buildRpcCall({ art: 'mediaRettigheder', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { status: 'licenseret', maaPubliceres: true, licens: 'CC BY 4.0', kildehenvisning: '' } } as never))
      .toEqual({ fn: 'red_set_media_rettigheder', args: {
        p_media_id: 91, p_status: 'licenseret', p_maa_publiceres: true, p_licens: 'CC BY 4.0',
      } });
  });

  it('uploadMedia fører kunstner/datering/status igennem', () => {
    const call = buildRpcCall({ art: 'uploadMedia', subjektType: 'person', subjektId: '42', payload: {
      afbildetPersonId: 42, slags: 'maleri', titel: 'Portræt', storagePath: 'x.jpg', mimeType: 'image/jpeg',
      kunstner: 'Jens Juel', datering: 'ca. 1780', rettighederStatus: 'public_domain',
    } } as never);
    expect(call?.args).toMatchObject({
      p_kunstner: 'Jens Juel', p_datering: 'ca. 1780', p_rettigheder_status: 'public_domain',
    });
  });

  it('nye domænefejl oversættes', () => {
    expect(oversaetFejl('Kan kun genoprette et fjernet medie')).toContain('kun genoprettes');
    expect(oversaetFejl('Slags kan ikke ryddes')).toBe('Slags kan ikke ryddes.');
  });

  it('oversætter indholdsdublet præcist før den generiske unique-fallback', () => {
    expect(oversaetFejl('duplicate key: Medie med samme indhold findes allerede'))
      .toBe("Billedet findes allerede i biblioteket — brug 'Tilknyt eksisterende' i stedet.");
  });

  it('oversætter allerede-tilknyttet præcist før den generiske unique-fallback', () => {
    expect(oversaetFejl('unique constraint: Mediet er allerede tilknyttet dette subjekt'))
      .toBe('Mediet er allerede tilknyttet dette subjekt.');
  });
});

describe('buildRpcCall — mediaFakta (medie-metadata Task 3)', () => {
  it('mediaFakta mapper til red_upsert_fakta på media-subjekt', () => {
    const rpc = buildRpcCall({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
      payload: { faktatype: 'kilde_url', vaerdi: 'https://www.deutsche-digitale-bibliothek.de/item/H4Z…' } } as never);
    expect(rpc).toEqual({ fn: 'red_upsert_fakta', args: {
      p_subjekt_type: 'media', p_subjekt_id: 42, p_faktatype: 'kilde_url',
      p_vaerdi: 'https://www.deutsche-digitale-bibliothek.de/item/H4Z…' } });
  });

  it('mediaFakta afviser ukendt faktatype', () => {
    expect(buildRpcCall({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
      payload: { faktatype: 'levende', vaerdi: 'x' } } as never)).toBeNull();
  });

  it('mediaFakta datering sætter p_date_raw og date-felter (kanoniske engelske qualifiers)', () => {
    const rpc = buildRpcCall({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
      payload: { faktatype: 'datering', vaerdi: 'ca. 1840', dateMin: '1835-01-01', dateMax: '1845-12-31', dateQualifier: 'about' } } as never);
    expect(rpc?.args).toMatchObject({ p_date_raw: 'ca. 1840', p_date_min: '1835-01-01', p_date_max: '1845-12-31', p_date_qualifier: 'about' });
  });

  it('mediaFakta afviser ugyldig qualifier og ikke-http(s) kilde_url', () => {
    expect(buildRpcCall({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
      payload: { faktatype: 'datering', vaerdi: '1840', dateQualifier: 'ca' } } as never)).toBeNull();
    expect(buildRpcCall({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
      payload: { faktatype: 'kilde_url', vaerdi: 'javascript:alert(1)' } } as never)).toBeNull();
  });

  // Regression (fix-runde 1): dateQualifier: '' er en uvalgt <select>-default i Task 4's kommende
  // UI, ikke en ugyldig værdi — skal give et gyldigt kald UDEN p_date_qualifier, ikke null (som
  // ellers ville degradere en direkte redaktør-skrivning tavst til red_suggest via planCall).
  it('mediaFakta med tom dateQualifier-streng giver gyldigt kald uden p_date_qualifier', () => {
    const rpc = buildRpcCall({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
      payload: { faktatype: 'datering', vaerdi: '1840', dateQualifier: '' } } as never);
    expect(rpc).toEqual({ fn: 'red_upsert_fakta', args: {
      p_subjekt_type: 'media', p_subjekt_id: 42, p_faktatype: 'datering',
      p_vaerdi: '1840', p_date_raw: '1840' } });
    expect(rpc?.args).not.toHaveProperty('p_date_qualifier');
  });

  it('mediaFakta afviser manglende mediaId og tom/blank værdi', () => {
    expect(buildRpcCall({ art: 'mediaFakta', subjektType: 'person', subjektId: '7',
      payload: { faktatype: 'kilde_url', vaerdi: 'https://example.org' } } as never)).toBeNull();
    expect(buildRpcCall({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
      payload: { faktatype: 'kilde_institution', vaerdi: '   ' } } as never)).toBeNull();
  });

  it('mediaFakta hentedato uden eksplicitte date-felter sætter kun p_date_raw', () => {
    const rpc = buildRpcCall({ art: 'mediaFakta', subjektType: 'person', subjektId: '7', mediaId: '42',
      payload: { faktatype: 'hentedato', vaerdi: '2026-08-06' } } as never);
    expect(rpc).toEqual({ fn: 'red_upsert_fakta', args: {
      p_subjekt_type: 'media', p_subjekt_id: 42, p_faktatype: 'hentedato',
      p_vaerdi: '2026-08-06', p_date_raw: '2026-08-06' } });
  });
});

describe('buildRpcCall — tilknytMedia (mediehåndtering fase 2)', () => {
  it('person står på subjekt-siden', () => {
    expect(buildRpcCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType: 'person', maalId: '42' } })).toEqual({
      fn: 'red_relation',
      args: {
        p_subjekt_type: 'person', p_subjekt_id: 42,
        p_objekt_type: 'media', p_objekt_id: 91,
        p_rolle: 'afbildet', p_periode_raw: null,
      },
    });
  });

  it.each(['estate', 'coat_of_arms', 'lineage'] as const)('media står på subjekt-siden for %s', (maalType) => {
    expect(buildRpcCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType, maalId: '7' } })).toEqual({
      fn: 'red_relation',
      args: {
        p_subjekt_type: 'media', p_subjekt_id: 91,
        p_objekt_type: maalType, p_objekt_id: 7,
        p_rolle: 'afbildet', p_periode_raw: null,
      },
    });
  });

  it('afviser manglende eller ugyldige id-er og ukendt måltype', () => {
    const base = { art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType: 'person', maalId: '42' } } as const;
    expect(buildRpcCall({ ...base, mediaId: undefined })).toBeNull();
    expect(buildRpcCall({ ...base, mediaId: '' })).toBeNull();
    expect(buildRpcCall({ ...base, mediaId: 'x' })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, maalId: '' } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, maalId: 'x' } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, maalId: '0' } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, maalId: '-1' } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, maalId: '9223372036854775808' } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { maalType: 'organisation', maalId: '7' } })).toBeNull();
  });

  it('bevarer gyldige BIGINT-id-er over JavaScripts sikre heltalsgrænse som strenge', () => {
    expect(buildRpcCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91',
      mediaId: '9223372036854775807', payload: { maalType: 'person', maalId: '9007199254740992' } }))
      .toMatchObject({ args: { p_subjekt_id: '9007199254740992', p_objekt_id: '9223372036854775807' } });
  });

  it('kan degradere til red_suggest uden upload-gate', () => {
    const call = planCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType: 'person', maalId: '42' } }, 'medlem');
    expect(call).toMatchObject({ fn: 'red_suggest', args: {
      p_art: 'tilknytMedia', p_payload: { maalType: 'person', maalId: '42', mediaId: '91' },
    } });
  });

  it('bevarer et stort media-id præcist i både staging-subjekt og payload', () => {
    const mediaId = '9223372036854775807';
    expect(planCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: mediaId, mediaId,
      payload: { maalType: 'person', maalId: '42' } }, 'medlem')).toMatchObject({
      fn: 'red_suggest', args: { p_subjekt_id: mediaId, p_payload: { mediaId } },
    });
  });

  it('afviser en ugyldig tilknytning før staging', () => {
    expect(() => planCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType: 'person', maalId: '0' } }, 'medlem')).toThrow('Ugyldig medietilknytning');
  });

  it('oversætter red_relation GDPR-guarden', () => {
    expect(oversaetFejl('afbildet skal gå person→media (person kan ikke stå på objekt-siden — GDPR-gating)'))
      .toBe('En person skal stå på subjekt-siden ved billedtilknytning.');
  });
});

describe('buildRpcCall — story/feed_pin (fase 3)', () => {
  it('opretStory → red_opret_story med payload-felter', () => {
    const change = { art: 'opretStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: 'En minihistorie.', titel: 'Slaget', haendelseId: 91, dateRaw: '1671' } } as const;
    expect(buildRpcCall(change)).toEqual({ fn: 'red_opret_story', args: {
      p_subjekt_type: 'person', p_subjekt_id: 7, p_tekst: 'En minihistorie.',
      p_titel: 'Slaget', p_haendelse_id: 91, p_fact_id: null, p_relation_id: null,
      p_historical_event_id: null, p_date_min: null, p_date_max: null,
      p_date_qualifier: null, p_date_raw: '1671', p_privat: false,
    } });
    expect(buildRpcCall({ art: 'opretStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: '   ' } })).toBeNull();
    expect(planCall(change, 'medlem')).toMatchObject({ fn: 'red_suggest',
      args: { p_art: 'opretStory', p_payload: change.payload } });
  });

  it('redigerStory → red_rediger_story; kræver storyId + tekst', () => {
    expect(buildRpcCall({ art: 'redigerStory', subjektType: 'person', subjektId: '7',
      storyId: 3, payload: { tekst: 'Omskrevet.', privat: true } }))
      .toMatchObject({ fn: 'red_rediger_story',
        args: { p_story_id: 3, p_tekst: 'Omskrevet.', p_privat: true } });
    expect(buildRpcCall({ art: 'redigerStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: 'x' } })).toBeNull();
    expect(planCall({ art: 'redigerStory', subjektType: 'person', subjektId: '7',
      storyId: 3, payload: { tekst: 'Omskrevet.' },
      kilder: [{ sourceId: 2, side: '112' }] }, 'medlem'))
      .toMatchObject({ fn: 'red_suggest', args: {
        p_payload: { storyId: 3, tekst: 'Omskrevet.', kilder: [{ sourceId: 2, side: '112' }] },
      } });
  });

  it('opretStory-staging medtager de valgte kilder i det samlede forslag', () => {
    expect(planCall({ art: 'opretStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: 'En minihistorie.' },
      kilder: [{ sourceId: 2 }, { sourceId: 5, side: '44' }] }, 'medlem'))
      .toMatchObject({ fn: 'red_suggest', args: {
        p_payload: { tekst: 'En minihistorie.', kilder: [{ sourceId: 2 }, { sourceId: 5, side: '44' }] },
      } });
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
    expect(planCall({ art: 'setFeedPin', subjektType: 'feed_pin', subjektId: '',
      kortNoegle: 'portrait:12', handling: 'skjul' }, 'medlem'))
      .toMatchObject({ fn: 'red_suggest', args: {
        p_payload: { kortNoegle: 'portrait:12', handling: 'skjul' },
      } });
    expect(planCall({ art: 'setStoryStatus', subjektType: 'person', subjektId: '7',
      storyId: 3, storyStatus: 'klar' }, 'medlem'))
      .toMatchObject({ fn: 'red_suggest', args: {
        p_payload: { storyId: 3, storyStatus: 'klar' },
      } });
  });
});

describe('fase 4: erstatMediaFil', () => {
  const base: Change = {
    art: 'erstatMediaFil', subjektType: 'media', subjektId: '7', mediaId: '7',
    payload: {
      file: new Blob(['x']), storagePath: 'redaktor/ab/s-large.jpg', mimeType: 'image/jpeg',
      byteSize: 3, bredde: 2, hoejde: 1, sha256: 'abc123', originalFilnavn: 'ny.jpg',
      varianter: [{
        tier: 'thumb', file: new Blob(['t']), storagePath: 'redaktor/ab/s-thumb.jpg',
        mimeType: 'image/jpeg', byteSize: 1, bredde: 1, hoejde: 1,
      }],
    },
  };

  it('bygger red_erstat_media_fil med metadata-varianter (ALDRIG file-blobs i args)', () => {
    const call = buildRpcCall(base)!;
    expect(call.fn).toBe('red_erstat_media_fil');
    expect(call.args.p_media_id).toBe(7);
    expect(call.args.p_sha256).toBe('abc123');
    expect(call.args.p_varianter).toEqual([{
      tier: 'thumb', storage_path: 'redaktor/ab/s-thumb.jpg', mime: 'image/jpeg',
      byte_size: 1, bredde: 1, hoejde: 1,
    }]);
    expect(JSON.stringify(call.args)).not.toContain('"file"');
  });

  it('afviser manglende mediaId/sha256/sti', () => {
    expect(buildRpcCall({ ...base, mediaId: undefined })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, sha256: undefined } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, storagePath: undefined } })).toBeNull();
  });

  it('kan IKKE degradere til red_suggest (hård gate som uploadMedia)', async () => {
    await expect(submitChange(base, { dryRun: false, role: 'medlem' }))
      .rejects.toThrow(/redaktør-rettigheder/);
  });

  it('dry-run uploader INTET og udfører intet RPC (dryRun respekteres)', async () => {
    const { performUpload } = await import('../mediaUpload');
    const { supabase } = await import('../../supabase');
    vi.clearAllMocks();
    const res = await submitChange(base, { dryRun: true, role: 'redaktion' });
    expect(res.dryRun).toBe(true);
    expect(performUpload).not.toHaveBeenCalled();
    expect(supabase.rpc).not.toHaveBeenCalled();
  });
});

describe('fase 4: udrensMedia', () => {
  const change: Change = {
    art: 'udrensMedia', subjektType: 'media', subjektId: '9', mediaId: '9',
  };

  it('bygger red_udrens_media', () => {
    expect(buildRpcCall(change)).toEqual({ fn: 'red_udrens_media', args: { p_media_id: 9 } });
    expect(buildRpcCall({ ...change, mediaId: undefined })).toBeNull();
  });

  it('kan IKKE degradere til red_suggest', async () => {
    await expect(submitChange(change, { dryRun: false, role: 'medlem' }))
      .rejects.toThrow(/redaktør-rettigheder/);
  });

  it('dry-run uploader INTET og udfører intet RPC', async () => {
    const { performUpload } = await import('../mediaUpload');
    const { supabase } = await import('../../supabase');
    vi.clearAllMocks();
    const res = await submitChange(change, { dryRun: true, role: 'redaktion' });
    expect(res.dryRun).toBe(true);
    expect(performUpload).not.toHaveBeenCalled();
    expect(supabase.rpc).not.toHaveBeenCalled();
  });
});

describe('fase 4: saetPortraet', () => {
  const change: Change = {
    art: 'saetPortraet', subjektType: 'person', subjektId: '5', personId: '5', mediaId: '7',
  };

  it('bygger red_saet_portraet med og uden media (NULL = ryd)', () => {
    expect(buildRpcCall(change))
      .toEqual({ fn: 'red_saet_portraet', args: { p_person_id: 5, p_media_id: 7 } });
    expect(buildRpcCall({ ...change, mediaId: undefined }))
      .toEqual({ fn: 'red_saet_portraet', args: { p_person_id: 5, p_media_id: null } });
    expect(buildRpcCall({ ...change, subjektId: '', personId: undefined })).toBeNull();
  });

  it('degraderer til red_suggest for ikke-redaktion (metadata-change)', () => {
    const call = buildSuggestCall(change);
    expect(call.fn).toBe('red_suggest');
    expect(call.args.p_payload).toEqual({ personId: '5', mediaId: '7' });
  });

  it('dry-run uploader INTET og udfører intet RPC', async () => {
    const { performUpload } = await import('../mediaUpload');
    const { supabase } = await import('../../supabase');
    vi.clearAllMocks();
    const res = await submitChange(change, { dryRun: true, role: 'redaktion' });
    expect(res.dryRun).toBe(true);
    expect(performUpload).not.toHaveBeenCalled();
    expect(supabase.rpc).not.toHaveBeenCalled();
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

// --- Union-redigering (2026-08-01): reparér en union der mangler sin ene part.
// Hullet kostede 65 barne-flytninger da 1939-loaderens mor-løse børne-familier
// skulle rettes — én "tilføj mor" havde været nok.
describe('buildRpcCall — union-redigering', () => {
  it('tilfoejPartner → red_tilfoej_partner', () => {
    const c = { art: 'tilfoejPartner', subjektType: 'person', subjektId: '1198',
      payload: { familyId: '726', personId: '1613' } } as Change;
    expect(buildRpcCall(c)).toEqual({
      fn: 'red_tilfoej_partner',
      args: { p_family_id: 726, p_person_id: 1613, p_ordinal: null },
    });
  });

  it('tilfoejPartner videresender ordinal når den er sat', () => {
    const c = { art: 'tilfoejPartner', subjektType: 'person', subjektId: '1198',
      payload: { familyId: '726', personId: '1613', ordinal: 2 } } as Change;
    expect(buildRpcCall(c)?.args).toMatchObject({ p_ordinal: 2 });
  });

  it('tilfoejPartner uden personId giver null (ingen halvt kald)', () => {
    const c = { art: 'tilfoejPartner', subjektType: 'person', subjektId: '1198',
      payload: { familyId: '726' } } as Change;
    expect(buildRpcCall(c)).toBeNull();
  });

  // Et ufuldstændigt struktur-kald må IKKE degradere til red_suggest: redaktøren ville få
  // "Forslag sendt til staging" som kvittering på en handling der ikke skete (Codex sol).
  it('tilfoejPartner uden mål kaster frem for at blive et tomt forslag', () => {
    const c = { art: 'tilfoejPartner', subjektType: 'person', subjektId: '1198', payload: {} } as Change;
    expect(() => planCall(c, 'redaktion')).toThrow(/Ufuldstændig/);
  });

  it('gyldigt tilfoejPartner routes direkte for redaktion', () => {
    const c = { art: 'tilfoejPartner', subjektType: 'person', subjektId: '1198',
      payload: { familyId: '726', personId: '1613' } } as Change;
    expect(planCall(c, 'redaktion').fn).toBe('red_tilfoej_partner');
  });

  it('ikke-redaktion får stadig forslags-stien for et GYLDIGT kald', () => {
    const c = { art: 'tilfoejPartner', subjektType: 'person', subjektId: '1198',
      payload: { familyId: '726', personId: '1613' } } as Change;
    expect(planCall(c, 'medlem').fn).toBe('red_suggest');
  });
});
