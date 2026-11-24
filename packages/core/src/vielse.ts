// Vielsesdato ved en ægtefælle: »⚭ 18. nov. 1670« når dagen kendes, »⚭ 1670« når kun året kendes, »⚭ ca. 1688«
// når Aarbogen skriver »ca.«, ellers intet. Ind kommer vielsesfaktummets valgte påstand som ISO-interval
// (date_min, date_max) plus kvalifikator og rå tekst. Strengen læses direkte (ingen Date), så en tidszone aldrig kan
// flytte dagen. I prod er kvalifikatoren tom for alle vielser, så »ca.« findes kun i den rå tekst (»Gift ca. 1688«).

const MAANEDER = ['jan.', 'feb.', 'marts', 'april', 'maj', 'juni', 'juli', 'aug.', 'sept.', 'okt.', 'nov.', 'dec.'];

const ISO = /^(\d{3,4})-(\d{2})-(\d{2})/;
const CA = /(^|[\s(])(ca\.|omkring|omkr\.)(\s|$)/i;

// En ISO-dag (»1943-11-26«) som i Aarbogen: »26. nov. 1943«; tom streng, hvis strengen ikke er en gyldig dag.
// Bruges også af forsidens dato-kort (»På denne dag«/»I denne måned«).
export function fmtDagDato(iso: string): string {
  const m = ISO.exec(iso);
  const maaned = m ? MAANEDER[Number(m[2]) - 1] : undefined;
  return m && maaned ? `${Number(m[3])}. ${maaned} ${Number(m[1])}` : '';
}

export type VielseKvalifikation = { qualifier?: string | null; raw?: string | null };

export function fmtVielse(dateMin: string | null, dateMax: string | null, k: VielseKvalifikation = {}): string {
  const a = dateMin ? ISO.exec(dateMin) : null;
  const b = dateMax ? ISO.exec(dateMax) : null;
  if (!a || !b) return '';
  const aar = Number(a[1]);
  if (Number(b[1]) !== aar) return '';
  const ca = k.qualifier === 'about' || (k.raw != null && CA.test(k.raw));
  if (ca) return `⚭ ca. ${aar}`;
  // Kun en eksakt (eller ukvalificeret) dato må vises som dag eller år; før/efter giver intet frem for en for præcis
  // dato (samme regel som isExactDay i @daa/feed).
  if (k.qualifier != null && k.qualifier !== 'exact') return '';
  const dag = a[0] === b[0] ? fmtDagDato(a[0]) : '';
  if (dag) return `⚭ ${dag}`;
  return `⚭ ${aar}`;
}

// Præcision af en formateret vielsestekst, så den mest præcise vinder, når et par står i flere familier (fx en
// sammenfoldet ægtefælle i både 1939 og 2018-20): dag 3 · år 2 · ca.-år 1 · intet 0.
export function vielsePraecision(tekst: string): number {
  if (!tekst) return 0;
  if (tekst.startsWith('⚭ ca.')) return 1;
  return /^⚭ \d+\. /.test(tekst) ? 3 : 2;
}
