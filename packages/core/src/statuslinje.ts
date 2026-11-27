// Personsidens statuslinje og træets titelord (spec 2026-11-27, »Statuslinjen — regel«). Rene visningsregler:
//   [hof-/rangtitel], [egen adelstitel][ partikel-adelsnavn][, gift <feminin mandstitel> <mandens adelsnavn>]
// Anti-mål: aldrig en titel personen ikke havde. Ved tvivl (ukendt skilsmisse, ukendt navn) vises mindre.
import { adelsRang, erAdelsTitel, feminiserTitel } from './adelsTitler';
import { personensAdelsnavn } from './adelsnavn';
import { erTekniskLinje } from './lineage';
import { parSkilsmisse } from './skilsmisse';
import { hofTitel } from './titelAlgoritme';
import type { Model } from './types';

const stort = (s: string): string => (s ? s[0].toLocaleUpperCase('da') + s.slice(1) : s);

/** Ægtefæller med id (kanoniske opslag via model.byId). */
function aegtefaelleIder(model: Model, id: string): string[] {
  return (model.indexes.spousesBy[id] ?? []).map((s) => s.id).filter((x): x is string => x != null);
}

/**
 * Personens egen adelstitel (bogens stavning) — `title`, hvis den står på `ADELS_TITLER`. For kvinder dog ikke, hvis den
 * er lig den feminine form af en ægtefælles adelstitel: så er den en ægteskabstitel og hører til i gift-delen.
 */
export function egenAdelstitel(model: Model, id: string): string | null {
  const person = model.byId[id];
  const titel = person?.title?.trim() ?? '';
  if (!titel || !erAdelsTitel(titel)) return null;
  if (person.koen === 'kvinde') {
    const lav = titel.toLowerCase();
    for (const h of aegtefaelleIder(model, id)) {
      const mt = model.byId[h]?.title;
      if (mt && feminiserTitel(mt)?.toLowerCase() === lav) return null;
    }
  }
  return titel;
}

/** Stamtræets ene titelord: den egne adelstitel med stort begyndelsesbogstav (titlen følger navnet). */
export function traeTitel(model: Model, id: string): string | null {
  const t = egenAdelstitel(model, id);
  return t ? stort(t) : null;
}

function mandensNavn(model: Model, mandId: string): string | null {
  const regler = model.adelsnavne ?? {};
  const fraLinje = model.lineage ? personensAdelsnavn(mandId, model.lineage, regler) : null;
  if (fraLinje) return fraLinje;
  const harLinje = (model.lineage?.byPerson[mandId] ?? []).some((key) => !erTekniskLinje(key));
  const slaegt = model.slaegtsnavn?.trim();
  return harLinje && slaegt ? slaegt : null;
}

/** Gift-delen (»gift grevinde af Reventlow«): højeste ægteskabstitel blandt ikke-opløste ægteskaber. */
function giftDel(model: Model, id: string): string | null {
  if (model.byId[id]?.koen !== 'kvinde') return null;
  let bedst: { rang: number; tekst: string } | null = null;
  for (const h of aegtefaelleIder(model, id)) {
    if (parSkilsmisse(model, id, h) !== null) continue; // skilt eller ukendt → ingen titel (fail-closed)
    const mt = model.byId[h]?.title?.trim();
    const fem = mt && erAdelsTitel(mt) ? feminiserTitel(mt) : null;
    if (!fem) continue;
    const navn = mandensNavn(model, h);
    if (!navn) continue;
    const rang = adelsRang(mt);
    if (!bedst || rang > bedst.rang) bedst = { rang, tekst: `gift ${fem.toLowerCase()} ${navn}` };
  }
  return bedst?.tekst ?? null;
}

/**
 * Statuslinjen under H1. `hofKilder` = rå titel-fakta + embedsroller; `null` = detaljer ikke hentet (ingen hof-del).
 * `null`, når ingen del kan vises.
 */
export function byggStatuslinje(model: Model, id: string, hofKilder: readonly string[] | null): string | null {
  const person = model.byId[id];
  if (!person) return null;
  const dele: string[] = [];
  if (person.koen === 'mand' && hofKilder) {
    const hof = hofTitel(hofKilder);
    if (hof) dele.push(hof);
  }
  const egen = egenAdelstitel(model, id);
  if (egen) {
    const adelsnavn = model.lineage ? personensAdelsnavn(id, model.lineage, model.adelsnavne ?? {}) : null;
    dele.push(adelsnavn ? `${egen.toLowerCase()} ${adelsnavn}` : egen.toLowerCase());
  }
  const gift = giftDel(model, id);
  if (gift) dele.push(gift);
  return dele.length ? stort(dele.join(', ')) : null;
}
