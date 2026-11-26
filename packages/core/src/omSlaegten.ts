// »Om slægten«: indledende narrativer på slægts-niveau (subjekt_type 'slaegt'/'lineage'). Flyttet fra
// web/src/data/public.ts og mobilens kopi i mobile/src/data/about.ts (mobil-paritet, rest fra batch 5), så web og mobil
// bygger afsnittene ens.
//
// Hver linje/"Generelt" kan have FLERE udgaver (billeder-i-narrativer 2026-07-05, Slice C3/C4); pickPreferredBio (samme
// selector som person-bio) vælger én pr. subjekt (nyeste DAA-udgave). lineageNavn bærer overskriften pr. linje-afsnit;
// "Generelt" har ingen (null) og står altid FØRST, linjer derefter i lineage-rækkernes orden (kalderen sorterer på kode).
// lineageId (lineage.id) skelner linjeafsnit fra slægtens eget afsnit (null) og er afsnittets nøgle; lineageKode er
// bogens kode for linjen i den udgave, rækken stammer fra. kilde er udgavens etiket efter udgavevælgerens regel
// (udgave ?? titel), så indledningen og personsiden nævner udgaven ens.
import { pickPreferredBio, type NarrativeCand } from './pickPreferredBio';

export type AboutSection = { lineageId: string | null; lineageNavn: string | null; lineageKode: string | null; tekst: string; kilde: string | null; aar: number | null };

export type RawAboutSource = { slags: string | null; titel?: string | null; aar: number | null; udgave: string | null };
// privat er valgfri: web filtrerer private rækker i forespørgslen, mobilen henter feltet og lader funktionen springe dem over.
export type RawAboutRow = { id: number; subjekt_type: string; subjekt_id: number; source_id: number | null; tekst: string | null; privat?: boolean | null; source: RawAboutSource | null };
export type RawAboutLineage = { id: number; navn: string | null; kode: string };

// Ren: narrativ-rækker + linjer → afsnit. "Generelt" (slaegt) først, linjer i lineageRows' orden. Private rækker springes over.
export function byggAboutSections(rows: readonly RawAboutRow[], lineageRows: readonly RawAboutLineage[]): AboutSection[] {
  const candsByKey = new Map<string, NarrativeCand[]>();
  const sourceById = new Map<number, RawAboutSource>();
  for (const r of rows) {
    if (r.privat) continue;
    const key = `${r.subjekt_type}:${r.subjekt_id}`;
    const cand: NarrativeCand = { narrativeId: r.id, tekst: r.tekst, sourceId: r.source_id, slags: r.source?.slags ?? null, aar: r.source?.aar ?? null, udgave: r.source?.udgave ?? null };
    if (r.source_id != null && r.source) sourceById.set(r.source_id, r.source);
    const list = candsByKey.get(key);
    if (list) list.push(cand); else candsByKey.set(key, [cand]);
  }
  const kildeAf = (c: NarrativeCand) => {
    const s = c.sourceId != null ? sourceById.get(c.sourceId) : undefined;
    return { kilde: s ? (s.udgave ?? s.titel ?? null) : null, aar: s?.aar ?? null };
  };

  const sections: AboutSection[] = [];
  const slaegtCands = [...candsByKey.entries()].find(([key]) => key.startsWith('slaegt:'))?.[1];
  const slaegtBedst = slaegtCands ? pickPreferredBio(slaegtCands) : null;
  if (slaegtBedst?.tekst) sections.push({ lineageId: null, lineageNavn: null, lineageKode: null, tekst: slaegtBedst.tekst, ...kildeAf(slaegtBedst) });
  for (const l of lineageRows) {
    const cands = candsByKey.get(`lineage:${l.id}`);
    const best = cands ? pickPreferredBio(cands) : null;
    if (best?.tekst) sections.push({ lineageId: String(l.id), lineageNavn: l.navn ?? `Linje ${l.kode}`, lineageKode: l.kode, tekst: best.tekst, ...kildeAf(best) });
  }
  return sections;
}

// Afsnittets kildelinje: »Kilde: DAA 2018-20« (udgavens etiket alene, som udgavevælgeren viser den), ellers årbogens år,
// ellers »Kilde ikke registreret«.
export function indledningKilde(s: Pick<AboutSection, 'kilde' | 'aar'>): string {
  if (s.kilde) return `Kilde: ${s.kilde}`;
  return s.aar ? `Kilde: Danmarks Adels Aarbog ${s.aar}` : 'Kilde ikke registreret';
}
