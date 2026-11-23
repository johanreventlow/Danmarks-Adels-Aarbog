// Vielsesdato ved en ægtefælle: »⚭ 18. nov. 1670« når dagen kendes, »⚭ 1670« når kun året kendes, ellers intet.
// Ind kommer vielsesfaktummets valgte påstand som ISO-interval (date_min, date_max). Strengen læses direkte
// (ingen Date), så en tidszone aldrig kan flytte dagen.

const MAANEDER = ['jan.', 'feb.', 'marts', 'april', 'maj', 'juni', 'juli', 'aug.', 'sept.', 'okt.', 'nov.', 'dec.'];

const ISO = /^(\d{3,4})-(\d{2})-(\d{2})/;

export function fmtVielse(dateMin: string | null, dateMax: string | null): string {
  const a = dateMin ? ISO.exec(dateMin) : null;
  const b = dateMax ? ISO.exec(dateMax) : null;
  if (!a || !b) return '';
  const aar = Number(a[1]);
  if (Number(b[1]) !== aar) return '';
  const maaned = MAANEDER[Number(a[2]) - 1];
  if (a[0] === b[0] && maaned) return `⚭ ${Number(a[3])}. ${maaned} ${aar}`;
  return `⚭ ${aar}`;
}
