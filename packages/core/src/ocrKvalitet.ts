// Personers OCR-kvalitetsark — delte typer, datonormalisering, QA-filtre og sortering.
// Ingen React/DOM/Supabase-imports her: modulet deles med mobile (RN/Hermes).

// --- Delte typer (kontrakt med red_person_grid() i schema.sql, 42 kolonner) ---

export type OcrFelt = 'navn' | 'foedsel' | 'doed' | 'koen';
export type OcrReviewStatus = 'aaben' | 'rettet' | 'godkendt' | 'udskudt' | 'stale';
export type KvalitetsarkPreset = 'alle' | 'aabne' | 'rettede' | 'godkendte' | 'udskudte' | 'stale';
export type KvalitetsarkSortKey = 'navn' | 'foedsel' | 'doed' | 'koen' | 'linje' | 'qa_alvor';
export type OcrDateQualifier =
  | 'exact'
  | 'before'
  | 'after'
  | 'about'
  | 'between'
  | 'floruit'
  | 'until_event'
  | 'open_end'
  | 'ongoing';

// bigint-kolonner (person_id, source_id, *_assertion_id, kanonisk_person_id) mappes til
// string for at undgå usikker JS-tal-afrunding af store IDs — se getAll.ts-konventionen.
export type PersonKvalitetsarkRow = {
  personId: string;
  importKey: string | null;
  recordKey: string | null;
  sourceId: string;
  sourceTitel: string | null;
  sourceUdgave: string | null;
  linje: string | null;
  nr: number | null;
  slaegtled: number | null;
  personStatus: string | null;
  navn: string;
  navnAssertionId: string | null;
  foedselRaw: string | null;
  foedselMin: string | null;
  foedselMax: string | null;
  foedselQualifier: string | null;
  foedselAssertionId: string | null;
  doedRaw: string | null;
  doedMin: string | null;
  doedMax: string | null;
  doedQualifier: string | null;
  doedAssertionId: string | null;
  koen: string | null;
  levende: boolean;
  privat: boolean;
  staged: boolean;
  kanoniskPersonId: string | null;
  sammeSomStatus: string | null;
  antalTitler: number;
  antalFamilier: number;
  antalRelationer: number;
  antalKildeAssertions: number;
  qaKoder: string[];
  qaAlvor: 'fejl' | 'advarsel' | 'info' | null;
  reviewStatus: Partial<Record<OcrFelt, OcrReviewStatus>>;
  kanRettes: Record<OcrFelt, boolean>;
  blokarsager: Partial<Record<OcrFelt, string>>;
  ocrContext: Partial<Record<OcrFelt, string | null>>;
  kildeSide: Partial<Record<OcrFelt, string | null>>;
  importeret: Partial<Record<OcrFelt, Record<string, unknown>>>;
  korrigeret: Partial<Record<OcrFelt, Record<string, unknown> | null>>;
  inputFingerprint: Partial<Record<OcrFelt, string>>;
};

const OCR_FELTER: readonly OcrFelt[] = ['navn', 'foedsel', 'doed', 'koen'];

// --- Datonormalisering ---
//
// Port af .claude/skills/daa-extract/scripts/validate.py::derive_date_info
// (samme fil, samme funktionsnavn i header-kommentaren dér). Kryds-sproglig
// paritet er dækket af tests/fixtures/ocr-date-normalization.json — ÆNDR IKKE
// disse regler uden at opdatere BÅDE denne fil, den fixture og
// test_validate.py's parity-test.
//
// BEVIDST UDELADT (matcher ikke fixturen, matcher IKKE derive_date_info for disse
// input): kirkelige mærkedage/computus (_kirkedag_dato, påskeberegning). Denne port
// dækker kun det spor validate.py kalder FØR mærkedags-opløsning. `calendar` er derfor
// altid 'gregoriansk' her (aldrig 'juliansk'). Input som "Mikkelsdag 1712" vil derfor
// IKKE matche Python-siden (Python: 1712-09-29 præcist; denne port: helår 1712) — der
// findes ingen fixture-case for det, og ingen test fanger divergensen. Hvis
// kvalitetsarkets datofelter rammer et sådant korpus-input, må denne begrænsning
// lukkes i en separat opgave, ikke stiltiende udvides her.
//
// Ingen kalender-validering (matcher Python): "31. april 1500" giver "1500-04-31",
// selvom april kun har 30 dage. Det er den eksisterende extraction-adfærd, ikke en
// fejl vi retter her.

const MAANEDER: Record<string, number> = {
  jan: 1, jän: 1, jaen: 1,
  feb: 2,
  mar: 3, mär: 3, maer: 3,
  apr: 4,
  maj: 5, mai: 5,
  jun: 6, jul: 7, aug: 8,
  sep: 9,
  okt: 10, oct: 10,
  nov: 11,
  dec: 12, dez: 12,
};

// Slår måned op via prefiks — 4-tegns transskription ('jaen'/'maer') FØRST, ellers 3-tegn.
function maanedFraNavn(name: string): number | null {
  const fire = name.slice(0, 4);
  if (fire in MAANEDER) return MAANEDER[fire];
  const tre = name.slice(0, 3);
  if (tre in MAANEDER) return MAANEDER[tre];
  return null;
}

const ROMERTAL_VAERDI: Record<string, number> = { m: 1000, d: 500, c: 100, l: 50, x: 10, v: 5, i: 1 };
const ROMERTAL_FORM_RE = /^m{0,4}(?:cm|cd|d?c{0,4})(?:xc|xl|l?x{0,4})(?:ix|iv|v?i{0,4})$/;
const ROMERTAL_TOKEN_RE = /\b[mdclxvi]{4,}\b/g;

function romertalAar(tok: string): number | null {
  if (!ROMERTAL_FORM_RE.test(tok)) return null;
  let total = 0;
  for (let i = 0; i < tok.length; i++) {
    const v = ROMERTAL_VAERDI[tok[i]];
    const next = i + 1 < tok.length ? ROMERTAL_VAERDI[tok[i + 1]] : undefined;
    if (next !== undefined && v < next) total -= v;
    else total += v;
  }
  return total >= 1000 && total <= 2100 ? total : null;
}

const Q_BEFORE_RE = /\b(?:før|inden|senest)\b/;
const Q_AFTER_RE = /\befter\b/;
const Q_ABOUT_RE = /\b(?:ca|circa|omkr|omkring|um)\b|\bo\./;
const Q_BETWEEN_RE = /\bmellem\b/;
// Bindestreg-flankeret nævnt-form '(-1223-1247-)' / '-1223-' = floruit (invariant #5),
// IKKE levetid.
const FLORUIT_FLANK_RE = /[-–]\s*\d{3,4}(?:\s*[-–]\s*\d{3,4})?\s*[-–](?!\s*\d)/;

type DateInfo = {
  min: string | null;
  max: string | null;
  qualifier: OcrDateQualifier | null;
  certainty: 'certain' | 'uncertain' | 'ambiguous' | null;
};

function deriveDateInfo(dateRaw: string): DateInfo {
  const info: DateInfo = { min: null, max: null, qualifier: null, certainty: null };
  if (!dateRaw) return info;
  let t = dateRaw.trim().toLowerCase();

  // --- Usikre cifre (kildens egen tvivl) → bedste læsning + 'uncertain' ---
  // '147(5?)' -> 1475: parentes-ciffer med '?' er kildens foreslåede læsning.
  let nParen = 0;
  t = t.replace(/\((\d{1,2})\s*\?\)/g, (_m, d) => {
    nParen++;
    return d;
  });
  // '1475?' -> 1475: spørgsmålstegn efter helt årstal.
  let nTail = 0;
  t = t.replace(/(\d{4})\s*\?/g, (_m, y) => {
    nTail++;
    return y;
  });
  if (nParen || nTail) info.certainty = 'uncertain';

  // '14?8': ulæseligt ciffer → ydre hylster over alle læsninger (?=0..9).
  const wm = /(?<![\d?])(\d{1,3})\?(\d{0,2})(?![\d?])/.exec(t);
  if (wm && wm[1].length + 1 + wm[2].length === 4) {
    const yLo = wm[1] + '0' + wm[2];
    const yHi = wm[1] + '9' + wm[2];
    info.min = `${yLo}-01-01`;
    info.max = `${yHi}-12-31`;
    info.certainty = 'uncertain';
    return info;
  }

  let years: string[] = t.match(/\d{4}/g) ?? [];
  if (years.length === 0) {
    // Fallback: romertals-årstal (kun når intet arabisk årstal findes)
    const romanTokens = t.match(ROMERTAL_TOKEN_RE) ?? [];
    const roman = romanTokens.map(romertalAar).filter((y): y is number => y !== null);
    if (roman.length === 1) years = [String(roman[0])];
  }
  if (years.length === 0 || years.length > 2) {
    // certainty overlever denne early-return (matcher Python: en tvivlsom
    // helhed uden brugbare bounds beholder alligevel 'uncertain').
    return info;
  }

  const qBetween = Q_BETWEEN_RE.test(t);
  const qBefore = Q_BEFORE_RE.test(t);
  const qAfter = Q_AFTER_RE.test(t);
  const qAbout = Q_ABOUT_RE.test(t);
  const qFloruit = FLORUIT_FLANK_RE.test(t);

  if (years.length === 2) {
    const sorted = [...years].sort();
    info.min = `${sorted[0]}-01-01`;
    info.max = `${sorted[sorted.length - 1]}-12-31`;
    if (qBetween || (qBefore && qAfter)) {
      info.qualifier = 'between';
    } else if (qFloruit) {
      info.qualifier = 'floruit';
    } else if (qAbout) {
      info.qualifier = 'about';
    }
    // NB: et bart span '1712-1783' (levetid) får bevidst INGEN qualifier.
    return info;
  }

  const y = years[0];
  const dm = /(\d{1,2})\.\s*([a-zæøåäöü]+)/.exec(t);
  let isoPoint: string | null = null;
  if (dm) {
    const mo = maanedFraNavn(dm[2]);
    const da = parseInt(dm[1], 10);
    if (mo && da >= 1 && da <= 31) {
      isoPoint = `${y}-${String(mo).padStart(2, '0')}-${String(da).padStart(2, '0')}`;
    }
  }

  if (qFloruit) {
    info.min = `${y}-01-01`;
    info.max = `${y}-12-31`;
    info.qualifier = 'floruit';
  } else if (qBefore) {
    // Skel på årets POSITION ift. 'før'-ordet:
    //   'før 1261' / 'før 26. juli 1261' → året ER grænsen → min åben (null).
    //   '1496, før 10. okt.' → året er kendt begivenheds-år, kun dagen er
    //     'før' → min=år-start (mister ellers den kendte nedre grænse).
    const m = Q_BEFORE_RE.exec(t);
    if (m && t.indexOf(y) < m.index) {
      info.min = `${y}-01-01`;
    }
    info.max = isoPoint ?? `${y}-12-31`;
    info.qualifier = 'before';
  } else if (qAfter) {
    const m = Q_AFTER_RE.exec(t);
    if (m && t.indexOf(y) < m.index) {
      info.max = `${y}-12-31`;
    }
    info.min = isoPoint ?? `${y}-01-01`;
    info.qualifier = 'after';
  } else if (qAbout) {
    // Approksimation: ét år -> hele års-spannet, uanset evt. dag-angivelse
    info.min = `${y}-01-01`;
    info.max = `${y}-12-31`;
    info.qualifier = 'about';
  } else if (isoPoint) {
    info.min = info.max = isoPoint;
  } else {
    info.min = `${y}-01-01`;
    info.max = `${y}-12-31`;
  }
  return info;
}

export function normaliserOcrDato(raw: string): {
  raw: string;
  min: string | null;
  max: string | null;
  qualifier: OcrDateQualifier | null;
  calendar: 'gregoriansk';
  certainty: 'certain' | 'uncertain' | 'ambiguous' | null;
  understood: boolean;
} {
  const info = deriveDateInfo(raw);
  return {
    raw,
    min: info.min,
    max: info.max,
    qualifier: info.qualifier,
    calendar: 'gregoriansk',
    certainty: info.certainty,
    understood: info.min !== null || info.max !== null,
  };
}

// --- QA-filtre ---

export type KvalitetsarkFilter = {
  preset: KvalitetsarkPreset;
  query: string;
  source: string | null;
  linje: string | null;
  felt: OcrFelt | null;
  reviewStatus: OcrReviewStatus | null;
  staged: boolean | null;
  sammeSom: boolean | null;
};

// Statusser der betyder "der er truffet en stående afgørelse" for et felt.
// 'stale' regnes bevidst IKKE med her: input har ændret sig siden afgørelsen,
// så feltet kræver reelt fornyet stillingtagen (design §9: "Stale: input har
// ændret sig siden afgørelsen") — det optræder derfor i BÅDE 'aabne' (fortsat
// åbent) og sin egen 'stale'-preset (til målrettet triage).
const AFGJORT: ReadonlySet<OcrReviewStatus> = new Set(['rettet', 'godkendt', 'udskudt']);

function harAktivQaUdenFuldfoertReview(row: PersonKvalitetsarkRow): boolean {
  if (row.qaKoder.length === 0) return false;
  // Kun felter med en FAKTISK registreret reviewstatus tæller med — ikke alle
  // fire redigerbare felter i abstrakto (de fleste rækker har intet review endnu
  // for de fleste af deres felter, det gør dem ikke i sig selv "åbne").
  const registrerede = OCR_FELTER.map((felt) => row.reviewStatus[felt]).filter(
    (status): status is OcrReviewStatus => status !== undefined,
  );
  if (registrerede.length === 0) return true; // QA-koder findes, intet afgjort endnu
  return registrerede.some((status) => !AFGJORT.has(status));
}

function harFeltMedStatus(row: PersonKvalitetsarkRow, status: OcrReviewStatus): boolean {
  return OCR_FELTER.some((felt) => row.reviewStatus[felt] === status);
}

function matcherPreset(row: PersonKvalitetsarkRow, preset: KvalitetsarkPreset): boolean {
  switch (preset) {
    case 'alle':
      return true;
    case 'aabne':
      return harAktivQaUdenFuldfoertReview(row);
    case 'rettede':
      return harFeltMedStatus(row, 'rettet');
    case 'godkendte':
      return harFeltMedStatus(row, 'godkendt');
    case 'udskudte':
      return harFeltMedStatus(row, 'udskudt');
    case 'stale':
      return harFeltMedStatus(row, 'stale');
    default:
      return true;
  }
}

function matcherSoegning(row: PersonKvalitetsarkRow, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const felter = [row.navn, row.recordKey, row.sourceTitel, row.linje, row.personId];
  return felter.some((v) => v != null && String(v).toLowerCase().includes(q));
}

export function filterKvalitetsark(
  rows: PersonKvalitetsarkRow[],
  filter: KvalitetsarkFilter,
): PersonKvalitetsarkRow[] {
  return rows.filter((row) => {
    if (!matcherPreset(row, filter.preset)) return false;
    if (!matcherSoegning(row, filter.query)) return false;
    if (filter.source !== null && row.sourceTitel !== filter.source) return false;
    if (filter.linje !== null && row.linje !== filter.linje) return false;
    if (filter.staged !== null && row.staged !== filter.staged) return false;
    if (filter.sammeSom !== null) {
      const harSammeSom = row.sammeSomStatus !== null;
      if (harSammeSom !== filter.sammeSom) return false;
    }
    if (filter.felt !== null) {
      if (filter.reviewStatus !== null) {
        if (row.reviewStatus[filter.felt] !== filter.reviewStatus) return false;
      } else if (row.reviewStatus[filter.felt] === undefined) {
        return false;
      }
    } else if (filter.reviewStatus !== null) {
      if (!harFeltMedStatus(row, filter.reviewStatus)) return false;
    }
    return true;
  });
}

// --- Sortering ---

let danskCollator: Intl.Collator | null = null;
function collator(): Intl.Collator {
  // Konstrueres lazy: modulet re-eksporteres til mobile (packages/core/src/index.ts),
  // og en 'ny Intl.Collator' ved modul-load ville køre på Hermes for en funktion,
  // mobile aldrig kalder.
  if (!danskCollator) danskCollator = new Intl.Collator('da');
  return danskCollator;
}

const QA_ALVOR_RANG: Record<string, number> = { fejl: 0, advarsel: 1, info: 2 };

// Sammenligner to (evt. null'able) værdier med given basis-komparator.
// Null placeres ALTID sidst — uanset retning — kun ikke-null-parret vender med retningen.
function sammenlignMedNullSidst<T>(
  a: T | null,
  b: T | null,
  direction: 'asc' | 'desc',
  basis: (x: T, y: T) => number,
): number {
  if (a === null && b === null) return 0;
  if (a === null) return 1;
  if (b === null) return -1;
  const cmp = basis(a, b);
  return direction === 'asc' ? cmp : -cmp;
}

function noegleVaerdi(row: PersonKvalitetsarkRow, key: KvalitetsarkSortKey): unknown {
  switch (key) {
    case 'navn':
      return row.navn;
    case 'foedsel':
      return row.foedselMin;
    case 'doed':
      return row.doedMin;
    case 'koen':
      return row.koen;
    case 'linje':
      return row.linje;
    case 'qa_alvor':
      return row.qaAlvor === null ? null : (QA_ALVOR_RANG[row.qaAlvor] ?? 3);
    default:
      return null;
  }
}

export function sortKvalitetsark(
  rows: PersonKvalitetsarkRow[],
  key: KvalitetsarkSortKey,
  direction: 'asc' | 'desc',
): PersonKvalitetsarkRow[] {
  const isNumeric = key === 'qa_alvor';
  return [...rows].sort((rowA, rowB) => {
    const a = noegleVaerdi(rowA, key) as string | number | null;
    const b = noegleVaerdi(rowB, key) as string | number | null;
    const primary = isNumeric
      ? sammenlignMedNullSidst(a as number | null, b as number | null, direction, (x, y) => x - y)
      : sammenlignMedNullSidst(a as string | null, b as string | null, direction, (x, y) =>
          collator().compare(x, y),
        );
    if (primary !== 0) return primary;
    // Deterministisk tiebreak: numerisk (BigInt) person_id-sammenligning, ALTID
    // stigende — uafhængig af sorteringsretning. Undgår leksikografisk fejl
    // ("100" < "20" < "3") på de store bigint-ID'er, der her er strenge.
    const idA = BigInt(rowA.personId);
    const idB = BigInt(rowB.personId);
    return idA < idB ? -1 : idA > idB ? 1 : 0;
  });
}
