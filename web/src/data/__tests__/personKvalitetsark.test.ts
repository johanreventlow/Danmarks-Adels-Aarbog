// Task 7: web-dataadapter til OCR-kvalitetsarket (red_person_grid / red_ret_ocr_felt /
// red_ocr_historik). In-memory fake af supabase-js's rpc-kæde: rpc() returnerer et objekt
// der ER en Promise<{data,error}> (direkte-await-brug, fx retOcrFelt/fetchOcrHistorik) OG
// bærer en .range()-metode (getAll-baseret paginering, fetchPersonKvalitetsark).
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PersonKvalitetsarkRow } from '@daa/core';

type RpcCall = { fn: string; args: unknown };
const rpcCalls: RpcCall[] = [];
let rpcImpl: (fn: string, args: unknown) => unknown = () => {
  throw new Error('rpcImpl ikke konfigureret for denne test');
};

vi.mock('../../supabase', () => ({
  supabase: {
    rpc: (fn: string, args?: unknown) => {
      rpcCalls.push({ fn, args });
      return rpcImpl(fn, args);
    },
    // redaktionWrite.ts (importeret for oversaetFejl) trækker nu media.ts ind (mediaFakta-arten,
    // Task 3), som kalder supabase.auth.onAuthStateChange ved modul-load (TTL-cache-invalidering).
    auth: { onAuthStateChange: vi.fn() },
  },
}));

const { fetchPersonKvalitetsark, fetchOcrHistorik, retOcrFelt, oversaetOcrFejl } = await import(
  '../personKvalitetsark'
);

beforeEach(() => {
  rpcCalls.length = 0;
  orderCalls.length = 0;
  rpcImpl = () => {
    throw new Error('rpcImpl ikke konfigureret for denne test');
  };
});

// Én komplet raw-række der dækker alle 42 kolonner fra red_person_grid() (schema.sql).
function rawRow(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    person_id: 42,
    import_key: 'daa-2018-reventlow',
    record_key: 'p-042',
    source_id: 7,
    source_titel: 'Danmarks Adels Aarbog 2018-20',
    source_udgave: '2018-20',
    linje: 'III',
    nr: 12,
    slaegtled: 5,
    person_status: 'ok',
    navn: 'Christian Ditlev Reventlow',
    navn_assertion_id: 501,
    foedsel_raw: '12. juli 1748',
    foedsel_min: '1748-07-12',
    foedsel_max: '1748-07-12',
    foedsel_qualifier: 'exact',
    foedsel_assertion_id: 502,
    doed_raw: '1827',
    doed_min: '1827-01-01',
    doed_max: '1827-12-31',
    doed_qualifier: null,
    doed_assertion_id: 503,
    input_fingerprint: { navn: 'fp-navn', foedsel: 'fp-foedsel' },
    importeret: {
      navn: { value: 'Christian Ditlev Reventlow' },
      foedsel: {
        raw: '12. juli 1748', min: '1748-07-12', max: '1748-07-12',
        qualifier: 'exact', calendar: 'gregoriansk', certainty: 'certain',
      },
    },
    korrigeret: { navn: null },
    ocr_context: { navn: 'Christian Ditlev Reventlow, f. 12. juli 1748' },
    kilde_side: { navn: '117' },
    koen: 'mand',
    levende: false,
    privat: false,
    staged: false,
    kanonisk_person_id: null,
    samme_som_status: null,
    antal_titler: 2,
    antal_familier: 1,
    antal_relationer: 4,
    antal_kilde_assertions: 3,
    qa_koder: ['dato_ufortolkelig'],
    qa_alvor: 'advarsel',
    review_status: { navn: 'aaben' },
    kan_rettes: { navn: true, foedsel: true, doed: false, koen: true },
    blokarsager: { doed: 'Flere kildebelagte påstande' },
    ...overrides,
  };
}

const MAPPED_ROW_FULL: PersonKvalitetsarkRow = {
  personId: '42',
  importKey: 'daa-2018-reventlow',
  recordKey: 'p-042',
  sourceId: '7',
  sourceTitel: 'Danmarks Adels Aarbog 2018-20',
  sourceUdgave: '2018-20',
  linje: 'III',
  nr: 12,
  slaegtled: 5,
  personStatus: 'ok',
  navn: 'Christian Ditlev Reventlow',
  navnAssertionId: '501',
  foedselRaw: '12. juli 1748',
  foedselMin: '1748-07-12',
  foedselMax: '1748-07-12',
  foedselQualifier: 'exact',
  foedselAssertionId: '502',
  doedRaw: '1827',
  doedMin: '1827-01-01',
  doedMax: '1827-12-31',
  doedQualifier: null,
  doedAssertionId: '503',
  koen: 'mand',
  levende: false,
  privat: false,
  staged: false,
  kanoniskPersonId: null,
  sammeSomStatus: null,
  antalTitler: 2,
  antalFamilier: 1,
  antalRelationer: 4,
  antalKildeAssertions: 3,
  qaKoder: ['dato_ufortolkelig'],
  qaAlvor: 'advarsel',
  reviewStatus: { navn: 'aaben' },
  kanRettes: { navn: true, foedsel: true, doed: false, koen: true },
  blokarsager: { doed: 'Flere kildebelagte påstande' },
  ocrContext: { navn: 'Christian Ditlev Reventlow, f. 12. juli 1748' },
  kildeSide: { navn: '117' },
  importeret: {
    navn: { value: 'Christian Ditlev Reventlow' },
    foedsel: {
      raw: '12. juli 1748', min: '1748-07-12', max: '1748-07-12',
      qualifier: 'exact', calendar: 'gregoriansk', certainty: 'certain',
    },
  },
  korrigeret: { navn: null },
  inputFingerprint: { navn: 'fp-navn', foedsel: 'fp-foedsel' },
};

const orderCalls: unknown[] = [];

// Spejler PostgrestFilterBuilder-kæden: .order() returnerer sig selv (chainable), .range()
// afslutter kaldet. red_person_grid() har ingen ORDER BY i sin egen SELECT (verificeret mod
// schema.sql), så adapteren SKAL selv lægge .order() ind før .range() for at gøre pagineringen
// deterministisk mellem to separate .range()-kald — ellers garanterer Postgres ikke rækkefølge.
function rangeResult(data: unknown[]) {
  const builder = {
    order: (col: string) => {
      orderCalls.push(col);
      return builder;
    },
    range: async () => ({ data, error: null }),
  };
  return builder;
}

describe('fetchPersonKvalitetsark — mapning', () => {
  it('mapper en komplet snake_case-række til camelCase, person_id som string', async () => {
    rpcImpl = () => rangeResult([rawRow()]);
    const rows = await fetchPersonKvalitetsark();
    expect(rows).toEqual([MAPPED_ROW_FULL]);
    expect(typeof rows[0].personId).toBe('string');
    expect(typeof rows[0].sourceId).toBe('string');
    expect(typeof rows[0].navnAssertionId).toBe('string');
  });

  it('bigint-ID mappes aldrig til number, selv for store værdier uden for Number-sikkerhed', async () => {
    const stort = '9007199254740993'; // > Number.MAX_SAFE_INTEGER
    rpcImpl = () => rangeResult([rawRow({ person_id: stort })]);
    const rows = await fetchPersonKvalitetsark();
    expect(rows[0].personId).toBe(stort);
    expect(typeof rows[0].personId).toBe('string');
  });
});

describe('fetchPersonKvalitetsark — paginering', () => {
  it('henter flere 1000-rækkers sider via ét RPC-kald pr. side, aldrig pr. person', async () => {
    const side1 = Array.from({ length: 1000 }, (_, i) => rawRow({ person_id: i + 1 }));
    const side2 = Array.from({ length: 5 }, (_, i) => rawRow({ person_id: 1001 + i }));
    let kald = 0;
    rpcImpl = (fn) => {
      expect(fn).toBe('red_person_grid');
      kald++;
      const data = kald === 1 ? side1 : kald === 2 ? side2 : [];
      return rangeResult(data);
    };
    const rows = await fetchPersonKvalitetsark();
    expect(rows).toHaveLength(1005);
    // Præcis to sider — IKKE ét kald pr. række (ville være 1005 kald).
    expect(rpcCalls.filter((c) => c.fn === 'red_person_grid')).toHaveLength(2);
  });

  it('lægger .order(person_id) før .range() — pagineringen skal være deterministisk', async () => {
    rpcImpl = () => rangeResult([rawRow()]);
    await fetchPersonKvalitetsark();
    expect(orderCalls).toEqual(['person_id']);
  });
});

describe('fetchPersonKvalitetsark — person uden importanker', () => {
  it('source_id=NULL (ingen person_external_id-række) → sourceId null, kaster ikke', async () => {
    // external_anchor er en LEFT JOIN i red_person_grid() (schema.sql) — en person uden
    // nogen person_external_id får stadig én grid-række, blot med source_id=NULL. Griddet
    // skal blive ved med at være "alle personer, permanent first-class view" — én ramt
    // person må aldrig vælte hele svaret.
    // NULL mappes til null, ikke til en sentinel: importKey og recordKey er nullable af
    // præcis samme grund, og en tom streng ville tvinge hver UI-komponent til at kende
    // sentinel-konventionen for at skelne "intet importanker" fra en gyldig værdi.
    rpcImpl = () => rangeResult([rawRow({
      source_id: null, import_key: null, record_key: null,
      kan_rettes: { navn: false, foedsel: false, doed: false, koen: true },
      blokarsager: { navn: 'ingen_importanker', foedsel: 'ingen_importanker', doed: 'ingen_importanker' },
    })]);
    const rows = await fetchPersonKvalitetsark();
    expect(rows).toHaveLength(1);
    expect(rows[0].sourceId).toBeNull();
    expect(rows[0].personId).toBe('42');
  });
});

describe('fetchPersonKvalitetsark — kontraktvalidering', () => {
  it('kaster en tydelig fejl ved manglende person_id', async () => {
    rpcImpl = () => rangeResult([rawRow({ person_id: null })]);
    await expect(fetchPersonKvalitetsark()).rejects.toThrow(/person_id/);
  });

  it('kaster en tydelig fejl når qa_koder ikke er en liste', async () => {
    rpcImpl = () => rangeResult([rawRow({ qa_koder: 'ikke-en-liste' })]);
    await expect(fetchPersonKvalitetsark()).rejects.toThrow(/qa_koder/);
  });

  it('kaster en tydelig fejl når kan_rettes mangler felter', async () => {
    rpcImpl = () => rangeResult([rawRow({ kan_rettes: { navn: true } })]);
    await expect(fetchPersonKvalitetsark()).rejects.toThrow(/kan_rettes/);
  });

  it('kaster en tydelig fejl når kan_rettes slet ikke er et objekt', async () => {
    rpcImpl = () => rangeResult([rawRow({ kan_rettes: null })]);
    await expect(fetchPersonKvalitetsark()).rejects.toThrow(/kan_rettes/);
  });
});

describe('retOcrFelt', () => {
  it('sender nøjagtig red_ret_ocr_felt-payload og erstatter rækken med svaret', async () => {
    rpcImpl = (fn) => {
      if (fn !== 'red_ret_ocr_felt') throw new Error(`uventet rpc: ${fn}`);
      return Promise.resolve({ data: rawRow(), error: null });
    };
    const result = await retOcrFelt({
      personId: '42',
      importKey: 'daa-2018-reventlow',
      recordKey: 'p-042',
      felt: 'navn',
      inputFingerprint: 'fp-navn',
      korrigeret: { value: 'Christian Ditlev Reventlow' },
      status: 'rettet',
      actorNavn: 'Test Redaktør',
    });
    expect(rpcCalls).toEqual([{
      fn: 'red_ret_ocr_felt',
      args: {
        p_person_id: 42,
        p_import_key: 'daa-2018-reventlow',
        p_record_key: 'p-042',
        p_felt: 'navn',
        p_input_fingerprint: 'fp-navn',
        p_korrigeret: { value: 'Christian Ditlev Reventlow' },
        p_status: 'rettet',
        p_actor_navn: 'Test Redaktør',
      },
    }]);
    expect(result).toEqual(MAPPED_ROW_FULL);
  });

  it('udelader actorNavn → sender p_actor_navn: null', async () => {
    rpcImpl = () => Promise.resolve({ data: rawRow(), error: null });
    await retOcrFelt({
      personId: '42', importKey: 'daa-2018-reventlow', recordKey: 'p-042', felt: 'koen',
      inputFingerprint: 'fp-koen', korrigeret: null, status: 'godkendt',
    });
    expect(rpcCalls[0].args).toMatchObject({ p_actor_navn: null, p_korrigeret: null, p_status: 'godkendt' });
  });

  it('videresender RPC-fejlen ved afvist rettelse (staleness/ambiguity o.l.)', async () => {
    rpcImpl = () => Promise.resolve({ data: null, error: { message: 'OCR_FINGERPRINT_STALE' } });
    await expect(retOcrFelt({
      personId: '42', importKey: 'daa-2018-reventlow', recordKey: 'p-042', felt: 'navn',
      inputFingerprint: 'fp-navn', korrigeret: { value: 'X' }, status: 'rettet',
    })).rejects.toBeTruthy();
  });
});

describe('fetchOcrHistorik', () => {
  it('sender nøjagtige red_ocr_historik-parametre og bevarer nyeste-først rækkefølge', async () => {
    const rawHistory = [
      {
        change_set_id: 205, changed_at: '2026-07-20T10:00:00Z', actor_navn: 'A',
        operation: 'red_ret_ocr_felt', foer: { value: 'X' }, efter: { value: 'Y' },
      },
      {
        change_set_id: 190, changed_at: '2026-07-18T09:00:00Z', actor_navn: 'B',
        operation: 'red_ret_ocr_felt', foer: null, efter: { value: 'X' },
      },
    ];
    rpcImpl = (fn) => {
      if (fn !== 'red_ocr_historik') throw new Error(`uventet rpc: ${fn}`);
      return Promise.resolve({ data: rawHistory, error: null });
    };
    const entries = await fetchOcrHistorik('daa-2018-reventlow', 'p-042', 'navn');
    expect(rpcCalls).toEqual([{
      fn: 'red_ocr_historik',
      args: { p_import_key: 'daa-2018-reventlow', p_record_key: 'p-042', p_felt: 'navn' },
    }]);
    expect(entries).toEqual([
      { changeSetId: '205', changedAt: '2026-07-20T10:00:00Z', actorNavn: 'A', operation: 'red_ret_ocr_felt', foer: { value: 'X' }, efter: { value: 'Y' } },
      { changeSetId: '190', changedAt: '2026-07-18T09:00:00Z', actorNavn: 'B', operation: 'red_ret_ocr_felt', foer: null, efter: { value: 'X' } },
    ]);
    // Ikke omsorteret — rækkefølgen fra RPC'en (allerede DESC i SQL) bevares uændret.
    expect(entries[0].changeSetId).toBe('205');
  });

  it('tom historik → tom liste', async () => {
    rpcImpl = () => Promise.resolve({ data: [], error: null });
    expect(await fetchOcrHistorik('k', 'r', 'doed')).toEqual([]);
  });

  it('data:null fra RPC → tom liste', async () => {
    rpcImpl = () => Promise.resolve({ data: null, error: null });
    expect(await fetchOcrHistorik('k', 'r', 'doed')).toEqual([]);
  });
});

describe('oversaetOcrFejl — samtlige OCR_*-koder plus ukendt-fallback', () => {
  it.each([
    ['OCR_ROLE_FORBIDDEN', /redaktør-rettigheder/i],
    ['OCR_PERSON_NOT_FOUND', /person(en)?.*(fundet|kilde-post)/i],
    ['OCR_IMPORT_ANCHOR_AMBIGUOUS', /entydig kildeforankring/i],
    ['OCR_ASSERTION_AMBIGUOUS', /kildebelagt påstand/i],
    ['OCR_FINGERPRINT_STALE', /ændret.*genindlæs/i],
    ['OCR_FIELD_INVALID', /gyldigt.*felt/i],
    ['OCR_VALUE_INVALID', /ugyldig/i],
  ])('%s → forståelig dansk tekst', (kode, forventet) => {
    expect(oversaetOcrFejl(new Error(kode))).toMatch(forventet);
    // Samme oversættelse uanset fejl-facade (string, Error, PostgrestError-lignende objekt).
    expect(oversaetOcrFejl(kode)).toMatch(forventet);
    expect(oversaetOcrFejl({ message: kode, code: 'P0001', details: null, hint: null })).toMatch(forventet);
  });

  it('ukendt/uigenkendt kode falder tilbage til en generisk, ikke-tom besked', () => {
    const besked = oversaetOcrFejl(new Error('noget helt andet gik galt'));
    expect(besked.length).toBeGreaterThan(0);
    expect(besked).not.toBe('noget helt andet gik galt');
  });

  it('håndterer non-Error/non-string input uden at kaste', () => {
    expect(() => oversaetOcrFejl(undefined)).not.toThrow();
    expect(() => oversaetOcrFejl({ foo: 'bar' })).not.toThrow();
  });

  it('delegerer til redaktionWrite.oversaetFejl for ikke-OCR_-fejl (fx den delte rolle-guard)', () => {
    // red_person_grid() selv rejser 'Kun redaktion' (ikke et OCR_-præfikset kodenavn) —
    // skal stadig oversættes forståeligt, ikke ende som "Ukendt fejl ved OCR-rettelse: Kun redaktion".
    expect(oversaetOcrFejl(new Error('Kun redaktion'))).toMatch(/redaktør-rettigheder/i);
  });
});
