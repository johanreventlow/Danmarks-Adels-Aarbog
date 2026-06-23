// Dansk collation — EKSPLICIT, ikke String.localeCompare(a,b,'da').
// Hvorfor: RN's Hermes-engine har ufuldstændig Intl/Collator-støtte, så localeCompare
// kan ignorere 'da'-locale på device (Æ/Ø/Å sorteres forkert) mens Jest i Node (fuld ICU)
// består grønt. Vi mapper hvert tegn til en rang hvor Æ Ø Å ligger EFTER Z, og tester den
// eksplicitte orden — så testen fanger reel device-adfærd. (advisor 2026-06-23)

// Dansk alfabet-orden. Æ/Ø/Å (+ historiske Aa-varianter) efter Z.
const DANISH_ORDER = 'AÁBCDEÉFGHIÍJKLMNOÓPQRSTUÚVWXYZÆØÅ';

// Bygger rang-tabel: tegn (uppercase) → indeks. Ukendte tegn (cifre, symboler) får høj rang.
const rank: Record<string, number> = {};
for (let i = 0; i < DANISH_ORDER.length; i++) {
  rank[DANISH_ORDER[i]] = i;
}
const UNKNOWN = 900;
// Accent-folding for almindelige danske/europæiske varianter til basis-bogstav.
const FOLD: Record<string, string> = {
  À: 'A', Â: 'A', Ä: 'A', Ã: 'A',
  È: 'E', Ê: 'E', Ë: 'E',
  Ì: 'I', Î: 'I', Ï: 'I',
  Ò: 'O', Ô: 'O', Ö: 'O', Õ: 'O',
  Ù: 'U', Û: 'U', Ü: 'U',
  Ç: 'C', Ñ: 'N',
};

function rankOf(ch: string): number {
  const u = ch.toUpperCase();
  const folded = FOLD[u] ?? u;
  return rank[folded] ?? UNKNOWN;
}

// Sammenlign to strenge efter dansk orden. Returnerer -1/0/1.
export function compareDanish(a: string, b: string): number {
  const sa = a ?? '';
  const sb = b ?? '';
  const n = Math.min(sa.length, sb.length);
  for (let i = 0; i < n; i++) {
    const ra = rankOf(sa[i]);
    const rb = rankOf(sb[i]);
    if (ra !== rb) return ra < rb ? -1 : 1;
    // Sekundær: hvis samme rang men forskellige tegn (fx Á vs A), brug kodepunkt som tiebreak.
    if (sa[i] !== sb[i]) {
      const ca = sa.charCodeAt(i);
      const cb = sb.charCodeAt(i);
      if (ca !== cb) return ca < cb ? -1 : 1;
    }
  }
  if (sa.length !== sb.length) return sa.length < sb.length ? -1 : 1;
  return 0;
}

// Initial-bogstav til alfabet-hop (§9.1). Bruger EFTERNAVN: sidste whitespace-adskilte token
// af visningsnavnet, så "Christian Ditlev Reventlow" grupperes under R, ikke C.
// Æ/Ø/Å bevares som egne bogstaver; ukendt/tomt → '#'.
export function initialOf(name: string): string {
  const n = (name ?? '').trim();
  if (!n) return '#';
  const tokens = n.split(/\s+/).filter(Boolean);
  const surname = tokens[tokens.length - 1] || n;
  const first = surname[0]?.toUpperCase() ?? '#';
  const folded = FOLD[first] ?? first;
  return rank[folded] !== undefined ? folded : '#';
}

// Sorter bogstav-nøgler efter dansk orden (til chip-rækken + sticky-grupper).
export function sortLetters(keys: string[]): string[] {
  return [...keys].sort(compareDanish);
}
