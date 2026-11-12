// Lighedsregel for faktaværdier på tværs af bogudgaver (6e-1, spec §5.4/§5.8). DOM-fri og konservativ:
// i tvivl er to værdier IKKE ens. Normaliseringen fjerner kun skrivemåde (versaler, tegnsætning, månedsnavn
// som tal) — aldrig betydning (usikkerhedstegn, sted, forkortelser udvides ikke).

export const DATO_TYPER: ReadonlySet<string> = new Set(['fødsel', 'dåb', 'død', 'begravelse']);

export const ENKELTVAERDI_TYPER: ReadonlySet<string> = new Set([
  'navn', 'fødsel', 'dåb', 'død', 'dødsårsag', 'begravelse', 'adling', 'klosterindgang',
]);

const MAANEDER: Record<string, string> = {
  jan: '1', januar: '1', feb: '2', febr: '2', februar: '2', mar: '3', marts: '3', apr: '4', april: '4',
  maj: '5', jun: '6', juni: '6', jul: '7', juli: '7', aug: '8', august: '8', sep: '9', sept: '9',
  september: '9', okt: '10', oktober: '10', nov: '11', november: '11', dec: '12', december: '12',
};

const CA = new Set(['ca', 'o', 'omkr', 'circa']);

export function erTomFaktaVaerdi(v: string): boolean {
  return v.replace(/[\s\p{P}\p{S}]/gu, '') === '';
}

function normaliserDato(v: string): string {
  const t = v
    .toLowerCase()
    .replace(/[†*⚭]/g, ' ')
    .replace(/s\.\s*a\./g, ' sa ')
    .replace(/\?/g, ' ? ')
    .replace(/[.,;:()/\-–]/g, ' ');
  return t
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => (CA.has(w) ? 'ca' : (MAANEDER[w] ?? w)))
    .join(' ');
}

function normaliserTekst(v: string): string {
  return v.toLowerCase().replace(/[\p{P}\p{S}]/gu, ' ').replace(/\s+/g, ' ').trim();
}

export function normaliserFaktaVaerdi(faktatype: string, v: string): string {
  return DATO_TYPER.has(faktatype) ? normaliserDato(v) : normaliserTekst(v);
}

export function faktaVaerdierEns(faktatype: string, a: string, b: string): boolean {
  if (erTomFaktaVaerdi(a) || erTomFaktaVaerdi(b)) return false;
  return normaliserFaktaVaerdi(faktatype, a) === normaliserFaktaVaerdi(faktatype, b);
}
