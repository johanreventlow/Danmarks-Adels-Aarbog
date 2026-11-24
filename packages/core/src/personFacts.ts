// B11 (spec 2026-10-29-5c2-b11-laeserflade-design.md §4.4): fakta-sektionen i persondetaljen. Rækkerne kommer fra
// public_person_facts (én pr. påstand og citation); her grupperes de pr. faktum, ordnes og får deres kildevisning:
// bundet til bogens post (trin 4-binding), fra den oprindelige import (citation), eller ingen registreret kilde.
import { visbarPostEtiket } from './recordLabel';

export type PublicPersonFactRow = {
  person_id: number | string;
  fact_id: number | string;
  faktatype: string;
  conclusion_status: 'afklaret' | 'omstridt' | string;
  assertion_id: number | string;
  chosen: boolean;
  vaerdi_tekst: string | null;
  date_raw: string | null;
  date_min: string | null;
  date_max: string | null;
  date_qualifier: string | null;
  date_certainty: string | null;
  source_id: number | string | null;
  source_label: string | null;
  side: string | null;
  record_ref: string | null;
  record_label: string | null;
  citation_label: string | null;
};

export type PersonFactSource = { kind: 'bundet' | 'import' | 'ingen'; label: string; recordRef: string | null };
export type PersonFactStatement = { assertionId: string; value: string; source: PersonFactSource };
export type PersonFactView = {
  factId: string;
  faktatype: string;
  omstridt: boolean;
  chosen: PersonFactStatement | null;
  others: PersonFactStatement[];
};

// forældrefamilie vises som familie med kildelinje; forældre_ukendt har sin egen markering.
export const FAKTA_UDELADT = ['forældrefamilie', 'forældre_ukendt'];

const FAKTA_RAEKKEFOELGE = ['navn', 'tilnavn', 'fødenavn', 'fødsel', 'dåb', 'titel', 'dekoration', 'adling', 'floruit',
  'klosterindgang', 'overhoved', 'død', 'dødsårsag', 'begravelse'];

// Intern genbrug i editionFacts.ts; bevidst ikke eksporteret fra index.ts.
export const typeRank = (t: string) => {
  const i = FAKTA_RAEKKEFOELGE.indexOf(t);
  return i === -1 ? FAKTA_RAEKKEFOELGE.length : i;
};

// Spec §5.8 (projektejeren 2026-11-12): et ledende *, † eller ⚭ fjernes — typen (»Født«, »Død«) siger det allerede.
const udenLedendeTegn = (v: string | null) => (v == null ? null : v.replace(/^\s*[*†⚭]\s*/u, ''));

// `date_raw` er dobbelt, når den er lig `vaerdi_tekst`, eller når `vaerdi_tekst` SLUTTER med den (efter mellemrum og
// afsluttende tegnsætning, ved en ordgrænse) og den er mere end et årstal — fx »hjemmedøbt 10. febr. 1922« +
// »10. febr. 1922« (spec §5.8 »Dobbelt værdi«, afgørelse 13). Et rent årstal kan være et tilfælde (»kirken opført
// 1845« + »1845«, »1845 eller 1846« + »1846«), så begge vises. Tjekket sker efter `del` (opløsning, §5.4a).
// Kun mellemrum og . , ; : er skrivemåde i halen; »?«, parenteser o.l. bærer betydning og fjernes aldrig — ellers
// forsvandt »21. april 1644?« bag »døbt 21. april 1644« (final review C1).
const udenHale = (v: string) => v.trim().replace(/[\s.,;:]+$/u, '');
const slutterMed = (tekst: string, del: string) => {
  const t = udenHale(tekst), d = udenHale(del);
  if (!d || !/\p{L}/u.test(d) || !t.endsWith(d)) return false;
  const foer = t[t.length - d.length - 1];
  return foer == null || !/[\p{L}\p{N}]/u.test(foer);
};

// Er `date_raw` en gentagelse af `vaerdi_tekst` (lig den eller dens afslutning)? Bruges af opløsningen af relative
// datoer (editionFacts.ts, »datofelt ved en dato i teksten«), hvor reglen er målt 2026-11-12 og bevidst stadig er
// »slutter med«. At lade opløsningen bruge visningens bredere regel er en senere opgave (#478).
export const datoErDobbelt = (tekst: string, dato: string) => dato.trim() === tekst.trim() || slutterMed(tekst, dato);

// Visningens regel (afgørelse 13 revideret 2026-11-24, projektejeren): `date_raw` vises ikke igen, når den står ORDRET
// et vilkårligt sted i `vaerdi_tekst` med ordgrænse på begge sider og er mere end et årstal — fx »25. april 1861 på
// Pederstrup« + »25. april 1861«. Værnene fra afgørelse 13 består: et rent årstal kan være et tilfælde, og »?« eller
// parenteser i datoen gør den forskellig fra teksten (kun mellemrum og . , ; : er skrivemåde i halen).
const staarITeksten = (tekst: string, del: string) => {
  const d = udenHale(del);
  if (!d || !/\p{L}/u.test(d)) return false;
  for (let i = tekst.indexOf(d); i !== -1; i = tekst.indexOf(d, i + 1)) {
    const foer = tekst[i - 1], efter = tekst[i + d.length];
    // efter datoen kun mellemrum, . , ; : eller tekstens slutning — »døbt 21. april 1644?« bærer en tvivl, datofeltet ikke
    if ((foer == null || !/[\p{L}\p{N}]/u.test(foer)) && (efter == null || /[\s.,;:]/u.test(efter))) return true;
  }
  return false;
};
const datoVisesIForvejen = (tekst: string, dato: string) => datoErDobbelt(tekst, dato) || staarITeksten(tekst, dato);

// Den rå værdi med ledende tegn fjernet; null for tom.
export const visDel = (v: string | null) => {
  const u = udenLedendeTegn(v);
  return u == null || u.trim() === '' ? null : u;
};

export function factValue(r: PublicPersonFactRow, del: (v: string) => string = (v) => v): string {
  const vis = (v: string | null) => {
    const u = visDel(v);
    return u == null ? null : del(u);
  };
  const tekst = vis(r.vaerdi_tekst);
  const dato = vis(r.date_raw);
  const dateRaw = dato && tekst && datoVisesIForvejen(tekst, dato) ? null : dato;
  const parts = [tekst, dateRaw].filter((x): x is string => !!x && x.trim() !== '');
  return parts.length ? parts.join(', ') : '—';
}

// Spec §5.8: kildeetiketter viser »<udgave>, s. N«; 1939's bundne etiketter siger »DAA 1939 side 532«.
// Kun den første » side N« efter udgaven får komma: »DAA 1939 side 12 og side 14« → »DAA 1939, s. 12 og s. 14«.
const SIDE = String.raw`side\s+(\d+(?:\s*[-–]\s*\d+)?)(?!\d)`;
export const sideForm = (label: string): string => label
  .replace(new RegExp(String.raw`,?\s+` + SIDE, 'u'), ', s. $1')
  .replace(new RegExp(String.raw`(?<=\s)` + SIDE, 'gu'), 's. $1');

// Postetiket til chips og familiekilder: bogens side + post. Tom post (''): kun siden. Teknisk etiket
// (record-…, legacy-source:…; før ceremonien bærer citationLabel endnu PDF-siden): udgavens navn som hidtil.
export function postEtiketTekst(sourceLabel: string, citationLabel: string, recordLabel: string): string {
  const etiket = visbarPostEtiket(recordLabel);
  if (etiket) return `${sideForm(citationLabel || sourceLabel)} · ${etiket}`;
  if (recordLabel === '') return sideForm(citationLabel || sourceLabel);
  return sourceLabel;
}

export function factSource(r: PublicPersonFactRow): PersonFactSource {
  if (r.record_ref) {
    // citation_label bærer allerede udgave og side (»DAA 2018-20, s. 45«); record_label er posten (»I-32«).
    const label = [r.citation_label || r.source_label, visbarPostEtiket(r.record_label)].filter(Boolean).join(' · ');
    return { kind: 'bundet', label: sideForm(label), recordRef: r.record_ref };
  }
  if (r.source_label) {
    return { kind: 'import', label: sideForm(r.side ? `${r.source_label}, s. ${r.side}` : r.source_label), recordRef: null };
  }
  return { kind: 'ingen', label: 'Kilde ikke registreret', recordRef: null };
}

// Forældet i web — brug faktaInput/byggUdgaveFakta (editionFacts.ts). Bevares for planens kompatibilitet.
export function buildPersonFacts(rows: PublicPersonFactRow[]): PersonFactView[] {
  const seen = new Set<string>();
  const byFact = new Map<string, { first: PublicPersonFactRow; rows: PublicPersonFactRow[] }>();
  for (const r of rows) {
    if (FAKTA_UDELADT.includes(r.faktatype)) continue;
    const key = JSON.stringify(r);
    if (seen.has(key)) continue; // samme række fra flere medlems-id'er
    seen.add(key);
    const g = byFact.get(String(r.fact_id));
    if (g) g.rows.push(r);
    else byFact.set(String(r.fact_id), { first: r, rows: [r] });
  }
  const views = [...byFact.values()].map(({ first, rows: rs }) => {
    const statements = rs.map((r) => ({ row: r, st: { assertionId: String(r.assertion_id), value: factValue(r), source: factSource(r) } }));
    const chosenIdx = statements.findIndex((s) => s.row.chosen);
    return {
      view: {
        factId: String(first.fact_id),
        faktatype: first.faktatype,
        omstridt: first.conclusion_status === 'omstridt',
        chosen: chosenIdx === -1 ? null : statements[chosenIdx].st,
        others: statements.filter((_, i) => i !== chosenIdx).map((s) => s.st),
      } satisfies PersonFactView,
      dateMin: first.date_min,
      factNum: Number(first.fact_id),
    };
  });
  views.sort((a, b) =>
    typeRank(a.view.faktatype) - typeRank(b.view.faktatype)
    || (a.dateMin === b.dateMin ? 0 : a.dateMin == null ? 1 : b.dateMin == null ? -1 : a.dateMin < b.dateMin ? -1 : 1)
    || a.factNum - b.factNum);
  return views.map((v) => v.view);
}
