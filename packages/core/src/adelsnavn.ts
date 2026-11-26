// Bogens formelle navneform (plan docs/superpowers/plans/2026-11-26-linjernes-adelsnavn.md). Partiklen og stavemåden
// følger linjen (IV »de Reventlou«, V »af Reventlow«: et kildebundet `adelsnavn`-faktum på lineage); titelordet følger
// personen (visningscachens adelstitel, allerede kønsbøjet). Ren visningsregel: der skrives intet i navn eller cache.
import { erAdelsTitel } from './adelsTitler';
import { compareLineHead } from './placementCoordinates';
import { udenSlaegtsnavnTilSidst } from './slaegtsnavn';
import type { Lineage } from './types';

/** lineage-id (streng) → linjens adelsnavn, fx `{ '5': 'af Reventlow' }`. */
export type LinjeAdelsnavne = Record<string, string>;

const tekst = (v: string | null | undefined): string => (v ?? '').trim();

/**
 * »Johan Martin greve af Reventlow«: fornavne + adelstitel med lille + linjens adelsnavn — samme form som
 * præsenslistens hovedrække (`formatAnkerNavn`). `null`, når en del mangler, eller titlen ikke er en adelstitel.
 */
export function formelNavneform(input: {
  fornavne: string | null | undefined;
  titel: string | null | undefined;
  adelsnavn: string | null | undefined;
  slaegtsnavn?: string | null;
}): string | null {
  const titel = tekst(input.titel);
  const adelsnavn = tekst(input.adelsnavn);
  const slaegtsnavn = tekst(input.slaegtsnavn);
  const fornavne = slaegtsnavn ? udenSlaegtsnavnTilSidst(tekst(input.fornavne), slaegtsnavn) : tekst(input.fornavne);
  if (!fornavne || !adelsnavn || !titel || !erAdelsTitel(titel)) return null;
  return `${fornavne} ${titel.toLowerCase()} ${adelsnavn}`;
}

/**
 * Personens adelsnavn ud fra linjerne: præcis én distinkt regel, ellers `null` (fail-closed, fx en samme_som-foldet
 * person i både IV og V). Er personen stifter af en linje med regel, `null`: stifterens navn kommer fra hans eget
 * patent (V: Conrad »de Reventlow« 1673; bevillingen 1692 på »af Reventlow« gælder sønner og descendenter).
 */
export function adelsnavnForLinjer(
  lineageIds: readonly string[],
  regler: LinjeAdelsnavne,
  stifterAf: readonly string[] = [],
): string | null {
  if (stifterAf.some((id) => tekst(regler[id]) !== '')) return null;
  const fundne = new Set(lineageIds.map((id) => tekst(regler[id])).filter((r) => r !== ''));
  return fundne.size === 1 ? [...fundne][0] : null;
}

type Id = number | string;

/**
 * Linjereglerne fra evidenslaget: `fact` (subjekt_type='lineage', faktatype='adelsnavn') → afklaret `conclusion` →
 * valgt `assertion.vaerdi_tekst`. Klienten henter de tre rækkesæt (web og mobil hver med sin supabase-klient); her
 * stykkes de sammen. To forskellige afklarede værdier på samme linje → ingen regel (fail-closed).
 */
export function byggLinjeAdelsnavne(
  facts: readonly { id: Id; subjekt_id: Id }[],
  conclusions: readonly { target_id: Id; valgt_assertion_id: Id | null }[],
  assertions: readonly { id: Id; vaerdi_tekst: string | null }[],
): LinjeAdelsnavne {
  const vaerdi = new Map(assertions.map((a) => [String(a.id), tekst(a.vaerdi_tekst)]));
  const valgt = new Map(conclusions.map((c) => [String(c.target_id), c.valgt_assertion_id == null ? '' : String(c.valgt_assertion_id)]));
  const prLinje = new Map<string, Set<string>>();
  facts.forEach((f) => {
    const v = vaerdi.get(valgt.get(String(f.id)) ?? '') ?? '';
    if (!v) return;
    const s = prLinje.get(String(f.subjekt_id)) ?? new Set<string>();
    s.add(v);
    prLinje.set(String(f.subjekt_id), s);
  });
  const ud: LinjeAdelsnavne = {};
  prLinje.forEach((s, linje) => { if (s.size === 1) ud[linje] = [...s][0]; });
  return ud;
}

/** Lineage-id fra en `lineageContextKey` (`slaegt:…:lineage:<id>:scheme:…`); `null` for rå koder og tekniske nøgler. */
export function lineageIdAfNoegle(key: string): string | null {
  const m = /(?:^|:)lineage:([^:]+)(?::|$)/.exec(key);
  return m && !key.startsWith('legacy-source:') ? m[1] : null;
}

/** Personens adelsnavn fra læserens linjemodel (web): personens linjenøgler + stifterskab i listen. */
export function personensAdelsnavn(personId: string, lineage: Lineage, regler: LinjeAdelsnavne): string | null {
  const ids = (lineage.byPerson[personId] ?? []).map(lineageIdAfNoegle).filter((id): id is string => id != null);
  const stifterAf = lineage.list
    .filter((l) => l.headId === personId)
    .map((l) => lineageIdAfNoegle(l.linje))
    .filter((id): id is string => id != null);
  return adelsnavnForLinjer(ids, regler, stifterAf);
}

/**
 * Adelsnavn pr. kanonisk person ud fra de rå koordinater (mobilens vej; web bruger `personensAdelsnavn` på sin
 * kanoniske linjemodel). Linjen findes som `(source_id, linjekode)` → lineage-række, aldrig koden alene: udgaverne
 * nummererer linjerne forskelligt (1939 »IV« er 2018-20's V). Stifteren af en koordinat er medlemmet med laveste
 * slægtled/nr (samme regel som linjelistens hoved, `compareLineHead`). Personer uden regel udelades.
 */
export function adelsnavnFraKoordinater(
  extIds: readonly { person_id: Id; source_id: Id; linje: string | null; nr: number | null; nr_label?: string | null; slaegtled_lokal?: number | null }[],
  lineageRows: readonly { id?: Id | null; source_id?: Id | null; kode?: string | null }[],
  regler: LinjeAdelsnavne,
  canonicalIdById: Record<string, string> = {},
): Record<string, string> {
  const cid = (id: Id) => canonicalIdById[String(id)] ?? String(id);
  const koordinat = (sourceId: Id, kode: string) => `${String(sourceId)}:${kode}`;
  const lineageAf = new Map<string, string>();
  lineageRows.forEach((l) => { if (l.id != null && l.source_id != null && l.kode) lineageAf.set(koordinat(l.source_id, l.kode), String(l.id)); });
  const linjer = new Map<string, Set<string>>();
  const hoved = new Map<string, { pid: string; key: { slaegtled: number | null; nr: number | null; nr_label: string | null } }>();
  extIds.forEach((x) => {
    if (!x.linje) return;
    const lid = lineageAf.get(koordinat(x.source_id, x.linje));
    if (!lid) return;
    const pid = cid(x.person_id);
    const s = linjer.get(pid) ?? new Set<string>();
    s.add(lid);
    linjer.set(pid, s);
    const key = { slaegtled: x.slaegtled_lokal ?? null, nr: x.nr ?? null, nr_label: x.nr_label ?? null };
    const k = koordinat(x.source_id, x.linje);
    const cur = hoved.get(k);
    if (!cur || compareLineHead(key, cur.key) < 0) hoved.set(k, { pid, key });
  });
  const stifterAf = new Map<string, string[]>();
  hoved.forEach((h, k) => {
    const lid = lineageAf.get(k);
    if (lid) stifterAf.set(h.pid, [...(stifterAf.get(h.pid) ?? []), lid]);
  });
  const ud: Record<string, string> = {};
  linjer.forEach((ids, pid) => {
    const r = adelsnavnForLinjer([...ids], regler, stifterAf.get(pid) ?? []);
    if (r) ud[pid] = r;
  });
  return ud;
}
