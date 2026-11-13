// 6e-2: linjens visningsnavn i »Kilde i Aarbogen«. Samme præfiksregel som SQL'ens private.linje_kode:
// et ledende romertal eller bogstav (»IV. «, »A. «) i etiketten er koden, ellers bruges skemaets kode.
export type LinjeSkemaIndgang = { code: string; label: string | null };

// Opslag (kilde-id, kode) → skemaindgang. Kun stamtavle-skemaer må ligge bag (bygges i appens model).
// undefined = kilden har slet ingen stamtavleindgange (skemaet mangler/kunne ikke hentes → kalderen falder
// tilbage til den gamle form); null = koden findes ikke i kildens udfyldte skema (legacy-kode).
export type SkemaOpslag = (sourceId: string, code: string) => LinjeSkemaIndgang | null | undefined;

const PRAEFIKS = /^([IVXLC]+|[A-Z])\.\s+/;

export function linjeKodeOgNavn(e: LinjeSkemaIndgang): { kode: string; navn: string } {
  const label = (e.label ?? '').trim();
  const m = PRAEFIKS.exec(label);
  const kode = m ? m[1] : e.code;
  const rest = (m ? label.slice(m[0].length) : label).trim().replace(/\.$/, '').trim();
  return { kode, navn: rest === '' ? kode : rest };
}

export function linjeTitel(e: LinjeSkemaIndgang): string {
  const { kode, navn } = linjeKodeOgNavn(e);
  return `${kode}. ${navn}`;
}
